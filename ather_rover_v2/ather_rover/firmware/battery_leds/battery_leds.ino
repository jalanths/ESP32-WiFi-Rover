
#include <WiFi.h>
#include <WebServer.h>

// =====================================
// WIFI ACCESS POINT
// =====================================

const char* AP_SSID = "ATHER-ROVER";
const char* AP_PASS = "rover1234";

// =====================================
// BATTERY CONFIGURATION
// =====================================

#define PIN_BATT 34

// LEDs: GPIO -> 330 ohm -> LED long leg, short leg -> GND
#define PIN_HEAD 27   // front LED
#define PIN_BRAKE 23  // rear LED

const float R1 = 100000.0f;
const float R2 = 100000.0f;

const float DIVIDER = (R1 + R2) / R2;

// Adjust after comparing with multimeter
const float CALIBRATION = 1.000f;

// 1S LiPo voltage thresholds
const float V_FULL = 4.20f;
const float V_LOW = 3.60f;
const float V_CRITICAL = 3.40f;

// =====================================
// SERVER
// =====================================

WebServer server(80);

float battV = 0.0f;
float rawVoltage = 0.0f;

unsigned long lastRead = 0;
unsigned long lastLed = 0;

// =====================================
// MOBILE DASHBOARD
// =====================================

const char PAGE[] PROGMEM = R"HTML(
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport"
content="width=device-width, initial-scale=1">

<title>ATHER Rover Battery</title>

<style>

* {
  box-sizing: border-box;
}

body {
  margin: 0;
  padding: 20px;
  font-family: Arial, sans-serif;
  background: #101827;
  color: white;
}

.container {
  max-width: 480px;
  margin: auto;
}

.header {
  text-align: center;
  padding: 15px 0 25px;
}

.header h2 {
  margin-bottom: 5px;
  font-size: 25px;
}

.header p {
  color: #94a3b8;
  font-size: 13px;
}

.card {
  background: #1e293b;
  border: 1px solid #334155;
  border-radius: 20px;
  padding: 25px 20px;
  margin-bottom: 16px;
}

.section-title {
  color: #94a3b8;
  font-size: 14px;
  text-align: center;
  margin-bottom: 20px;
}

/* BATTERY ICON */

.battery-wrapper {
  display: flex;
  justify-content: center;
  align-items: center;
  margin: 25px 0;
}

.battery {
  width: 190px;
  height: 85px;
  border: 4px solid #94a3b8;
  border-radius: 13px;
  padding: 5px;
  position: relative;
}

.battery:after {
  content: "";
  position: absolute;
  right: -13px;
  top: 24px;
  width: 9px;
  height: 30px;
  background: #94a3b8;
  border-radius: 0 5px 5px 0;
}

.battery-fill {
  height: 100%;
  width: 0%;
  border-radius: 6px;
  background: #22c55e;
  transition: width 0.6s ease,
              background 0.6s ease;
}

.percentage {
  text-align: center;
  font-size: 48px;
  font-weight: bold;
  margin: 15px 0 5px;
}

.voltage {
  text-align: center;
  color: #94a3b8;
  font-size: 20px;
}

.status {
  margin-top: 22px;
  padding: 14px;
  text-align: center;
  border-radius: 12px;
  font-weight: bold;
  background: #14532d;
  color: #86efac;
}

.status.warning {
  background: #713f12;
  color: #fde68a;
}

.status.critical {
  background: #7f1d1d;
  color: #fecaca;
}

.details {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}

.detail-box {
  background: #0f172a;
  border-radius: 12px;
  padding: 16px 10px;
  text-align: center;
}

.detail-box small {
  display: block;
  color: #94a3b8;
  margin-bottom: 10px;
}

.detail-box strong {
  font-size: 21px;
}

.footer {
  text-align: center;
  font-size: 12px;
  color: #64748b;
  margin-top: 20px;
}

</style>
</head>

<body>

