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

// LED async blink queue
static uint8_t       blinkRemain = 0;    // blinks left to emit
static unsigned long blinkNext   = 0;    // next toggle time
static bool          blinkState  = false;
static unsigned long heartbeatAt = 0;    // next idle heartbeat

// ── Helpers ──────────────────────────────────────────────

static void setRelay(bool on) {
  relayOn = on;
  digitalWrite(RELAY_PIN, on ? RELAY_ON : RELAY_OFF);
  if (on) {
    powerOnAt = millis();
    lastPing  = millis();
  }
  if (blinkRemain == 0) {
    digitalWrite(LED_PIN, on ? LED_ON : LED_OFF);
  }
}

// Queue N short blinks (non-blocking, handled in loop)
static void queueBlinks(uint8_t n) {
  blinkRemain = n * 2;            // each blink = ON + OFF
  blinkNext   = millis();
  blinkState  = false;
}

static void sendJSON(int code, const String &json) {
  server.send(code, "application/json", json);
}

// ── Handlers ─────────────────────────────────────────────

static void handlePowerOn() {
  setRelay(true);
  queueBlinks(2);
  sendJSON(200, "{\"ok\":true,\"powered\":true}");
}

static void handlePowerOff() {
  setRelay(false);
  queueBlinks(3);
  sendJSON(200, "{\"ok\":true,\"powered\":false}");
}

static void handleStatus() {
  unsigned long up = relayOn ? (millis() - powerOnAt) / 1000 : 0;
  sendJSON(200, "{\"powered\":" + String(relayOn ? "true" : "false") +
                ",\"uptime_sec\":" + String(up) + "}");
}

static void handlePing() {
  if (relayOn) lastPing = millis();
  queueBlinks(4);
  sendJSON(200, "{\"ok\":true,\"ping\":\"pong\"}");
}

static void handleHealth() {
  sendJSON(200, "{\"wifi_rssi\":" + String(WiFi.RSSI()) +
                ",\"heap_free\":" + String(ESP.getFreeHeap()) +
                ",\"relay_state\":" + String(relayOn ? "true" : "false") + "}");
}

static void handleNotFound() {
  sendJSON(404, "{\"error\":\"not_found\"}");
}

// ── Setup ────────────────────────────────────────────────

void setup() {
  // Relay OFF immediately (pull-up safe default)
  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, RELAY_OFF);

  // LED
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LED_OFF);

  // WiFi — fast-blink while connecting
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

  // ── Auto-off safety ────────────────────────────────────
  if (relayOn && (now - lastPing >= AUTO_OFF_MS)) {
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

  // ── Idle heartbeat (inverse if relay is ON) ────────────
  if (blinkRemain == 0 && now >= heartbeatAt) {
    digitalWrite(LED_PIN, relayOn ? LED_OFF : LED_ON);
    delay(30);                       // tiny blocking blink — acceptable
    digitalWrite(LED_PIN, relayOn ? LED_ON : LED_OFF);
    heartbeatAt = now + HEARTBEAT_MS;
  }
}
