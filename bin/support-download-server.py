#!/usr/bin/env python3
import json
import re
import os, glob, subprocess
import urllib.request
from urllib.parse import urlparse, parse_qs, unquote
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse

BUNDLE_DIR = "/var/tmp"
GEN_SCRIPT = "/opt/zwetow/bin/zwetow-support-bundle.sh"

UPDATE_SCRIPT = "/opt/zwetow/bin/zwetow-update.sh"
ROLLBACK_SCRIPT = "/opt/zwetow/bin/zwetow-rollback.sh"

CLIENT_DIR = "/etc/zwetow/clients"
WG_ADD_CLIENT_SCRIPT = "/opt/zwetow/bin/wg-add-client.sh"
CLIENT_NAME_RE = re.compile(r"^[A-Za-z0-9_-]+$")

def latest_bundle():
    files = sorted(
        glob.glob(os.path.join(BUNDLE_DIR, "zwetow-support-*.tgz")),
        key=os.path.getmtime,
        reverse=True
    )
    return files[0] if files else None

def run_script(path):
    if not os.path.exists(path):
        return (1, f"Missing script: {path}")
    p = subprocess.run([path], capture_output=True, text=True)
    out = (p.stdout or "") + (p.stderr or "")
    out = out.strip() or "(no output)"
    return (p.returncode, out)

def json_response(handler, status_code, payload):
    body = json.dumps(payload).encode("utf-8")
    handler.send_response(status_code)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Cache-Control", "no-store")
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.end_headers()
    handler.wfile.write(body)

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
    p = subprocess.run(
        [WG_ADD_CLIENT_SCRIPT, name],
        capture_output=True,
        text=True
    )
    out = ((p.stdout or "") + (p.stderr or "")).strip() or "(no output)"
    return (p.returncode, out)

