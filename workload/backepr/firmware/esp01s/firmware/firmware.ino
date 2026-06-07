// ─── firmware.ino ────────────────────────────────────────
// ESP-01S relay controller for 14 TB HDD bay power control.
//
// Endpoints:
//   POST /click        → toggle relay pulse
//   GET  /power/status → {"powered":bool,"uptime_sec":N}
//   GET  /health       → {"wifi_rssi":N,"heap_free":N,...}
//   POST /reboot       → restart ESP module
//
// LED: fast-blink during WiFi connect, steady ON when powered,
//   heartbeat pulse when idle, double-flash on /click.
// ──────────────────────────────────────────────────────────

#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>

#include "config.h"
#include "secrets.h"

// ── State ────────────────────────────────────────────────
static ESP8266WebServer server(HTTP_PORT);

static bool     virtualPowerOn = false;
static unsigned long powerOnAt = 0;      // millis() when virtually powered on

static bool     relayActive    = false;
static unsigned long relayActiveUntil = 0; // millis() when relay should turn off

// Relay and LED async queue
static uint8_t       blinkRemain = 0;    // blinks left to emit
static unsigned long blinkNext   = 0;    // next toggle time
static bool          blinkState  = false;
static bool          heartbeatPhase = false; // true = LED on half
static unsigned long heartbeatAt  = 0;   // next heartbeat phase flip

static bool          pendingClick      = false;
static unsigned long pendingClickNext  = 0;

// Boot stabilization guard — relay is blocked for BOOT_STABLE_MS after boot
// to let the 3.3 V regulator settle before the coil pulls extra current.
static unsigned long bootStableAt = 0;   // set in setup()

// Last reset reason — readable via GET /health
static char lastResetReason[48];
static unsigned long wifiLostAt = 0;    // millis() when WiFi was lost (0 = connected)

// ── Helpers ──────────────────────────────────────────────

static void triggerClick() {
  WiFi.setOutputPower(0.0);
  digitalWrite(RELAY_PIN, RELAY_ON);
  relayActive = true;
  relayActiveUntil = millis() + 1000; // 1-second pulse
  delay(50);
  WiFi.setOutputPower(15.0);
}

static void setVirtualPower(bool on) {
  virtualPowerOn = on;
  
  if (on) {
    powerOnAt = millis();
  }
  
  if (blinkRemain == 0) {
    digitalWrite(LED_PIN, on ? LED_ON : LED_OFF);
  }

  triggerClick();
}

// Queue N short blinks (non-blocking, handled in loop)
static void queueBlinks(uint8_t n) {
  blinkRemain = n * 2;            // each blink = ON + OFF
  blinkNext   = millis();
  blinkState  = false;
}

static void sendJSON(int code, const char* json) {
  server.sendHeader("Connection", "close");
  server.send(code, "application/json", json);
}

// ── Handlers ─────────────────────────────────────────────

static void handleClick() {
  if (pendingClick) {
    sendJSON(429, "{\"error\":\"click_pending\"}");
    return;
  }

  bool expectedState = !virtualPowerOn;
  sendJSON(200, expectedState ? "{\"ok\":true,\"powered\":true}" : "{\"ok\":true,\"powered\":false}");
  queueBlinks(2);
  pendingClick = true;
  unsigned long earliest = millis() + 750;
  pendingClickNext = (bootStableAt > earliest) ? bootStableAt : earliest;
}

static void handleStatus() {
  bool state = virtualPowerOn;
  if (pendingClick) state = !state;
  unsigned long up = state ? (millis() - powerOnAt) / 1000 : 0;

  if (state) {
    char response[64];
    snprintf(response, sizeof(response), "{\"powered\":true,\"uptime_sec\":%lu}", up);
    sendJSON(200, response);
  } else {
    sendJSON(200, "{\"powered\":false,\"uptime_sec\":0}");
  }
}

static void handleHealth() {
  bool state = virtualPowerOn;
  if (pendingClick) state = !state;

  char response[256];
  snprintf(response, sizeof(response),
           "{\"wifi_rssi\":%d,\"heap_free\":%u,\"relay_state\":%s,\"relay_active\":%s,\"reset_reason\":\"%s\",\"uptime_ms\":%lu}",
           WiFi.RSSI(),
           ESP.getFreeHeap(),
           state ? "true" : "false",
           relayActive ? "true" : "false",
           lastResetReason,
           millis());
  sendJSON(200, response);
}

static void handleNotFound() {
  sendJSON(404, "{\"error\":\"not_found\"}");
}

static void handleReboot() {
  sendJSON(200, "{\"ok\":true,\"message\":\"rebooting\"}");
  delay(500);
  ESP.restart();
}

// ── Setup ────────────────────────────────────────────────

void setup() {
  // Capture reset reason before anything else overwrites it
  snprintf(lastResetReason, sizeof(lastResetReason), "%s",
           ESP.getResetReason().c_str());

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
  unsigned long wifiDeadline = millis() + WIFI_TIMEOUT_MS;
  while (WiFi.status() != WL_CONNECTED) {
    if (TIME_REACHED(millis(), wifiDeadline)) ESP.restart();
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
  server.on("/click",        HTTP_POST, handleClick);
  server.on("/power/status", HTTP_GET,  handleStatus);
  server.on("/health",       HTTP_GET,  handleHealth);
  server.on("/reboot",       HTTP_POST, handleReboot);
  server.onNotFound(handleNotFound);
  server.begin();
}

// ── Loop ─────────────────────────────────────────────────

void loop() {
  server.handleClient();

  unsigned long now = millis();

  // ── WiFi reconnection — reboot if disconnected too long ─
  if (WiFi.status() != WL_CONNECTED) {
    if (wifiLostAt == 0) wifiLostAt = now;
    else if (TIME_REACHED(now, wifiLostAt + WIFI_TIMEOUT_MS)) ESP.restart();
  } else {
    wifiLostAt = 0;
  }

  // ── Async relay switch ─────────────────────────────────
  if (pendingClick && TIME_REACHED(now, pendingClickNext)) {
    pendingClick = false;
    setVirtualPower(!virtualPowerOn);
  }

  // ── Turn off pulse relay ───────────────────────────────
  if (relayActive && TIME_REACHED(now, relayActiveUntil)) {
    relayActive = false;
    WiFi.setOutputPower(0.0);
    digitalWrite(RELAY_PIN, RELAY_OFF);
    delay(50);
    WiFi.setOutputPower(15.0);
  }

  // ── LED blink queue ────────────────────────────────────
  if (blinkRemain > 0 && TIME_REACHED(now, blinkNext)) {
    blinkState = !blinkState;
    digitalWrite(LED_PIN, blinkState ? LED_ON : LED_OFF);
    blinkNext = now + BLINK_MS;
    blinkRemain--;
    if (blinkRemain == 0) {
      digitalWrite(LED_PIN, virtualPowerOn ? LED_ON : LED_OFF);
    }
  }

  // ── Idle heartbeat — fully non-blocking ──────────────
  // Phase 0 (heartbeatPhase=false): flash LED on for HEARTBEAT_PULSE_MS
  // Phase 1 (heartbeatPhase=true ): restore LED, wait HEARTBEAT_MS for next beat
  if (blinkRemain == 0 && TIME_REACHED(now, heartbeatAt)) {
    if (virtualPowerOn) {
      // Keep LED steady when virtualPowerOn is ON
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
