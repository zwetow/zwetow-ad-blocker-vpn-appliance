#!/usr/bin/env python3
import glob
import hashlib
import html
import json
import os
import re
import secrets
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
import base64
from datetime import datetime, timezone
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlparse

BUNDLE_DIR = "/var/tmp"
GEN_SCRIPT = "/opt/zwetow/bin/zwetow-support-bundle.sh"
STATUS_JSON_PATH = "/var/www/html/zwetow/status.json"
PROTECTED_DASHBOARD_PATH = "/var/www/html/zwetow/dashboard.html"
LOGO_PATH = "/var/www/html/zwetow-logo.png"
STATE_DIR = "/opt/zwetow/state"
SETUP_CONFIG_PATH = os.path.join(STATE_DIR, "setup.json")
SETUP_COMPLETE_PATH = os.path.join(STATE_DIR, "setup_complete")
CURRENT_VERSION_PATH = "/opt/zwetow/VERSION"
LATEST_VERSION_PATH = "/opt/zwetow/state/LATEST_VERSION"
UPDATE_AVAILABLE_PATH = "/opt/zwetow/state/UPDATE_AVAILABLE"
ADMIN_CONFIG_PATH = "/etc/zwetow/admin.json"
ADMIN_RESET_PATH = "/etc/zwetow/admin-reset.json"
ADGUARD_INIT_SCRIPT = "/opt/zwetow/bin/zwetow-init-adguard-admin.py"
KUMA_INIT_SCRIPT = "/opt/zwetow/bin/zwetow-init-kuma-admin.js"

UPDATE_SCRIPT = "/opt/zwetow/bin/zwetow-update.sh"
ROLLBACK_SCRIPT = "/opt/zwetow/bin/zwetow-rollback.sh"

CLIENT_DIR = "/etc/zwetow/clients"
WG_ADD_CLIENT_SCRIPT = "/opt/zwetow/bin/wg-add-client.sh"
CLIENT_NAME_RE = re.compile(r"^[A-Za-z0-9_-]+$")

SESSION_COOKIE_NAME = "zwetow_session"
SESSION_TTL_SECONDS = 12 * 60 * 60
RESET_TOKEN_TTL_SECONDS = 15 * 60
ADMIN_USERNAME_RE = re.compile(r"^[A-Za-z0-9_.-]{1,64}$")
UPSTREAM_TIMEOUT = 10

APP_ROUTES = {
    "adguard": {
        "prefix": "/apps/adguard",
        "upstream": os.environ.get("ZWETOW_ADGUARD_URL", "http://127.0.0.1/admin/"),
        "rewrite_html_prefix": "/apps/adguard/",
        "rewrite_location_prefix": "/apps/adguard/",
    },
    "kuma": {
        "prefix": "/apps/kuma",
        "upstream": os.environ.get("ZWETOW_KUMA_URL", "http://127.0.0.1:3001/"),
        "rewrite_html_prefix": "/apps/kuma/",
        "rewrite_location_prefix": "/apps/kuma/",
    },
}

SESSIONS = {}


def utc_now():
    return datetime.now(timezone.utc)


def iso_now():
    return utc_now().replace(microsecond=0).isoformat()


def latest_bundle():
    files = sorted(
        glob.glob(os.path.join(BUNDLE_DIR, "zwetow-support-*.tgz")),
        key=os.path.getmtime,
        reverse=True,
    )
    return files[0] if files else None


def run_script(path):
    if not os.path.exists(path):
        return (1, f"Missing script: {path}")
    proc = subprocess.run([path], capture_output=True, text=True)
    out = ((proc.stdout or "") + (proc.stderr or "")).strip() or "(no output)"
    return (proc.returncode, out)


def read_text_file(path, default_value="unknown"):
    try:
        with open(path, "r", encoding="utf-8") as file_handle:
            value = file_handle.read().strip()
            return value if value else default_value
    except Exception:
        return default_value


def get_update_info():
    current_version = read_text_file(CURRENT_VERSION_PATH, "unknown")
    latest_version = read_text_file(LATEST_VERSION_PATH, "unknown")
    update_available = (
        os.path.exists(UPDATE_AVAILABLE_PATH)
        and current_version != "unknown"
        and latest_version != "unknown"
        and latest_version != current_version
    )
    return {
        "current_version": current_version,
        "latest_version": latest_version,
        "update_available": update_available,
    }


def json_response(handler, status_code, payload, headers=None):
    body = json.dumps(payload).encode("utf-8")
    extra_headers = headers or {}
    handler.send_response(status_code)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Cache-Control", "no-store")
    for key, value in extra_headers.items():
        handler.send_header(key, value)
    handler.end_headers()
    handler.wfile.write(body)


def html_result_page(action, code, out, host):
    safe_host = (host or "").split(":")[0]
    result = "Complete" if code == 0 else "Failed"
    escaped_out = html.escape(out)
    return f"""<!doctype html>
<html><head><meta charset="utf-8"><title>{html.escape(action)}</title></head>
<body style="background:#0b0f14;color:#e6edf3;font-family:Arial,sans-serif;padding:24px;">
<h2>{html.escape(action)} {result}</h2>
<pre style="background:#0a0f1a;border:1px solid #243244;border-radius:12px;padding:12px;white-space:pre-wrap;">{escaped_out}</pre>
<p><a href="http://{safe_host}:9091/" style="color:#7dd3fc;">Back to Appliance Login</a></p>
</body></html>""".encode("utf-8")


def is_valid_client_name(name):
    return bool(name and CLIENT_NAME_RE.fullmatch(name))


def list_clients():
    os.makedirs(CLIENT_DIR, exist_ok=True)
    items = []
    for fname in sorted(os.listdir(CLIENT_DIR)):
        if fname.endswith(".conf"):
            items.append(fname[:-5])
    return items


def client_conf_path(name):
    return os.path.join(CLIENT_DIR, f"{name}.conf")


