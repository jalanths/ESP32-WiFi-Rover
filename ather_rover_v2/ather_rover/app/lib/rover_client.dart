import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum RoverMode { eco, ride, sport }

/// Talks to the rover over WebSocket using the plain-text protocol
/// described at the top of rover_firmware.ino.
class RoverClient extends ChangeNotifier {
  RoverClient({this.host = '192.168.4.1', this.port = 81});

  String host;
  final int port;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _sendTimer;
  Timer? _retryTimer;

  bool connected = false;
  bool connecting = false;
  String? error;

  // Telemetry from the rover
  double volts = 0;
  int percent = 0;
  RoverMode mode = RoverMode.ride;
  String state = 'OK';
  String firmware = '-';
  double trim = 0; // -0.30..0.30, positive fixes drift to the right
  String selfTest = ''; // OK, BATT_SENSE, BATT_LOW, DRIVER (firmware 1.5+)

  // Firmware 2.0+: range, trip stats, activity, recorded path length
  int rangeMin = -1; // -1 = still learning
  int driveSec = 0;
  double minVolts = 0;
  int usedPct = 0;
  String activity = '-'; // -, TURBO, COOL, REC, PLAY
  int pathSec = 0;

  // Firmware 2.1+: actual voltage under load, and the saved calibration factor
  double loadVolts = 0;
  double calibration = 1.0;
  bool get hasCalibration => (double.tryParse(firmware) ?? 0) >= 2.1;

  final List<double> voltHistory = []; // last 60 s, two readings a second
  DateTime? lastTelemetry;
  DateTime _trimSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Latest joystick values, resent every 50 ms as a heartbeat
  double _x = 0;
  double _y = 0;

  Future<void> connect() async {
    if (connecting) return;
    connecting = true;
    error = null;
    notifyListeners();
    await _close();

    WebSocketChannel? channel;
    try {
      channel = WebSocketChannel.connect(Uri.parse('ws://$host:$port'));
      await channel.ready.timeout(const Duration(seconds: 4));
      _channel = channel;
      _sub = channel.stream.listen(
        _onMessage,
        onDone: _onLost,
        onError: (Object e) => _onLost(),
      );
      connected = true;
      connecting = false;
      _x = 0;
      _y = 0;
      _sendTimer?.cancel();
      _sendTimer =
          Timer.periodic(const Duration(milliseconds: 50), (_) => _sendDrive());
      _send('M,${mode.index}');
      notifyListeners();
    } catch (e) {
      // Do not await: closing a socket that never opened can hang forever,
      // which used to leave the app stuck on "Connecting".
      _closeQuietly(channel);
      connected = false;
      connecting = false;
      error = 'Could not reach the rover at $host. '
          'Join the ATHER-ROVER Wi-Fi network first.';
      notifyListeners();
      _scheduleRetry();
    }
  }

  void _onLost() {
    connected = false;
    _sendTimer?.cancel();
    error = 'Connection lost. The rover has stopped itself.';
    notifyListeners();
    _scheduleRetry();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 3), () {
      if (!connected) connect();
    });
  }

  void _onMessage(dynamic data) {
    if (data is! String || !data.startsWith('T,')) return;
    final p = data.split(',');
    if (p.length < 6) return;
    volts = double.tryParse(p[1]) ?? volts;
    percent = int.tryParse(p[2]) ?? percent;
    final m = int.tryParse(p[3]);
    if (m != null && m >= 0 && m < RoverMode.values.length) {
      mode = RoverMode.values[m];
    }
    state = p[4];
    firmware = p[5];
    if (p.length >= 8) {
      // don't overwrite the slider while the user is still adjusting it
      if (DateTime.now().difference(_trimSentAt).inMilliseconds > 1500) {
        trim = double.tryParse(p[6]) ?? trim;
      }
      selfTest = p[7];
    }
    if (p.length >= 14) {
      rangeMin = int.tryParse(p[8]) ?? rangeMin;
      driveSec = int.tryParse(p[9]) ?? driveSec;
      minVolts = double.tryParse(p[10]) ?? minVolts;
      usedPct = int.tryParse(p[11]) ?? usedPct;
      activity = p[12];
      pathSec = int.tryParse(p[13]) ?? pathSec;
    }
    if (p.length >= 16) {
      loadVolts = double.tryParse(p[14]) ?? loadVolts;
      calibration = double.tryParse(p[15]) ?? calibration;
    }
    voltHistory.add(volts);
    if (voltHistory.length > 120) voltHistory.removeAt(0);
    lastTelemetry = DateTime.now();
    notifyListeners();
  }

  void _send(String text) {
    if (!connected) return;
    try {
      _channel?.sink.add(text);
    } catch (_) {
      _onLost();
    }
  }

  void _sendDrive() =>
      _send('D,${_x.toStringAsFixed(2)},${_y.toStringAsFixed(2)}');

  /// x: steer (-1 left .. 1 right), y: throttle (-1 reverse .. 1 forward)
  void drive(double x, double y) {
    _x = x.clamp(-1.0, 1.0);
    _y = y.clamp(-1.0, 1.0);
  }

  void stop() {
    _x = 0;
    _y = 0;
    _send('S');
  }

  void setMode(RoverMode m) {
    mode = m;
    _send('M,${m.index}');
    notifyListeners();
  }

  /// Turbo: 3 s of full power, then a 10 s cool-down (the rover enforces it).
  void turbo() => _send('B');

  /// Flash both LEDs for a few seconds.
  void find() => _send('F');

  /// Start or stop recording a path (up to 60 s).
  void toggleRecord() => _send(activity == 'REC' ? 'P,S' : 'P,R');

  /// Play or stop the recorded path. Moving the joystick also stops it.
  void togglePlay() => _send(activity == 'PLAY' ? 'P,X' : 'P,P');

  /// Reset drive time, minimum voltage, battery used and range.
  void resetTrip() {
    voltHistory.clear();
    _send('Z');
  }

  /// Battery calibration: the battery voltage measured with a multimeter
  /// while the motors are stopped. 0 resets. The rover saves it.
  void calibrateBattery(double multimeterVolts) {
    voltHistory.clear();
    _send('C,${multimeterVolts.toStringAsFixed(2)}');
  }

  /// Straight-line trim. The rover saves it, so it survives power-off.
  void setTrim(double value) {
    trim = value.clamp(-0.30, 0.30);
    _trimSentAt = DateTime.now();
    _send('R,${trim.toStringAsFixed(2)}');
    notifyListeners();
  }

  Future<void> _close() async {
    _sendTimer?.cancel();
    _retryTimer?.cancel();
    final sub = _sub;
    _sub = null;
    _closeQuietly(_channel);
    _channel = null;
    connected = false;
    try {
      await sub?.cancel().timeout(const Duration(seconds: 1));
    } catch (_) {}
  }

  static void _closeQuietly(WebSocketChannel? ch) {
    if (ch == null) return;
    try {
      unawaited(ch.sink.close().catchError((Object _) {}));
    } catch (_) {}
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }
}
