import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/drive_math.dart';
import '../core/protocol.dart';
import '../core/transport.dart';

enum LinkPhase { disconnected, connecting, connected, reconnecting }

/// All timing knobs in one place so tests can shrink them.
class RoverTimings {
  const RoverTimings({
    this.heartbeat = const Duration(milliseconds: 50),
    this.connectTimeout = const Duration(seconds: 4),
    this.staleAfter = const Duration(milliseconds: 1500),
    this.dropAfter = const Duration(seconds: 5),
    this.watchdog = const Duration(milliseconds: 250),
    this.backoffBase = const Duration(seconds: 1),
    this.backoffMax = const Duration(seconds: 10),
    this.echoHold = const Duration(milliseconds: 1500),
  });

  /// Drive commands are resent this often (firmware failsafe is 400 ms).
  final Duration heartbeat;
  final Duration connectTimeout;

  /// No telemetry for this long: show "signal weak".
  final Duration staleAfter;

  /// No telemetry for this long: treat the link as dead and reconnect.
  final Duration dropAfter;
  final Duration watchdog;
  final Duration backoffBase;
  final Duration backoffMax;

  /// After the user changes trim or mode, ignore the rover's echo of the old
  /// value for this long so the control doesn't jump back.
  final Duration echoHold;
}

class VoltSample {
  const VoltSample(this.time, this.volts);
  final DateTime time;
  final double volts;
}

class RoverEvent {
  const RoverEvent(this.time, this.message, this.severity);
  final DateTime time;
  final String message;
  final Severity severity;
}

/// Owns the connection, the 50 ms heartbeat and the latest telemetry.
/// UI code only reads its fields and calls its methods.
class RoverController extends ChangeNotifier {
  RoverController({
    LinkOpener? opener,
    this.timings = const RoverTimings(),
    DateTime Function()? clock,
  })  : _open = opener ?? WebSocketLink.open,
        _now = clock ?? DateTime.now;

  static const int historyLength = 120; // 60 s at two frames a second
  static const int eventLimit = 50;

  final LinkOpener _open;
  final DateTime Function() _now;
  final RoverTimings timings;

  // ---- public read-only state ----
  String host = '192.168.4.1';
  int port = 81;
  LinkPhase phase = LinkPhase.disconnected;
  Telemetry? telemetry;
  DateTime? lastTelemetryAt;
  String? errorMessage;
  int retryAttempt = 0;
  DateTime? nextRetryAt;
  RideMode mode = RideMode.ride;
  double trim = 0;
  int badFrames = 0;

  final List<VoltSample> _history = [];
  final List<RoverEvent> _events = [];
  List<VoltSample> get history => List.unmodifiable(_history);
  List<RoverEvent> get events => List.unmodifiable(_events);

  bool get isConnected => phase == LinkPhase.connected;

  /// Connected, but telemetry has gone quiet.
  bool get isStale {
    if (!isConnected) return false;
    final ref = lastTelemetryAt ?? _connectedAt;
    if (ref == null) return false;
    return _now().difference(ref) > timings.staleAfter;
  }

  /// True when the controls should accept input.
  bool get canDrive {
    final s = telemetry?.state;
    return isConnected && s != RoverState.lowBatt && s != RoverState.fault;
  }

  DriveInput get currentInput => _input;

  // ---- private ----
  RoverLink? _link;
  StreamSubscription<String>? _sub;
  Timer? _heartbeat;
  Timer? _watchdog;
  Timer? _retryTimer;
  DateTime? _connectedAt;
  DateTime _trimSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _modeSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  DriveInput _input = DriveInput.zero;
  bool _wantConnected = false;
  bool _wasStale = false;
  bool _disposed = false;
  int _session = 0;

  // ================= connection =================

  /// Connect (or reconnect now, skipping any backoff wait).
  Future<void> connect({String? host, int? port}) async {
    if (host != null) this.host = host.trim();
    if (port != null) this.port = port;
    _wantConnected = true;
    retryAttempt = 0;
    await _attempt();
  }

