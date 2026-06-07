"""
test_esp01s_firmware.py — Contract tests for ESP-01S relay controller.

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
from urllib.error import HTTPError

# ── Configuration ─────────────────────────────────────────

ESP_HOST = os.environ.get("ESP_HOST", "")

# ── Mock ESP Server (mirrors firmware logic) ──────────────

class MockESPState:
    def __init__(self):
        self.powered = False
        self.power_on_time = 0


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
        if self.path == "/click":
            self.state.powered = not self.state.powered
            if self.state.powered:
                self.state.power_on_time = time.time()
            self._json(200, {"ok": True, "powered": self.state.powered})
        elif self.path == "/reboot":
            self._json(200, {"ok": True, "message": "rebooting"})
        else:
            self._json(404, {"error": "not_found"})

    def do_GET(self):
        if self.path == "/power/status":
            up = int(time.time() - self.state.power_on_time) if self.state.powered else 0
            self._json(200, {
                "powered": self.state.powered,
                "uptime_sec": up
            })
        elif self.path == "/health":
            self._json(200, {"wifi_rssi": -50, "heap_free": 30000,
                             "relay_state": self.state.powered,
                             "relay_active": False,
                             "reset_reason": "Power On",
                             "uptime_ms": 0})
        else:
            self._json(404, {"error": "not_found"})


# ── Fixtures ──────────────────────────────────────────────

@pytest.fixture(scope="session")
def base_url():
    """Return base URL — real ESP or local mock."""
    if ESP_HOST:
        url = f"http://{ESP_HOST}"
        # ensure we start with relay off
        s = _get(url + "/power/status")
        if s.get("powered"):
            _post(url + "/click")
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
    s = _get(base_url + "/power/status")
    if s.get("powered"):
        _post(base_url + "/click")
    # Reset mock state timing if using mock
    if not ESP_HOST:
        MockESPHandler.state = MockESPState()
    yield
    s = _get(base_url + "/power/status")
    if s.get("powered"):
        _post(base_url + "/click")


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


class TestClick:
    def test_click_toggles_power(self, base_url):
        r = _post(base_url + "/click")
        assert r["ok"] is True
        assert r["powered"] is True
        
        s = _get(base_url + "/power/status")
        assert s["powered"] is True
        
        r = _post(base_url + "/click")
        assert r["powered"] is False
        
        s = _get(base_url + "/power/status")
        assert s["powered"] is False

    def test_click_starts_uptime(self, base_url):
        _post(base_url + "/click")
        time.sleep(1)
        s = _get(base_url + "/power/status")
        assert s["uptime_sec"] >= 1


class TestStatus:
    def test_status_when_off(self, base_url):
        s = _get(base_url + "/power/status")
        assert s["powered"] is False
        assert s["uptime_sec"] == 0

    def test_status_has_required_fields(self, base_url):
        s = _get(base_url + "/power/status")
        assert "powered" in s
        assert "uptime_sec" in s


class TestHealth:
    def test_health_returns_fields(self, base_url):
        h = _get(base_url + "/health")
        assert "wifi_rssi" in h
        assert "heap_free" in h
        assert "relay_state" in h

    def test_health_relay_matches_status(self, base_url):
        _post(base_url + "/click")
        h = _get(base_url + "/health")
        assert h["relay_state"] is True
        _post(base_url + "/click")
        h = _get(base_url + "/health")
        assert h["relay_state"] is False


class TestNotFound:
    def test_unknown_path_returns_404(self, base_url):
        with pytest.raises(HTTPError) as exc_info:
            _get(base_url + "/does/not/exist")
        assert exc_info.value.code == 404


class TestReboot:
    def test_reboot_endpoint(self, base_url):
        r = _post(base_url + "/reboot")
        assert r["ok"] is True
        assert r["message"] == "rebooting"


class TestRateLimit:
    @pytest.mark.skipif(not ESP_HOST, reason="Rate-limit requires real hardware timing")
    def test_rapid_click_returns_429(self, base_url):
        """Second click while first is pending should be rejected."""
        _post(base_url + "/click")
        with pytest.raises(HTTPError) as exc_info:
            _post(base_url + "/click")
        assert exc_info.value.code == 429


class TestFullSequence:
    def test_backepr_happy_path(self, base_url):
        """Simulate the full Backepr backup sequence."""
        # 1. Power on via click
        r = _post(base_url + "/click")
        assert r["powered"] is True

        # 2. Status check
        s = _get(base_url + "/power/status")
        assert s["powered"] is True

        # 3. Health check
        h = _get(base_url + "/health")
        assert h["relay_state"] is True

        # 4. Power off (after hdparm -Y + sleep on server side)
        r = _post(base_url + "/click")
        assert r["powered"] is False

        # 5. Final status
        s = _get(base_url + "/power/status")
        assert s["powered"] is False
        assert s["uptime_sec"] == 0
