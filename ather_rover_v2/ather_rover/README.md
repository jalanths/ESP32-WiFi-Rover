# Ather rover: ESP32 firmware + Flutter app

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

Wi-Fi name `ATHER-ROVER`, password `rover1234` (change both at the top of the file).

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

1. Power the rover. On the phone, join Wi-Fi `ATHER-ROVER`.
2. If the phone says the network has no internet, choose to stay connected, and turn **mobile data off** so Android does not route the app away from the rover.
3. Open the app. It connects to `192.168.4.1:81` by itself. The address can be changed with the top-right icon.
4. Joystick drives, STOP stops, Eco / Ride / Sport sets power limit and acceleration.

## Behaviour (firmware 2.0)

| Feature | Detail |
|---|---|
| Fail-safe | No command for 400 ms stops the motors. The app sends a heartbeat every 50 ms. |
| Ride modes | Eco 40%, Ride 70%, Sport 100% top power, each with its own acceleration. Small commands start at 45% so the wheels always turn (`MIN_POWER`). |
| Battery | Below 3.70 V: limp mode (30% power). Below 3.60 V for 3 s: motors stop until restart. |
| Overload guard | Full power + battery sagging 0.25 V below rest for 2 s = wheels likely jammed: power capped at 40% for 3 s. Estimated from voltage; the kit has no current sensor. Optional: wire the DRV8833 fault pin and set `PIN_FAULT`. |
| Self-test | At power-up each wheel twitches, the battery reading is checked. Result shows in the app. Both LEDs flash 5 times if something is wrong. |
| Straight-line trim | Tune icon in the app (slider on the web page). Saved on the rover. |
| Range and trip | Drive time, minimum voltage, battery used and minutes left (appears after about a minute of driving with short pauses). Reset trip clears them. |
| Turbo | 3 s full power, then 10 s cool-down. Cancelled by low battery or overload. |
| Sharp turns | Up to 35% less power when steering hard (`TURN_SLOWDOWN`). |
| Auto-stop | After 5 min without driving the rover sleeps (LEDs glow gently). Move the joystick to wake it. |
| Recorded paths | Record up to 60 s, then Play. Moving the joystick or STOP cancels a replay. Open-loop: it drifts as the battery drains. |
| Lights | Front blinks when turning, rear blinks when reversing, front strobes in turbo, both flash for Find. |
| Tilt steering | App only. Rotate icon in the app bar; the phone's position when you switch it on is "neutral". If it steers backwards, flip `kTiltSteerSign` / `kTiltThrottleSign` in `main.dart`. |
| Battery graph | Last minute of voltage, with lines at 3.7 V and 3.6 V. |
| OTA update | Arduino OTA from the laptop: join the rover Wi-Fi, pick network port `ather-rover`, upload. |

The direction settings `INVERT_B = true` and `SWAP_SIDES = true` match the current rover's wiring.

## Protocol (plain text)

App to rover: `D,<x>,<y>` drive, `M,<0|1|2>` mode, `S` stop, `R,<trim>` trim, `B` turbo, `F` find,
`P,R` / `P,S` record start/stop, `P,P` / `P,X` play/stop, `Z` reset trip.

Rover to app, twice a second:
`T,<volts>,<percent>,<mode>,<state>,<fw>,<trim>,<selftest>,<rangeMin>,<driveSec>,<minV>,<usedPct>,<activity>,<pathSec>`

## iOS

Tilt steering needs `NSMotionUsageDescription` in `ios/Runner/Info.plist`, or the app crashes when tilt is switched on.

## What was and was not tested

Tested here: the firmware compiles cleanly against stand-in Arduino headers, and simulations of every feature above passed. The web page JavaScript was run with sample telemetry.
Not tested: the Flutter app (no Flutter SDK available where this was written) and everything on real hardware. Run `flutter analyze` first and fix anything it reports.
