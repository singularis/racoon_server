// ─── config.h ────────────────────────────────────────────
// ESP-01S relay controller configuration.
// Safe to commit — no secrets here.
// ──────────────────────────────────────────────────────────

#ifndef CONFIG_H
#define CONFIG_H

// ── Relay ────────────────────────────────────────────────
#define RELAY_PIN         0        // GPIO0 → relay IN
#define RELAY_ON          HIGH     // active-high relay module
#define RELAY_OFF         LOW

// ── LED (ESP-01S built-in, active LOW) ───────────────────
#define LED_PIN           2        // GPIO2 built-in blue LED
#define LED_ON            LOW
#define LED_OFF           HIGH

// ── Timers ───────────────────────────────────────────────
#define HEARTBEAT_MS      5000UL                    // idle blink every 5 s
#define BLINK_MS          80UL                      // single blink duration
#define BOOT_STABLE_MS    3000UL                    // relay blocked for 3 s after boot
#define HEARTBEAT_PULSE_MS 30UL                     // LED-on time for heartbeat pulse
#define WIFI_TIMEOUT_MS   60000UL                   // reboot after 60 s without WiFi

// ── HTTP ─────────────────────────────────────────────────
#define HTTP_PORT         80

// Overflow-safe millis() deadline check (~49.7-day rollover safe)
#define TIME_REACHED(now, deadline) ((long)((now) - (deadline)) >= 0)

#endif
