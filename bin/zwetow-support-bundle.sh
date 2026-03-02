#!/usr/bin/env bash
set -euo pipefail

TS="$(date +%Y%m%d-%H%M%S)"
HOST="$(hostname)"
OUTDIR="/var/tmp/zwetow-support-${HOST}-${TS}"
REPORT="${OUTDIR}/support-report.txt"
BUNDLE="/var/tmp/zwetow-support-${HOST}-${TS}.tgz"

mkdir -p "$OUTDIR"
chmod 700 "$OUTDIR"

# Helpers
run() {
  local title="$1"; shift
  {
    echo
    echo "================================================================================"
    echo "### ${title}"
    echo "--------------------------------------------------------------------------------"
    "$@" 2>&1 || true
  } >> "$REPORT"
}

run_sh() {
  local title="$1"; shift
  run "$title" bash -lc "$*"
}

copy_file() {
  local src="$1"
  local dest="${OUTDIR}${src}"
  if [[ -f "$src" ]]; then
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest" 2>/dev/null || true
  fi
}

redact_inplace() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  # WireGuard private keys
  sed -i -E 's/^(PrivateKey\s*=\s*).+/\1REDACTED/g' "$f" 2>/dev/null || true
  sed -i -E 's/^(PresharedKey\s*=\s*).+/\1REDACTED/g' "$f" 2>/dev/null || true
  # Pi-hole web password hash (setupVars.conf)
  sed -i -E 's/^(WEBPASSWORD=).+/\1REDACTED/g' "$f" 2>/dev/null || true
  # Any obvious tokens/keys lines (best-effort)
  sed -i -E 's/((token|apikey|api_key|secret|password)\s*[:=]\s*).+/\1REDACTED/Ig' "$f" 2>/dev/null || true
}

# Header
{
  echo "Zwetow Network Appliance - Support Bundle"
  echo "Generated: $(date -Is)"
  echo "Hostname: ${HOST}"
  echo "User: $(id)"
  echo "Kernel: $(uname -a)"
  echo "Uptime: $(uptime -p 2>/dev/null || true)"
  echo "================================================================================"
} > "$REPORT"

# Core system identity
run_sh "OS Release" "cat /etc/os-release || true"
run_sh "CPU / Memory (summary)" "lscpu || true; echo; free -h || true"
run_sh "Disk usage" "df -hT || true; echo; lsblk -f || true"
run_sh "PCI / USB (if available)" "lspci -nn || true; echo; lsusb || true"
run_sh "Thermals (if available)" "vcgencmd measure_temp 2>/dev/null || true; cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || true"
run_sh "Firmware / Dmesg (last 200 lines)" "dmesg --ctime 2>/dev/null | tail -n 200 || true"

# Networking
run_sh "Interfaces + IPs" "ip -br addr || true"
run_sh "Routes" "ip route show || true; ip -6 route show || true"
run_sh "DNS + resolv.conf" "resolvectl status 2>/dev/null || true; echo; cat /etc/resolv.conf || true"
run_sh "Listening ports" "ss -lntup || true"
run_sh "Firewall / NAT (iptables)" "iptables -S 2>/dev/null || true; echo; iptables -t nat -S 2>/dev/null || true"
run_sh "Firewall / NAT (nftables)" "nft list ruleset 2>/dev/null || true"

# App/service status
run_sh "Systemd failed units" "systemctl --failed --no-pager || true"
run_sh "Key service status" "systemctl status pihole-FTL --no-pager 2>/dev/null || true; echo; systemctl status wg-quick@wg0 --no-pager 2>/dev/null || true; echo; systemctl status uptime-kuma --no-pager 2>/dev/null || true; echo; systemctl status zwetow-render --no-pager 2>/dev/null || true; echo; systemctl status zwetow-status --no-pager 2>/dev/null || true; echo; systemctl status zwetow-metrics --no-pager 2>/dev/null || true"

run_sh "Pi-hole versions + status" "pihole -v 2>/dev/null || true; echo; pihole status 2>/dev/null || true"
run_sh "WireGuard status" "wg show 2>/dev/null || true"
run_sh "Uptime Kuma (port check)" "ss -ltnp | grep -E ':(3001)\\s' || true"
run_sh "Zwetow metrics (local)" "curl -s --max-time 2 http://127.0.0.1:9090/metrics | python3 -m json.tool 2>/dev/null || true; echo; curl -s -i --max-time 2 http://127.0.0.1:9090/health | head -n 20 || true"

# Logs (last N lines)
run_sh "pihole-FTL journal (last 200)" "journalctl -u pihole-FTL -n 200 --no-pager 2>/dev/null || true"
run_sh "wg-quick@wg0 journal (last 200)" "journalctl -u wg-quick@wg0 -n 200 --no-pager 2>/dev/null || true"
run_sh "uptime-kuma journal (last 200)" "journalctl -u uptime-kuma -n 200 --no-pager 2>/dev/null || true"
run_sh "zwetow-render journal (last 200)" "journalctl -u zwetow-render -n 200 --no-pager 2>/dev/null || true"
run_sh "zwetow-status journal (last 200)" "journalctl -u zwetow-status -n 200 --no-pager 2>/dev/null || true"
run_sh "zwetow-metrics journal (last 200)" "journalctl -u zwetow-metrics -n 200 --no-pager 2>/dev/null || true"

# Copy configs (then redact)
copy_file "/etc/wireguard/wg0.conf"
copy_file "/etc/sysctl.conf"
copy_file "/etc/ssh/sshd_config"
copy_file "/etc/pihole/setupVars.conf"
copy_file "/etc/dnsmasq.d/01-pihole.conf"
copy_file "/etc/pihole/pihole.toml"
copy_file "/etc/pihole/pihole-FTL.conf"
copy_file "/opt/zwetow/bin/render-index.sh"
copy_file "/opt/zwetow/bin/metrics-server.py"
copy_file "/etc/systemd/system/uptime-kuma.service"
copy_file "/etc/systemd/system/zwetow-*.service"
copy_file "/etc/systemd/system/zwetow-*.timer"

# Redact secrets in copied configs
for f in \
  "${OUTDIR}/etc/wireguard/wg0.conf" \
  "${OUTDIR}/etc/pihole/setupVars.conf" \
  "${OUTDIR}/etc/pihole/pihole.toml" \
  "${OUTDIR}/etc/pihole/pihole-FTL.conf" \
; do
  redact_inplace "$f"
done

# Also redact secrets in the report itself (best effort)
redact_inplace "$REPORT"

# Bundle it
tar -C "$(dirname "$OUTDIR")" -czf "$BUNDLE" "$(basename "$OUTDIR")"
chmod 600 "$BUNDLE"

echo "Support report: $REPORT"
echo "Support bundle: $BUNDLE"
