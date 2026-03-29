// ─── config.h ────────────────────────────────────────────
// ESP-01S relay watchdog configuration.
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
#define AUTO_OFF_MS       (2UL * 60 * 60 * 1000)   // 2 hours
#define HEARTBEAT_MS      5000UL                    // idle blink every 5 s
#define BLINK_MS          80UL                      // single blink duration

// ── HTTP ─────────────────────────────────────────────────
#define HTTP_PORT         80

#endif