def run_add_client(name):
    if not os.path.exists(WG_ADD_CLIENT_SCRIPT):
        return (1, f"Missing script: {WG_ADD_CLIENT_SCRIPT}")
    proc = subprocess.run([WG_ADD_CLIENT_SCRIPT, name], capture_output=True, text=True)
    out = ((proc.stdout or "") + (proc.stderr or "")).strip() or "(no output)"
    return (proc.returncode, out)


def build_qr_png(conf_path):
    with open(conf_path, "rb") as conf_file:
        conf_data = conf_file.read()
    proc = subprocess.run(
        ["qrencode", "-o", "-", "-t", "PNG"],
        input=conf_data,
        capture_output=True,
    )
    if proc.returncode != 0:
        raise RuntimeError((proc.stderr or b"qrencode failed").decode("utf-8", errors="ignore"))
    return proc.stdout


def load_setup_config():
    if not os.path.exists(SETUP_CONFIG_PATH):
        return {}
    try:
        with open(SETUP_CONFIG_PATH, "r", encoding="utf-8") as setup_file:
            data = json.load(setup_file)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def write_setup_config(config):
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(SETUP_CONFIG_PATH, "w", encoding="utf-8") as setup_file:
        json.dump(config, setup_file, indent=2, sort_keys=True)
        setup_file.write("\n")


def sanitize_setup_payload(payload):
    if not isinstance(payload, dict):
        raise ValueError("Request body must be a JSON object")

    hostname = str(payload.get("hostname", "")).strip()
    timezone_name = str(payload.get("timezone", "")).strip()
    admin_email = str(payload.get("admin_email", "")).strip()
    admin_username = str(payload.get("admin_username", "")).strip()
    first_client = str(payload.get("first_client", "")).strip()
    raw_wireguard_enabled = payload.get("wireguard_enabled", False)

    if isinstance(raw_wireguard_enabled, bool):
        wireguard_enabled = raw_wireguard_enabled
    elif isinstance(raw_wireguard_enabled, str):
        val = raw_wireguard_enabled.strip().lower()
        if val in ("true", "1", "yes", "on"):
            wireguard_enabled = True
        elif val in ("false", "0", "no", "off", ""):
            wireguard_enabled = False
        else:
            raise ValueError("Invalid wireguard_enabled value")
    elif isinstance(raw_wireguard_enabled, (int, float)):
        if raw_wireguard_enabled == 1:
            wireguard_enabled = True
        elif raw_wireguard_enabled == 0:
            wireguard_enabled = False
        else:
            raise ValueError("Invalid wireguard_enabled value")
    else:
        raise ValueError("Invalid wireguard_enabled value")

    if hostname and not re.fullmatch(r"[A-Za-z0-9-]{1,63}", hostname):
        raise ValueError("Invalid hostname format")
    if timezone_name and not re.fullmatch(r"[A-Za-z0-9_./+-]+", timezone_name):
        raise ValueError("Invalid timezone format")
    if admin_email and not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", admin_email):
        raise ValueError("Invalid email format")
    if admin_username:
        admin_username = sanitize_admin_username(admin_username)
    if first_client and not is_valid_client_name(first_client):
        raise ValueError("Invalid WireGuard client name")

    return {
        "hostname": hostname,
        "timezone": timezone_name,
        "admin_email": admin_email,
        "admin_username": admin_username,
        "wireguard_enabled": wireguard_enabled,
        "first_client": first_client,
    }


def sanitize_setup_admin_credentials(payload, require_password):
    if not isinstance(payload, dict):
        raise ValueError("Request body must be a JSON object")

    raw_username = str(payload.get("admin_username", "")).strip()
    username = sanitize_admin_username(raw_username) if raw_username else ""
    password = str(payload.get("admin_password", ""))
    confirm_password = str(payload.get("admin_password_confirm", ""))

    if require_password:
        if not username:
            raise ValueError("Admin username is required")
        validate_new_password(password)
        if password != confirm_password:
            raise ValueError("Admin password confirmation does not match")
    elif password or confirm_password:
        validate_new_password(password)
        if password != confirm_password:
            raise ValueError("Admin password confirmation does not match")

    return {
        "username": username,
        "password": password,
        "confirm_password": confirm_password,
    }


def run_json_helper(command, payload):
    proc = subprocess.run(
        command,
        input=json.dumps(payload),
        capture_output=True,
        text=True,
    )
    output = ((proc.stdout or "") + (proc.stderr or "")).strip()
    if proc.returncode != 0:
        return {
            "ok": False,
            "detail": output or "helper failed",
        }

    if not output:
        return {"ok": True, "detail": ""}

    try:
        data = json.loads(output)
        if isinstance(data, dict):
            data.setdefault("ok", True)
            return data
    except Exception:
        pass

    return {
        "ok": True,
        "detail": output,
    }


def initialize_native_admin_credentials(credentials):
    results = []
    warnings = []

    helper_jobs = [
        ("AdGuard admin credentials", [ADGUARD_INIT_SCRIPT]),
        ("Uptime Kuma admin credentials", ["node", KUMA_INIT_SCRIPT]),
    ]

    for label, command in helper_jobs:
        if not os.path.exists(command[-1] if len(command) == 1 else command[1]):
            warnings.append(f"{label} helper is missing")
            continue

        result = run_json_helper(command, {
            "username": credentials["username"],
            "password": credentials["password"],
        })

        if result.get("ok"):
            message = result.get("message") or result.get("detail") or "initialized"
            results.append(f"{label}: {message}")
        else:
            detail = result.get("error") or result.get("detail") or "helper failed"
            warnings.append(f"{label}: {detail}")

    return results, warnings


def apply_setup_config(config):
    details = []
    warnings = []

    wireguard_enabled = bool(config.get("wireguard_enabled", False))
    first_client = config.get("first_client", "").strip()

    details.append("Setup preferences saved for deferred application")

    if wireguard_enabled:
        if first_client:
            conf_path = client_conf_path(first_client)
            if os.path.exists(conf_path):
                details.append(f"WireGuard client '{first_client}' already exists")
            else:
                code, out = run_add_client(first_client)
                if code == 0:
                    details.append(f"WireGuard client '{first_client}' created")
                else:
                    warnings.append(f"Failed to create WireGuard client '{first_client}': {out}")
    elif first_client:
        warnings.append("first_client was provided but wireguard_enabled is false; client was not created")

    return details, warnings


