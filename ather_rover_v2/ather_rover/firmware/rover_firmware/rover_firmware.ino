// Ather hackathon rover firmware
// Board: ESP32 Dev Module, ESP32 Arduino core 3.x
// Library needed: "WebSockets" by Markus Sattler (Library Manager)
//
// Protocol (plain text over WebSocket, port 81):
//   App -> rover:  D,<x>,<y>   drive, x = steer, y = throttle, both -1.0..1.0
//                  M,<0|1|2>   ride mode: 0 Eco, 1 Ride, 2 Sport
//                  S           stop now
//                  R,<trim>    straight-line trim, -0.30..0.30 (saved)
//                  B           turbo (3 s full power, then 10 s cool-down)
//                  F           find my rover (flash both LEDs)
//                  P,R / P,S   start / stop recording a path
//                  P,P / P,X   play / stop the recorded path
//                  Z           reset trip stats
//                  C,<volts>   battery calibration: multimeter reading with motors stopped
//                              (C,0 resets, saved)
//   Rover -> app:  T,<volts>,<percent>,<mode>,<state>,<fw>,<trim>,<selftest>,
//                    <rangeMin>,<driveSec>,<minV>,<usedPct>,<activity>,<pathSec>,
//                    <loadVolts>,<calib>
//                  volts = estimated resting voltage, loadVolts = actual voltage now
//                  activity: -, TURBO, COOL, REC, PLAY   (rangeMin -1 = not enough data)
//                  state: OK, FAILSAFE, LIMP, LOWBATT, OVERLOAD, FAULT, SLEEP
//                  selftest: OK, BATT_SENSE, BATT_LOW, DRIVER

//   Browser:       open http://192.168.4.1 after joining the rover's Wi-Fi

#include <WiFi.h>
#include <WebServer.h>
#include <WebSocketsServer.h>
#include <ArduinoOTA.h>
#include <Preferences.h>

// ---------- settings ----------
const char* AP_SSID = "ATHER-ROVER";
const char* AP_PASS = "rover1234";   // at least 8 characters
const char* FW_VERSION = "2.1";

// DRV8833 inputs (match the wiring picture)
const int PIN_IN1 = 32;  // motor A, IN1 / AIN1
const int PIN_IN2 = 33;  // motor A, IN2 / AIN2
const int PIN_IN3 = 25;  // motor B, IN3 / BIN1
const int PIN_IN4 = 26;  // motor B, IN4 / BIN2
const int PIN_BATT = 34; // battery divider midpoint (2 x 100k)
const int PIN_HEAD = 27;  // front LED: GPIO27 -> 330 ohm -> LED -> GND
const int PIN_BRAKE = 23; // rear LED:  GPIO23 -> 330 ohm -> LED -> GND

const int PWM_FREQ = 20000;  // 20 kHz, above hearing range
const int PWM_BITS = 8;      // duty 0..255

// Smallest power that still turns the wheels (0..1). Any non-zero command
// starts here, so Eco and Ride still move. Raise it if a mode still won't
// move, lower it if starts feel too jumpy.
const float MIN_POWER = 0.45f;

// DRV8833 slow-decay drive: more torque at partial power than coasting
const bool SLOW_DECAY = true;

// Set to true if a motor runs backwards, or swap its two wires instead
const bool INVERT_A = false;
const bool INVERT_B = true;   // motor B's wires are reversed on this rover

// true if motor A (OUT1/OUT2) is the RIGHT wheel instead of the left
const bool SWAP_SIDES = true;

// Mode limits: top power (0..1) and ramp per 20 ms step
const float MODE_CAP[3]  = {0.40f, 0.70f, 1.00f};
const float MODE_RAMP[3] = {0.04f, 0.08f, 0.20f};

const unsigned long FAILSAFE_MS = 400;   // stop if no command for this long

// ---------- battery ----------
// All limits below use the ESTIMATED RESTING voltage: the reading plus the
// sag the motors are expected to cause (learned while driving). So a short
// dip under load no longer drops the % or triggers limp / cut-off.
const float V_LIMP = 3.70f;              // below this, cap power (warning stage)
const float V_LIMP_EXIT = 3.78f;         // must recover above this to leave limp (no flicker)
const float V_CUTOFF = 3.60f;            // below this for CUTOFF_HOLD_MS, motors off until restart
const unsigned long CUTOFF_HOLD_MS = 3000;
// The actual voltage under load must not fall below this, or the boost
// converter browns out. If it does, power is cut back for a few seconds.
const float V_SAG_MIN = 3.20f;
const unsigned long SAG_HOLD_MS = 300;   // how long below V_SAG_MIN before easing off
const unsigned long SAG_EASE_MS = 3000;  // how long power stays reduced
const float DIVIDER = 2.0f;              // two equal resistors
const float CALIBRATION_DEFAULT = 1.000f; // multimeter / app; set from the app and saved
const float SAG_INIT = 0.15f;            // first guess: volts lost at full power
const int BATT_SAMPLES = 16;             // ADC samples per reading (top and bottom 4 dropped)