def build_qr_png(conf_path):
    p = subprocess.run(
        ["qrencode", "-o", "-", "-t", "PNG"],
        input=open(conf_path, "rb").read(),
        capture_output=True
    )
    if p.returncode != 0:
        raise RuntimeError((p.stderr or b"qrencode failed").decode("utf-8", errors="ignore"))
    return p.stdout


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlparse(self.path).path

        parsed = urlparse(self.path)
        path = parsed.path
        qs = parse_qs(parsed.query)

        # ----- Metrics proxy -----
        if path == "/metrics":
            try:
                with urllib.request.urlopen("http://127.0.0.1:9090/metrics", timeout=2) as r:
                    payload = r.read()

                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(payload)
                return

            except Exception as e:
                self.send_response(500)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(
                    ('{"error": "%s"}' % str(e)).encode("utf-8")
                )
                return

        if path == "/status.json":
            fpath = "/var/www/html/zwetow/status.json"
            if not os.path.isfile(fpath):
                self.send_response(404)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(b'{"error":"status.json not found"}')
                return

            size = os.path.getsize(fpath)
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(size))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()

            with open(fpath, "rb") as f:
                self.wfile.write(f.read())
            return

        if path == "/wireguard/clients":
            json_response(self, 200, {"clients": list_clients()})
            return

        if path == "/wireguard/add-client":
            name = (qs.get("name") or [""])[0].strip()
            if not is_valid_client_name(name):
                json_response(self, 400, {
                    "error": "Invalid client name. Use letters, numbers, dash, underscore only."
                })
                return

            conf_path = client_conf_path(name)
            if os.path.exists(conf_path):
                json_response(self, 200, {
                    "ok": True,
                    "client": name,
                    "message": "Client already exists"
                })
                return

            code, out = run_add_client(name)
            if code != 0:
                json_response(self, 500, {
                    "error": "Failed to create client",
                    "detail": out
                })
                return

            json_response(self, 200, {
                "ok": True,
                "client": name,
                "message": "Client created",
                "detail": out
            })
            return

        if path.startswith("/wireguard/client/") and path.endswith("/config"):
            name = path[len("/wireguard/client/"):-len("/config")].strip("/")
            name = unquote(name)
            if not is_valid_client_name(name):
                json_response(self, 400, {"error": "Invalid client name"})
                return

            conf_path = client_conf_path(name)
            if not os.path.isfile(conf_path):
                json_response(self, 404, {"error": "Client config not found"})
                return

            size = os.path.getsize(conf_path)
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(size))
            self.send_header("Content-Disposition", f'attachment; filename="{name}.conf"')
            self.send_header("Cache-Control", "no-store")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            with open(conf_path, "rb") as f:
                self.wfile.write(f.read())
            return

        if path.startswith("/wireguard/client/") and path.endswith("/qr"):
            name = path[len("/wireguard/client/"):-len("/qr")].strip("/")
            name = unquote(name)
            if not is_valid_client_name(name):
                json_response(self, 400, {"error": "Invalid client name"})
                return

            conf_path = client_conf_path(name)
            if not os.path.isfile(conf_path):
                json_response(self, 404, {"error": "Client config not found"})
                return

            try:
                png = build_qr_png(conf_path)
                self.send_response(200)
                self.send_header("Content-Type", "image/png")
                self.send_header("Content-Length", str(len(png)))
                self.send_header("Cache-Control", "no-store")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(png)
                return
            except Exception as e:
                json_response(self, 500, {"error": str(e)})
                return

        # ----- Support bundle flow -----
        if path == "/support":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"""<!doctype html>
<html><head>
<meta charset="utf-8">
<meta http-equiv="refresh" content="1; url=/support.tgz">
<title>Generating Support Bundle</title>
</head>
<body style="background:#0b0f14;color:#e6edf3;font-family:Arial;text-align:center;padding-top:60px;">
<h2>Generating Support Bundle...</h2>
<p>Your download will begin automatically.</p>
</body></html>""")
            return

        if path == "/support.tgz":
            # Generate bundle (if script exists)
            if os.path.exists(GEN_SCRIPT):
                subprocess.run([GEN_SCRIPT], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            fpath = latest_bundle()
            if not fpath or not os.path.isfile(fpath):
                self.send_response(500)
                self.send_header("Content-Type", "text/plain; charset=utf-8")
                self.end_headers()
                self.wfile.write(b"Support bundle not found")
                return

            fname = os.path.basename(fpath)
            size = os.path.getsize(fpath)

            self.send_response(200)
            self.send_header("Content-Type", "application/gzip")
            self.send_header("Content-Length", str(size))
            self.send_header("Content-Disposition", f'attachment; filename="{fname}"')
            self.end_headers()

            with open(fpath, "rb") as f:
                while True:
                    chunk = f.read(1024 * 256)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
            return

        # ----- Update / Rollback flow -----
        if path == "/update":
            code, out = run_script(UPDATE_SCRIPT)
            self.send_response(200 if code == 0 else 500)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            body = f"""<!doctype html>
<html><head><meta charset="utf-8"><title>Update</title></head>
<body style="background:#0b0f14;color:#e6edf3;font-family:Arial;padding:24px;">
<h2>Update {'Complete' if code==0 else 'Failed'}</h2>
<pre style="background:#0a0f1a;border:1px solid #243244;border-radius:12px;padding:12px;white-space:pre-wrap;">{out}</pre>
<p><a href="http://{self.headers.get('Host','').split(':')[0]}/" style="color:#7dd3fc;">Back to Home</a></p>
</body></html>"""
            self.wfile.write(body.encode("utf-8"))
            return

        if path == "/rollback":
            code, out = run_script(ROLLBACK_SCRIPT)
            self.send_response(200 if code == 0 else 500)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            body = f"""<!doctype html>
<html><head><meta charset="utf-8"><title>Rollback</title></head>
<body style="background:#0b0f14;color:#e6edf3;font-family:Arial;padding:24px;">
<h2>Rollback {'Complete' if code==0 else 'Failed'}</h2>
<pre style="background:#0a0f1a;border:1px solid #243244;border-radius:12px;padding:12px;white-space:pre-wrap;">{out}</pre>
<p><a href="http://{self.headers.get('Host','').split(':')[0]}/" style="color:#7dd3fc;">Back to Home</a></p>
</body></html>"""
            self.wfile.write(body.encode("utf-8"))
            return

        self.send_response(404)
        self.end_headers()

    def log_message(self, fmt, *args):
        return

if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 9091), Handler).serve_forever()
