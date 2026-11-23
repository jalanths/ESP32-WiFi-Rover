# Ather hackathon rover: ESP32 firmware + Flutter app

The rover creates its own Wi-Fi network. The phone joins it and the app drives the rover over a WebSocket. No internet and no router needed.

```
Phone (Flutter app) --Wi-Fi, WebSocket port 81--> ESP32 --PWM--> DRV8833 --> 2 motors
```

## 1. Flash the firmware (laptop)

1. Arduino IDE, install **esp32 by Espressif, version 3.x** (the code uses the 3.x `ledcAttach` API).
2. Library Manager: install **WebSockets** by Markus Sattler.
3. Open `firmware/rover_firmware/rover_firmware.ino`. Board: **ESP32 Dev Module**.
4. If you did not fit the two 100k battery resistors on GPIO34, set `HAVE_DIVIDER = false`.
5. Upload (battery switch OFF while the USB cable is connected).

Pins (same as the wiring picture): IN1=32, IN2=33, IN3=25, IN4=26, battery sense=34, SLP to 3V3.
If a motor spins backwards, swap its two wires or set `INVERT_A` / `INVERT_B`.

Wi-Fi name `Ather`, password `123456789` (change both at the top of the file).

## 2. Build the app

```bash
cd app
flutter create . --project-name ather_rover --platforms android,ios
flutter pub get
flutter run
```

`flutter create .` adds the android/ and ios/ folders and keeps `lib/` and `pubspec.yaml`.
Needs Flutter 3.22 or newer.

For a release APK on Android, add this line inside `<manifest>` in `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

## 3. Use it

1. Power the rover. On the phone, join Wi-Fi `Ather`.
2. If the phone says the network has no internet, choose to stay connected, and turn **mobile data off** so Android does not route the app away from the rover.
3. Open the app. It connects to `192.168.4.1:81` by itself. The address can be changed with the top-right icon.
4. Joystick drives, STOP stops, Eco / Ride / Sport sets power limit and acceleration.

## Behaviour

| Feature | Detail |
|---|---|
| Fail-safe | No command for 400 ms stops the motors. The app sends a heartbeat every 50 ms. |
| Ride modes | Eco 40% power, Ride 70%, Sport 100%, each with its own acceleration ramp. |
| Limp mode | Below 3.5 V the power is capped at 30%. |
| Battery cut-off | Below 3.3 V the motors stop and stay stopped until the rover is rebooted. |
| OTA update | Arduino OTA: join the rover Wi-Fi on the laptop, pick the network port `ather-rover` in Arduino IDE, upload. Motors stop when an update starts. |

The app itself does not push firmware; the update is sent from the laptop.

## Protocol (plain text)

App to rover: `D,<x>,<y>` drive (-1..1), `M,<0|1|2>` mode, `S` stop.
Rover to app, twice a second: `T,<volts>,<percent>,<mode>,<state>,<fw>`.

## What was and was not tested

Tested here: the firmware compiles cleanly against stand-in Arduino headers, and a simulation of its logic passed (drive directions, mode limits, fail-safe, telemetry format, battery cut-off).
Not tested: the Flutter app (no Flutter SDK available where this was written) and everything on real hardware. Run `flutter analyze` first and fix anything it reports.
