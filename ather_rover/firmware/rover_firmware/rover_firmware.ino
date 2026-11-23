// Ather rover firmware
// Board: ESP32 Dev Module. Works with ESP32 Arduino core 2.x and 3.x.
// Library needed: "WebSockets" by Markus Sattler (Library Manager)
//
// Protocol (plain text over WebSocket, port 81):
//   App -> rover:  D,<x>,<y>   drive, x = steer, y = throttle, both -1.0..1.0
//                  M,<0|1|2>   ride mode: 0 Eco, 1 Ride, 2 Sport
//                  S           stop now
//   Rover -> app:  T,<volts>,<percent>,<mode>,<state>,<fw>
//                  state: OK, FAILSAFE, LIMP, LOWBATT

#include <WiFi.h>
#include <WebSocketsServer.h>
#include <ArduinoOTA.h>

// ---------- settings ----------
const char* AP_SSID = "Ather";
const char* AP_PASS = "123456789";   // at least 8 characters
const char* FW_VERSION = "1.1";

// DRV8833 inputs (match the wiring picture)
const int PIN_IN1 = 32;  // motor A, IN1 / AIN1
const int PIN_IN2 = 33;  // motor A, IN2 / AIN2
const int PIN_IN3 = 25;  // motor B, IN3 / BIN1
const int PIN_IN4 = 26;  // motor B, IN4 / BIN2
const int PIN_BATT = 34; // battery divider midpoint (2 x 100k)

const int PWM_FREQ = 20000;  // 20 kHz, above hearing range
const int PWM_BITS = 8;      // duty 0..255

// Set to true if a motor runs backwards, or swap its two wires instead
const bool INVERT_A = false;
const bool INVERT_B = false;

// Mode limits: top power (0..1) and ramp per 20 ms step
const float MODE_CAP[3]  = {0.40f, 0.70f, 1.00f};
const float MODE_RAMP[3] = {0.04f, 0.08f, 0.20f};

const unsigned long FAILSAFE_MS = 400;   // stop if no command for this long
const float V_FULL = 4.15f;
const float V_EMPTY = 3.30f;
const float V_LIMP = 3.50f;              // below this, cap power
const float V_CUTOFF = 3.30f;            // below this, motors off
const float DIVIDER = 2.0f;              // two equal resistors

// false = the two 100k resistors on GPIO34 are NOT fitted.
// The battery is then reported as a fixed 4.0 V and low-battery
// protection is off, so watch the battery yourself.
const bool HAVE_DIVIDER = false;

// ---------- state ----------
WebSocketsServer ws(81);
int mode = 1;
float cmdX = 0, cmdY = 0;
float curA = 0, curB = 0;
unsigned long lastCmd = 0;
unsigned long lastDrive = 0;
unsigned long lastTelemetry = 0;
float battV = 4.0f;
const char* stateText = "OK";

// ---------- PWM (core 2.x and 3.x) ----------
#if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
// Core 3.x: ledcAttach/ledcWrite take the pin number
void pwmSetup(int pin, int ch) {
  (void)ch;
  ledcAttach(pin, PWM_FREQ, PWM_BITS);
}
void pwmWrite(int pin, int ch, int duty) {
  (void)ch;
  ledcWrite(pin, duty);
}
#else
// Core 2.x: each pin gets its own LEDC channel
void pwmSetup(int pin, int ch) {
  ledcSetup(ch, PWM_FREQ, PWM_BITS);
  ledcAttachPin(pin, ch);
}
void pwmWrite(int pin, int ch, int duty) {
  (void)pin;
  ledcWrite(ch, duty);
}
#endif

// Channel assignments: IN1->ch0, IN2->ch1, IN3->ch2, IN4->ch3
int pinToChannel(int pin) {
  if (pin == PIN_IN1) return 0;
  if (pin == PIN_IN2) return 1;
  if (pin == PIN_IN3) return 2;
  return 3; // PIN_IN4
}

// ---------- helpers ----------
float clampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }

void writeMotor(int pinFwd, int pinRev, float power, bool invert) {
  if (invert) power = -power;
  int duty = (int)(fabsf(power) * 255.0f);
  if (duty > 255) duty = 255;
  int chFwd = pinToChannel(pinFwd);
  int chRev = pinToChannel(pinRev);
  if (power > 0.0f) {
    pwmWrite(pinFwd, chFwd, duty);
    pwmWrite(pinRev, chRev, 0);
  } else if (power < 0.0f) {
    pwmWrite(pinFwd, chFwd, 0);
    pwmWrite(pinRev, chRev, duty);
  } else {
    pwmWrite(pinFwd, chFwd, 0);
    pwmWrite(pinRev, chRev, 0);  // coast
  }
}

void stopMotors() {
  cmdX = 0;
  cmdY = 0;
  curA = 0;
  curB = 0;
  writeMotor(PIN_IN1, PIN_IN2, 0, false);
  writeMotor(PIN_IN3, PIN_IN4, 0, false);
}

