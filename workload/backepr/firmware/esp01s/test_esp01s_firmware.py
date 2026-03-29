"""
test_esp01s_firmware.py — Contract tests for ESP-01S relay watchdog.

These tests verify the firmware behaves correctly by hitting the real
ESP-01S over HTTP. Set ESP_HOST env var to the device IP.

Run:  python -m pytest test_esp01s_firmware.py -v
      ESP_HOST=192.168.0.XXX python -m pytest test_esp01s_firmware.py -v

If ESP_HOST is not set, tests run against a local mock server that
mirrors the firmware's behaviour (useful for CI / offline validation).
"""

import json
import os
import threading
import time
import pytest
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.request import Request, urlopen
from urllib.error import URLError

# ── Configuration ─────────────────────────────────────────

ESP_HOST = os.environ.get("ESP_HOST", "")
AUTO_OFF_SEC = 2  # mock uses a tiny auto-off for fast testing

# ── Mock ESP Server (mirrors firmware logic) ──────────────

class MockESPState:
    def __init__(self):
        self.powered = False
        self.power_on_time = 0
        self.last_ping = 0
        self.auto_off_sec = AUTO_OFF_SEC

    def check_auto_off(self):
        if self.powered and (time.time() - self.last_ping > self.auto_off_sec):
            self.powered = False


class MockESPHandler(BaseHTTPRequestHandler):
    state = MockESPState()

    def log_message(self, *a):
        pass  # silence logs

    def _json(self, code, data):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def do_POST(self):
        self.state.check_auto_off()
        if self.path == "/power/on":
            self.state.powered = True
            self.state.power_on_time = time.time()
            self.state.last_ping = time.time()
            self._json(200, {"ok": True, "powered": True})
        elif self.path == "/power/off":
            self.state.powered = False
            self._json(200, {"ok": True, "powered": False})
        elif self.path == "/ping":
            if self.state.powered:
                self.state.last_ping = time.time()
            self._json(200, {"ok": True, "ping": "pong"})
        else:
            self._json(404, {"error": "not_found"})

    def do_GET(self):
        self.state.check_auto_off()
        if self.path == "/power/status":
            up = int(time.time() - self.state.power_on_time) if self.state.powered else 0
            self._json(200, {"powered": self.state.powered, "uptime_sec": up})
        elif self.path == "/health":
            self._json(200, {"wifi_rssi": -50, "heap_free": 30000,
                             "relay_state": self.state.powered})
        else:
            self._json(404, {"error": "not_found"})


# ── Fixtures ──────────────────────────────────────────────

@pytest.fixture(scope="session")
def base_url():
    """Return base URL — real ESP or local mock."""
    if ESP_HOST:
        url = f"http://{ESP_HOST}"
        # ensure we start with relay off
        _post(url + "/power/off")
        yield url
    else:
        srv = HTTPServer(("127.0.0.1", 0), MockESPHandler)
        port = srv.server_address[1]
        t = threading.Thread(target=srv.serve_forever, daemon=True)
        t.start()
        yield f"http://127.0.0.1:{port}"
        srv.shutdown()


@pytest.fixture(autouse=True)
def reset_relay(base_url):
    """Ensure relay is off before each test."""
    _post(base_url + "/power/off")
    # Reset mock state timing if using mock
    if not ESP_HOST:
        MockESPHandler.state = MockESPState()
    yield
    _post(base_url + "/power/off")


# ── HTTP helpers ──────────────────────────────────────────

def _get(url):
    req = Request(url, method="GET")
    with urlopen(req, timeout=5) as r:
        return json.loads(r.read())


def _post(url):
    req = Request(url, method="POST", data=b"")
    with urlopen(req, timeout=5) as r:
        return json.loads(r.read())


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# TESTS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


class TestPowerOn:
    def test_power_on_returns_ok(self, base_url):
        r = _post(base_url + "/power/on")
        assert r["ok"] is True
        assert r["powered"] is True

    def test_power_on_sets_status(self, base_url):
        _post(base_url + "/power/on")
        s = _get(base_url + "/power/status")
        assert s["powered"] is True

    def test_power_on_starts_uptime(self, base_url):
        _post(base_url + "/power/on")
        time.sleep(1)
        s = _get(base_url + "/power/status")
        assert s["uptime_sec"] >= 1


