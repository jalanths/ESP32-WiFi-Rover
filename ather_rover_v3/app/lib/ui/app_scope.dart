import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../state/rover_controller.dart';
import '../state/settings_controller.dart';

/// Hands the two controllers to every screen without a state package.
/// Widgets rebuild by wrapping parts in ListenableBuilder.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.rover,
    required this.settings,
    required super.child,
  });

  final RoverController rover;
  final SettingsController settings;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing above this widget');
    return scope!;
  }

  /// For callbacks (button presses): reads without subscribing to rebuilds.
  static AppScope read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      rover != oldWidget.rover || settings != oldWidget.settings;
}

/// Haptic feedback that respects the user's setting.
class Haptics {
  Haptics._();

  static void tap(BuildContext context) {
    if (AppScope.read(context).settings.value.haptics) HapticFeedback.selectionClick();
  }

  static void medium(BuildContext context) {
    if (AppScope.read(context).settings.value.haptics) HapticFeedback.mediumImpact();
  }

  static void heavy(BuildContext context) {
    if (AppScope.read(context).settings.value.haptics) HapticFeedback.heavyImpact();
  }
}