def read_admin_config():
    try:
        with open(ADMIN_CONFIG_PATH, "r", encoding="utf-8") as admin_file:
            data = json.load(admin_file)
        return data if isinstance(data, dict) else None
    except Exception:
        return None


def admin_exists():
    return read_admin_config() is not None


def hash_password(password):
    salt = secrets.token_bytes(16)
    n_value = 2 ** 14
    r_value = 8
    p_value = 1
    digest = hashlib.scrypt(
        password.encode("utf-8"),
        salt=salt,
        n=n_value,
        r=r_value,
        p=p_value,
        dklen=32,
    )
    return "scrypt${}${}${}${}${}".format(
        n_value,
        r_value,
        p_value,
        salt.hex(),
        digest.hex(),
    )


def verify_password(password, stored_hash):
    if not isinstance(stored_hash, str):
        return False
    parts = stored_hash.split("$")
    if len(parts) != 6 or parts[0] != "scrypt":
        return False

    try:
        n_value = int(parts[1])
        r_value = int(parts[2])
        p_value = int(parts[3])
        salt = bytes.fromhex(parts[4])
        expected = bytes.fromhex(parts[5])
    except Exception:
        return False

    try:
        actual = hashlib.scrypt(
            password.encode("utf-8"),
            salt=salt,
            n=n_value,
            r=r_value,
            p=p_value,
            dklen=len(expected),
        )
    except Exception:
        return False
    return secrets.compare_digest(actual, expected)


def sanitize_admin_username(username):
    candidate = str(username or "").strip()
    if not ADMIN_USERNAME_RE.fullmatch(candidate):
        raise ValueError("Username must use letters, numbers, dot, dash, or underscore only")
    return candidate


def validate_new_password(password):
    if not isinstance(password, str) or len(password) < 10:
        raise ValueError("Password must be at least 10 characters")
    return password


def write_admin_config(username, password):
    os.makedirs(os.path.dirname(ADMIN_CONFIG_PATH), exist_ok=True)
    payload = {
        "username": sanitize_admin_username(username),
        "password_hash": hash_password(validate_new_password(password)),
        "updated_at": iso_now(),
    }
    with open(ADMIN_CONFIG_PATH, "w", encoding="utf-8") as admin_file:
        json.dump(payload, admin_file, indent=2, sort_keys=True)
        admin_file.write("\n")
    os.chmod(ADMIN_CONFIG_PATH, 0o600)
    return payload


def hash_reset_token(token):
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def read_reset_config():
    try:
        with open(ADMIN_RESET_PATH, "r", encoding="utf-8") as reset_file:
            data = json.load(reset_file)
        return data if isinstance(data, dict) else None
    except Exception:
        return None


def clear_reset_config():
    try:
        os.remove(ADMIN_RESET_PATH)
    except FileNotFoundError:
        pass


def write_reset_config(username, token, expires_at):
    os.makedirs(os.path.dirname(ADMIN_RESET_PATH), exist_ok=True)
    payload = {
        "username": sanitize_admin_username(username),
        "token_hash": hash_reset_token(token),
        "created_at": iso_now(),
        "expires_at": expires_at,
    }
    with open(ADMIN_RESET_PATH, "w", encoding="utf-8") as reset_file:
        json.dump(payload, reset_file, indent=2, sort_keys=True)
        reset_file.write("\n")
    os.chmod(ADMIN_RESET_PATH, 0o600)
    return payload


def verify_reset_token(token):
    reset_config = read_reset_config()
    if not reset_config:
        return (False, "No active reset token", None)

    expires_at = str(reset_config.get("expires_at", "")).strip()
    try:
        expires_ts = datetime.fromisoformat(expires_at).timestamp()
    except Exception:
        clear_reset_config()
        return (False, "Reset token metadata is invalid", None)

    if expires_ts <= time.time():
        clear_reset_config()
        return (False, "Reset token has expired", None)

    expected_hash = str(reset_config.get("token_hash", ""))
    actual_hash = hash_reset_token(token)
    if not expected_hash or not secrets.compare_digest(actual_hash, expected_hash):
        return (False, "Invalid reset token", None)

    return (True, "", reset_config)


def cleanup_sessions():
    now_ts = time.time()
    expired = [token for token, data in SESSIONS.items() if data.get("expires_at", 0) <= now_ts]
    for token in expired:
        SESSIONS.pop(token, None)


def create_session(username):
    cleanup_sessions()
    token = secrets.token_urlsafe(32)
    now_ts = time.time()
    SESSIONS[token] = {
        "username": username,
        "created_at": now_ts,
        "expires_at": now_ts + SESSION_TTL_SECONDS,
    }
    return token


def format_cookie(token, max_age):
    cookie = SimpleCookie()
    cookie[SESSION_COOKIE_NAME] = token
    cookie[SESSION_COOKIE_NAME]["path"] = "/"
    cookie[SESSION_COOKIE_NAME]["httponly"] = True
    cookie[SESSION_COOKIE_NAME]["samesite"] = "Strict"
    cookie[SESSION_COOKIE_NAME]["max-age"] = str(max_age)
    return cookie.output(header="").strip()


def clear_session_cookie():
    return format_cookie("", 0)


def get_session_from_headers(headers):
    cleanup_sessions()
    raw_cookie = headers.get("Cookie", "")
    if not raw_cookie:
        return None
    cookie = SimpleCookie()
    try:
        cookie.load(raw_cookie)
    except Exception:
        return None
    morsel = cookie.get(SESSION_COOKIE_NAME)
    if not morsel:
        return None
    token = morsel.value
    session = SESSIONS.get(token)
    if not session:
        return None
    if session.get("expires_at", 0) <= time.time():
        SESSIONS.pop(token, None)
        return None
    session["expires_at"] = time.time() + SESSION_TTL_SECONDS
    return {"token": token, "username": session.get("username", "admin")}


def is_setup_complete():
    return os.path.exists(SETUP_COMPLETE_PATH)


def is_html_request(handler):
    accept = handler.headers.get("Accept", "")
    return "text/html" in accept or accept in ("", "*/*")


