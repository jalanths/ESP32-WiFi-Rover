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
  DateTime? lastTelemetry;

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
      _sendTimer = Timer.periodic(const Duration(milliseconds: 50), (_) => _sendDrive());
      _send('M,${mode.index}');
      notifyListeners();
    } catch (e) {
      // Do not await: closing a socket that never opened can hang forever,
      // which used to leave the app stuck on "Connecting".
      _closeQuietly(channel);
      connected = false;
      connecting = false;
      error = 'Could not reach the rover at $host. '
          'Join the "Ather" Wi-Fi network first.';
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

  void _sendDrive() => _send('D,${_x.toStringAsFixed(2)},${_y.toStringAsFixed(2)}');

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
