#!/usr/bin/env python3
import json
import os
import shutil
import subprocess
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

PIHOLE_PASSWORD_FILE = "/etc/zwetow/pihole-api-password"
PIHOLE_API_BASE = "http://127.0.0.1/api"
PIHOLE_SID_TTL_SECONDS = 15 * 60
PIHOLE_AUTH_COOLDOWN_SECONDS = 5 * 60
PIHOLE_METRICS_CACHE_SECONDS = 30
PIHOLE_FETCH_RETRY_SECONDS = 60

PIHOLE_SESSION = {
    "sid": "",
    "valid_until": 0,
    "auth_retry_after": 0,
    "last_error": "",
}

PIHOLE_CACHE = {
    "payload": None,
    "valid_until": 0,
    "retry_after": 0,
}


def read_pihole_password():
    try:
        with open(PIHOLE_PASSWORD_FILE, "r", encoding="utf-8") as password_file:
            return password_file.read().strip()
    except FileNotFoundError:
        return ""


def post_json(url, payload, timeout=3):
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def get_json(url, timeout=3):
    with urllib.request.urlopen(url, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def get_cpu_temp_c():
    for path in ("/sys/class/thermal/thermal_zone0/temp",):
        try:
            with open(path, "r", encoding="utf-8") as temp_file:
                raw = temp_file.read().strip()
            value = float(raw)
            if value > 1000:
                value = value / 1000.0
            return round(value, 1)
        except Exception:
            continue
    return "?"


def get_loadavg_cpu_percent():
    try:
        load1, _, _ = os.getloadavg()
        cpus = os.cpu_count() or 1
        return round((load1 / cpus) * 100, 1)
    except Exception:
        return "?"


def get_memory_percent():
    try:
        mem_total = 0
        mem_avail = 0
        with open("/proc/meminfo", "r", encoding="utf-8") as meminfo_file:
            for line in meminfo_file:
                if line.startswith("MemTotal:"):
                    mem_total = int(line.split()[1])
                elif line.startswith("MemAvailable:"):
                    mem_avail = int(line.split()[1])
        if mem_total > 0:
            used = mem_total - mem_avail
            return round((used / mem_total) * 100, 1)
    except Exception:
        pass
    return "?"


def get_disk_percent():
    try:
        usage = shutil.disk_usage("/")
        if usage.total > 0:
            return round((usage.used / usage.total) * 100, 1)
    except Exception:
        pass
    return "?"


def get_wireguard_peer_count():
    try:
        output = subprocess.check_output(["wg", "show"], text=True, timeout=3)
        return sum(1 for line in output.splitlines() if line.strip().startswith("peer:"))
    except Exception:
        return "?"


def reset_pihole_session():
    PIHOLE_SESSION["sid"] = ""
    PIHOLE_SESSION["valid_until"] = 0


def set_pihole_auth_cooldown(message, seconds):
    PIHOLE_SESSION["auth_retry_after"] = time.time() + seconds
    PIHOLE_SESSION["last_error"] = message


def authenticate_pihole(force=False):
    now = time.time()

    if PIHOLE_SESSION["sid"] and now < PIHOLE_SESSION["valid_until"] and not force:
        return PIHOLE_SESSION["sid"]

    if not force and now < PIHOLE_SESSION["auth_retry_after"]:
        return ""

    password = read_pihole_password()
    if not password:
        set_pihole_auth_cooldown("Pi-hole password file missing", PIHOLE_FETCH_RETRY_SECONDS)
        return ""

    try:
        auth = post_json(f"{PIHOLE_API_BASE}/auth", {"password": password})
    except urllib.error.HTTPError as exc:
        if exc.code == 429:
            set_pihole_auth_cooldown("Pi-hole auth rate-limited", PIHOLE_AUTH_COOLDOWN_SECONDS)
        else:
            set_pihole_auth_cooldown(f"Pi-hole auth failed: HTTP {exc.code}", PIHOLE_FETCH_RETRY_SECONDS)
        return ""
    except Exception as exc:
        set_pihole_auth_cooldown(f"Pi-hole auth failed: {exc}", PIHOLE_FETCH_RETRY_SECONDS)
        return ""

    sid = (auth.get("session") or {}).get("sid", "")
    if not sid:
        set_pihole_auth_cooldown("Pi-hole auth returned no SID", PIHOLE_FETCH_RETRY_SECONDS)
        return ""

    PIHOLE_SESSION["sid"] = sid
    PIHOLE_SESSION["valid_until"] = now + PIHOLE_SID_TTL_SECONDS
    PIHOLE_SESSION["auth_retry_after"] = 0
    PIHOLE_SESSION["last_error"] = ""
    return sid


def pihole_api_get(path):
    sid = authenticate_pihole()
    if not sid:
        raise RuntimeError(PIHOLE_SESSION["last_error"] or "Pi-hole SID unavailable")

    url = f"{PIHOLE_API_BASE}{path}"
    separator = "&" if "?" in url else "?"
    url = f"{url}{separator}sid={sid}"

    try:
        return get_json(url)
    except urllib.error.HTTPError as exc:
        if exc.code in (401, 403):
            reset_pihole_session()
            sid = authenticate_pihole(force=True)
            if not sid:
                raise RuntimeError("Pi-hole SID refresh failed")
            retry_url = f"{PIHOLE_API_BASE}{path}"
            retry_separator = "&" if "?" in retry_url else "?"
            return get_json(f"{retry_url}{retry_separator}sid={sid}")
        if exc.code == 429:
            PIHOLE_CACHE["retry_after"] = time.time() + PIHOLE_AUTH_COOLDOWN_SECONDS
            raise RuntimeError("Pi-hole API rate-limited")
        raise RuntimeError(f"Pi-hole API HTTP {exc.code}") from exc


def build_default_pihole_stats():
    return {
        "pihole_status": "BAD",
        "pihole_dns_queries_today": "?",
        "pihole_ads_blocked_today": "?",
        "pihole_ads_percentage_today": "?",
        "pihole_core": "",
        "pihole_web": "",
        "pihole_ftl": "",
    }


def build_pihole_stats(summary, version):
    result = build_default_pihole_stats()

    queries = "?"
    blocked = "?"
    percent = "?"
    query_info = summary.get("queries")
    if isinstance(query_info, dict):
        queries = query_info.get("total", "?")
        blocked = query_info.get("blocked", "?")
        percent = query_info.get("percent_blocked", "?")
    elif query_info is not None:
        queries = query_info

    if blocked == "?":
        ads = summary.get("ads")
        if isinstance(ads, dict):
            blocked = ads.get("blocked") or ads.get("blocked_today") or ads.get("total_blocked") or "?"
            percent = ads.get("percent_blocked") or ads.get("percentage") or ads.get("percent") or "?"

    if blocked == "?":
        blocked = summary.get("ads_blocked_today") or summary.get("blocked") or summary.get("blocked_today") or "?"

    if percent == "?":
        percent = summary.get("ads_percentage_today") or summary.get("percent_blocked") or summary.get("blocked_percent") or "?"

    version_info = version.get("version") or {}
    for key, result_key in (("core", "pihole_core"), ("web", "pihole_web"), ("ftl", "pihole_ftl")):
        value = version_info.get(key) or {}
        if isinstance(value, dict):
            result[result_key] = (value.get("local") or {}).get("version", "")
        else:
            result[result_key] = value or ""

    result["pihole_dns_queries_today"] = queries
    result["pihole_ads_blocked_today"] = blocked
    result["pihole_ads_percentage_today"] = percent
    if queries != "?" or blocked != "?":
        result["pihole_status"] = "OK"
    return result


def get_pihole_stats():
    now = time.time()

    if PIHOLE_CACHE["payload"] and now < PIHOLE_CACHE["valid_until"]:
        return dict(PIHOLE_CACHE["payload"])

    if now < PIHOLE_CACHE["retry_after"] and PIHOLE_CACHE["payload"]:
        return dict(PIHOLE_CACHE["payload"])

    default_result = build_default_pihole_stats()
    try:
        summary = pihole_api_get("/stats/summary")
        version = pihole_api_get("/info/version")
        result = build_pihole_stats(summary, version)
        PIHOLE_CACHE["payload"] = dict(result)
        PIHOLE_CACHE["valid_until"] = now + PIHOLE_METRICS_CACHE_SECONDS
        PIHOLE_CACHE["retry_after"] = 0
        return result
    except Exception:
        if PIHOLE_CACHE["payload"]:
            PIHOLE_CACHE["retry_after"] = now + PIHOLE_FETCH_RETRY_SECONDS
            return dict(PIHOLE_CACHE["payload"])
        PIHOLE_CACHE["retry_after"] = now + PIHOLE_FETCH_RETRY_SECONDS
        return default_result


def build_metrics():
    data = {
        "cpu_percent": get_loadavg_cpu_percent(),
        "memory_percent": get_memory_percent(),
        "disk_percent": get_disk_percent(),
        "cpu_temp_c": get_cpu_temp_c(),
        "wg_peer_count": get_wireguard_peer_count(),
    }
    data.update(get_pihole_stats())
    return data


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path not in ("/metrics", "/health"):
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"not found")
            return

        payload = build_metrics()
        body = json.dumps(payload, indent=2).encode("utf-8")

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return


def main():
    server = HTTPServer(("127.0.0.1", 9090), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
