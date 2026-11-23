import 'package:ather_rover/app.dart';
import 'package:ather_rover/state/rover_controller.dart';
import 'package:ather_rover/state/settings_controller.dart';
import 'package:ather_rover/ui/widgets/voltage_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  SettingsController settingsWith({bool onboarded = true}) =>
      SettingsController(MemoryStore({'onboarded': onboarded}))..load();

  void phoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('first run shows the guide, Skip opens the drive screen', (tester) async {
    phoneSize(tester);
    final rover = RoverController(opener: FakeNetwork([true]).open);
    await tester.pumpWidget(
        RoverApp(rover: rover, settings: settingsWith(onboarded: false), autoConnect: false));
    await tester.pumpAndSettle();

    expect(find.text('Join the rover Wi-Fi'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('STOP'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // unmount before disposing
    rover.dispose();
  });

  testWidgets('bottom navigation switches between the three tabs', (tester) async {
    phoneSize(tester);
    final rover = RoverController(opener: FakeNetwork([true]).open);
    await tester.pumpWidget(RoverApp(rover: rover, settings: settingsWith(), autoConnect: false));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.text('Trip'));
    await tester.pumpAndSettle();
    expect(find.text('Drive time'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Rover address'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // unmount before disposing
    rover.dispose();
  });

  testWidgets('wide screens use a navigation rail', (tester) async {
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final rover = RoverController(opener: FakeNetwork([true]).open);
    await tester.pumpWidget(RoverApp(rover: rover, settings: settingsWith(), autoConnect: false));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.pumpWidget(const SizedBox()); // unmount before disposing
    rover.dispose();
  });

  testWidgets('live telemetry updates the dashboard and STOP is sent', (tester) async {
    phoneSize(tester);
    final net = FakeNetwork([true]);
    final rover = RoverController(opener: net.open);
    await tester.pumpWidget(RoverApp(rover: rover, settings: settingsWith(), autoConnect: false));
    // Real async for the socket side; widget time stays fake.
    await tester.runAsync(() async {
      await rover.connect();
      net.links.single.push('T,3.98,78,1,OK,2.0,0.00,OK,-1,0,3.98,0,-,0');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('78%'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);

    await tester.ensureVisible(find.text('STOP'));
    await tester.tap(find.text('STOP'));
    await tester.pump();
    expect(net.links.single.sent, contains('S'));

    await tester.runAsync(() => rover.disconnect());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox()); // unmount before disposing
    rover.dispose();
  });

  testWidgets('invalid address shows a validation message', (tester) async {
    phoneSize(tester);
    final rover = RoverController(opener: FakeNetwork([true]).open);
    await tester.pumpWidget(RoverApp(rover: rover, settings: settingsWith(), autoConnect: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '999.1.1.1');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Each number must be 0 to 255'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // unmount before disposing
    rover.dispose();
  });

  test('voltage chart floor drops for a drained battery', () {
    expect(VoltageChart.floorFor([3.9, 3.8]), 3.4);
    expect(VoltageChart.floorFor([3.3, 3.2]), closeTo(3.0, 1e-9));
    expect(VoltageChart.floorFor([2.87]), closeTo(2.6, 1e-9));
  });
}
