# Contributing

Thanks for your interest! This is a personal project, but issues and pull requests are welcome.

## Before you open a pull request

1. **Open an issue first** for anything bigger than a small fix, so we can agree on the approach.
2. **App changes:** run these from `app/`. All of them must pass. CI runs the same checks.
   ```bash
   flutter analyze
   flutter test
   ```
   Add or update tests for any behaviour you change.
3. **Firmware changes:** the sketch must compile for **ESP32 Dev Module** with esp32 core 3.x. If you change the protocol, also update `docs/protocol.md`, `app/lib/core/protocol.dart` and `app/test/protocol_test.dart`.
4. Keep the app and the firmware compatible, or bump both versions and note it in `CHANGELOG.md`.

## Style

- Dart: follow `analysis_options.yaml`. Keep the UI out of `lib/core/`.
- Arduino: put tunable settings as `const` at the top of the sketch, with a comment explaining each one.
- Commit messages: short imperative subject, for example `Fix reconnect when connect hangs`.

## Safety

Test motor changes with the wheels off the ground first. Never bypass the failsafe or the battery cut-off.
