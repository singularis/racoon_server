// ─── firmware.ino ────────────────────────────────────────
// ESP-01S relay watchdog for 14 TB HDD bay power control.
//
// Endpoints:
//   POST /power/on    → close relay, reset auto-off timer
//   POST /power/off   → open relay
//   GET  /power/status → {"powered":bool,"uptime_sec":N}
//   POST /ping        → keep-alive, reset auto-off timer
//   GET  /health      → {"wifi_rssi":N,"heap_free":N,"relay_state":bool}
//
// Safety: 2-hour auto-off if no /ping received.
// LED patterns: fast-blink WiFi connecting, heartbeat when idle,
//   2 blinks /power/on, 3 blinks /power/off, 4 blinks /ping.
// ──────────────────────────────────────────────────────────

#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>

#include "config.h"
#include "secrets.h"

// ── State ────────────────────────────────────────────────
static ESP8266WebServer server(HTTP_PORT);

static bool     relayOn        = false;
static unsigned long powerOnAt = 0;      // millis() when relay closed
static unsigned long lastPing  = 0;      // millis() of last keep-alive

// Relay and LED async queue
static uint8_t       blinkRemain = 0;    // blinks left to emit
static unsigned long blinkNext   = 0;    // next toggle time
static bool          blinkState  = false;
static bool          heartbeatPhase = false; // true = LED on half
static unsigned long heartbeatAt  = 0;   // next heartbeat phase flip

static bool          pendingRelay      = false;
static bool          pendingRelayState = false;
static unsigned long pendingRelayNext  = 0;

// Boot stabilization guard — relay is blocked for BOOT_STABLE_MS after boot
// to let the 3.3 V regulator settle before the coil pulls extra current.
static unsigned long bootStableAt = 0;   // set in setup()

// Last reset reason — readable via GET /health
static String lastResetReason;

// ── Helpers ──────────────────────────────────────────────

static void setRelay(bool on) {
  // Mitigate ESP-01S LDO brownout: temporarily lower WiFi TX power 
  // so the relay coil's inrush current doesn't crash the WiFi PHY.
  WiFi.setOutputPower(0.0);

  relayOn = on;
  digitalWrite(RELAY_PIN, on ? RELAY_ON : RELAY_OFF);
  
  if (on) {
    powerOnAt = millis();
    lastPing  = millis();
  }
  if (blinkRemain == 0) {
    digitalWrite(LED_PIN, on ? LED_ON : LED_OFF);
  }

  // Allow coil magnetic field and LDO voltage to stabilize
  delay(50);
  
  // Restore to a lower TX power (15.0 dBm instead of 20.5) to keep combined
  // current draw (relay coil + WiFi) under the AMS1117-3.3 LDO limits.
  WiFi.setOutputPower(15.0);
}

// Queue N short blinks (non-blocking, handled in loop)
static void queueBlinks(uint8_t n) {
  blinkRemain = n * 2;            // each blink = ON + OFF
  blinkNext   = millis();
  blinkState  = false;
}

static void sendJSON(int code, const String &json) {
  server.sendHeader("Connection", "close");
  server.send(code, "application/json", json);
}

// ── Handlers ─────────────────────────────────────────────

static void handlePowerOn() {
  sendJSON(200, "{\"ok\":true,\"powered\":true}");
  queueBlinks(2);
  // Delay relay switch: let WiFi finish Tx AND wait until boot is stable
  pendingRelay = true;
  pendingRelayState = true;
  unsigned long earliest = millis() + 750;
  pendingRelayNext = (bootStableAt > earliest) ? bootStableAt : earliest;
}

static void handlePowerOff() {
  sendJSON(200, "{\"ok\":true,\"powered\":false}");
  queueBlinks(3);
  pendingRelay = true;
  pendingRelayState = false;
  unsigned long earliest = millis() + 750;
  pendingRelayNext = (bootStableAt > earliest) ? bootStableAt : earliest;
}

static void handleStatus() {
  bool state = pendingRelay ? pendingRelayState : relayOn;
  unsigned long up = state ? (millis() - powerOnAt) / 1000 : 0;
  sendJSON(200, "{\"powered\":" + String(state ? "true" : "false") +
                ",\"uptime_sec\":" + String(up) + "}");
}