  /// Stop the rover and stay disconnected until [connect] is called.
  Future<void> disconnect() async {
    _wantConnected = false;
    _retryTimer?.cancel();
    if (_link != null) _send(Commands.stop);
    _session++;
    await _teardown();
    phase = LinkPhase.disconnected;
    errorMessage = null;
    nextRetryAt = null;
    _log('Disconnected', Severity.info);
    notifyListeners();
  }

  Future<void> _attempt() async {
    _retryTimer?.cancel();
    nextRetryAt = null;
    final gen = ++_session;
    await _teardown();
    if (gen != _session) return;

    phase = retryAttempt > 0 ? LinkPhase.reconnecting : LinkPhase.connecting;
    errorMessage = null;
    notifyListeners();

    final RoverLink link;
    try {
      // Our own deadline too, in case a transport never answers at all.
      final pending = _open(Uri(scheme: 'ws', host: host, port: port), timings.connectTimeout);
      link = await pending.timeout(timings.connectTimeout * 2, onTimeout: () {
        pending.then((l) => l.close(), onError: (Object _) {});
        throw TimeoutException('connect');
      });
    } catch (e) {
      if (gen != _session || _disposed) return;
      errorMessage = _friendly(e);
      _scheduleRetry();
      return;
    }

    if (gen != _session || !_wantConnected || _disposed) {
      await link.close();
      return;
    }

    _link = link;
    _sub = link.incoming.listen(
      _onLine,
      onDone: () => _onLost(gen, 'Connection closed by rover'),
      onError: (Object _) => _onLost(gen, 'Connection error'),
      cancelOnError: true,
    );
    phase = LinkPhase.connected;
    retryAttempt = 0;
    _connectedAt = _now();
    lastTelemetryAt = null;
    _wasStale = false;
    _input = DriveInput.zero;
    _heartbeat = Timer.periodic(timings.heartbeat, (_) => _sendDrive());
    _watchdog = Timer.periodic(timings.watchdog, (_) => _checkWatchdog(gen));
    _send(Commands.mode(mode));
    _log('Connected to $host', Severity.good);
    notifyListeners();
  }

  void _onLost(int gen, String why) {
    if (gen != _session || _disposed) return;
    _session++;
    _teardown();
    _log('$why. The rover stops on its own within 0.4 s.', Severity.warning);
    if (_wantConnected) {
      errorMessage = 'Connection lost. Reconnecting...';
      _scheduleRetry();
    } else {
      phase = LinkPhase.disconnected;
      notifyListeners();
    }
  }

