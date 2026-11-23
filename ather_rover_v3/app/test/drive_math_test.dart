import 'package:ather_rover/core/drive_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('applyDeadZone', () {
    test('zeroes small values and keeps full scale', () {
      expect(applyDeadZone(0.05, 0.1), 0);
      expect(applyDeadZone(-0.1, 0.1), 0);
      expect(applyDeadZone(1, 0.1), closeTo(1, 1e-9));
      expect(applyDeadZone(-1, 0.1), closeTo(-1, 1e-9));
      expect(applyDeadZone(0.55, 0.1), closeTo(0.5, 1e-9));
    });

    test('is continuous at the edge (no jump)', () {
      expect(applyDeadZone(0.1001, 0.1), lessThan(0.001));
    });
  });

  group('applyExpo', () {
    test('keeps end points and centre', () {
      for (final k in [0.0, 0.3, 1.0]) {
        expect(applyExpo(0, k), 0);
        expect(applyExpo(1, k), closeTo(1, 1e-9));
        expect(applyExpo(-1, k), closeTo(-1, 1e-9));
      }
    });

    test('softens the middle', () {
      expect(applyExpo(0.5, 0.5), lessThan(0.5));
      expect(applyExpo(0.5, 0), 0.5);
    });
  });

  test('shapeJoystick limits to the unit circle', () {
    final d = shapeJoystick(3, 4, deadZone: 0, expo: 0);
    expect(d.x, closeTo(0.6, 1e-9));
    expect(d.y, closeTo(0.8, 1e-9));
    expect(shapeJoystick(0.02, -0.03), DriveInput.zero);
  });

  group('tiltToDrive', () {
    test('neutral pose gives zero', () {
      expect(tiltToDrive(ax: 1.2, ay: -0.4, neutralX: 1.2, neutralY: -0.4), DriveInput.zero);
    });

    test('signs match the tested v2 app', () {
      // tilt that lowers ax steers right; lowers ay drives forward
      final d = tiltToDrive(ax: -5, ay: -5, neutralX: 0, neutralY: 0, deadZone: 0);
      expect(d.x, closeTo(1, 1e-9));
      expect(d.y, closeTo(1, 1e-9));
    });

    test('lower full-scale is more sensitive and output is clamped', () {
      final soft = tiltToDrive(ax: -2, ay: 0, neutralX: 0, neutralY: 0, fullScale: 8, deadZone: 0);
      final hard = tiltToDrive(ax: -2, ay: 0, neutralX: 0, neutralY: 0, fullScale: 3, deadZone: 0);
      expect(hard.x, greaterThan(soft.x));
      expect(tiltToDrive(ax: -50, ay: 0, neutralX: 0, neutralY: 0).x, 1);
    });
  });

  test('formatDuration', () {
    expect(formatDuration(0), '0:00');
    expect(formatDuration(65), '1:05');
    expect(formatDuration(3725), '1:02:05');
    expect(formatDuration(-3), '0:00');
  });
}
