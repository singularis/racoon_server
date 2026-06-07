# ESP-01S Relay Controller — Backepr

Remote HTTP relay controller for the 14 TB Backepr archive HDD bay, running on an ESP-01S (ESP8266) module.

---

## Endpoints

| Endpoint | Method | Response | Description |
|---|---|---|---|
| `/click` | `POST` | `{"ok":true,"powered":true}` | Toggles virtual power state and pulses relay for 1 s. Returns `429` if a click is already pending. |
| `/power/status` | `GET` | `{"powered":true,"uptime_sec":300}` | Returns virtual power state and uptime in seconds. |
| `/health` | `GET` | `{"wifi_rssi":-35,"heap_free":49120,...}` | Diagnostic telemetry: RSSI, free heap, relay state, reset reason, uptime. |
| `/reboot` | `POST` | `{"ok":true,"message":"rebooting"}` | Triggers a hardware-level restart (`ESP.restart()`). |

---

## Design Decisions

### Why the ESP has no auto-off watchdog

The ESP-01S is wired to a momentary switch on the HDD bay. It has **zero hardware feedback** — no current sensor, no connection line — to read the actual power state of the drive.

If the ESP ever lost sync (e.g. rebooted while the drive was physically ON), a watchdog "safety click" meant to turn the drive off could actually **turn it on** in the middle of the night, or **cut power mid-backup**.

**Solution:** The host server (`racoon`) knows the true drive state by checking block devices (`/dev/sdX`) and mount tables. All safety timers and power lifecycle management live server-side.

### Why no dynamic `String` allocations

The ESP-01S has only 80 KB of RAM. The Arduino `String` class dynamically allocates heap memory and causes fragmentation over weeks of continuous operation.

**Solution:** All HTTP responses use stack-allocated `char[]` buffers with `snprintf`. The firmware can run indefinitely without heap fragmentation.

### Why WiFi auto-recovers

If the router reboots or WiFi drops, the ESP attempts reconnection automatically via `WiFi.setAutoReconnect(true)`. If WiFi remains unavailable for 60 seconds (at boot or during runtime), the ESP reboots itself to start with a clean connection state.

---

## Hardware Safeguards

| Safeguard | Description |
|---|---|
| **Boot stabilization** | Relay is blocked for 3 s after boot to let the 3.3 V regulator settle before the coil draws current. |
| **Async HTTP response** | `/click` sends the HTTP response first, then delays 750 ms before pulsing the relay. Prevents socket hangs. |
| **Rate-limiting** | Rapid `/click` requests return HTTP `429` while a click is pending. Prevents relay state desync. |
| **millis() overflow safety** | All timer comparisons use the `TIME_REACHED` macro (signed-cast arithmetic), safe across the ~49.7-day `unsigned long` overflow boundary. |
| **WiFi self-healing** | Reboots automatically after 60 s of lost WiFi to recover from AP drops or router restarts. |

---

## Compile & Flash

1. Open **Arduino IDE**.
2. Open `firmware/firmware.ino`.
3. Ensure `firmware/secrets.h` exists (see [WiFi Credentials](#wifi-credentials)).
4. Board: **Generic ESP8266 Module**, Flash: **1 MB (FS:64KB OTA:~470KB)**.
5. Connect programmer in **PROG/FLASH** mode → click **Upload**.

---

## Network Configuration

The ESP uses DHCP. Assign a **static DHCP reservation** on your router for the ESP's MAC address so the IP remains stable.

---

## WiFi Credentials

Create `firmware/secrets.h` (this file is `.gitignored` and never committed):

```cpp
#ifndef SECRETS_H
#define SECRETS_H

#define WIFI_SSID     "your_wifi_ssid"
#define WIFI_PASSWORD "your_wifi_password"

#endif
```

To rotate credentials, edit this file and re-flash the board.

---

## Testing

### Functional tests (live device, zero dependencies)

```powershell
python run_functional_tests.py 192.168.0.12
```

Runs an end-to-end sequence: health check → click ON → rate-limit (429) → status → click OFF → reboot.

### Contract tests (pytest, with local mock fallback)

```powershell
# Against local mock (no hardware needed)
python -m pytest test_esp01s_firmware.py -v

# Against real device
$env:ESP_HOST="192.168.0.12"; python -m pytest test_esp01s_firmware.py -v
```
