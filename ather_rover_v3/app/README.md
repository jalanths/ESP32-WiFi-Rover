# Ather Rover app v3.0

A Flutter controller app for the ESP32 hackathon rover. It talks to **rover firmware 2.0** over WebSocket port 81 using the same plain-text protocol as before, so you don't need to change the firmware.

## Run it

Copy `lib/`, `test/`, `pubspec.yaml` and `analysis_options.yaml` into your Flutter project, replacing the old ones. Or start a new project from this folder:

```
flutter create . --project-name ather_rover --platforms android,ios
flutter pub get
flutter analyze
flutter test
flutter run
```

You need Flutter 3.22 or newer.

**Android release APK:** add `<uses-permission android:name="android.permission.INTERNET"/>` inside `<manifest>` in `android/app/src/main/AndroidManifest.xml`.

**iOS:** add `NSMotionUsageDescription` to `ios/Runner/Info.plist`. Without it, the app crashes when you turn on tilt steering.

## Screens

| Screen | What it has |
|---|---|
| First-run guide | Three pages: join the Wi-Fi, how to drive, safety. You can open it again from Settings. |
| Drive | Animated battery ring, live status banner, Eco/Ride/Sport, Turbo/Record/Replay/Find, joystick with spring-back, tilt mode with a bubble indicator, big STOP button |
| Trip | Drive time, range, battery used, lowest voltage, path length, firmware and self-test; 60 s voltage chart with the 3.7 V and 3.6 V lines; event log; reset trip |
| Settings | Rover address with validation; connect and disconnect; dead zone, expo and tilt sensitivity; straight-line trim (saved on the rover); theme; haptics; about and licences |

## How it meets a standard app-development rubric

| Rubric area | Where it is done |
|---|---|
| **Architecture / separation of concerns** | `core/` is pure Dart: protocol, drive maths and transport interface. `state/` holds the controllers. `ui/` holds the widgets. The UI never touches sockets or parses strings. |
| **State management** | `ChangeNotifier` controllers, passed down by an `InheritedWidget` (`AppScope`). Only the parts that change rebuild, through `ListenableBuilder`. |
| **UI / UX design** | Material 3 with one seed colour, light and dark themes, an 8-point spacing scale, animated gauge, chart and status, a first-run guide, confirmation before reset, empty and loading states |
| **Responsive layout** | Bottom navigation bar on phones and a side rail at 600 dp and wider. The Drive screen splits into two columns in landscape. The joystick sizes itself from the space it gets. Stat tiles wrap. |
| **Accessibility** | `Semantics` labels on the gauge, chart, joystick, tilt view and tiles. Live-region status. Header semantics. Touch targets of 48 dp or more. Text scaling is respected (no fixed-height tiles). Colour is never the only signal (icon and text too). |
| **Error handling & resilience** | Connect timeout. Automatic reconnect with backoff (1, 2, 4, 8, 10 s). "Signal weak" warning after 1.5 s without data. A silent link is dropped after 5 s. Bad telemetry frames are counted and ignored. All outgoing values are clamped. Error messages are written for the user. |
| **Safety** | 50 ms heartbeat (firmware failsafe is 400 ms). STOP when the app goes to the background. Driving is blocked on LOWBATT and FAULT. Tilt turns off on STOP and when the sensor fails. |
| **Persistence** | `shared_preferences` behind a `KeyValueStore` interface. Corrupt or out-of-range stored values fall back to defaults. Trim is saved on the rover only when you release the slider, so flash isn't written on every drag step. |
| **Input validation** | IPv4 and host-name validator, shown inline in the form |
| **Testing** | Unit tests for the protocol, drive maths, settings and controller (connect, heartbeat, telemetry, backoff, reconnect, watchdog, disconnect, trim echo). Widget tests for onboarding, navigation, rail layout, live dashboard and form validation. A fake link means no hardware is needed. |
| **Code quality** | `flutter_lints` plus strict casts, strict raw types and extra rules in `analysis_options.yaml`. Doc comments on public APIs. No magic numbers in the UI (`Tokens`, `RoverTimings`). |
| **Performance** | `CustomPainter` with `shouldRepaint`, `IndexedStack` to keep tab state, `const` widgets, and the history is capped at 120 points |

## Files

```
lib/
  main.dart, app.dart           start-up, theme mode, lifecycle STOP
  core/protocol.dart            telemetry model + parser, command builder, host validator
  core/drive_math.dart          dead zone, expo, joystick shaping, tilt mapping
  core/transport.dart           RoverLink interface + WebSocket implementation
  state/rover_controller.dart   connection state machine, heartbeat, watchdog, event log
  state/settings_controller.dart persisted settings
  ui/theme.dart, app_scope.dart, home_shell.dart
  ui/screens/                   drive, trip, settings, onboarding
  ui/widgets/                   battery gauge, voltage chart, joystick, status widgets
test/                           5 test files + support/fakes.dart
```

## Testing status

This code has **not been compiled or run yet**. The Dart SDK couldn't be run in the environment where it was written. Run `flutter analyze` and `flutter test` first. If anything fails, send the output back.
