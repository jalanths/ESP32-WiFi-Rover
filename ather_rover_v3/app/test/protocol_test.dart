import 'package:ather_rover/core/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Telemetry.tryParse', () {
    test('parses a full firmware 2.0 frame', () {
      final t = Telemetry.tryParse('T,3.98,78,1,OK,2.0,0.05,OK,42,125,3.81,6,TURBO,12')!;
      expect(t.volts, 3.98);
      expect(t.percent, 78);
      expect(t.mode, RideMode.ride);
      expect(t.state, RoverState.ok);
      expect(t.firmware, '2.0');
      expect(t.trim, closeTo(0.05, 1e-9));
      expect(t.selfTest, SelfTest.ok);
      expect(t.rangeMinutes, 42);
      expect(t.driveSeconds, 125);
      expect(t.minVolts, 3.81);
      expect(t.usedPercent, 6);
      expect(t.activity, Activity.turbo);
      expect(t.pathSeconds, 12);
      expect(t.hasTripData, isTrue);
    });

    test('range -1 means still learning', () {
      final t = Telemetry.tryParse('T,4.10,95,0,OK,2.0,0.00,OK,-1,0,4.10,0,-,0')!;
      expect(t.rangeMinutes, isNull);
      expect(t.activity, Activity.none);
    });

    test('accepts an old 6-field frame with defaults', () {
      final t = Telemetry.tryParse('T,3.70,30,2,LIMP,1.2')!;
      expect(t.state, RoverState.limp);
      expect(t.mode, RideMode.sport);
      expect(t.selfTest, SelfTest.none);
      expect(t.hasTripData, isFalse);
    });

    test('every firmware state maps to a known enum', () {
      for (final code in ['OK', 'FAILSAFE', 'LIMP', 'LOWBATT', 'OVERLOAD', 'FAULT', 'SLEEP']) {
        expect(RoverState.parse(code), isNot(RoverState.unknown), reason: code);
      }
      expect(RoverState.parse('BANANA'), RoverState.unknown);
    });

    test('rejects malformed input', () {
      expect(Telemetry.tryParse(''), isNull);
      expect(Telemetry.tryParse('hello'), isNull);
      expect(Telemetry.tryParse('X,3.9,50,1,OK,2.0'), isNull); // wrong tag
      expect(Telemetry.tryParse('T,abc,50,1,OK,2.0'), isNull); // bad volts
      expect(Telemetry.tryParse('T,3.9,50,7,OK,2.0'), isNull); // bad mode
      expect(Telemetry.tryParse('T,3.9,50'), isNull); // too short
      expect(Telemetry.tryParse('T,99,50,1,OK,2.0'), isNull); // impossible volts
    });

    test('clamps percent and trim into range', () {
      final t = Telemetry.tryParse('T,4.3,140,1,OK,2.0,0.9,OK')!;
      expect(t.percent, 100);
      expect(t.trim, Commands.trimLimit);
    });
  });

  group('Commands', () {
    test('drive clamps and formats to 2 dp', () {
      expect(Commands.drive(0.5, -0.25), 'D,0.50,-0.25');
      expect(Commands.drive(3, -9), 'D,1.00,-1.00');
      expect(Commands.drive(-0.001, 0), 'D,0.00,0.00');
    });

    test('mode, trim and fixed commands match the firmware', () {
      expect(Commands.mode(RideMode.eco), 'M,0');
      expect(Commands.mode(RideMode.sport), 'M,2');
      expect(Commands.trim(0.123), 'R,0.12');
      expect(Commands.trim(-1), 'R,-0.30');
      expect(Commands.stop, 'S');
      expect(Commands.turbo, 'B');
      expect(Commands.find, 'F');
      expect(Commands.recordStart, 'P,R');
      expect(Commands.recordStop, 'P,S');
      expect(Commands.playStart, 'P,P');
      expect(Commands.playStop, 'P,X');
      expect(Commands.resetTrip, 'Z');
    });
  });

  group('validateHost', () {
    test('accepts IPs and host names', () {
      expect(validateHost('192.168.4.1'), isNull);
      expect(validateHost(' 10.0.0.25 '), isNull);
      expect(validateHost('rover.local'), isNull);
      expect(validateHost('esp32'), isNull);
    });

    test('rejects bad input', () {
      expect(validateHost(''), isNotNull);
      expect(validateHost(null), isNotNull);
      expect(validateHost('192.168.4.256'), isNotNull);
      expect(validateHost('192.168.4'), isNotNull);
      expect(validateHost('http://192.168.4.1'), isNotNull);
      expect(validateHost('bad host'), isNotNull);
    });
  });
}