def app_prefix_for_upstream(target_url):
    for route in APP_ROUTES.values():
        upstream = route["upstream"].rstrip("/")
        if target_url.startswith(upstream):
            return route["rewrite_location_prefix"]
    return "/"

def login_logo_html():
    if os.path.isfile(LOGO_PATH):
        try:
            with open(LOGO_PATH, "rb") as fh:
                logo_b64 = base64.b64encode(fh.read()).decode("ascii")
            return f'<img src="data:image/png;base64,{logo_b64}" class="logo" alt="Zwetow">'
        except Exception:
            pass
    return '<div class="badge">Z</div>'

def login_page_html():
    logo_html = login_logo_html()
    html = """<!doctype html>

<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Zwetow Appliance Login</title>
  <style>
    :root {
      --bg: #0b0f14;
      --panel: #101826;
      --panel-2: #0c1320;
      --border: #243244;
      --text: #e6edf3;
      --muted: #9aa6b2;
      --accent: #f97316;
      --accent-2: #fb923c;
      --ok: #22c55e;
      --bad: #ef4444;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: Arial, sans-serif;
      color: var(--text);
      background:
        radial-gradient(1000px 500px at 15% 0%, rgba(125,211,252,0.08), transparent 55%),
        radial-gradient(900px 500px at 100% 10%, rgba(249,115,22,0.08), transparent 50%),
        var(--bg);
      display: grid;
      place-items: center;
      padding: 20px;
    }
    .shell {
      width: min(460px, 100%);
      border: 1px solid var(--border);
      border-radius: 22px;
      background: linear-gradient(145deg, var(--panel), var(--panel-2));
      box-shadow: 0 18px 40px rgba(0,0,0,0.35);
      overflow: hidden;
    }
    .hero {
      padding: 24px 24px 10px;
      border-bottom: 1px solid rgba(255,255,255,0.04);
    }
    .brand {
      display: flex;
      justify-content: center;
      margin-bottom: 12px;
    }

    .logo {
      width: 140px;
      height: auto;
      display: block;
    }
    .badge {
      width: 72px;
      height: 72px;
      border-radius: 20px;
      display: grid;
      place-items: center;
      font-size: 34px;
      font-weight: 800;
      color: #fff;
      background: linear-gradient(180deg, rgba(249,115,22,0.9), rgba(249,115,22,0.55));
      box-shadow: 0 10px 24px rgba(0,0,0,0.25);
    }
    h1 {
      margin: 0 0 8px;
      font-size: 28px;
      line-height: 1.15;
    }
    p {
      margin: 0;
      color: var(--muted);
      line-height: 1.5;
    }
    .panel {
      padding: 22px 24px 24px;
    }
    label {
      display: block;
      margin: 14px 0 6px;
      font-weight: 700;
    }
    input {
      width: 100%;
      border: 1px solid var(--border);
      border-radius: 12px;
      background: #0a0f1a;
      color: var(--text);
      padding: 11px 13px;
      font: inherit;
    }
    .row {
      display: flex;
      gap: 10px;
      flex-wrap: wrap;
      margin-top: 18px;
    }
    button {
      border: 1px solid rgba(249,115,22,0.55);
      border-radius: 12px;
      background: linear-gradient(180deg, rgba(249,115,22,0.22), rgba(249,115,22,0.12));
      color: var(--text);
      padding: 10px 16px;
      font: inherit;
      font-weight: 700;
      cursor: pointer;
    }
    button.secondary {
      border-color: var(--border);
      background: transparent;
    }
    .note {
      margin-top: 14px;
      font-size: 13px;
      color: var(--muted);
      white-space: pre-line;
    }
    .note.ok { color: var(--ok); }
    .note.bad { color: var(--bad); }
    .hidden { display: none; }
    .footer {
      padding: 0 24px 24px;
      color: var(--muted);
      font-size: 12px;
    }
  </style>
</head>
<body>
  <div class="shell">

<div class="hero">
  <div class="brand">
    __ZWETOW_LOGO__
  </div>
  <h1>Appliance Login</h1>
  <p id="hero-copy">Sign in to reach the dashboard and appliance apps.</p>
</div>

    <div class="panel">
      <form id="login-form">
        <label for="login-username">Admin Username</label>
        <input id="login-username" name="username" type="text" autocomplete="username" required>

        <label for="login-password">Password</label>
        <input id="login-password" name="password" type="password" autocomplete="current-password" required>

        <div class="row">
          <button type="submit">Sign In</button>
        </div>
      </form>

      <form id="bootstrap-form" class="hidden">
        <label for="bootstrap-username">Create Admin Username</label>
        <input id="bootstrap-username" name="username" type="text" autocomplete="username" value="admin" required>

        <label for="bootstrap-password">Create Password</label>
        <input id="bootstrap-password" name="password" type="password" autocomplete="new-password" required>

        <label for="bootstrap-confirm">Confirm Password</label>
        <input id="bootstrap-confirm" name="confirm_password" type="password" autocomplete="new-password" required>

        <div class="row">
          <button type="submit">Create Appliance Admin</button>
        </div>
      </form>

      <form id="reset-form" class="hidden">
        <label for="reset-token">Reset Token</label>
        <input id="reset-token" name="token" type="text" autocomplete="one-time-code" required>

        <label for="reset-password">New Password</label>
        <input id="reset-password" name="password" type="password" autocomplete="new-password" required>

        <label for="reset-confirm">Confirm New Password</label>
        <input id="reset-confirm" name="confirm_password" type="password" autocomplete="new-password" required>

        <div class="row">
          <button type="submit">Reset Password</button>
          <button id="show-login" class="secondary" type="button">Back to Sign In</button>
        </div>

        <div class="note">Generate a one-time reset token locally on the appliance with `sudo /opt/zwetow/bin/zwetow-reset-admin.py`.</div>
      </form>

      <div id="message" class="note"></div>
    </div>

    <div class="footer">
      Session-based appliance login. This is the central gate for the dashboard, WireGuard, AdGuard, and Uptime Kuma.
    </div>
  </div>

  <script>
    const loginForm = document.getElementById('login-form');
    const bootstrapForm = document.getElementById('bootstrap-form');
    const resetForm = document.getElementById('reset-form');
    const heroCopy = document.getElementById('hero-copy');
    const message = document.getElementById('message');
    const showLoginBtn = document.getElementById('show-login');

    function setMessage(text, tone) {
      message.textContent = text || '';
      message.className = 'note' + (tone ? ' ' + tone : '');
    }

    function showLoginMode() {
      loginForm.classList.remove('hidden');
      bootstrapForm.classList.add('hidden');
      resetForm.classList.add('hidden');
      heroCopy.textContent = 'Sign in to reach the dashboard and appliance apps.';
    }

    function showBootstrapMode() {
      loginForm.classList.add('hidden');
      bootstrapForm.classList.remove('hidden');
      resetForm.classList.add('hidden');
      heroCopy.textContent = 'Create the appliance admin account to enable the central login.';
    }

    function showResetMode() {
      loginForm.classList.add('hidden');
      bootstrapForm.classList.add('hidden');
      resetForm.classList.remove('hidden');
      heroCopy.textContent = 'Use a one-time local reset token to replace the appliance admin password.';
      setMessage('', '');
    }

    async function loadAuthState() {
      const res = await fetch('/auth/state', { cache: 'no-store' });
      const data = await res.json();

      if (data.authenticated) {
        window.location.replace('/dashboard');
        return;
      }

      if (data.admin_configured) {
        showLoginMode();
        document.getElementById('login-username').value = data.username_hint || 'admin';
      } else {
        showBootstrapMode();
      }
    }

    loginForm.addEventListener('submit', async (event) => {
      event.preventDefault();
      setMessage('Signing in...', '');

      const payload = {
        username: document.getElementById('login-username').value.trim(),
        password: document.getElementById('login-password').value
      };

      const res = await fetch('/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });
      const data = await res.json();
      if (!res.ok) {
        setMessage(data.error || 'Login failed.', 'bad');
        return;
      }
      window.location.replace(data.redirect || '/dashboard');
    });

    loginForm.insertAdjacentHTML('beforeend', `
      <div class="row">
        <button id="show-reset" class="secondary" type="button">Reset Password</button>
      </div>
    `);

    document.getElementById('show-reset').addEventListener('click', () => {
      showResetMode();
    });

    bootstrapForm.addEventListener('submit', async (event) => {
      event.preventDefault();

      const password = document.getElementById('bootstrap-password').value;
      const confirmPassword = document.getElementById('bootstrap-confirm').value;
      if (password !== confirmPassword) {
        setMessage('Passwords do not match.', 'bad');
        return;
      }

      setMessage('Creating appliance admin...', '');

      const payload = {
        username: document.getElementById('bootstrap-username').value.trim(),
        password: password
      };

      const res = await fetch('/auth/bootstrap', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });
      const data = await res.json();
      if (!res.ok) {
        setMessage(data.error || 'Could not create admin account.', 'bad');
        return;
      }
      setMessage('Admin account created. Sign in to continue.', 'ok');
      document.getElementById('login-username').value = payload.username;
      document.getElementById('login-password').value = '';
      await loadAuthState();
    });

    resetForm.addEventListener('submit', async (event) => {
      event.preventDefault();

      const password = document.getElementById('reset-password').value;
      const confirmPassword = document.getElementById('reset-confirm').value;
      if (password !== confirmPassword) {
        setMessage('Passwords do not match.', 'bad');
        return;
      }

      setMessage('Resetting appliance admin password...', '');

      const payload = {
        token: document.getElementById('reset-token').value.trim(),
        password: password,
        confirm_password: confirmPassword
      };

      const res = await fetch('/auth/reset', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });
      const data = await res.json();
      if (!res.ok) {
        setMessage(data.error || 'Could not reset admin password.', 'bad');
        return;
      }

      setMessage('Admin password reset. Sign in with the new password.', 'ok');
      document.getElementById('reset-password').value = '';
      document.getElementById('reset-confirm').value = '';
      document.getElementById('reset-token').value = '';
      showLoginMode();
    });

    showLoginBtn.addEventListener('click', () => {
      showLoginMode();
    });

    loadAuthState().catch((error) => {
      setMessage('Failed to load appliance auth state: ' + error.message, 'bad');
    });
  </script>
</body>
</html>"""
    return html.replace("__ZWETOW_LOGO__", logo_html).encode("utf-8")


