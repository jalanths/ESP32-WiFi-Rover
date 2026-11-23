/// Plain-text protocol shared with rover_firmware.ino (firmware 2.0).
///
/// This file has no Flutter imports so it can be unit-tested with plain Dart.
library;

/// Ride modes. The index is what the firmware expects in `M,<n>`.
enum RideMode {
  eco('Eco', 40),
  ride('Ride', 70),
  sport('Sport', 100);

  const RideMode(this.label, this.maxPowerPercent);

  final String label;
  final int maxPowerPercent;

  static RideMode? fromIndex(int? i) =>
      (i != null && i >= 0 && i < values.length) ? values[i] : null;
}

/// Severity drives the colour of the status banner.
enum Severity { good, info, warning, danger }

/// Rover safety state, the 5th telemetry field.
enum RoverState {
  ok('OK', 'Ready', 'All systems normal', Severity.good),
  failsafe('FAILSAFE', 'Waiting for app', 'No commands received, motors held off',
      Severity.info),
  limp('LIMP', 'Limp mode', 'Battery low, power limited', Severity.warning),
  lowBatt('LOWBATT', 'Battery empty', 'Motors cut at 3.6 V. Charge the battery.',
      Severity.danger),
  overload('OVERLOAD', 'Motor overload', 'Stalled or blocked, power reduced',
      Severity.warning),
  fault('FAULT', 'Driver fault', 'Motor driver reported a fault', Severity.danger),
  sleep('SLEEP', 'Sleeping', 'Idle for 5 minutes. Move the joystick to wake.',
      Severity.info),
  unknown('?', 'Unknown', 'Unrecognised state from rover', Severity.warning);

  const RoverState(this.code, this.label, this.detail, this.severity);

  final String code;
  final String label;
  final String detail;
  final Severity severity;

  static RoverState parse(String code) => values.firstWhere(
        (s) => s.code == code,
        orElse: () => RoverState.unknown,
      );
}

/// Result of the power-on self-test, the 7th field.
enum SelfTest {
  ok('OK', 'Self-test passed'),
  battSense('BATT_SENSE', 'Battery sense wire not detected'),
  battLow('BATT_LOW', 'Battery low at power-on'),
  driver('DRIVER', 'Motor driver check failed'),
  none('', 'Self-test not reported');

  const SelfTest(this.code, this.message);

  final String code;
  final String message;

  bool get passed => this == SelfTest.ok;

  static SelfTest parse(String code) =>
      values.firstWhere((s) => s.code == code, orElse: () => SelfTest.none);
}

/// What the rover is doing right now, the 13th field.
enum Activity {
  none('-', ''),
  turbo('TURBO', 'Turbo'),
  cooldown('COOL', 'Turbo cooling'),
  recording('REC', 'Recording'),
  playing('PLAY', 'Replaying');

  const Activity(this.code, this.label);

  final String code;
  final String label;

  static Activity parse(String code) =>
      values.firstWhere((a) => a.code == code, orElse: () => Activity.none);
}

/// One telemetry frame:
/// `T,volts,pct,mode,state,fw,trim,selftest,rangeMin,driveSec,minV,usedPct,activity,pathSec`
///
/// Older firmware sends fewer fields; missing ones get safe defaults.
class Telemetry {
  const Telemetry({
    required this.volts,
    required this.percent,
    required this.mode,
    required this.state,
    required this.firmware,
    this.trim = 0,
    this.selfTest = SelfTest.none,
    this.rangeMinutes,
    this.driveSeconds = 0,
    this.minVolts,
    this.usedPercent = 0,
    this.activity = Activity.none,
    this.pathSeconds = 0,
    this.hasTripData = false,
  });

  final double volts;
  final int percent;
  final RideMode mode;
  final RoverState state;
  final String firmware;
  final double trim;
  final SelfTest selfTest;

  /// null while the rover is still learning the drain rate.
  final int? rangeMinutes;
  final int driveSeconds;
  final double? minVolts;
  final int usedPercent;
  final Activity activity;
  final int pathSeconds;

  /// True when the rover sent the full firmware 2.0 frame.
  final bool hasTripData;

  static const int minFields = 6;
  static const int fullFields = 14;

  /// Returns null for anything that is not a well-formed telemetry line.
  static Telemetry? tryParse(String line) {
    final p = line.trim().split(',');
    if (p.length < minFields || p[0] != 'T') return null;

    final volts = double.tryParse(p[1]);
    final pct = int.tryParse(p[2]);
    final mode = RideMode.fromIndex(int.tryParse(p[3]));
    if (volts == null || pct == null || mode == null) return null;
    if (volts.isNaN || volts < 0 || volts > 10) return null;

    String at(int i) => i < p.length ? p[i] : '';
    final range = int.tryParse(at(8));

    return Telemetry(
      volts: volts,
      percent: pct.clamp(0, 100),
      mode: mode,
      state: RoverState.parse(p[4]),
      firmware: p[5],
      trim: (double.tryParse(at(6)) ?? 0).clamp(-Commands.trimLimit, Commands.trimLimit),
      selfTest: SelfTest.parse(at(7)),
      rangeMinutes: (range == null || range < 0) ? null : range,
      driveSeconds: int.tryParse(at(9)) ?? 0,
      minVolts: double.tryParse(at(10)),
      usedPercent: int.tryParse(at(11)) ?? 0,
      activity: Activity.parse(at(12)),
      pathSeconds: int.tryParse(at(13)) ?? 0,
      hasTripData: p.length >= fullFields,
    );
  }
}

/// Builds the app -> rover messages. Every value is clamped so a UI bug can
/// never send something the firmware would misread.
class Commands {
  Commands._();

  static const double trimLimit = 0.30;

  static String drive(double x, double y) =>
      'D,${_fmt(x.clamp(-1.0, 1.0))},${_fmt(y.clamp(-1.0, 1.0))}';
  static String mode(RideMode m) => 'M,${m.index}';
  static const String stop = 'S';
  static String trim(double t) => 'R,${_fmt(t.clamp(-trimLimit, trimLimit))}';
  static const String turbo = 'B';
  static const String find = 'F';
  static const String recordStart = 'P,R';
  static const String recordStop = 'P,S';
  static const String playStart = 'P,P';
  static const String playStop = 'P,X';
  static const String resetTrip = 'Z';

  // "-0.00" would look odd in logs; normalise it.
  static String _fmt(double v) {
    final s = v.toStringAsFixed(2);
    return s == '-0.00' ? '0.00' : s;
  }
}

/// Accepts dotted IPv4 addresses and plain host names.
String? validateHost(String? input) {
  final h = (input ?? '').trim();
  if (h.isEmpty) return 'Enter the rover address';
  final ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');
  final m = ipv4.firstMatch(h);
  if (m != null) {
    for (var i = 1; i <= 4; i++) {
      if (int.parse(m.group(i)!) > 255) return 'Each number must be 0 to 255';
    }
    return null;
  }
  final name = RegExp(r'^[A-Za-z0-9]([A-Za-z0-9-]{0,62}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,62}[A-Za-z0-9])?)*$');
  if (RegExp(r'^[\d.]+$').hasMatch(h) || !name.hasMatch(h)) {
    return 'Not a valid IP address or host name';
  }
  return null;
}