  void _scheduleRetry() {
    if (!_wantConnected || _disposed) {
      phase = LinkPhase.disconnected;
      notifyListeners();
      return;
    }
    retryAttempt++;
    final delay = backoffFor(retryAttempt, timings);
    phase = LinkPhase.reconnecting;
    nextRetryAt = _now().add(delay);
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (_wantConnected && !_disposed) _attempt();
    });
    notifyListeners();
  }

  /// 1 s, 2 s, 4 s, 8 s, then capped.
  @visibleForTesting
  static Duration backoffFor(int attempt, RoverTimings t) {
    final n = math.max(1, attempt);
    final ms = t.backoffBase.inMilliseconds * math.pow(2, math.min(n - 1, 16));
    return Duration(milliseconds: math.min(ms.toInt(), t.backoffMax.inMilliseconds));
  }

  void _checkWatchdog(int gen) {
    if (gen != _session || !isConnected) return;
    final ref = lastTelemetryAt ?? _connectedAt;
    if (ref != null && _now().difference(ref) > timings.dropAfter) {
      _onLost(gen, 'No data from rover for ${timings.dropAfter.inSeconds} s');
      return;
    }
    final stale = isStale;
    if (stale != _wasStale) {
      _wasStale = stale;
      if (stale) _log('Signal weak: no telemetry', Severity.warning);
      notifyListeners();
    }
  }

  Future<void> _teardown() async {
    _heartbeat?.cancel();
    _watchdog?.cancel();
    _heartbeat = null;
    _watchdog = null;
    final link = _link;
    _link = null;
    _connectedAt = null;
    final cancelled = _sub?.cancel();
    _sub = null;
    await cancelled;
    await link?.close();
  }

  static String _friendly(Object e) {
    if (e is TimeoutException) {
      return 'The rover did not answer. Join the ATHER-ROVER Wi-Fi and check the rover is on.';
    }
    return 'Could not reach the rover. Join the ATHER-ROVER Wi-Fi and check the address in Settings.';
  }

  // ================= incoming =================

  void _onLine(String line) {
    final t = Telemetry.tryParse(line);
    if (t == null) {
      badFrames++;
      return;
    }
    final now = _now();
    final prev = telemetry;

    if (prev == null) {
      if (!t.selfTest.passed && t.selfTest != SelfTest.none) {
        _log(t.selfTest.message, Severity.warning);
      }
    } else if (prev.state != t.state) {
      _log('${t.state.label}: ${t.state.detail}', t.state.severity);
    }
    if (prev != null && prev.activity != t.activity && t.activity != Activity.none) {
      _log(t.activity.label, Severity.info);
    }

    telemetry = t;
    lastTelemetryAt = now;
    if (now.difference(_trimSentAt) > timings.echoHold) trim = t.trim;
    if (now.difference(_modeSentAt) > timings.echoHold) mode = t.mode;

    _history.add(VoltSample(now, t.volts));
    if (_history.length > historyLength) _history.removeAt(0);

    if (_wasStale) {
      _wasStale = false;
      _log('Signal back', Severity.good);
    }
    notifyListeners();
  }

  // ================= outgoing =================

  bool _send(String msg) {
    final link = _link;
    if (link == null) return false;
    try {
      link.send(msg);
      return true;
    } catch (_) {
      _onLost(_session, 'Send failed');
      return false;
    }
  }

  void _sendDrive() => _send(Commands.drive(_input.x, _input.y));

  /// Latest stick or tilt position. Sent on the next heartbeat.
  void drive(DriveInput input) {
    _input = canDrive ? input : DriveInput.zero;
  }

  /// Immediate stop, also cancels any playback on the rover.
  void stop() {
    _input = DriveInput.zero;
    _send(Commands.stop);
  }

  void setMode(RideMode m) {
    mode = m;
    _modeSentAt = _now();
    _send(Commands.mode(m));
    _log('Mode: ${m.label}', Severity.info);
    notifyListeners();
  }

  /// Moves the trim value locally while the slider is dragged. Nothing is
  /// sent, because the rover writes trim to flash on every `R` command.
  void previewTrim(double value) {
    trim = value.clamp(-Commands.trimLimit, Commands.trimLimit);
    _trimSentAt = _now();
    notifyListeners();
  }

  /// Sends and saves the trim (call when the slider is released).
  void setTrim(double value) {
    trim = value.clamp(-Commands.trimLimit, Commands.trimLimit);
    _trimSentAt = _now();
    _send(Commands.trim(trim));
    notifyListeners();
  }

  void turbo() => _send(Commands.turbo);
  void find() => _send(Commands.find);

  void toggleRecord() => _send(
      telemetry?.activity == Activity.recording ? Commands.recordStop : Commands.recordStart);

  void togglePlay() => _send(
      telemetry?.activity == Activity.playing ? Commands.playStop : Commands.playStart);

  void resetTrip() {
    _history.clear();
    _send(Commands.resetTrip);
    _log('Trip reset', Severity.info);
    notifyListeners();
  }

  void clearEvents() {
    _events.clear();
    notifyListeners();
  }

  void _log(String message, Severity severity) {
    _events.insert(0, RoverEvent(_now(), message, severity));
    if (_events.length > eventLimit) _events.removeLast();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _wantConnected = false;
    _retryTimer?.cancel();
    _session++;
    _teardown();
    super.dispose();
  }
}