float readBattery() {
  if (!HAVE_DIVIDER) return 4.0f;
  // average a few samples to smooth motor noise
  long sum = 0;
  for (int i = 0; i < 8; i++) sum += analogReadMilliVolts(PIN_BATT);
  float mv = sum / 8.0f;
  return (mv / 1000.0f) * DIVIDER;
}

int batteryPercent(float v) {
  float p = (v - V_EMPTY) / (V_FULL - V_EMPTY) * 100.0f;
  return (int)clampf(p, 0, 100);
}

void handleMessage(const char* msg) {
  if (msg[0] == 'D') {
    float x = 0, y = 0;
    if (sscanf(msg, "D,%f,%f", &x, &y) == 2) {
      cmdX = clampf(x, -1, 1);
      cmdY = clampf(y, -1, 1);
      lastCmd = millis();
    }
  } else if (msg[0] == 'M') {
    int m = 1;
    if (sscanf(msg, "M,%d", &m) == 1 && m >= 0 && m <= 2) {
      mode = m;
      lastCmd = millis();
    }
  } else if (msg[0] == 'S') {
    stopMotors();
    lastCmd = millis();
  }
}

void onWsEvent(uint8_t num, WStype_t type, uint8_t* payload, size_t length) {
  if (type == WStype_TEXT) {
    char buf[48];
    size_t n = length < sizeof(buf) - 1 ? length : sizeof(buf) - 1;
    memcpy(buf, payload, n);
    buf[n] = 0;
    handleMessage(buf);
  } else if (type == WStype_DISCONNECTED) {
    stopMotors();
  }
}

// ---------- setup / loop ----------
void setup() {
  Serial.begin(115200);

  pwmSetup(PIN_IN1, 0);
  pwmSetup(PIN_IN2, 1);
  pwmSetup(PIN_IN3, 2);
  pwmSetup(PIN_IN4, 3);
  stopMotors();

  if (HAVE_DIVIDER) {
    analogReadResolution(12);
    analogSetPinAttenuation(PIN_BATT, ADC_11db);
  }

  WiFi.mode(WIFI_AP);
  WiFi.softAP(AP_SSID, AP_PASS);
  Serial.print("Rover Wi-Fi: ");
  Serial.println(AP_SSID);
  Serial.print("IP: ");
  Serial.println(WiFi.softAPIP());  // normally 192.168.4.1

  ws.begin();
  ws.onEvent(onWsEvent);

  ArduinoOTA.setHostname("ather-rover");
  ArduinoOTA.onStart([]() { stopMotors(); });
  ArduinoOTA.begin();

  battV = readBattery();
  lastCmd = millis();
}

void loop() {
  ws.loop();
  ArduinoOTA.handle();

  unsigned long now = millis();

  // battery, every 500 ms (smoothed)
  static unsigned long lastBatt = 0;
  if (now - lastBatt >= 500) {
    lastBatt = now;
    battV = 0.8f * battV + 0.2f * readBattery();
  }

  // motor update every 20 ms
  if (now - lastDrive >= 20) {
    lastDrive = now;

    bool failsafe = (now - lastCmd) > FAILSAFE_MS;
    // Once the battery is flat, stay stopped until the rover is rebooted
    static bool cutoffLatched = false;
    if (HAVE_DIVIDER && battV < V_CUTOFF) cutoffLatched = true;
    bool cutoff = cutoffLatched;
    float cap = MODE_CAP[mode];
    stateText = "OK";
    if (HAVE_DIVIDER && battV < V_LIMP) {
      cap = clampf(cap, 0, 0.30f);
      stateText = "LIMP";
    }
    if (cutoff) stateText = "LOWBATT";
    if (failsafe) stateText = "FAILSAFE";

    float x = cmdX, y = cmdY;
    if (failsafe || cutoff) {
      x = 0;
      y = 0;
    }

    // differential drive mix
    float left = clampf(y + x, -1, 1) * cap;
    float right = clampf(y - x, -1, 1) * cap;

    // ramp toward target; stop requests are not ramped when failing safe
    float ramp = MODE_RAMP[mode];
    if (failsafe || cutoff) {
      curA = 0;
      curB = 0;
    } else {
      curA += clampf(left - curA, -ramp, ramp);
      curB += clampf(right - curB, -ramp, ramp);
    }

    writeMotor(PIN_IN1, PIN_IN2, curA, INVERT_A);
    writeMotor(PIN_IN3, PIN_IN4, curB, INVERT_B);
  }

  // telemetry, every 500 ms
  if (now - lastTelemetry >= 500) {
    lastTelemetry = now;
    char out[64];
    snprintf(out, sizeof(out), "T,%.2f,%d,%d,%s,%s", battV, batteryPercent(battV), mode, stateText, FW_VERSION);
    ws.broadcastTXT(out);
  }
}