// ---------- power saving ----------
// 80 MHz is plenty for Wi-Fi + motor control and draws ~20 mA less than 240 MHz.
// Use 160 if the app or web page ever feels laggy.
const int CPU_MHZ = 80;
// Lower Wi-Fi transmit power: less current, smaller voltage dips, fewer
// brownouts. Range is still about 30 m. Use WIFI_POWER_19_5dBm for maximum range.
const wifi_power_t WIFI_TX = WIFI_POWER_13dBm;

// Set to false if you did NOT fit the two 100k resistors on GPIO34.
// The battery is then reported as a fixed 4.0 V and low-battery
// protection is off, so watch the battery yourself.
const bool HAVE_DIVIDER = true;

// ---------- overload (stall) guard ----------
// The kit has no current sensor, so a stall is estimated from how far the
// battery voltage sags below its resting value while the motors work hard.
const float OVERLOAD_POWER = 0.80f;          // "working hard" = this much power or more
const float OVERLOAD_SAG = 0.25f;            // volts below resting voltage that counts as overload
const float OVERLOAD_EXTRA = 0.12f;          // ...and at least this much more than the usual sag
const unsigned long OVERLOAD_MS = 2000;      // must last this long before easing off
const unsigned long OVERLOAD_COOL_MS = 3000; // how long power stays reduced
const float OVERLOAD_CAP = 0.40f;            // power cap while cooling down
// Optional: DRV8833 fault pin (nFAULT / FLT / ULT) to a GPIO, e.g. 4.
// Leave at -1 if it is not wired.
const int PIN_FAULT = -1;

// ---------- start-up self-test ----------
const bool SELFTEST_WIGGLE = true;  // twitch each wheel briefly at power-up

// ---------- straight-line trim ----------
// Saved in flash. Positive slows the LEFT wheel (fixes drift to the right),
// negative slows the RIGHT wheel (fixes drift to the left). Set from the app.
const float TRIM_LIMIT = 0.30f;

// ---------- driving extras ----------
const float TURN_SLOWDOWN = 0.35f;            // sharp turns lose up to 35% power
const unsigned long IDLE_SLEEP_MS = 300000;   // auto-stop after 5 min without driving
const unsigned long TURBO_MS = 3000;          // turbo lasts 3 s...
const unsigned long TURBO_COOL_MS = 10000;    // ...then needs 10 s before the next one
const unsigned long FIND_MS = 4000;           // "find my rover" flash time

// ---------- recorded paths ----------
// Records the joystick 10 times a second, up to 60 s. Replays open-loop:
// without wheel encoders the replay drifts as the battery drains.
const int PATH_STEPS = 600;
const unsigned long PATH_STEP_MS = 100;

