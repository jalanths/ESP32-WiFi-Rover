import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ather_rover/main.dart';

void main() {
  testWidgets('Joystick reports full forward when dragged to the top',
      (tester) async {
    double? x, y;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Joystick(onChanged: (a, b) {
            x = a;
            y = b;
          }),
        ),
      ),
    ));
    final center = tester.getCenter(find.byType(Joystick));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(0, -20));
    await gesture.moveBy(const Offset(0, -200));
    await tester.pump();
    expect(x, closeTo(0, 0.01));
    expect(y, closeTo(1, 0.01));
    await gesture.up();
    await tester.pump();
    expect(x, 0);
    expect(y, 0);
  });
}