<div class="container">

  <div class="header">
    <h2>ATHER ROVER</h2>
    <p>Smart Battery Monitoring System</p>
  </div>

  <div class="card">

    <div class="section-title">
      BATTERY LEVEL
    </div>

    <div class="battery-wrapper">
      <div class="battery">
        <div class="battery-fill" id="fill"></div>
      </div>
    </div>

    <div class="percentage" id="pct">--%</div>

    <div class="voltage" id="voltage">
      -- V
    </div>

    <div class="status" id="status">
      Connecting...
    </div>

  </div>

  <div class="card">

    <div class="section-title">
      BATTERY INFORMATION
    </div>

    <div class="details">

      <div class="detail-box">
        <small>Battery Type</small>
        <strong>1S LiPo</strong>
      </div>

      <div class="detail-box">
        <small>Nominal Voltage</small>
        <strong>3.7 V</strong>
      </div>

      <div class="detail-box">
        <small>Full Voltage</small>
        <strong>4.2 V</strong>
      </div>

      <div class="detail-box">
        <small>Live Voltage</small>
        <strong id="live">-- V</strong>
      </div>

    </div>

  </div>

  <div class="footer">
    ESP32 Wi-Fi Battery Monitor<br>
    Updates automatically every second
    <p id="connection">Connecting to ESP32...</p>
  </div>

</div>

<script>

async function updateBattery() {

  try {

    const response = await fetch('/data');

    if (!response.ok) {
      throw new Error("Server error");
    }

    const data = await response.json();

    const v = data.v;
    const pct = data.pct;

    document.getElementById("pct").textContent =
      pct + "%";

    document.getElementById("voltage").textContent =
      v.toFixed(2) + " V";

    document.getElementById("live").textContent =
      v.toFixed(2) + " V";

    const fill = document.getElementById("fill");

    fill.style.width = pct + "%";

    const status = document.getElementById("status");

    status.className = "status";

    if (v <= 3.40) {

      fill.style.background = "#ef4444";

      status.textContent =
        "CRITICAL BATTERY - Recharge Immediately";

      status.classList.add("critical");

    }

    else if (v <= 3.60) {

      fill.style.background = "#f97316";

      status.textContent =
        "LOW BATTERY - Recharge Soon";

      status.classList.add("warning");

    }

    else if (pct <= 20) {

      fill.style.background = "#eab308";

      status.textContent =
        "Battery Level Low";

      status.classList.add("warning");

    }

    else {

      fill.style.background = "#22c55e";

      status.textContent =
        "BATTERY NORMAL";

    }

    document.getElementById("connection").textContent =
      "Connected to ESP32";

  }

  catch(error) {

    document.getElementById("connection").textContent =
      "Connection lost";

  }

}

setInterval(updateBattery, 1000);

updateBattery();

</script>

</body>
</html>
)HTML";

// =====================================
// LED ANIMATIONS
// =====================================

void setLeds(int head, int brake) {
  ledcWrite(PIN_HEAD, head);
  ledcWrite(PIN_BRAKE, brake);
}

// Power-up: lights bounce front-back three times, then fade in and out
void bootAnimation() {
  for (int r = 0; r < 3; r++) {
    setLeds(255, 0);
    delay(120);
    setLeds(0, 255);
    delay(120);
  }
  for (int b = 0; b <= 255; b += 5) { setLeds(b, b); delay(5); }
  for (int b = 255; b >= 0; b -= 5) { setLeds(b, b); delay(5); }
  setLeds(0, 0);
}

// Smooth 0..255 breathing brightness with the given period in ms
int breathe(unsigned long now, unsigned long period) {
  float phase = (now % period) / (float)period;
  float s = 0.5f - 0.5f * cosf(phase * 2.0f * (float)PI);
  return (int)(s * s * 255.0f);
}

void updateLeds(unsigned long now) {
  int head = 0, brake = 0;
  bool phone = WiFi.softAPgetStationNum() > 0;

  if (battV <= V_CRITICAL) {
    // critical battery: alternating hazard flash
    bool a = (now / 150) % 2;
    head = a ? 255 : 0;
    brake = a ? 0 : 255;
  } else if (!phone) {
    // nobody on the Wi-Fi yet: both breathe slowly
    head = brake = breathe(now, 2400);
  } else if (battV <= V_LOW) {
    // low battery: front dim, rear pulses
    head = 60;
    brake = breathe(now, 1200);
  } else {
    // phone connected, battery fine: headlight on, tail glow
    head = 255;
    brake = 40;
  }

  setLeds(head, brake);
}