// ---------- control web page ----------
const char PAGE[] PROGMEM = R"HTML(<!DOCTYPE html>
<html><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
<title>ATHER Rover</title>
<style>
*{box-sizing:border-box}
body{margin:0;padding:16px;font-family:Arial,sans-serif;background:#101827;color:#fff;user-select:none;-webkit-user-select:none}
.wrap{max-width:480px;margin:auto}
h2{text-align:center;margin:4px 0 2px}
.sub{text-align:center;color:#94a3b8;font-size:13px;margin-bottom:14px}
.card{background:#1e293b;border:1px solid #334155;border-radius:18px;padding:16px;margin-bottom:14px}
.row{display:flex;align-items:center;gap:12px}
.bat{flex:1;height:24px;border:3px solid #94a3b8;border-radius:7px;padding:2px}
#fill{height:100%;width:0;border-radius:3px;background:#22c55e;transition:width .5s}
#pct{font-size:26px;font-weight:bold;min-width:70px;text-align:right}
#info{color:#94a3b8;font-size:14px;margin-top:8px;display:flex;justify-content:space-between}
#state{margin-top:10px;padding:10px;border-radius:10px;text-align:center;font-weight:bold;background:#334155}
.modes{display:flex;gap:8px}
.modes button{flex:1;padding:14px 0;border-radius:12px;border:1px solid #334155;background:#0f172a;color:#cbd5e1;font-size:16px}
.modes button.on{background:#1D9E75;color:#fff;border-color:#1D9E75}
#pad{width:240px;height:240px;margin:6px auto;border-radius:50%;background:#0f172a;border:2px solid #334155;position:relative;touch-action:none}
#knob{width:80px;height:80px;border-radius:50%;background:#1D9E75;position:absolute;left:78px;top:78px}
#stop{width:100%;padding:18px;border:none;border-radius:14px;background:#ef4444;color:#fff;font-size:20px;font-weight:bold}
#test{margin-top:8px;font-size:13px;color:#94a3b8;text-align:center}
.trim{display:flex;align-items:center;gap:10px;color:#94a3b8;font-size:13px}
.trim input{flex:1}
#trip{margin-top:8px;font-size:13px;color:#cbd5e1;display:flex;flex-wrap:wrap;gap:4px 14px;justify-content:center}
#graph{width:100%;height:70px;margin-top:10px;background:#0f172a;border-radius:8px}
.acts{display:grid;grid-template-columns:repeat(4,1fr);gap:8px}
.acts button{padding:12px 0;border-radius:12px;border:1px solid #334155;background:#0f172a;color:#cbd5e1;font-size:14px}
.acts button.on{background:#7c3aed;color:#fff;border-color:#7c3aed}
.small{background:none;border:none;color:#94a3b8;font-size:12px;text-decoration:underline}
</style></head><body><div class="wrap">
<h2>ATHER ROVER</h2><div class="sub" id="conn">Connecting...</div>
<div class="card"><div class="row"><div class="bat"><div id="fill"></div></div><div id="pct">--%</div></div>
<div id="info"><span id="volt">-- V</span><span id="fw">fw --</span></div><div id="state">--</div><div id="test">Self-test: --</div>
<div id="trip"><span id="range">Range --</span><span id="dtime">Drive 0:00</span><span id="minv">Min -- V</span><span id="used">Used --%</span><button class="small" id="tripz">Reset trip</button></div>
<canvas id="graph" width="440" height="70"></canvas></div>
<div class="card"><div class="acts"><button id="turbo">Turbo</button><button id="rec">Record</button><button id="play">Play</button><button id="find">Find</button></div></div>
<div class="card"><div class="modes"><button id="m0">Eco</button><button id="m1" class="on">Ride</button><button id="m2">Sport</button></div></div>
<div class="card"><div id="pad"><div id="knob"></div></div></div>
<button id="stop">STOP</button>
<div class="card" style="margin-top:14px"><div class="trim"><span>Drifts left</span><input id="trim" type="range" min="-30" max="30" step="1" value="0"><span>Drifts right</span></div>
<div id="trimv" style="text-align:center;color:#94a3b8;font-size:13px;margin-top:6px">Trim 0</div></div></div>
<script>
let ws,x=0,y=0,up=false,drag=false;
const $=id=>document.getElementById(id);
const names={OK:'Ready',LIMP:'Limp mode: low battery',LOWBATT:'Battery cut-off: recharge',FAILSAFE:'Fail-safe stop',OVERLOAD:'Overload: easing off',FAULT:'Motor driver fault',SLEEP:'Asleep: move the joystick to wake'};
let act='-',pathSec=0;const hist=[];
const tests={OK:'passed',BATT_SENSE:'battery sense wire not connected',BATT_LOW:'battery too low',DRIVER:'motor driver fault',PENDING:'running'};
let trimTouch=0;
function connect(){
 ws=new WebSocket('ws://'+location.hostname+':81/');
 ws.onopen=()=>{up=true;$('conn').textContent='Connected';};
 ws.onclose=()=>{up=false;$('conn').textContent='Connection lost, retrying...';setTimeout(connect,2000);};
 ws.onmessage=e=>{const p=String(e.data).split(',');if(p[0]!=='T'||p.length<6)return;
  const v=parseFloat(p[1]),pct=parseInt(p[2]),m=parseInt(p[3]);
  $('pct').textContent=pct+'%';$('volt').textContent=v.toFixed(2)+' V';$('fw').textContent='fw '+p[5];
  const f=$('fill');f.style.width=pct+'%';f.style.background=v<=3.6?'#ef4444':v<=3.7?'#f97316':'#22c55e';
  const s=$('state');s.textContent=names[p[4]]||p[4];
  s.style.background=p[4]==='OK'?'#14532d':p[4]==='LIMP'?'#713f12':'#7f1d1d';
  setMode(m);
  if(p.length>=8){
   const t=$('test');t.textContent='Self-test: '+(tests[p[7]]||p[7]);t.style.color=p[7]==='OK'?'#86efac':'#fca5a5';
   if(Date.now()-trimTouch>1500){const tv=Math.round(parseFloat(p[6])*100);$('trim').value=tv;showTrim(tv);}
  }
  if(p.length>=14){
   const r=parseInt(p[8]),ds=parseInt(p[9]);
   $('range').textContent=r<0?'Range: learning...':'Range ~'+r+' min';
   $('dtime').textContent='Drive '+Math.floor(ds/60)+':'+String(ds%60).padStart(2,'0');
   $('minv').textContent='Min '+parseFloat(p[10]).toFixed(2)+' V';
   $('used').textContent='Used '+p[11]+'%';
   act=p[12];pathSec=parseInt(p[13]);
   $('turbo').classList.toggle('on',act==='TURBO');$('turbo').textContent=act==='COOL'?'Cooling':'Turbo';
   $('rec').classList.toggle('on',act==='REC');$('rec').textContent=act==='REC'?'Stop rec':'Record';
   $('play').classList.toggle('on',act==='PLAY');$('play').textContent=act==='PLAY'?'Stop':(pathSec>0?'Play '+pathSec+'s':'Play');
  }
  hist.push(v);if(hist.length>120)hist.shift();draw();};
}
function draw(){const c=$('graph'),g=c.getContext('2d'),w=c.width,h=c.height;g.clearRect(0,0,w,h);
 if(hist.length<2)return;const lo=3.3,hi=4.25;
 g.strokeStyle='#334155';g.lineWidth=1;[3.6,3.7].forEach(t=>{const yy=h-(t-lo)/(hi-lo)*h;g.beginPath();g.moveTo(0,yy);g.lineTo(w,yy);g.stroke();});
 g.strokeStyle='#22c55e';g.lineWidth=2;g.beginPath();
 hist.forEach((v,i)=>{const xx=i/(119)*w,yy=h-(Math.min(hi,Math.max(lo,v))-lo)/(hi-lo)*h;i?g.lineTo(xx,yy):g.moveTo(xx,yy);});g.stroke();}
$('turbo').onclick=()=>send('B');
$('find').onclick=()=>send('F');
$('rec').onclick=()=>send(act==='REC'?'P,S':'P,R');
$('play').onclick=()=>send(act==='PLAY'?'P,X':'P,P');
$('tripz').onclick=()=>send('Z');
function showTrim(v){$('trimv').textContent='Trim '+(v>0?'+':'')+v;}
$('trim').oninput=e=>{trimTouch=Date.now();showTrim(parseInt(e.target.value));};
$('trim').onchange=e=>{trimTouch=Date.now();send('R,'+(parseInt(e.target.value)/100).toFixed(2));};
function send(t){if(up&&ws.readyState===1)ws.send(t);}
function setMode(m){for(let i=0;i<3;i++)$('m'+i).classList.toggle('on',i===m);}
for(let i=0;i<3;i++)$('m'+i).onclick=()=>{setMode(i);send('M,'+i);};
const pad=$('pad'),knob=$('knob');
function place(dx,dy){knob.style.left=(78+dx*80)+'px';knob.style.top=(78+dy*80)+'px';}
function release(){drag=false;x=0;y=0;place(0,0);}
function move(e){const r=pad.getBoundingClientRect();
 let dx=(e.clientX-r.left-r.width/2)/(r.width/2),dy=(e.clientY-r.top-r.height/2)/(r.height/2);
 const d=Math.hypot(dx,dy);if(d>1){dx/=d;dy/=d;}place(dx,dy);x=dx;y=-dy;}
pad.onpointerdown=e=>{drag=true;pad.setPointerCapture(e.pointerId);move(e);};
pad.onpointermove=e=>{if(drag)move(e);};
pad.onpointerup=release;pad.onpointercancel=release;
$('stop').onclick=()=>{release();send('S');};
setInterval(()=>send('D,'+x.toFixed(2)+','+y.toFixed(2)),50);
connect();
</script></body></html>)HTML";

// ---------- state ----------
WebServer server(80);
WebSocketsServer ws(81);
int lastModeShown = -1;
unsigned long modeFlashStart = 0;
int mode = 1;
float cmdX = 0, cmdY = 0;
float curA = 0, curB = 0;
unsigned long lastCmd = 0;
unsigned long lastDrive = 0;
unsigned long lastTelemetry = 0;
float battV = 4.0f;
const char* stateText = "OK";
const char* selfTest = "PENDING";   // OK, BATT_SENSE, BATT_LOW, DRIVER
Preferences prefs;
float trim = 0;
float vNow = 4.0f;    // actual battery voltage right now (under load when driving)
float vRest = 4.0f;   // battery voltage while the motors are idle
float sagK = SAG_INIT; // learned: volts of sag per unit of motor power
float calib = CALIBRATION_DEFAULT;
int pctShown = -1;    // battery % sent to the app (steady, only rises after a rest)

// trip stats and range
unsigned long driveMs = 0;      // time spent actually moving
float minV = 9.9f;              // lowest battery voltage this trip
int startPct = -1;              // battery % when the trip started
int rangeMin = -1;              // estimated driving minutes left, -1 = not enough data

// extras
unsigned long lastActive = 0;   // last non-zero joystick command
bool sleeping = false;
unsigned long turboUntil = 0, turboReadyAt = 0;
unsigned long findUntil = 0;

// recorded paths
int8_t pathX[PATH_STEPS], pathY[PATH_STEPS];
int pathLen = 0, playIdx = 0;
bool recording = false, playing = false;
unsigned long pathNext = 0;
float effX = 0, effY = 0;       // what the rover is actually being driven with

// ---------- helpers ----------
float clampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }

void writeMotor(int pinFwd, int pinRev, float power, bool invert) {
  if (invert) power = -power;
  float mag = fabsf(power);
  if (mag < 0.02f) {
    ledcWrite(pinFwd, 0);
    ledcWrite(pinRev, 0);  // stopped: coast
    return;
  }
  // lift small commands above the motor's starting threshold
  mag = MIN_POWER + (1.0f - MIN_POWER) * clampf(mag, 0, 1);
  int duty = (int)(mag * 255.0f + 0.5f);
  if (duty > 255) duty = 255;

  if (SLOW_DECAY) {
    // one input held high, the other PWM'd inverted (DRV8833 slow decay)
    if (power > 0.0f) {
      ledcWrite(pinFwd, 255);
      ledcWrite(pinRev, 255 - duty);
    } else {
      ledcWrite(pinFwd, 255 - duty);
      ledcWrite(pinRev, 255);
    }
  } else {
    // fast decay: PWM one input, other low
    if (power > 0.0f) {
      ledcWrite(pinFwd, duty);
      ledcWrite(pinRev, 0);
    } else {
      ledcWrite(pinFwd, 0);
      ledcWrite(pinRev, duty);
    }
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
  // Take 16 samples, sort them, and average the middle half.
  // This throws away the spikes the motors put on the wires.
  int s[BATT_SAMPLES];
  for (int i = 0; i < BATT_SAMPLES; i++) s[i] = analogReadMilliVolts(PIN_BATT);
  for (int i = 1; i < BATT_SAMPLES; i++) {
    int v = s[i], j = i - 1;
    while (j >= 0 && s[j] > v) { s[j + 1] = s[j]; j--; }
    s[j + 1] = v;
  }
  const int drop = BATT_SAMPLES / 4;
  long sum = 0;
  for (int i = drop; i < BATT_SAMPLES - drop; i++) sum += s[i];
  float mv = sum / (float)(BATT_SAMPLES - 2 * drop);
  return (mv / 1000.0f) * DIVIDER * calib;
}

// Approximate 1S LiPo charge table (for a rested battery)
int batteryPercent(float v) {
  const float vt[] = {3.30, 3.50, 3.60, 3.65, 3.70, 3.75, 3.80, 3.85,
                      3.90, 3.95, 4.00, 4.05, 4.10, 4.15, 4.20};
  const int pt[] = {0, 5, 10, 15, 20, 30, 40, 50, 60, 70, 80, 85, 90, 95, 100};
  const int n = 15;
  if (v <= vt[0]) return 0;
  if (v >= vt[n - 1]) return 100;
  for (int i = 0; i < n - 1; i++) {
    if (v <= vt[i + 1]) {
      float f = (v - vt[i]) / (vt[i + 1] - vt[i]);
      return (int)(pt[i] + f * (pt[i + 1] - pt[i]) + 0.5f);
    }
  }
  return 100;
}

void handleMessage(const char* msg) {
  if (msg[0] == 'D') {
    float x = 0, y = 0;
    if (sscanf(msg, "D,%f,%f", &x, &y) == 2) {
      cmdX = clampf(x, -1, 1);
      cmdY = clampf(y, -1, 1);
      lastCmd = millis();
      if (fabsf(cmdX) + fabsf(cmdY) > 0.05f) {
        lastActive = lastCmd;
        sleeping = false;          // any joystick movement wakes the rover
        playing = false;           // and takes over from a path replay
      }
    }
  } else if (msg[0] == 'M') {
    int m = 1;
    if (sscanf(msg, "M,%d", &m) == 1 && m >= 0 && m <= 2) {
      mode = m;
      lastCmd = millis();
    }
  } else if (msg[0] == 'S') {
    stopMotors();
    playing = false;
    turboUntil = 0;
    lastCmd = millis();
  } else if (msg[0] == 'B') {
    unsigned long now = millis();
    if ((long)(now - turboReadyAt) >= 0) {      // not cooling down
      turboUntil = now + TURBO_MS;
      turboReadyAt = turboUntil + TURBO_COOL_MS;
    }
    lastCmd = now;
  } else if (msg[0] == 'F') {
    findUntil = millis() + FIND_MS;
    lastCmd = millis();
  } else if (msg[0] == 'P' && strlen(msg) >= 3) {
    char c = msg[2];
    if (c == 'R') {                               // start recording
      pathLen = 0; recording = true; playing = false; pathNext = millis();
    } else if (c == 'S') {                        // stop recording
      recording = false;
    } else if (c == 'P' && pathLen > 0) {         // play back
      recording = false; playing = true; playIdx = 0; pathNext = millis();
      sleeping = false; lastActive = millis();
    } else if (c == 'X') {                        // stop playback
      playing = false;
    }
    lastCmd = millis();
  } else if (msg[0] == 'Z') {                     // reset trip stats
    driveMs = 0;
    minV = vNow;
    startPct = pctShown;
    rangeMin = -1;
    lastCmd = millis();
  } else if (msg[0] == 'C') {
    // battery calibration: C,<multimeter volts> with the motors stopped, C,0 resets
    float meas = 0;
    if (sscanf(msg, "C,%f", &meas) == 1) {
      bool idle = fmaxf(fabsf(curA), fabsf(curB)) < 0.05f;
      if (meas < 0.5f) {
        calib = CALIBRATION_DEFAULT;
      } else if (idle && vNow > 1.0f && meas >= 3.0f && meas <= 4.4f) {
        float raw = vNow / calib;                   // reading without correction
        calib = clampf(meas / raw, 0.80f, 1.25f);
      }
      prefs.putFloat("cal", calib);                 // remembered after power-off
      vNow = vRest = battV = readBattery();
      pctShown = batteryPercent(battV);
      startPct = pctShown;
      lastCmd = millis();
    }
  } else if (msg[0] == 'R') {
    float t = 0;
    if (sscanf(msg, "R,%f", &t) == 1) {
      trim = clampf(t, -TRIM_LIMIT, TRIM_LIMIT);
      prefs.putFloat("trim", trim);   // remembered after power-off
      lastCmd = millis();
    }
  }
}

// ---------- start-up self-test ----------
// Checks what can be checked without sensors and reports it to the app.
void setLeds(int head, int brake);  // defined in the LED section below

void runSelfTest() {
  selfTest = "OK";
  if (HAVE_DIVIDER) {
    float v = readBattery();
    if (v < 2.5f || v > 4.5f) {
      selfTest = "BATT_SENSE";      // divider or GPIO34 wire not connected
    } else if (v < V_CUTOFF) {
      selfTest = "BATT_LOW";
    }
  }
  if (PIN_FAULT >= 0 && digitalRead(PIN_FAULT) == LOW) {
    selfTest = "DRIVER";            // DRV8833 reports a fault
  }
  if (SELFTEST_WIGGLE) {
    // twitch each wheel forward then back so you can see both respond
    const float p = 0.6f;
    writeMotor(PIN_IN1, PIN_IN2, p, INVERT_A);  delay(120);
    writeMotor(PIN_IN1, PIN_IN2, -p, INVERT_A); delay(120);
    writeMotor(PIN_IN1, PIN_IN2, 0, false);     delay(150);
    writeMotor(PIN_IN3, PIN_IN4, p, INVERT_B);  delay(120);
    writeMotor(PIN_IN3, PIN_IN4, -p, INVERT_B); delay(120);
    writeMotor(PIN_IN3, PIN_IN4, 0, false);
  }
  if (strcmp(selfTest, "OK") != 0) {
    // problem found: both LEDs flash quickly five times
    for (int i = 0; i < 5; i++) {
      setLeds(255, 255); delay(100);
      setLeds(0, 0);     delay(100);
    }
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

// ---------- LED animations ----------
void setLeds(int head, int brake) {
  ledcWrite(PIN_HEAD, head);
  ledcWrite(PIN_BRAKE, brake);
}

// Power-up: lights bounce front-back three times, then both fade in and out
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

// Smooth 0..255 "breathing" brightness with the given period in ms
int breathe(unsigned long now, unsigned long period) {
  float phase = (now % period) / (float)period;
  float s = 0.5f - 0.5f * cosf(phase * 2.0f * (float)PI);
  return (int)(s * s * 255.0f);
}

void updateLeds(unsigned long now) {
  int head = 0, brake = 0;
  bool phone = ws.connectedClients() > 0;
  bool stopping = (fabsf(cmdX) + fabsf(cmdY)) < 0.05f;

  if (!phone) {
    // waiting for the app: both breathe slowly
    head = brake = breathe(now, 2400);
  } else if (strcmp(stateText, "FAILSAFE") == 0) {
    // link dropped while connected: alternating hazard flash
    bool a = (now / 150) % 2;
    head = a ? 255 : 0;
    brake = a ? 0 : 255;
  } else if (strcmp(stateText, "OVERLOAD") == 0 || strcmp(stateText, "FAULT") == 0) {
    // overload or driver fault: rear LED flashes fast, front dim
    head = 60;
    brake = ((now / 100) % 2) ? 255 : 0;
  } else if (strcmp(stateText, "LOWBATT") == 0) {
    // battery cut-off: rear double-pulse, front off
    unsigned long t = now % 1000;
    brake = (t < 100 || (t > 200 && t < 300)) ? 255 : 0;
  } else if (sleeping) {
    // auto-stopped after idling: both glow very gently
    head = brake = breathe(now, 4000) / 4;
  } else {
    // normal driving: headlight on, dimmer when idle; tail glow, full when stopping
    head = stopping ? 120 : 255;
    brake = stopping ? 255 : 40;
    bool blink = (now / 350) % 2;
    if (fabsf(effX) > 0.4f) head = blink ? 255 : 0;   // turning: front LED blinks
    if (effY < -0.1f) brake = blink ? 255 : 0;          // reversing: rear LED blinks
    if ((long)(turboUntil - now) > 0) head = ((now / 80) % 2) ? 255 : 0;  // turbo strobe
    if (recording) brake = (now % 1000 < 120) ? 255 : brake;           // recording tick
    if (playing) head = breathe(now, 600);                             // replaying
    if (strcmp(stateText, "LIMP") == 0) {
      head = 60;
      brake = breathe(now, 1200);  // low battery: rear pulses
    }
  }

  // ride mode changed: headlight flashes 1x Eco, 2x Ride, 3x Sport
  if (mode != lastModeShown) {
    lastModeShown = mode;
    modeFlashStart = now;
  }
  unsigned long e = now - modeFlashStart;
  if (phone && e < (unsigned long)(mode + 1) * 240) {
    head = ((e / 120) % 2 == 0) ? 255 : 0;
  }

  // find my rover: both LEDs flash together, overrides everything
  if ((long)(findUntil - now) > 0) {
    head = brake = ((now / 150) % 2) ? 255 : 0;
  }

  setLeds(head, brake);
}

// ---------- setup / loop ----------
void setup() {
  setCpuFrequencyMhz(CPU_MHZ);   // power saving, see CPU_MHZ
  Serial.begin(115200);

  ledcAttach(PIN_IN1, PWM_FREQ, PWM_BITS);
  ledcAttach(PIN_IN2, PWM_FREQ, PWM_BITS);
  ledcAttach(PIN_IN3, PWM_FREQ, PWM_BITS);
  ledcAttach(PIN_IN4, PWM_FREQ, PWM_BITS);
  stopMotors();

  ledcAttach(PIN_HEAD, 5000, 8);
  ledcAttach(PIN_BRAKE, 5000, 8);
  bootAnimation();
  lastModeShown = mode;

  analogReadResolution(12);
  analogSetPinAttenuation(PIN_BATT, ADC_11db);

  if (PIN_FAULT >= 0) pinMode(PIN_FAULT, INPUT_PULLUP);
  prefs.begin("rover", false);
  trim = clampf(prefs.getFloat("trim", 0.0f), -TRIM_LIMIT, TRIM_LIMIT);
  calib = clampf(prefs.getFloat("cal", CALIBRATION_DEFAULT), 0.80f, 1.25f);
  runSelfTest();

  WiFi.mode(WIFI_AP);
  WiFi.softAP(AP_SSID, AP_PASS);
  WiFi.setTxPower(WIFI_TX);     // power saving, see WIFI_TX
  Serial.print("Rover Wi-Fi: ");
  Serial.println(AP_SSID);
  Serial.print("IP: ");
  Serial.println(WiFi.softAPIP());  // normally 192.168.4.1

  server.on("/", []() { server.send_P(200, "text/html", PAGE); });
  server.begin();

  ws.begin();
  ws.onEvent(onWsEvent);

  ArduinoOTA.setHostname("ather-rover");
  ArduinoOTA.onStart([]() { stopMotors(); });
  ArduinoOTA.begin();

  battV = readBattery();
  vNow = battV;
  vRest = battV;
  minV = battV;
  pctShown = batteryPercent(battV);
  startPct = pctShown;
  lastActive = millis();
  lastCmd = millis();
}

void loop() {
  server.handleClient();
  ws.loop();
  ArduinoOTA.handle();

  unsigned long now = millis();

  // motor update every 20 ms
  if (now - lastDrive >= 20) {
    lastDrive = now;

    bool failsafe = (now - lastCmd) > FAILSAFE_MS;

    // ----- battery: read every 100 ms, estimate the resting voltage -----
    static unsigned long fastLast = 0, idleSince = 0, hardSince = 0, coolUntil = 0;
    static unsigned long sagLowSince = 0, sagEaseUntil = 0;
    float workload = fmaxf(fabsf(curA), fabsf(curB));
    if (workload < 0.05f) {
      if (idleSince == 0) idleSince = now;
    } else {
      idleSince = 0;
    }
    bool rested1s = idleSince != 0 && now - idleSince >= 1000;
    if (now - fastLast >= 100) {
      fastLast = now;
      vNow = 0.5f * vNow + 0.5f * readBattery();
      if (rested1s) {
        vRest = 0.8f * vRest + 0.2f * vNow;           // motors idle: true resting voltage
      } else if (workload > 0.3f && vRest > vNow && (vRest - vNow) < OVERLOAD_SAG + 0.15f) {
        // learn how much this battery sags per unit of motor power
        float k = clampf((vRest - vNow) / workload, 0.0f, 0.8f);
        sagK = 0.98f * sagK + 0.02f * k;
      }
      // resting-equivalent voltage = reading + the sag the motors are causing
      float vEst = vNow + sagK * workload;
      battV = 0.9f * battV + 0.1f * vEst;              // about 1 s of smoothing

      // battery %: steps down at most 1% per reading, only goes back up
      // after 5 s of rest (so it doesn't bounce while driving)
      int pctEst = batteryPercent(battV);
      bool rested5s = idleSince != 0 && now - idleSince >= 5000;
      if (pctShown < 0) pctShown = pctEst;
      if (pctEst < pctShown) pctShown--;
      else if (rested5s && pctEst >= pctShown + 3) pctShown = pctEst;

      // voltage under load too low: ease off before the boost converter browns out
      if (HAVE_DIVIDER && vNow < V_SAG_MIN) {
        if (sagLowSince == 0) sagLowSince = now;
        if (now - sagLowSince >= SAG_HOLD_MS) sagEaseUntil = now + SAG_EASE_MS;
      } else {
        sagLowSince = 0;
      }
    }
    bool sagEase = (long)(sagEaseUntil - now) > 0;

    // Once the battery is flat, stay stopped until the rover is rebooted
    // (uses the resting estimate, so a dip when the motors start does not count)
    static bool cutoffLatched = false;
    static unsigned long lowSince = 0;
    if (HAVE_DIVIDER && battV < V_CUTOFF) {
      if (lowSince == 0) lowSince = now;
      if (now - lowSince >= CUTOFF_HOLD_MS) cutoffLatched = true;
    } else {
      lowSince = 0;
    }
    bool cutoff = cutoffLatched;

    // limp mode with hysteresis: enter below V_LIMP, leave above V_LIMP_EXIT
    static bool limp = false;
    if (HAVE_DIVIDER) {
      if (battV < V_LIMP) limp = true;
      else if (battV > V_LIMP_EXIT) limp = false;
    }

    // ----- overload (stall) guard -----
    // a stall sags the battery well beyond what this rover normally sags
    float expectedSag = sagK * workload;
    bool overloadNow = HAVE_DIVIDER && workload >= OVERLOAD_POWER &&
                       (vRest - vNow) >= fmaxf(OVERLOAD_SAG, expectedSag + OVERLOAD_EXTRA);
    if (overloadNow) {
      if (hardSince == 0) hardSince = now;
      if (now - hardSince >= OVERLOAD_MS) coolUntil = now + OVERLOAD_COOL_MS;
    } else {
      hardSince = 0;
    }
    bool overload = (long)(coolUntil - now) > 0;
    bool driverFault = PIN_FAULT >= 0 && digitalRead(PIN_FAULT) == LOW;

    float cap = MODE_CAP[mode];
    stateText = "OK";
    if (limp || sagEase) {
      cap = clampf(cap, 0, 0.30f);
      stateText = "LIMP";
    }
    if (overload) {
      cap = clampf(cap, 0, OVERLOAD_CAP);
      stateText = "OVERLOAD";
    }
    // ----- turbo: full power for a few seconds, only when everything is healthy -----
    float ramp = MODE_RAMP[mode];
    bool turbo = (long)(turboUntil - now) > 0;
    if (turbo && strcmp(stateText, "OK") == 0) {
      cap = 1.0f;
      ramp = MODE_RAMP[2];
    } else if (turbo) {
      turboUntil = 0;          // low battery or overload cancels turbo
    }

    // ----- auto-stop after idling -----
    if (!sleeping && !playing && now - lastActive >= IDLE_SLEEP_MS) sleeping = true;
    if (sleeping) stateText = "SLEEP";

    if (driverFault) stateText = "FAULT";
    if (cutoff) stateText = "LOWBATT";
    if (failsafe) stateText = "FAILSAFE";

    // ----- where the drive command comes from: joystick or a recorded path -----
    float x = cmdX, y = cmdY;
    if ((long)(now - pathNext) >= 0) {
      if (recording) {
        pathX[pathLen] = (int8_t)(cmdX * 100);
        pathY[pathLen] = (int8_t)(cmdY * 100);
        if (++pathLen >= PATH_STEPS) recording = false;   // 60 s limit reached
      }
      if (playing) {
        if (playIdx >= pathLen) playing = false;        // replay finished
        else playIdx++;
      }
      pathNext = now + PATH_STEP_MS;
    }
    if (playing && playIdx > 0) {
      x = pathX[playIdx - 1] / 100.0f;
      y = pathY[playIdx - 1] / 100.0f;
    }
    if (failsafe || cutoff || driverFault) {
      x = 0;
      y = 0;
      playing = false;
    }
    effX = x;
    effY = y;

    // ----- sharp turns: ease off power so the rover doesn't skid or tip -----
    float ax = fabsf(x);
    if (ax > 0.5f) cap *= 1.0f - TURN_SLOWDOWN * ((ax - 0.5f) / 0.5f);

    // differential drive mix
    float left = clampf(y + x, -1, 1) * cap;
    float right = clampf(y - x, -1, 1) * cap;
    // straight-line trim: slow the faster wheel slightly
    if (trim > 0) left *= (1.0f - trim);
    if (trim < 0) right *= (1.0f + trim);

    // ramp toward target; stop requests are not ramped when failing safe
    if (failsafe || cutoff || driverFault) {
      curA = 0;
      curB = 0;
    } else {
      float targetA = SWAP_SIDES ? right : left;
      float targetB = SWAP_SIDES ? left : right;
      curA += clampf(targetA - curA, -ramp, ramp);
      curB += clampf(targetB - curB, -ramp, ramp);
    }

    writeMotor(PIN_IN1, PIN_IN2, curA, INVERT_A);
    writeMotor(PIN_IN3, PIN_IN4, curB, INVERT_B);
    updateLeds(now);

    // ----- trip stats -----
    if (fmaxf(fabsf(curA), fabsf(curB)) > 0.05f) driveMs += 20;
    if (vNow > 0.5f && vNow < minV) minV = vNow;     // lowest voltage under load
  }

  // telemetry, every 500 ms
  if (now - lastTelemetry >= 500) {
    lastTelemetry = now;
    // range estimate: battery % used per minute of actual driving,
    // from the steady (load-compensated) %
    int usedPct = startPct >= 0 ? startPct - pctShown : 0;
    if (usedPct < 0) usedPct = 0;
    if (driveMs >= 60000 && usedPct >= 2) {
      float perMin = usedPct / (driveMs / 60000.0f);
      rangeMin = (int)(pctShown / perMin);
    }
    const char* activity = "-";
    if ((long)(turboUntil - now) > 0) activity = "TURBO";
    else if (recording) activity = "REC";
    else if (playing) activity = "PLAY";
    else if ((long)(turboReadyAt - now) > 0) activity = "COOL";

    char out[180];
    snprintf(out, sizeof(out), "T,%.2f,%d,%d,%s,%s,%.2f,%s,%d,%lu,%.2f,%d,%s,%d,%.2f,%.3f",
             battV, pctShown, mode, stateText, FW_VERSION, trim, selfTest,
             rangeMin, driveMs / 1000, minV < 9.0f ? minV : vNow, usedPct, activity,
             pathLen / 10, vNow, calib);
    ws.broadcastTXT(out);
  }
}
