import 'dart:async';

import 'package:ather_rover/core/drive_math.dart';
import 'package:ather_rover/core/protocol.dart';
import 'package:ather_rover/core/transport.dart';
import 'package:ather_rover/state/rover_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const fast = RoverTimings(
  heartbeat: Duration(milliseconds: 10),
  connectTimeout: Duration(milliseconds: 100),
  staleAfter: Duration(milliseconds: 120),
  dropAfter: Duration(milliseconds: 400),
  watchdog: Duration(milliseconds: 20),
  backoffBase: Duration(milliseconds: 30),
  backoffMax: Duration(milliseconds: 60),
  echoHold: Duration(milliseconds: 150),
);

Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

const okFrame = 'T,3.98,78,1,OK,2.0,0.00,OK,-1,0,3.98,0,-,0';

void main() {
  late FakeNetwork net;
  late RoverController rover;
  RoverController? created;

  void make(List<bool> plan) {
    net = FakeNetwork(plan);
    rover = RoverController(opener: net.open, timings: fast);
    created = rover;
  }

  tearDown(() {
    created?.dispose();
    created = null;
  });

  test('connects, sends the mode first, then heartbeats', () async {
    make([true]);
    await rover.connect();
    expect(rover.phase, LinkPhase.connected);
    await wait(60);
    final sent = net.links.single.sent;
    expect(sent.first, 'M,1');
    expect(sent.where((m) => m == 'D,0.00,0.00').length, greaterThanOrEqualTo(3));
  });

  test('joystick input goes out on the heartbeat', () async {
    make([true]);
    await rover.connect();
    net.links.single.push(okFrame);
    await wait(5);
    rover.drive(const DriveInput(0.5, -0.25));
    await wait(40);
    expect(net.links.single.sent, contains('D,0.50,-0.25'));
  });

  test('parses telemetry, keeps history and logs state changes', () async {
    make([true]);
    await rover.connect();
    final link = net.links.single;
    link.push(okFrame);
    link.push('T,3.68,20,1,LIMP,2.0,0.00,OK,-1,30,3.68,10,-,0');
    link.push('garbage');
    await wait(10);
    expect(rover.telemetry!.state, RoverState.limp);
    expect(rover.history.length, 2);
    expect(rover.badFrames, 1);
    expect(rover.events.first.message, startsWith('Limp mode'));
  });

  test('LOWBATT blocks driving', () async {
    make([true]);
    await rover.connect();
    net.links.single.push('T,3.55,0,1,LOWBATT,2.0,0.00,OK,-1,0,3.55,0,-,0');
    await wait(10);
    expect(rover.canDrive, isFalse);
    rover.drive(const DriveInput(1, 1));
    expect(rover.currentInput, DriveInput.zero);
  });

  test('trim echo from the rover does not snap the slider back', () async {
    make([true]);
    await rover.connect();
    final link = net.links.single;
    rover.setTrim(0.10);
    expect(link.sent, contains('R,0.10'));
    link.push(okFrame); // still reports 0.00
    await wait(10);
    expect(rover.trim, 0.10);
    await wait(200);
    link.push(okFrame);
    await wait(10);
    expect(rover.trim, 0.0);
  });

  test('previewTrim moves locally without sending', () async {
    make([true]);
    await rover.connect();
    rover.previewTrim(0.2);
    expect(rover.trim, closeTo(0.2, 1e-9));
    expect(net.links.single.sent.where((m) => m.startsWith('R,')), isEmpty);
  });

  test('retries with backoff until the rover answers', () async {
    make([false, false, true]);
    await rover.connect();
    expect(rover.phase, LinkPhase.reconnecting);
    expect(rover.errorMessage, isNotNull);
    await wait(250);
    expect(net.attempts, 3);
    expect(rover.phase, LinkPhase.connected);
    expect(rover.retryAttempt, 0);
  });

  test('reconnects after the link drops', () async {
    make([true, true]);
    await rover.connect();
    net.links.first.drop();
    await wait(10);
    expect(rover.phase, LinkPhase.reconnecting);
    await wait(120);
    expect(rover.phase, LinkPhase.connected);
    expect(net.links.length, 2);
    expect(net.links.first.closed, isTrue);
  });

  test('goes stale, then drops a silent link', () async {
    make([true, true]);
    await rover.connect();
    expect(rover.isStale, isFalse);
    await wait(200);
    expect(rover.isStale, isTrue);
    await wait(350);
    expect(net.attempts, greaterThanOrEqualTo(2)); // watchdog forced a reconnect
  });

  test('disconnect sends STOP and stays offline', () async {
    make([true]);
    await rover.connect();
    final link = net.links.single;
    await rover.disconnect();
    expect(link.sent.last, 'S');
    expect(link.closed, isTrue);
    await wait(150);
    expect(rover.phase, LinkPhase.disconnected);
    expect(net.attempts, 1);
  });

  test('record and play toggle on the rover activity', () async {
    make([true]);
    await rover.connect();
    final link = net.links.single;
    rover.toggleRecord();
    link.push('T,3.98,78,1,OK,2.0,0.00,OK,-1,0,3.98,0,REC,3');
    await wait(10);
    rover.toggleRecord();
    rover.togglePlay();
    expect(link.sent, containsAllInOrder(['P,R', 'P,S', 'P,P']));
  });

  test('a connect attempt that never answers still times out and retries', () async {
    var calls = 0;
    final never = Completer<RoverLink>(); // never completes
    rover = RoverController(
      opener: (uri, timeout) {
        calls++;
        return never.future;
      },
      timings: const RoverTimings(
        connectTimeout: Duration(milliseconds: 100), // own deadline = 200 ms
        backoffBase: Duration(milliseconds: 300),
      ),
    );
    created = rover;
    unawaited(rover.connect());
    await wait(300); // past the 200 ms deadline, before the retry
    expect(rover.phase, LinkPhase.reconnecting);
    expect(rover.errorMessage, isNotNull);
    expect(calls, 1);
    await wait(400); // retry has started
    expect(calls, greaterThanOrEqualTo(2));
  });

  test('backoff doubles and is capped', () {
    const t = RoverTimings();
    expect(RoverController.backoffFor(1, t), const Duration(seconds: 1));
    expect(RoverController.backoffFor(2, t), const Duration(seconds: 2));
    expect(RoverController.backoffFor(4, t), const Duration(seconds: 8));
    expect(RoverController.backoffFor(9, t), const Duration(seconds: 10));
  });
}