// =====================================
// BATTERY VOLTAGE READING
// =====================================

float readBattery() {

  uint32_t sum = 0;

  const int samples = 32;

  for (int i = 0; i < samples; i++) {

    sum += analogReadMilliVolts(PIN_BATT);

    delay(2);

  }

  float pinVoltage =
    (sum / (float)samples) / 1000.0f;

  float batteryVoltage =
    pinVoltage * DIVIDER * CALIBRATION;

  return batteryVoltage;
}

// =====================================
// APPROXIMATE LIPO SOC TABLE
// Intended for a rested battery.
// Actual SOC varies with load and temperature.
// =====================================

int batteryPercent(float v) {

  const float voltageTable[] = {
    3.30, 3.50, 3.60, 3.65,
    3.70, 3.75, 3.80, 3.85,
    3.90, 3.95, 4.00, 4.05,
    4.10, 4.15, 4.20
  };

  const int percentTable[] = {
    0, 5, 10, 15,
    20, 30, 40, 50,
    60, 70, 80, 85,
    90, 95, 100
  };

  const int count = 15;

  if (v <= voltageTable[0]) return 0;

  if (v >= voltageTable[count - 1]) return 100;

  for (int i = 0; i < count - 1; i++) {

    if (v >= voltageTable[i] &&
        v <= voltageTable[i + 1]) {

      float fraction =
        (v - voltageTable[i]) /
        (voltageTable[i + 1] - voltageTable[i]);

      float result =
        percentTable[i] +
        fraction *
        (percentTable[i + 1] - percentTable[i]);

      return (int)(result + 0.5f);
    }

  }

  return 0;
}

// =====================================
// WEBPAGE
// =====================================

void handleRoot() {

  server.send_P(200, "text/html", PAGE);

}

// =====================================
// JSON DATA
// =====================================

void handleData() {

  char output[100];

  snprintf(
    output,
    sizeof(output),
    "{\"v\":%.3f,\"pct\":%d}",
    battV,
    batteryPercent(battV)
  );

  server.send(
    200,
    "application/json",
    output
  );

}

// =====================================
// SETUP
// =====================================

void setup() {

  Serial.begin(115200);

  analogReadResolution(12);

  analogSetPinAttenuation(
    PIN_BATT,
    ADC_11db
  );

  // LEDs
  ledcAttach(PIN_HEAD, 5000, 8);
  ledcAttach(PIN_BRAKE, 5000, 8);
  bootAnimation();

  // Start Wi-Fi Access Point

  WiFi.mode(WIFI_AP);

  WiFi.softAP(AP_SSID, AP_PASS);

  Serial.println();
  Serial.println("==============================");
  Serial.println("ATHER ROVER BATTERY MONITOR");
  Serial.println("==============================");

  Serial.print("WiFi Name: ");
  Serial.println(AP_SSID);

  Serial.print("Dashboard: http://");
  Serial.println(WiFi.softAPIP());

  // Web server routes

  server.on("/", handleRoot);

  server.on("/data", handleData);

  server.begin();

  // Initial battery reading

  for (int i = 0; i < 5; i++) {
    readBattery();
  }

  battV = readBattery();

}

// =====================================
// MAIN LOOP
// =====================================

void loop() {

  server.handleClient();

  if (millis() - lastRead >= 500) {

    lastRead = millis();

    rawVoltage = readBattery();

    // Exponential smoothing

    battV =
      0.7f * battV +
      0.3f * rawVoltage;

    Serial.print("Battery Voltage: ");

    Serial.print(battV, 3);

    Serial.print(" V | Battery: ");

    Serial.print(batteryPercent(battV));

    Serial.println("%");

  }

  if (millis() - lastLed >= 20) {
    lastLed = millis();
    updateLeds(lastLed);
  }

}