static void handlePing() {
  bool state = pendingRelay ? pendingRelayState : relayOn;
  if (state) lastPing = millis();
  queueBlinks(4);
  sendJSON(200, "{\"ok\":true,\"ping\":\"pong\"}");
}

static void handleHealth() {
  bool state = pendingRelay ? pendingRelayState : relayOn;
  sendJSON(200, "{\"wifi_rssi\":" + String(WiFi.RSSI()) +
                ",\"heap_free\":" + String(ESP.getFreeHeap()) +
                ",\"relay_state\":" + String(state ? "true" : "false") +
                ",\"reset_reason\":\"" + lastResetReason + "\"" +
                ",\"uptime_ms\":" + String(millis()) + "}");
}

static void handleNotFound() {
  sendJSON(404, "{\"error\":\"not_found\"}");
}

// ── Setup ────────────────────────────────────────────────

void setup() {
  // Capture reset reason before anything else overwrites it
  lastResetReason = ESP.getResetReason();

  // Relay OFF immediately (pull-up safe default)
  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, RELAY_OFF);

  // LED
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LED_OFF);

  // WiFi — fast-blink while connecting
  WiFi.persistent(false);           // don't write credentials to flash
  WiFi.setAutoReconnect(true);      // recover from transient AP drops
  WiFi.setSleepMode(WIFI_NONE_SLEEP); // prevent modem-sleep crash after ~20 s idle
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) {
    digitalWrite(LED_PIN, LED_ON);
    delay(100);
    digitalWrite(LED_PIN, LED_OFF);
    delay(100);
  }
  // connected — single blink to confirm
  queueBlinks(1);

  // Mark when the relay is allowed to switch (3 s after boot)
  bootStableAt = millis() + BOOT_STABLE_MS;

  // Routes
  server.on("/power/on",     HTTP_POST, handlePowerOn);
  server.on("/power/off",    HTTP_POST, handlePowerOff);
  server.on("/power/status", HTTP_GET,  handleStatus);
  server.on("/ping",         HTTP_POST, handlePing);
  server.on("/health",       HTTP_GET,  handleHealth);
  server.onNotFound(handleNotFound);
  server.begin();
}

// ── Loop ─────────────────────────────────────────────────

void loop() {
  server.handleClient();

  unsigned long now = millis();

  // ── Async relay switch ─────────────────────────────────
  if (pendingRelay && now >= pendingRelayNext) {
    pendingRelay = false;
    setRelay(pendingRelayState);
  }

  // ── Auto-off safety ────────────────────────────────────
  if (relayOn && !pendingRelay && (now - lastPing >= AUTO_OFF_MS)) {
    setRelay(false);                 // hard cut — acceptable
  }

  // ── LED blink queue ────────────────────────────────────
  if (blinkRemain > 0 && now >= blinkNext) {
    blinkState = !blinkState;
    digitalWrite(LED_PIN, blinkState ? LED_ON : LED_OFF);
    blinkNext = now + BLINK_MS;
    blinkRemain--;
    if (blinkRemain == 0) {
      digitalWrite(LED_PIN, relayOn ? LED_ON : LED_OFF);
    }
  }

  // ── Idle heartbeat — fully non-blocking ──────────────
  // Phase 0 (heartbeatPhase=false): flash LED on for HEARTBEAT_PULSE_MS
  // Phase 1 (heartbeatPhase=true ): restore LED, wait HEARTBEAT_MS for next beat
  if (blinkRemain == 0 && now >= heartbeatAt) {
    if (relayOn) {
      // Keep LED steady when relay is ON to avoid 5-second LDO power spikes
      digitalWrite(LED_PIN, LED_ON);
      heartbeatAt    = now + HEARTBEAT_MS;
      heartbeatPhase = false;
    } else {
      if (!heartbeatPhase) {
        // start of pulse: flip LED briefly
        digitalWrite(LED_PIN, LED_ON);
        heartbeatAt    = now + HEARTBEAT_PULSE_MS;
        heartbeatPhase = true;
      } else {
        // end of pulse: restore and schedule next beat
        digitalWrite(LED_PIN, LED_OFF);
        heartbeatAt    = now + HEARTBEAT_MS;
        heartbeatPhase = false;
      }
    }
  }

  yield(); // feed software WDT and process WiFi background tasks
}
