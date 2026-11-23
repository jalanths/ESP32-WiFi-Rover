import 'package:flutter/material.dart';

import 'state/rover_controller.dart';
import 'state/settings_controller.dart';
import 'ui/app_scope.dart';
import 'ui/home_shell.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/theme.dart';

class RoverApp extends StatefulWidget {
  const RoverApp({
    super.key,
    required this.rover,
    required this.settings,
    this.autoConnect = true,
  });

  final RoverController rover;
  final SettingsController settings;

  /// Tests turn this off so nothing tries to open a socket.
  final bool autoConnect;

  @override
  State<RoverApp> createState() => _RoverAppState();
}

class _RoverAppState extends State<RoverApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.autoConnect && widget.settings.value.onboarded) {
      widget.rover.connect(host: widget.settings.value.host);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Safety: stop the rover whenever the app leaves the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      widget.rover.stop();
    }
  }

  void _finishOnboarding() {
    widget.settings.setOnboarded();
    if (widget.autoConnect) widget.rover.connect(host: widget.settings.value.host);
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      rover: widget.rover,
      settings: widget.settings,
      child: ListenableBuilder(
        listenable: widget.settings,
        builder: (context, _) {
          final s = widget.settings.value;
          return MaterialApp(
            title: 'Ather Rover',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light),
            darkTheme: buildTheme(Brightness.dark),
            themeMode: s.themeMode,
            home: s.onboarded
                ? const HomeShell()
                : OnboardingScreen(onDone: _finishOnboarding),
          );
        },
      ),
    );
  }
}
