#!/usr/bin/env python3
import json
import os
import secrets
import sys
from datetime import datetime, timedelta, timezone
import hashlib

ADMIN_CONFIG_PATH = "/etc/zwetow/admin.json"
ADMIN_RESET_PATH = "/etc/zwetow/admin-reset.json"
RESET_TOKEN_TTL_SECONDS = 15 * 60


def iso_now():
    return datetime.now(timezone.utc).replace(microsecond=0)


def read_admin_config():
    try:
        with open(ADMIN_CONFIG_PATH, "r", encoding="utf-8") as admin_file:
            data = json.load(admin_file)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def hash_reset_token(token):
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def main():
    admin_config = read_admin_config()
    username = str(admin_config.get("username") or "admin").strip() or "admin"

    token = secrets.token_urlsafe(24)
    expires_at = iso_now() + timedelta(seconds=RESET_TOKEN_TTL_SECONDS)
    payload = {
        "username": username,
        "token_hash": hash_reset_token(token),
        "created_at": iso_now().isoformat(),
        "expires_at": expires_at.isoformat(),
    }

    os.makedirs(os.path.dirname(ADMIN_RESET_PATH), exist_ok=True)
    with open(ADMIN_RESET_PATH, "w", encoding="utf-8") as reset_file:
        json.dump(payload, reset_file, indent=2, sort_keys=True)
        reset_file.write("\n")
    os.chmod(ADMIN_RESET_PATH, 0o600)

    print("Zwetow appliance admin reset token generated.")
    print(f"Username: {username}")
    print(f"Reset token: {token}")
    print(f"Expires: {expires_at.isoformat()}")
    print("Use this token on the appliance login page to set a new password.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
