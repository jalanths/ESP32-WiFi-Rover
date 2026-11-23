// Battery voltage monitor: ESP32 reads the battery and shows it on a web page.
// Board: ESP32 Dev Module. No extra libraries needed.
//
// Wiring (two 100k resistors):
//   battery line after the switch -> 100k -> GPIO34 -> 100k -> GND
//
// Use:
//   1. Upload, then join Wi-Fi "ATHER-ROVER" (password rover1234) on a phone or laptop.
//   2. Open http://192.168.4.1 in a browser.

#include <WiFi.h>
#include <WebServer.h>

const char* AP_SSID = "ATHER-ROVER";
const char* AP_PASS = "rover1234";  // at least 8 characters

const int PIN_BATT = 34;      // divider midpoint
const float DIVIDER = 2.0f;   // two equal resistors halve the voltage
const float CALIBRATION = 1.00f;  // multimeter reading / page reading, if they differ
const float V_FULL = 4.15f;
const float V_EMPTY = 3.30f;

WebServer server(80);
float battV = 0;

const char PAGE[] = R"HTML(<!DOCTYPE html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Rover battery</title>
<style>
body{font-family:sans-serif;text-align:center;margin:40px 16px;background:#111;color:#eee}
#v{font-size:64px;margin:16px 0 4px}
#p{font-size:24px;color:#aaa}
#bar{height:18px;background:#333;border-radius:9px;max-width:320px;margin:24px auto;overflow:hidden}
#fill{height:100%;width:0;background:#1D9E75}
#s{color:#aaa}
</style></head><body>
<h2>Rover battery</h2>
<div id="v">-- V</div>
<div id="p">--%</div>
<div id="bar"><div id="fill"></div></div>
<div id="s">Connecting</div>
<script>
async function tick(){
  try{
    const r=await fetch('/data');const d=await r.json();
    document.getElementById('v').textContent=d.v.toFixed(2)+' V';
    document.getElementById('p').textContent=d.pct+'%';
    const f=document.getElementById('fill');
    f.style.width=d.pct+'%';
    f.style.background=d.v<3.5?'#E24B4A':'#1D9E75';
    document.getElementById('s').textContent=d.v<3.3?'Battery empty: switch off':d.v<3.5?'Battery low':'OK';
  }catch(e){document.getElementById('s').textContent='No connection';}
}
setInterval(tick,1000);tick();
</script></body></html>)HTML";

float readBattery() {
  long sum = 0;
  for (int i = 0; i < 16; i++) sum += analogReadMilliVolts(PIN_BATT);
  float pinVolts = (sum / 16.0f) / 1000.0f;
  return pinVolts * DIVIDER * CALIBRATION;
}

int batteryPercent(float v) {
  float p = (v - V_EMPTY) / (V_FULL - V_EMPTY) * 100.0f;
  if (p < 0) p = 0;
  if (p > 100) p = 100;
  return (int)p;
}

void handleRoot() {
  server.send(200, "text/html", PAGE);
}

void handleData() {
  char out[48];
  snprintf(out, sizeof(out), "{\"v\":%.2f,\"pct\":%d}", battV, batteryPercent(battV));
  server.send(200, "application/json", out);
}

void setup() {
  Serial.begin(115200);
  analogReadResolution(12);
  analogSetPinAttenuation(PIN_BATT, ADC_11db);

  WiFi.mode(WIFI_AP);
  WiFi.softAP(AP_SSID, AP_PASS);
  Serial.print("Open http://");
  Serial.println(WiFi.softAPIP());  // normally 192.168.4.1

  server.on("/", handleRoot);
  server.on("/data", handleData);
  server.begin();

  battV = readBattery();
}

void loop() {
  server.handleClient();

  static unsigned long last = 0;
  if (millis() - last >= 500) {
    last = millis();
    battV = 0.7f * battV + 0.3f * readBattery();  // smooth out noise
    Serial.printf("Battery: %.2f V\n", battV);
  }
}
