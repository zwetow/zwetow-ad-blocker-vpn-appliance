#!/usr/bin/env python3
import os, glob, subprocess
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse

BUNDLE_DIR = "/var/tmp"
GEN_SCRIPT = "/opt/zwetow/bin/zwetow-support-bundle.sh"

UPDATE_SCRIPT = "/opt/zwetow/bin/zwetow-update.sh"
ROLLBACK_SCRIPT = "/opt/zwetow/bin/zwetow-rollback.sh"

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

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlparse(self.path).path

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
