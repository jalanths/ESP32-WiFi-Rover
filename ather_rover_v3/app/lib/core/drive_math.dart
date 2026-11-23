/// Joystick and tilt shaping. Pure Dart, unit-tested.
library;

import 'dart:math' as math;

/// Values smaller than [deadZone] become 0; the rest is rescaled so the
/// output still reaches 1.0 at full deflection (no jump at the edge).
double applyDeadZone(double v, double deadZone) {
  final dz = deadZone.clamp(0.0, 0.9);
  final a = v.abs();
  if (a <= dz) return 0;
  final out = (a - dz) / (1 - dz);
  return (v.isNegative ? -out : out).clamp(-1.0, 1.0);
}

/// Expo curve: softer near the centre for fine control, same end points.
/// [k] = 0 is linear, 1 is fully cubic.
double applyExpo(double v, double k) {
  final kk = k.clamp(0.0, 1.0);
  return ((1 - kk) * v + kk * v * v * v).clamp(-1.0, 1.0);
}

/// A drive command: x = steer (-1 left .. 1 right), y = throttle (-1 .. 1).
class DriveInput {
  const DriveInput(this.x, this.y);

  static const zero = DriveInput(0, 0);

  final double x;
  final double y;

  bool get isZero => x == 0 && y == 0;

  @override
  bool operator ==(Object other) =>
      other is DriveInput && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'DriveInput(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';
}

/// Turns a raw joystick offset (any length) into a shaped drive command.
DriveInput shapeJoystick(double dx, double dy,
    {double deadZone = 0.08, double expo = 0.3}) {
  var x = dx, y = dy;
  final len = math.sqrt(x * x + y * y);
  if (len > 1) {
    x /= len;
    y /= len;
  }
  return DriveInput(
    applyExpo(applyDeadZone(x, deadZone), expo),
    applyExpo(applyDeadZone(y, deadZone), expo),
  );
}

/// Tilt steering. Phone held flat in landscape, screen up.
/// Accelerometer x/y are m/s^2 relative to the pose captured when tilt was
/// switched on ([neutralX], [neutralY]). [fullScale] is how much tilt (m/s^2)
/// gives full output; about 5 m/s^2 is roughly 30 degrees.
///
/// The signs match the v2 app that was tested on the real rover.
DriveInput tiltToDrive({
  required double ax,
  required double ay,
  required double neutralX,
  required double neutralY,
  double fullScale = 5.0,
  double deadZone = 0.12,
}) {
  final fs = fullScale <= 0 ? 5.0 : fullScale;
  final steer = (-(ax - neutralX) / fs).clamp(-1.0, 1.0);
  final throttle = (-(ay - neutralY) / fs).clamp(-1.0, 1.0);
  return DriveInput(applyDeadZone(steer, deadZone), applyDeadZone(throttle, deadZone));
}

/// Formats seconds as "m:ss" or "h:mm:ss".
String formatDuration(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, r = s % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(r)}' : '$m:${two(r)}';
}
