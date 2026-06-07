#!/usr/bin/env python3
import sys
import time
import json
import urllib.request
import urllib.error

DEFAULT_IP = "192.168.0.12"

def make_request(url, method="GET", data=None):
    req = urllib.request.Request(url, method=method)
    if data is not None:
        req.add_header("Content-Type", "application/json")
        encoded_data = json.dumps(data).encode("utf-8")
    else:
        encoded_data = b"" if method == "POST" else None
        
    try:
        with urllib.request.urlopen(req, data=encoded_data, timeout=5) as response:
            return response.getcode(), json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        try:
            err_body = json.loads(e.read().decode("utf-8"))
        except Exception:
            err_body = e.reason
        return e.code, err_body
    except urllib.error.URLError as e:
        print(f"[-] Connection Error to {url}: {e.reason}")
        sys.exit(1)
    except Exception as e:
        print(f"[-] Unexpected error: {e}")
        sys.exit(1)

def run_tests(ip):
    base_url = f"http://{ip}"
    print(f"[*] Targeting ESP-01S at: {base_url}")
    print("-" * 50)
    
    # 1. Health check
    print("[*] Step 1: Checking health status...")
    code, res = make_request(f"{base_url}/health")
    if code == 200:
        print(f"[+] Health OK! RSSI: {res.get('wifi_rssi')} dBm, Free Heap: {res.get('heap_free')} bytes")
    else:
        print(f"[-] Health failed with code {code}: {res}")
        sys.exit(1)
        
    # 2. Get initial power status
    print("[*] Step 2: Querying initial power status...")
    code, res = make_request(f"{base_url}/power/status")
    print(f"[+] Status: powered={res.get('powered')}")
    
    # Ensure it starts OFF for the clean test run
    if res.get('powered'):
        print("[*] Device is currently ON. Turning it OFF first to start test sequence...")
        code, res = make_request(f"{base_url}/click", method="POST")
        time.sleep(2) # wait for click stabilization
        code, res = make_request(f"{base_url}/power/status")
        if res.get('powered'):
            print("[-] Failed to initialize device to OFF state.")
            sys.exit(1)
            
    # 3. Click ON
    print("[*] Step 3: Sending click to turn ON...")
    code, res = make_request(f"{base_url}/click", method="POST")
    if code == 200 and res.get("ok"):
        print("[+] Click sent successfully!")
    else:
        print(f"[-] Click failed: {res}")
        sys.exit(1)

    # 3b. Rate-limit test (must be immediate after step 3 click)
    print("[*] Step 3b: Testing rate-limit (rapid double-click)...")
    code, res = make_request(f"{base_url}/click", method="POST")
    if code == 429:
        print("[+] Rate-limit correctly returned HTTP 429!")
    else:
        print(f"[-] Expected HTTP 429 but got {code}: {res}")
        sys.exit(1)

    # Wait for pending click to resolve and boot stable guard
    print("[*] Waiting 4 seconds for boot stabilization guard and relay pulse to complete...")
    time.sleep(4)
    
    # 4. Check ON status
    print("[*] Step 4: Verifying power status is ON...")
    code, res = make_request(f"{base_url}/power/status")
    if code == 200 and res.get("powered") is True:
        print(f"[+] Verified ON! Uptime: {res.get('uptime_sec')}s")
    else:
        print(f"[-] Status check failed: {res}")
        sys.exit(1)
        
    # 5. Click OFF
    print("[*] Step 5: Sending click to turn OFF...")
    code, res = make_request(f"{base_url}/click", method="POST")
    if code == 200 and res.get("ok"):
        print("[+] Click sent successfully!")
    else:
        print(f"[-] Click failed: {res}")
        sys.exit(1)
        
    # Wait for relay pulse
    print("[*] Waiting 2 seconds...")
    time.sleep(2)
    
    # 6. Check OFF status
    print("[*] Step 6: Verifying power status is OFF...")
    code, res = make_request(f"{base_url}/power/status")
    if code == 200 and res.get("powered") is False:
        print("[+] Verified OFF!")
    else:
        print(f"[-] Status check failed: {res}")
        sys.exit(1)

    # 7. Reboot test
    print("[*] Step 7: Triggering remote reboot...")
    code, res = make_request(f"{base_url}/reboot", method="POST")
    if code == 200 and res.get("ok"):
        print("[+] Reboot command accepted. Device is restarting!")
    else:
        print(f"[-] Reboot failed: {res}")
        sys.exit(1)
        
    print("-" * 50)
    print("[+] ALL FUNCTIONAL TESTS PASSED SUCCESSFULLY! ✅")

if __name__ == "__main__":
    ip = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_IP
    run_tests(ip)
