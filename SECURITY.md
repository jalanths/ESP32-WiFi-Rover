# Security

This is a hobby robot meant for local use. Known limitations:

| Area | Current behaviour | How to harden it |
|---|---|---|
| Wi-Fi access point | WPA2 with the default password `rover1234` | Change `AP_PASS` in `firmware/rover_firmware/rover_firmware.ino` (8+ characters) |
| WebSocket control (port 81) | No authentication beyond joining the Wi-Fi | Keep the AP password private |
| OTA updates | `ArduinoOTA` with **no password** | Add `ArduinoOTA.setPassword("...")` before `ArduinoOTA.begin()` |
| Web page (port 80) | Plain HTTP on the local AP | Acceptable for a local AP |

## Reporting a problem

Please open a GitHub issue. For anything sensitive, contact the maintainer through their GitHub profile instead of a public issue.
