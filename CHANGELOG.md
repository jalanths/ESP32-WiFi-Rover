# Changelog

All notable changes to this project are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [3.0.0] - 2026-11-23

### App
- Rebuilt with a layered architecture (core / state / ui), Material 3 light and dark themes, and Drive, Trip and Settings tabs with adaptive navigation.
- Animated battery ring, status banner, 60 s voltage chart with the limp and cut-off lines, and an event log.
- Joystick dead zone, expo and tilt sensitivity settings, all saved.
- Automatic reconnect with backoff, weak-signal warning, watchdog for a silent link, and a deadline for a connect attempt that never answers.
- STOP is pinned on screen. The rover is stopped when the app goes to the background.
- Trim is sent only when the slider is released, to save flash writes on the rover.
- 42 unit and widget tests.

### Fixed
- A failed connect attempt could leave the app on "Connecting..." forever.
- The voltage chart now extends below 3.4 V for a drained battery.
- The app bar title overflowed on narrow screens.

## [2.1.0] - firmware

- Resting-voltage estimate (motor sag learned while driving), so a short dip under load doesn't trigger limp mode or the cut-off.
- Brownout guard: power is eased back if the voltage under load drops below 3.2 V.
- Battery calibration command `C,<volts>`, saved in flash.
- 16-sample median-mean ADC filter. CPU at 80 MHz and Wi-Fi TX power at 13 dBm to save power.
- Telemetry adds `loadVolts` and `calib`.

## [2.0.0] - 2026-11-17

- Stall/overload guard, self-test, trim, range estimate, trip stats, turn and reverse lights, idle sleep, sharp-turn limit, turbo, path record and replay, and Find my rover.
- Flutter app v2 with tilt steering and a battery graph.

## [1.0.0] - 2026-11-16

- First drivable version: Wi-Fi AP, WebSocket joystick control, ride modes, failsafe and low-voltage cut-off.
