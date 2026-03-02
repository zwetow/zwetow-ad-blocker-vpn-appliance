#!/usr/bin/env bash
set -euo pipefail

LOG="/var/log/zwetow-firstboot.log"
exec > >(tee -a "$LOG") 2>&1

echo "== Zwetow first boot provisioning =="

# Unique machine identity
sudo rm -f /etc/machine-id /var/lib/dbus/machine-id || true
sudo systemd-machine-id-setup

# Unique SSH host keys
sudo rm -f /etc/ssh/ssh_host_* || true
sudo dpkg-reconfigure openssh-server

# Unique hostname based on Pi serial
SERIAL="$(awk '/Serial/ {print $3}' /proc/cpuinfo | tail -n1)"
SUFFIX="$(echo "$SERIAL" | tail -c 5)"
NEW_HOST="zwetow-${SUFFIX}"

echo "$NEW_HOST" | sudo tee /etc/hostname >/dev/null
sudo sed -i "s/127.0.1.1.*/127.0.1.1\t$NEW_HOST/g" /etc/hosts || true
sudo hostnamectl set-hostname "$NEW_HOST"

# Generate WireGuard server keys unique per device
sudo mkdir -p /etc/wireguard
sudo chmod 700 /etc/wireguard
if ! sudo test -f /etc/wireguard/server_private.key; then
  umask 077
  wg genkey | sudo tee /etc/wireguard/server_private.key >/dev/null
  sudo cat /etc/wireguard/server_private.key | wg pubkey | sudo tee /etc/wireguard/server_public.key >/dev/null
fi

# Set a unique Pi-hole admin password per device (write it to /boot for packaging only)
if command -v pihole >/dev/null 2>&1; then
  ADMIN_PASS="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)"
  sudo pihole setpassword "$ADMIN_PASS"
  {
    echo "Zwetow Device Setup"
    echo "Hostname: $NEW_HOST"
    echo "Serial: $SERIAL"
    echo "Pi-hole Admin Password: $ADMIN_PASS"
  } | sudo tee /boot/ZWETOW_SECRETS.txt >/dev/null
  sudo chmod 600 /boot/ZWETOW_SECRETS.txt || true
fi

# Generate device info JSON for the landing page
sudo /opt/zwetow/bin/update-status.sh || true

# Mark complete
sudo touch /etc/zwetow/.firstboot_done

echo "== First boot complete. Rebooting... =="
sleep 3
sudo reboot