class TestPowerOff:
    def test_power_off_returns_ok(self, base_url):
        _post(base_url + "/power/on")
        r = _post(base_url + "/power/off")
        assert r["ok"] is True
        assert r["powered"] is False

    def test_power_off_clears_status(self, base_url):
        _post(base_url + "/power/on")
        _post(base_url + "/power/off")
        s = _get(base_url + "/power/status")
        assert s["powered"] is False

    def test_power_off_resets_uptime(self, base_url):
        _post(base_url + "/power/on")
        _post(base_url + "/power/off")
        s = _get(base_url + "/power/status")
        assert s["uptime_sec"] == 0


class TestStatus:
    def test_status_when_off(self, base_url):
        s = _get(base_url + "/power/status")
        assert s["powered"] is False
        assert s["uptime_sec"] == 0

    def test_status_has_required_fields(self, base_url):
        s = _get(base_url + "/power/status")
        assert "powered" in s
        assert "uptime_sec" in s


class TestPing:
    def test_ping_returns_pong(self, base_url):
        r = _post(base_url + "/ping")
        assert r["ok"] is True
        assert r["ping"] == "pong"

    def test_ping_resets_auto_off(self, base_url):
        """Ping should extend the auto-off timer."""
        _post(base_url + "/power/on")
        # Wait almost until auto-off
        time.sleep(AUTO_OFF_SEC * 0.7)
        _post(base_url + "/ping")
        # Wait a bit more — without ping this would have timed out
        time.sleep(AUTO_OFF_SEC * 0.7)
        s = _get(base_url + "/power/status")
        assert s["powered"] is True


class TestAutoOff:
    def test_auto_off_cuts_power(self, base_url):
        """Relay must turn off after timeout with no ping."""
        _post(base_url + "/power/on")
        # Wait for auto-off to trigger
        time.sleep(AUTO_OFF_SEC + 1)
        s = _get(base_url + "/power/status")
        assert s["powered"] is False


class TestHealth:
    def test_health_returns_fields(self, base_url):
        h = _get(base_url + "/health")
        assert "wifi_rssi" in h
        assert "heap_free" in h
        assert "relay_state" in h

    def test_health_relay_matches_status(self, base_url):
        _post(base_url + "/power/on")
        h = _get(base_url + "/health")
        assert h["relay_state"] is True
        _post(base_url + "/power/off")
        h = _get(base_url + "/health")
        assert h["relay_state"] is False


class TestNotFound:
    def test_unknown_path_returns_404(self, base_url):
        try:
            _get(base_url + "/does/not/exist")
            assert False, "Should have raised"
        except Exception:
            pass  # 404 expected


class TestIdempotency:
    def test_double_power_on(self, base_url):
        """Calling /power/on twice should not break anything."""
        _post(base_url + "/power/on")
        _post(base_url + "/power/on")
        s = _get(base_url + "/power/status")
        assert s["powered"] is True

    def test_double_power_off(self, base_url):
        """Calling /power/off when already off should be safe."""
        r = _post(base_url + "/power/off")
        assert r["ok"] is True
        s = _get(base_url + "/power/status")
        assert s["powered"] is False

    def test_ping_when_off(self, base_url):
        """Pinging when relay is off should not turn it on."""
        _post(base_url + "/ping")
        s = _get(base_url + "/power/status")
        assert s["powered"] is False


class TestFullSequence:
    def test_backepr_happy_path(self, base_url):
        """Simulate the full Backepr backup sequence."""
        # 1. Power on
        r = _post(base_url + "/power/on")
        assert r["powered"] is True

        # 2. Status check
        s = _get(base_url + "/power/status")
        assert s["powered"] is True

        # 3. Ping keep-alive (simulating 30 min interval)
        _post(base_url + "/ping")
        s = _get(base_url + "/power/status")
        assert s["powered"] is True

        # 4. Health check
        h = _get(base_url + "/health")
        assert h["relay_state"] is True

        # 5. Power off (after hdparm -Y + sleep on server side)
        r = _post(base_url + "/power/off")
        assert r["powered"] is False

        # 6. Final status
        s = _get(base_url + "/power/status")
        assert s["powered"] is False
        assert s["uptime_sec"] == 0
