#!/usr/bin/env python3
import getpass
import hashlib
import json
import os
import secrets
import sys
from datetime import datetime, timezone

ADMIN_CONFIG_PATH = "/etc/zwetow/admin.json"


def iso_now():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


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


def main():
    username = sys.argv[1] if len(sys.argv) > 1 else "admin"
    username = username.strip()
    if not username:
        print("Username cannot be empty", file=sys.stderr)
        return 1

    password = getpass.getpass("New appliance admin password: ")
    confirm = getpass.getpass("Confirm password: ")

    if password != confirm:
        print("Passwords do not match", file=sys.stderr)
        return 1
    if len(password) < 10:
        print("Password must be at least 10 characters", file=sys.stderr)
        return 1

    payload = {
        "username": username,
        "password_hash": hash_password(password),
        "updated_at": iso_now(),
    }

    os.makedirs(os.path.dirname(ADMIN_CONFIG_PATH), exist_ok=True)
    with open(ADMIN_CONFIG_PATH, "w", encoding="utf-8") as admin_file:
        json.dump(payload, admin_file, indent=2, sort_keys=True)
        admin_file.write("\n")
    os.chmod(ADMIN_CONFIG_PATH, 0o600)

    print(f"Wrote appliance admin config to {ADMIN_CONFIG_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