def redirect_page_html(target):
    escaped_target = html.escape(target, quote=True)
    return f"""<!doctype html>
<html><head>
<meta charset="utf-8">
<meta http-equiv="refresh" content="0; url={escaped_target}">
<title>Zwetow Redirect</title>
</head>
<body style="background:#0b0f14;color:#e6edf3;font-family:Arial,sans-serif;padding:24px;">
<p>Redirecting to <a href="{escaped_target}" style="color:#7dd3fc;">{escaped_target}</a>...</p>
</body></html>""".encode("utf-8")


class Handler(BaseHTTPRequestHandler):
    server_version = "ZwetowAuthGateway/1.0"

    def send_raw(self, status_code, content_type, payload, cache_control=True, headers=None):
        extra_headers = headers or {}
        self.send_response(status_code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        if cache_control:
            self.send_header("Cache-Control", "no-store")
        for key, value in extra_headers.items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(payload)

    def send_file(self, file_path, content_type, attachment_name=None, cache_control=True, headers=None):
        extra_headers = headers or {}
        size = os.path.getsize(file_path)
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(size))
        if attachment_name:
            self.send_header("Content-Disposition", f'attachment; filename="{attachment_name}"')
        if cache_control:
            self.send_header("Cache-Control", "no-store")
        for key, value in extra_headers.items():
            self.send_header(key, value)
        self.end_headers()
        with open(file_path, "rb") as file_handle:
            while True:
                chunk = file_handle.read(1024 * 256)
                if not chunk:
                    break
                self.wfile.write(chunk)

    def read_json_body(self):
        length_str = self.headers.get("Content-Length", "0").strip()
        if not length_str.isdigit():
            raise ValueError("Invalid Content-Length")
        length = int(length_str)
        raw = self.rfile.read(length) if length > 0 else b"{}"
        if not raw:
            return {}
        try:
            data = json.loads(raw.decode("utf-8"))
        except Exception as exc:
            raise ValueError("Invalid JSON body") from exc
        if not isinstance(data, dict):
            raise ValueError("JSON body must be an object")
        return data

    def is_api_request(self):
        return self.path.startswith("/auth/") or self.path.startswith("/wireguard/") or self.path.startswith("/setup/") or self.path in (
            "/status.json",
            "/metrics",
            "/support.tgz",
            "/support",
            "/update",
            "/rollback",
            "/logout",
        )

    def require_session(self):
        session = get_session_from_headers(self.headers)
        if session:
            return session

        path = urlparse(self.path).path
        is_api_path = path == "/status.json" or path == "/metrics" or path.startswith("/wireguard/")
        if is_api_path:
            json_response(self, 401, {"error": "Authentication required"})
        else:
            self.send_raw(
                302,
                "text/html; charset=utf-8",
                redirect_page_html("/login"),
                cache_control=False,
                headers={"Location": "/login"},
            )
        return None

    def require_admin_bootstrap_available(self):
        if admin_exists():
            json_response(self, 409, {"error": "Admin account already configured"})
            return False
        return True

    def serve_dashboard(self):
        if not os.path.isfile(PROTECTED_DASHBOARD_PATH):
            self.send_raw(
                503,
                "text/html; charset=utf-8",
                b"Dashboard not rendered yet. Run /opt/zwetow/bin/render-index.sh.",
            )
            return
        self.send_file(PROTECTED_DASHBOARD_PATH, "text/html; charset=utf-8")

    def proxy_request(self, route):
        upstream_base = route["upstream"]
        prefix = route["prefix"]
        parsed_path = urlparse(self.path)
        remainder = parsed_path.path[len(prefix):]
        remainder = remainder if remainder.startswith("/") else f"/{remainder}"
        target_url = urllib.parse.urljoin(upstream_base.rstrip("/") + "/", remainder.lstrip("/"))
        if parsed_path.query:
            target_url = f"{target_url}?{parsed_path.query}"

        body = None
        if self.command in ("POST", "PUT", "PATCH"):
            length = int(self.headers.get("Content-Length", "0") or "0")
            body = self.rfile.read(length) if length > 0 else None

        req = urllib.request.Request(target_url, data=body, method=self.command)
        req.add_header("Host", urllib.parse.urlparse(upstream_base).netloc)
        req.add_header("X-Forwarded-For", self.client_address[0])
        req.add_header("X-Forwarded-Host", self.headers.get("Host", ""))
        req.add_header("X-Forwarded-Proto", "http")

        content_type = self.headers.get("Content-Type")
        if content_type:
            req.add_header("Content-Type", content_type)

        accept = self.headers.get("Accept")
        if accept:
            req.add_header("Accept", accept)

        try:
            with urllib.request.urlopen(req, timeout=UPSTREAM_TIMEOUT) as upstream_response:
                payload = upstream_response.read()
                status_code = upstream_response.getcode()
                content_type = upstream_response.headers.get("Content-Type", "application/octet-stream")

                response_headers = {}
                location = upstream_response.headers.get("Location")
                if location:
                    response_headers["Location"] = self.rewrite_upstream_location(location, route)

                if content_type.startswith("text/html"):
                    payload = self.rewrite_html_payload(payload, route)
                elif content_type.startswith("text/css") or "javascript" in content_type:
                    payload = self.rewrite_text_payload(payload, route)

                self.send_raw(status_code, content_type, payload, cache_control=False, headers=response_headers)
        except urllib.error.HTTPError as exc:
            payload = exc.read() if hasattr(exc, "read") else str(exc).encode("utf-8")
            response_headers = {}
            if exc.headers.get("Location"):
                response_headers["Location"] = self.rewrite_upstream_location(exc.headers.get("Location"), route)
            self.send_raw(exc.code, exc.headers.get("Content-Type", "text/plain; charset=utf-8"), payload, cache_control=False, headers=response_headers)
        except Exception as exc:
            json_response(self, 502, {"error": f"Upstream proxy failed: {exc}"})

    def rewrite_upstream_location(self, location, route):
        parsed = urllib.parse.urlparse(location)
        if parsed.scheme or parsed.netloc:
            for app_route in APP_ROUTES.values():
                upstream = urllib.parse.urlparse(app_route["upstream"])
                if parsed.netloc == upstream.netloc:
                    suffix = parsed.path
                    if upstream.path and suffix.startswith(upstream.path):
                        suffix = suffix[len(upstream.path):]
                    if not suffix.startswith("/"):
                        suffix = f"/{suffix}"
                    result = urllib.parse.urljoin(app_route["rewrite_location_prefix"], suffix.lstrip("/"))
                    if parsed.query:
                        result = f"{result}?{parsed.query}"
                    return result
            return location

        path = parsed.path or "/"
        upstream_path = urllib.parse.urlparse(route["upstream"]).path or "/"
        if upstream_path != "/" and path.startswith(upstream_path):
            path = path[len(upstream_path):] or "/"
        if not path.startswith("/"):
            path = f"/{path}"
        rewritten = urllib.parse.urljoin(route["rewrite_location_prefix"], path.lstrip("/"))
        if parsed.query:
            rewritten = f"{rewritten}?{parsed.query}"
        return rewritten

    def rewrite_html_payload(self, payload, route):
        text = payload.decode("utf-8", errors="ignore")
        text = self.rewrite_text_string(text, route)
        return text.encode("utf-8")

    def rewrite_text_payload(self, payload, route):
        text = payload.decode("utf-8", errors="ignore")
        text = self.rewrite_text_string(text, route)
        return text.encode("utf-8")

    def rewrite_text_string(self, text, route):
        prefix = route["rewrite_html_prefix"]
        upstream_path = urllib.parse.urlparse(route["upstream"]).path.rstrip("/")
        if upstream_path:
            text = text.replace(f'"{upstream_path}/', f'"{prefix}')
            text = text.replace(f"'{upstream_path}/", f"'{prefix}")
        text = text.replace('href="/', f'href="{prefix}')
        text = text.replace("href='/", f"href='{prefix}")
        text = text.replace('src="/', f'src="{prefix}')
        text = text.replace("src='/", f"src='{prefix}")
        text = text.replace('action="/', f'action="{prefix}')
        text = text.replace("action='/", f"action='{prefix}")
        text = text.replace('content="/', f'content="{prefix}')
        text = text.replace("content='/", f"content='{prefix}")
        text = text.replace('url(/', f'url({prefix}')
        text = text.replace('fetch("/', f'fetch("{prefix}')
        text = text.replace("fetch('/", f"fetch('{prefix}")
        return text

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Max-Age", "600")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        qs = parse_qs(parsed.query)

        if path == "/auth/state":
            admin_config = read_admin_config() or {}
            session = get_session_from_headers(self.headers)
            json_response(self, 200, {
                "admin_configured": bool(admin_config),
                "authenticated": bool(session),
                "username_hint": admin_config.get("username", "admin"),
            })
            return

        if path == "/login":
            session = get_session_from_headers(self.headers)
            if session:
                self.send_raw(302, "text/html; charset=utf-8", redirect_page_html("/dashboard"), cache_control=False, headers={"Location": "/dashboard"})
                return
            self.send_raw(200, "text/html; charset=utf-8", login_page_html())
            return

        if path == "/logout":
            session = get_session_from_headers(self.headers)
            if session:
                SESSIONS.pop(session["token"], None)
            self.send_raw(
                302,
                "text/html; charset=utf-8",
                redirect_page_html("/login"),
                cache_control=False,
                headers={"Location": "/login", "Set-Cookie": clear_session_cookie()},
            )
            return

        if not is_setup_complete():
            if path == "/" or path == "/dashboard":
                host_name = (self.headers.get("Host") or "").split(":")[0]
                target = f"http://{host_name or '127.0.0.1'}/"
                self.send_raw(302, "text/html; charset=utf-8", redirect_page_html(target), cache_control=False, headers={"Location": target})
                return

        if path == "/":
            session = get_session_from_headers(self.headers)
            target = "/dashboard" if session else "/login"
            self.send_raw(302, "text/html; charset=utf-8", redirect_page_html(target), cache_control=False, headers={"Location": target})
            return

        if path == "/dashboard":
            if not self.require_session():
                return
            self.serve_dashboard()
            return

        if path == "/setup/status":
            json_response(self, 200, {"setup_complete": is_setup_complete()})
            return

        if path == "/setup/config":
            json_response(self, 200, {
                "setup_complete": is_setup_complete(),
                "config": load_setup_config(),
                "update": get_update_info(),
            })
            return

        protected_session = None
        protected_prefixes = ("/apps/adguard", "/apps/kuma", "/wireguard/")
        protected_exact = {"/status.json", "/metrics", "/support", "/support.tgz", "/update", "/rollback"}

        if path in protected_exact or any(path.startswith(prefix) for prefix in protected_prefixes):
            protected_session = self.require_session()
            if not protected_session:
                return

        if path == "/metrics":
            try:
                with urllib.request.urlopen("http://127.0.0.1:9090/metrics", timeout=2) as response:
                    payload = response.read()
                self.send_raw(200, "application/json", payload)
                return
            except Exception as exc:
                self.send_raw(500, "application/json", ('{"error": "%s"}' % str(exc)).encode("utf-8"), cache_control=False)
                return

        if path == "/status.json":
            if not os.path.isfile(STATUS_JSON_PATH):
                json_response(self, 404, {"error": "status.json not found"})
                return
            self.send_file(STATUS_JSON_PATH, "application/json; charset=utf-8")
            return

        if path == "/wireguard/clients":
            json_response(self, 200, {"clients": list_clients()})
            return

        if path == "/wireguard/add-client":
            name = (qs.get("name") or [""])[0].strip()
            if not is_valid_client_name(name):
                json_response(self, 400, {"error": "Invalid client name. Use letters, numbers, dash, underscore only."})
                return

            conf_path = client_conf_path(name)
            if os.path.exists(conf_path):
                json_response(self, 200, {"ok": True, "client": name, "message": "Client already exists"})
                return

            code, out = run_add_client(name)
            if code != 0:
                json_response(self, 500, {"error": "Failed to create client", "detail": out})
                return

            json_response(self, 200, {"ok": True, "client": name, "message": "Client created", "detail": out})
            return

        if path.startswith("/wireguard/client/") and path.endswith("/config"):
            name = unquote(path[len("/wireguard/client/"):-len("/config")].strip("/"))
            if not is_valid_client_name(name):
                json_response(self, 400, {"error": "Invalid client name"})
                return

            conf_path = client_conf_path(name)
            if not os.path.isfile(conf_path):
                json_response(self, 404, {"error": "Client config not found"})
                return

            self.send_file(conf_path, "text/plain; charset=utf-8", attachment_name=f"{name}.conf")
            return

        if path.startswith("/wireguard/client/") and path.endswith("/qr"):
            name = unquote(path[len("/wireguard/client/"):-len("/qr")].strip("/"))
            if not is_valid_client_name(name):
                json_response(self, 400, {"error": "Invalid client name"})
                return

            conf_path = client_conf_path(name)
            if not os.path.isfile(conf_path):
                json_response(self, 404, {"error": "Client config not found"})
                return

            try:
                png = build_qr_png(conf_path)
                self.send_raw(200, "image/png", png)
                return
            except Exception as exc:
                json_response(self, 500, {"error": str(exc)})
                return

        if path == "/support":
            self.send_raw(
                200,
                "text/html; charset=utf-8",
                b"""<!doctype html>
<html><head>
<meta charset="utf-8">
<meta http-equiv="refresh" content="1; url=/support.tgz">
<title>Generating Support Bundle</title>
</head>
<body style="background:#0b0f14;color:#e6edf3;font-family:Arial,sans-serif;text-align:center;padding-top:60px;">
<h2>Generating Support Bundle...</h2>
<p>Your download will begin automatically.</p>
</body></html>""",
                cache_control=False,
            )
            return

        if path == "/support.tgz":
            if os.path.exists(GEN_SCRIPT):
                subprocess.run([GEN_SCRIPT], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            fpath = latest_bundle()
            if not fpath or not os.path.isfile(fpath):
                self.send_raw(500, "text/plain; charset=utf-8", b"Support bundle not found")
                return

            self.send_file(fpath, "application/gzip", attachment_name=os.path.basename(fpath), cache_control=False)
            return

        if path == "/update":
            code, out = run_script(UPDATE_SCRIPT)
            body = html_result_page("Update", code, out, self.headers.get("Host", ""))
            self.send_raw(200 if code == 0 else 500, "text/html; charset=utf-8", body, cache_control=False)
            return

        if path == "/rollback":
            code, out = run_script(ROLLBACK_SCRIPT)
            body = html_result_page("Rollback", code, out, self.headers.get("Host", ""))
            self.send_raw(200 if code == 0 else 500, "text/html; charset=utf-8", body, cache_control=False)
            return

        if path.startswith(APP_ROUTES["adguard"]["prefix"]):
            self.proxy_request(APP_ROUTES["adguard"])
            return

        if path.startswith(APP_ROUTES["kuma"]["prefix"]):
            self.proxy_request(APP_ROUTES["kuma"])
            return

        self.send_response(404)
        self.end_headers()

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/auth/bootstrap":
            if not self.require_admin_bootstrap_available():
                return
            try:
                payload = self.read_json_body()
                username = sanitize_admin_username(payload.get("username", ""))
                password = validate_new_password(payload.get("password", ""))
                admin_config = write_admin_config(username, password)
                json_response(self, 200, {"ok": True, "username": admin_config["username"]})
                return
            except ValueError as exc:
                json_response(self, 400, {"error": str(exc)})
                return
            except Exception as exc:
                json_response(self, 500, {"error": str(exc)})
                return

        if path == "/auth/login":
            admin_config = read_admin_config()
            if not admin_config:
                json_response(self, 409, {"error": "Admin account not configured yet"})
                return
            try:
                payload = self.read_json_body()
            except ValueError as exc:
                json_response(self, 400, {"error": str(exc)})
                return

            username = str(payload.get("username", "")).strip()
            password = str(payload.get("password", ""))
            if username != admin_config.get("username") or not verify_password(password, admin_config.get("password_hash")):
                json_response(self, 401, {"error": "Invalid username or password"})
                return

            token = create_session(username)
            json_response(
                self,
                200,
                {"ok": True, "redirect": "/dashboard"},
                headers={"Set-Cookie": format_cookie(token, SESSION_TTL_SECONDS)},
            )
            return

        if path == "/auth/reset":
            admin_config = read_admin_config() or {}
            try:
                payload = self.read_json_body()
                token = str(payload.get("token", "")).strip()
                password = validate_new_password(str(payload.get("password", "")))
                confirm_password = str(payload.get("confirm_password", ""))
                if password != confirm_password:
                    raise ValueError("Password confirmation does not match")
                if not token:
                    raise ValueError("Reset token is required")
            except ValueError as exc:
                json_response(self, 400, {"error": str(exc)})
                return

            ok, error, reset_config = verify_reset_token(token)
            if not ok:
                json_response(self, 400, {"error": error})
                return

            username = admin_config.get("username") or reset_config.get("username") or "admin"
            try:
                updated_admin = write_admin_config(username, password)
            except ValueError as exc:
                json_response(self, 400, {"error": str(exc)})
                return
            except Exception as exc:
                json_response(self, 500, {"error": str(exc)})
                return

            clear_reset_config()
            SESSIONS.clear()
            json_response(self, 200, {
                "ok": True,
                "username": updated_admin["username"],
                "message": "Admin password reset",
            })
            return

        if path == "/setup/save":
            try:
                request_payload = self.read_json_body()
                payload = sanitize_setup_payload(request_payload)
                sanitize_setup_admin_credentials(request_payload, require_password=False)
                write_setup_config(payload)
                json_response(self, 200, {"ok": True, "config": payload})
                return
            except ValueError as exc:
                json_response(self, 400, {"error": str(exc)})
                return
            except Exception as exc:
                json_response(self, 500, {"error": str(exc)})
                return

        if path == "/setup/complete":
            try:
                request_payload = self.read_json_body()
                payload = sanitize_setup_payload(request_payload)
                credentials = sanitize_setup_admin_credentials(request_payload, require_password=True)
                write_setup_config(payload)
                details, warnings = apply_setup_config(payload)
                admin_config = write_admin_config(credentials["username"], credentials["password"])
                details.append(f"Appliance admin '{admin_config['username']}' initialized")
                helper_details, helper_warnings = initialize_native_admin_credentials(credentials)
                details.extend(helper_details)
                warnings.extend(helper_warnings)
                os.makedirs(STATE_DIR, exist_ok=True)
                with open(SETUP_COMPLETE_PATH, "w", encoding="utf-8") as marker:
                    marker.write("1\n")
                json_response(self, 200, {
                    "ok": True,
                    "setup_complete": True,
                    "detail": details,
                    "warnings": warnings,
                })
                return
            except ValueError as exc:
                json_response(self, 400, {"error": str(exc)})
                return
            except Exception as exc:
                json_response(self, 500, {"error": str(exc)})
                return

        if path == "/setup/update-now":
            code, out = run_script(UPDATE_SCRIPT)
            json_response(self, 200, {"ok": code == 0, "detail": out, "update": get_update_info()})
            return

        if path.startswith(APP_ROUTES["adguard"]["prefix"]) or path.startswith(APP_ROUTES["kuma"]["prefix"]):
            if not self.require_session():
                return
            route = APP_ROUTES["adguard"] if path.startswith(APP_ROUTES["adguard"]["prefix"]) else APP_ROUTES["kuma"]
            self.proxy_request(route)
            return

        self.send_response(404)
        self.end_headers()

    def log_message(self, fmt, *args):
        return


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 9091), Handler).serve_forever()
