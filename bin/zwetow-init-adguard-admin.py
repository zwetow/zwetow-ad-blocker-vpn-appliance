#!/usr/bin/env python3
import json
import os
import re
import subprocess
import tempfile

CONFIG_CANDIDATES = [
    os.environ.get("ZWETOW_ADGUARD_CONFIG", "").strip(),
    "/opt/AdGuardHome/conf/AdGuardHome.yaml",
    "/etc/AdGuardHome.yaml",
    "/opt/adguardhome/conf/AdGuardHome.yaml",
]

SERVICE_CANDIDATES = [
    "AdGuardHome",
    "adguardhome",
]


def emit(payload, exit_code):
    print(json.dumps(payload))
    raise SystemExit(exit_code)


def read_request():
    raw = os.sys.stdin.read()
    try:
        payload = json.loads(raw or "{}")
    except Exception as exc:
        emit({"ok": False, "error": f"Invalid JSON input: {exc}"}, 2)

    username = str(payload.get("username", "")).strip()
    password = str(payload.get("password", ""))
    if not username or not password:
        emit({"ok": False, "error": "username and password are required"}, 2)
    return username, password


def find_config_path():
    for candidate in CONFIG_CANDIDATES:
        if candidate and os.path.isfile(candidate):
            return candidate
    return None


def generate_bcrypt_hash(password):
    node_code = r"""
const bcrypt = require('/opt/uptime-kuma/node_modules/bcryptjs');
const chunks = [];
process.stdin.on('data', (chunk) => chunks.push(chunk));
process.stdin.on('end', () => {
  const password = Buffer.concat(chunks).toString('utf8');
  process.stdout.write(bcrypt.hashSync(password, 10));
});
"""
    proc = subprocess.run(
        ["node", "-e", node_code],
        input=password,
        text=True,
        capture_output=True,
    )
    if proc.returncode != 0:
        detail = ((proc.stdout or "") + (proc.stderr or "")).strip()
        emit({"ok": False, "error": f"Could not generate bcrypt hash: {detail or 'node helper failed'}"}, 3)
    return (proc.stdout or "").strip()


def build_users_block(username, password_hash):
    return "\n".join([
        "users:",
        f"  - name: {username}",
        f"    password: {password_hash}",
        "",
    ])


def replace_users_block(text, replacement):
    lines = text.splitlines()
    start = None
    end = None

    for index, line in enumerate(lines):
        if re.match(r"^users:\s*(\[\])?\s*$", line):
            start = index
            end = index + 1
            while end < len(lines):
                next_line = lines[end]
                if next_line and not next_line.startswith((" ", "\t")):
                    break
                end += 1
            break

    replacement_lines = replacement.rstrip("\n").splitlines()
    if start is None:
        if lines and lines[-1] != "":
            lines.append("")
        lines.extend(replacement_lines)
    else:
        lines[start:end] = replacement_lines
    return "\n".join(lines) + "\n"


def write_file(path, text):
    directory = os.path.dirname(path)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=directory, delete=False) as temp_file:
        temp_file.write(text)
        temp_path = temp_file.name
    os.replace(temp_path, path)
    os.chmod(path, 0o600)


def restart_service():
    for service_name in SERVICE_CANDIDATES:
        proc = subprocess.run(
            ["systemctl", "restart", service_name],
            capture_output=True,
            text=True,
        )
        if proc.returncode == 0:
            return f"restarted {service_name}"
    return "updated config; service restart not confirmed"


def main():
    username, password = read_request()
    config_path = find_config_path()
    if not config_path:
        emit({"ok": False, "error": "AdGuard config not found"}, 4)

    with open(config_path, "r", encoding="utf-8") as config_file:
        config_text = config_file.read()

    password_hash = generate_bcrypt_hash(password)
    updated_text = replace_users_block(config_text, build_users_block(username, password_hash))
    write_file(config_path, updated_text)
    restart_detail = restart_service()

    emit({
        "ok": True,
        "message": f"updated {config_path} and {restart_detail}",
    }, 0)


if __name__ == "__main__":
    main()
