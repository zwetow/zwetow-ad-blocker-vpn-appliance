#!/usr/bin/env bash
set -euo pipefail

OUT="/var/www/html/index.html"

# Optional embedded logo (keeps Pi-hole webserver locked down)
LOGO_PATH="/var/www/html/zwetow-logo.png"
LOGO_B64=""
if [[ -f "$LOGO_PATH" ]]; then
  LOGO_B64="$(base64 -w 0 "$LOGO_PATH" 2>/dev/null || true)"
fi

LOGO_HTML='<div class="logo-fallback">Z</div>'
if [[ -n "$LOGO_B64" ]]; then
  LOGO_HTML="<img class='logo' src='data:image/png;base64,${LOGO_B64}' alt='Zwetow Logo'>"
fi

HOST="$(hostname)"
IP="$(hostname -I | awk '{print $1}')"
CURRENT_VER="$(cat /opt/zwetow/VERSION 2>/dev/null || echo 'unknown')"
LATEST_VER="$(cat /opt/zwetow/state/LATEST_VERSION 2>/dev/null || echo 'unknown')"
UPDATE_AVAIL=""

if [[ -f /opt/zwetow/state/UPDATE_AVAILABLE && "$LATEST_VER" != "$CURRENT_VER" ]]; then
  UPDATE_AVAIL="$(cat /opt/zwetow/state/UPDATE_AVAILABLE 2>/dev/null || true)"
fi
UPTIME="$(uptime -p 2>/dev/null || echo 'unknown')"
NOW="$(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo '')"
BUILD="$(date '+%Y.%m.%d' 2>/dev/null || echo 'dev')"

# Best-effort public IP (won't block page if outbound is blocked)
PUB_IP="$(curl -s --max-time 2 https://ifconfig.me 2>/dev/null || true)"
[[ -z "${PUB_IP:-}" ]] && PUB_IP="unavailable"


METRICS_JSON="$(curl -s --max-time 2 http://127.0.0.1:9090/metrics || echo '{}')"
HEALTH_OK="no"
if curl -s --max-time 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:9090/health | grep -q '^200$'; then
  HEALTH_OK="yes"
fi

HEALTH_PILL_CLASS="pill-bad"
HEALTH_LABEL="BAD"
HEALTH_PULSE="pulse"

if [[ "$HEALTH_OK" == "yes" ]]; then
  HEALTH_PILL_CLASS="pill-ok"
  HEALTH_LABEL="OK"
  HEALTH_PULSE=""
fi

CPU_PCT="$(python3 -c "import json; d=json.loads('''$METRICS_JSON'''); print(d.get('cpu_percent','?'))" 2>/dev/null || echo '?')"
MEM_PCT="$(python3 -c "import json; d=json.loads('''$METRICS_JSON'''); print(d.get('memory_percent','?'))" 2>/dev/null || echo '?')"
DISK_PCT="$(python3 -c "import json; d=json.loads('''$METRICS_JSON'''); print(d.get('disk_percent','?'))" 2>/dev/null || echo '?')"
sanitize_pct() {
  local v="${1:-}"
  if [[ "$v" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    awk -v n="$v" 'BEGIN {
      if (n < 0) n = 0;
      if (n > 100) n = 100;
      print n;
    }'
  else
    printf '0'
  fi
}
CPU_PCT="$(sanitize_pct "$CPU_PCT")"
MEM_PCT="$(sanitize_pct "$MEM_PCT")"
DISK_PCT="$(sanitize_pct "$DISK_PCT")"
CPU_TEMP="$(python3 -c "import json; d=json.loads('''$METRICS_JSON'''); print(d.get('cpu_temp_c','?'))" 2>/dev/null || echo '?')"
WG_PEERS="$(python3 -c "import json; d=json.loads('''$METRICS_JSON'''); print(d.get('wg_peer_count','?'))" 2>/dev/null || echo '?')"
PH_Q="$(python3 -c "import json; d=json.loads('''$METRICS_JSON'''); print(d.get('pihole_dns_queries_today','?'))" 2>/dev/null || echo '?')"
PH_STATUS="$(python3 -c "import json; d=json.loads('''$METRICS_JSON'''); print(d.get('pihole_status','?'))" 2>/dev/null || echo '?')"
PH_BLOCKED="$(python3 -c "import json;print(json.loads('''$METRICS_JSON''').get('pihole_ads_blocked_today','?'))" 2>/dev/null || echo '?')"
PH_PCT="$(python3 -c "import json;print(json.loads('''$METRICS_JSON''').get('pihole_ads_percentage_today','?'))" 2>/dev/null || echo '?')"
PH_LABEL="$PH_STATUS"
if [[ "$PH_STATUS" == "enabled" ]]; then PH_LABEL="active"; fi
if [[ "$PH_STATUS" == "disabled" ]]; then PH_LABEL="disabled"; fi
# Pi-hole service pill based on PH_STATUS (enabled/disabled/unknown)
PH_PILL_CLASS="pill-bad"
if [[ "$PH_STATUS" == "enabled" ]]; then
  PH_PILL_CLASS="pill-ok"
fi

# DNS listener check (Pi-hole typically listens on 53 TCP/UDP)
PH_DNS_LISTEN="53 (not listening)"
if ss -lunp 2>/dev/null | grep -qE ':(53)\s'; then
  PH_DNS_LISTEN="53/udp (listening)"
fi
if ss -ltnp 2>/dev/null | grep -qE ':(53)\s'; then
  # if both, show a nicer combined string
  if [[ "$PH_DNS_LISTEN" == "53/udp (listening)" ]]; then
    PH_DNS_LISTEN="53/tcp+udp (listening)"
  else
    PH_DNS_LISTEN="53/tcp (listening)"
  fi
fi

SERIAL="$(awk '/Serial/ {print $3}' /proc/cpuinfo | tail -n1)"
OS="$(. /etc/os-release; echo "$PRETTY_NAME")"
KERNEL="$(uname -r)"

# LAN subnet detection (eth0)
LAN_CIDR="$(ip -o -f inet addr show eth0 2>/dev/null | awk '{print $4}' | head -n1 || true)"
LAN_SUBNET="${LAN_CIDR:-unknown}"
PIHOLE_VERSION="$(pihole -v 2>/dev/null | awk -F'[: ]+' '/version is/ {print $1 " " $4}' | paste -sd ' | ' -)"

WG_VER="$(wg --version 2>/dev/null | awk '{print $2}' | sed 's/^v//' || echo 'not installed')"
WG_ACTIVE="$(systemctl is-active wg-quick@wg0 2>/dev/null || echo 'inactive')"
WG_PILL_CLASS="pill-bad"
if [[ "$WG_ACTIVE" == "active" ]]; then
  WG_PILL_CLASS="pill-ok"
fi
WG_PORT="51820"
if ss -lunp 2>/dev/null | grep -qE ':(51820)\s'; then
  WG_PORT="51820 (listening)"
else
  WG_PORT="51820 (not listening)"
fi

KUMA_VER="$(node -p "require('/opt/uptime-kuma/package.json').version" 2>/dev/null || echo 'unknown')"
KUMA_ACTIVE="$(systemctl is-active uptime-kuma 2>/dev/null || echo 'inactive')"
KUMA_PILL_CLASS="pill-bad"
if [[ "$KUMA_ACTIVE" == "active" ]]; then
  KUMA_PILL_CLASS="pill-ok"
fi
KUMA_LISTEN="3001 (not listening)"
if ss -ltnp 2>/dev/null | grep -qE ':(3001)\s'; then
  KUMA_LISTEN="3001 (listening)"
fi

RENDER_TIMER_ACTIVE="$(systemctl is-active zwetow-render.timer 2>/dev/null || echo 'unknown')"
UPDATE_TIMER_ACTIVE="$(systemctl is-active zwetow-check-update.timer 2>/dev/null || echo 'unknown')"

RENDER_TIMER_PILL="pill-bad"
[[ "$RENDER_TIMER_ACTIVE" == "active" ]] && RENDER_TIMER_PILL="pill-ok"

UPDATE_TIMER_PILL="pill-bad"
[[ "$UPDATE_TIMER_ACTIVE" == "active" ]] && UPDATE_TIMER_PILL="pill-ok"

STATUS_CLASS="status-ok"
STATUS_TEXT="All services operational"

if [[ "$HEALTH_OK" != "yes" || "$WG_ACTIVE" != "active" || "$KUMA_ACTIVE" != "active" ]]; then
  STATUS_CLASS="status-bad"
  STATUS_TEXT="Attention: "
  [[ "$HEALTH_OK" != "yes" ]] && STATUS_TEXT+="Health check failed • "
  [[ "$WG_ACTIVE" != "active" ]] && STATUS_TEXT+="WireGuard inactive • "
  [[ "$KUMA_ACTIVE" != "active" ]] && STATUS_TEXT+="Uptime Kuma inactive • "
  STATUS_TEXT="${STATUS_TEXT% • }"
fi


KUMA_URL="http://${IP}:3001/"
ADMIN_URL="http://${IP}/admin/"

cat > "$OUT" <<EOF
<!doctype html>
<html>
<head>
  <link rel="icon" href="data:,">
  <meta charset="utf-8">
  <title>Zwetow Network Appliance</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
<style>
:root{
  --bg: #0b0f14;
  --panel1: #0f172a;
  --panel2: #0b1220;
  --border: #243244;
  --borderHover: #334155;
  --text: #e6edf3;
  --muted: #9aa6b2;
  --link: #7dd3fc;
  --linkHover: #bae6fd;
  --warnBg: #451a03;
  --warnBorder: #92400e;
  --warnText: #f59e0b;
  --okBg: #064e3b;
  --okBorder: #065f46;
  --okText: #22c55e;

  --badBg: #7f1d1d;
  --badBorder: #991b1b;
  --badText: #ef4444;
  --accent: #f97316;
  --accent2: #fb923c;

}

body {
  font-family: Arial, sans-serif;
  max-width: 980px;
  margin: 40px auto;
  padding: 0 16px;
  background: radial-gradient(1200px 600px at 20% 0%, rgba(125,211,252,0.08), transparent 55%),
              radial-gradient(900px 500px at 90% 10%, rgba(239,68,68,0.06), transparent 55%),
              var(--bg);
  color: var(--text);
}

.header{ margin: 0 0 16px 0; }

.header-strip{
  display:flex;
  align-items:center;
  justify-content:space-between;
  gap:16px;
  margin: 0 0 10px 0;
  padding-bottom: 10px;
}

.brand-mini{
  display:flex;
  align-items:center;
}

/* logo image sizing for the strip */
.brand-mini .logo{
  height: 60px;
  width: auto;
  max-width: 220px;
  object-fit: contain;
  border: 0;
  background: transparent;
}

/* fallback "Z" badge if logo missing */
.brand-mini .logo-fallback{
  height: 64px;
  padding: 0 10px;
  border-radius: 12px;
  border: 1px solid var(--border);
  display:flex;
  align-items:center;
  justify-content:center;
  font-weight: 900;
  background: rgba(31,41,55,0.35);
  color: var(--text);
}

.topbar{
  display:flex;
  align-items:center;
  justify-content:space-between;
  gap:16px;
  padding: 14px 16px;
  margin: 0 0 16px 0;

  border: 1px solid var(--border);
  border-radius: 18px;
  background: linear-gradient(145deg, rgba(15,23,42,0.85), rgba(11,18,32,0.75));
  box-shadow: 0 10px 28px rgba(0,0,0,0.35);
}

.meter-row{
  margin: 8px 0 10px;
}

.meter-head{
  display:flex;
  align-items:baseline;
  justify-content:space-between;
  gap: 12px;
  font-size: 13px;
}

.meter{
  margin-top: 6px;
  height: 8px;
  background: rgba(31,41,55,0.55);
  border: 1px solid var(--border);
  border-radius: 999px;
  overflow: hidden;
}

.meter > span{
  display:block;
  height:100%;
  width:0%;
  background: linear-gradient(90deg, var(--accent), var(--accent2));
  transition: width 0.6s ease;
}

.icons{
  display:flex;
  gap:10px;
}

.iconbtn{
  display:inline-flex;
  align-items:center;
  justify-content:center;
  width:42px;
  height:42px;
  border-radius: 12px;
  border: 1px solid var(--border);
  background: rgba(31,41,55,0.35);
  color: var(--text);
  text-decoration:none;
}

.iconbtn:hover{
  transform: translateY(-1px);
  border-color: rgba(249,115,22,0.55);
  box-shadow: 0 0 0 3px rgba(249,115,22,0.12);
}

.iconbtn svg{
  width:22px;
  height:22px;
  display:block;
}

.iconbtn.discord svg{
  transform: scale(1.45) translateY(1px) translateX(1px);
  transform-origin: 50% 50%;
}

.brand-text{ min-width:0; }
.title{
  font-size: 22px;
  font-weight: 800;
  letter-spacing: 0.2px;
}
.subtitle{
  color: var(--muted);
  font-size: 13px;
  margin-top: 2px;
}

.nav{
  display:flex;
  gap:10px;
  flex-wrap: wrap;
  justify-content:flex-end;
}

.navlink{
  text-decoration:none;
  font-weight: 700;
  font-size: 13px;
  color: var(--text);

  padding: 6px 10px;
  border-radius: 999px;
  border: 1px solid var(--border);
  background: rgba(31,41,55,0.35);
  transition: transform 0.2s ease, border-color 0.2s ease;
}

.navlink:hover{
  transform: translateY(-1px);
  border-color: rgba(249,115,22,0.55);
}

a { color: var(--link); }
a:hover { color: var(--linkHover); }

.tabs a { margin-right: 14px; text-decoration: none; font-weight: 700; }

.top-grid {
  display: grid;
  grid-template-columns: 1fr;
  gap: 14px;
  margin-bottom: 14px;
  align-items: stretch;
}

@media (min-width: 860px) {
  .top-grid {
    grid-template-columns: 1fr 1fr;
    align-items: stretch;
  }

  .grid {
    grid-template-columns: 1fr 1fr;
    align-items: start;
  }

  .span-2 {
    grid-column: span 2;
  }
}

.grid {
  display: grid;
  grid-template-columns: 1fr;
  gap: 14px;
  align-items: stretch;
}

.equal-card {
  min-height: 260px;
}

.card {
  position: relative;
  background: linear-gradient(145deg, var(--panel1), var(--panel2));
  border: 1px solid var(--border);
  border-radius: 16px;
  padding: 16px;
  box-shadow: 0 10px 28px rgba(0,0,0,0.35);
  backdrop-filter: blur(6px);
  transition: transform 0.25s ease, box-shadow 0.25s ease, border-color 0.25s ease;
}

/* Inner highlight line */
.card:before{
  content:"";
  position:absolute;
  inset: 1px 1px auto 1px;
  height: 42px;
  border-radius: 15px 15px 12px 12px;
  background: linear-gradient(180deg, rgba(255,255,255,0.06), transparent);
  pointer-events:none;
}

.card:hover{
  transform: translateY(-4px);
  box-shadow: 0 16px 42px rgba(0,0,0,0.55);
  border-color: var(--borderHover);
}

pre {
  background: #0a0f1a;
  color: #e5e7eb;
  padding: 12px;
  border-radius: 12px;
  overflow: auto;
  border: 1px solid var(--border);
}

.muted { color: var(--muted); }

.status-bar{
  padding: 8px 14px;
  margin: 0 0 14px 0;
  border-radius: 14px;
  border: 1px solid var(--border);
  font-size: 13px;
  font-weight: 750;
  letter-spacing: 0.2px;
}

.status-ok{
  background: rgba(34,197,94,0.10);
  border-color: rgba(34,197,94,0.25);
  color: #86efac;
}

.status-bad{
  background: rgba(239,68,68,0.10);
  border-color: rgba(239,68,68,0.25);
  color: #fca5a5;
}

.service-tiles {
  display: grid;
  grid-template-columns: 1fr;
  gap: 12px;
  margin-top: 12px;
}

.service-tile {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 14px;
  padding: 14px 16px;
  border: 1px solid var(--border);
  border-radius: 14px;
  background: rgba(255,255,255,0.02);
}


.service-tile:hover {
  transform: translateY(-2px);
}

.service-tile.ok {
  border-color: rgba(34,197,94,0.28);
  background: rgba(34,197,94,0.05);
  box-shadow: 0 0 0 1px rgba(34,197,94,0.05) inset;
}

.service-tile.bad {
  border-color: rgba(239,68,68,0.32);
  background: rgba(239,68,68,0.07);
  box-shadow: 0 0 0 1px rgba(239,68,68,0.05) inset;
}

.service-left {
  display: flex;
  flex-direction: column;
  gap: 4px;
  min-width: 0;
}

.service-icon {
  width: 38px;
  height: 38px;
  border-radius: 12px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  background: rgba(255,255,255,0.04);
  border: 1px solid var(--border);
  font-size: 18px;
  flex: 0 0 auto;
}

.service-info {
  min-width: 0;
}

.service-name {
  font-weight: 800;
  font-size: 16px;
  line-height: 1.2;
}

.service-meta {
  color: var(--muted);
  font-size: 13px;
  margin-top: 4px;
  word-break: break-word;
}

.service-right {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-wrap: wrap;
  justify-content: flex-end;
}

.service-stat {
  color: var(--text);
  font-size: 13px;
  white-space: nowrap;
}

.stat-label {
  color: var(--muted);
  font-size: 12px;
  margin-bottom: 6px;
}

.stat-value {
  font-size: 18px;
  font-weight: 800;
}

@media (min-width: 860px) {
  .service-tiles {
    grid-template-columns: 1fr;
  }
}

.updatebar{
  display:flex;
  align-items:center;
  justify-content:space-between;
  gap:12px;
  margin: 0 0 14px 0;
  padding: 10px 12px;
  border: 1px solid var(--warnBorder);
  border-radius: 14px;
  background: rgba(69,26,3,0.20);
}

.update-left, .update-right{
  display:flex;
  align-items:center;
  gap:10px;
  flex-wrap:wrap;
}

.btn{
  display:inline-flex;
  align-items:center;
  justify-content:center;
  height:36px;
  padding:0 14px;
  border-radius:10px;
  border:1px solid rgba(249,115,22,0.55);
  background: linear-gradient(180deg, rgba(249,115,22,0.22), rgba(249,115,22,0.12));
  color: var(--text);
  text-decoration:none;
  font-weight:700;
  font-size:12px;
  cursor:pointer;
  appearance:none;
  -webkit-appearance:none;
  font-family: inherit;
  line-height:1;
  box-shadow: 0 0 0 1px rgba(249,115,22,0.08) inset;
}

.btn:hover{
  border-color: rgba(249,115,22,0.85);
  background: linear-gradient(180deg, rgba(249,115,22,0.30), rgba(249,115,22,0.16));
  transform: translateY(-1px);
}

.btn:active{
  transform: translateY(0);
}

button.btn{
  font: inherit;
}

.btn-ghost{
  background: transparent;
}

.pill {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 3px 10px;
  border-radius: 999px;
  background: #1f2937;
  border: 1px solid var(--border);
  color: var(--text);
  font-size: 12px;
  line-height: 1.3;
}

.pill-warn {
  background: var(--warnBg);
  border-color: var(--warnBorder);
  color: var(--warnText);
}

@keyframes pulseWarn {
  0%   { box-shadow: 0 0 0 0 rgba(245,158,11,0.28); }
  70%  { box-shadow: 0 0 0 8px rgba(245,158,11,0.00); }
  100% { box-shadow: 0 0 0 0 rgba(245,158,11,0.00); }
}
.pulse-warn { animation: pulseWarn 1.6s infinite; }

.pill-ok  { background: var(--okBg);  border-color: var(--okBorder);  color: var(--okText); }
.pill-bad { background: var(--badBg); border-color: var(--badBorder); color: var(--badText); }

/* Subtle glow on hover for OK/BAD */
.pill-ok:hover  { box-shadow: 0 0 0 3px rgba(34,197,94,0.14); }
.pill-bad:hover { box-shadow: 0 0 0 3px rgba(239,68,68,0.14); }

/* Pulse animation for BAD */
@keyframes pulseBad {
  0%   { box-shadow: 0 0 0 0 rgba(239,68,68,0.30); }
  70%  { box-shadow: 0 0 0 8px rgba(239,68,68,0.00); }
  100% { box-shadow: 0 0 0 0 rgba(239,68,68,0.00); }
}
.pill-bad.pulse { animation: pulseBad 1.6s infinite; }

/* small labels */
h1 { margin-bottom: 6px; }
h2 { margin-top: 0; }
</style>
</head>
<body>
<header class="header">
  <div class="header-strip">
    <div class="brand-mini">
      ${LOGO_HTML}
    </div>

    <div class="icons">
      <a class="iconbtn" href="mailto:support@zwetow.com" title="Email Support" aria-label="Email Support">
        <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
          <path fill="currentColor" d="M20 4H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2Zm0 4-8 5L4 8V6l8 5 8-5v2Z"/>
        </svg>
      </a>

      <a class="iconbtn discord" href="https://discord.gg/5GaaqvT76v" target="_blank" rel="noreferrer" title="Discord" aria-label="Discord">
        <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
          <path fill="currentColor" d="M19.5 6.5a14.8 14.8 0 0 0-3.7-1.2l-.2.4a13.4 13.4 0 0 0-3.2-.1 13 13 0 0 0-3.2.1l-.2-.4a14.8 14.8 0 0 0-3.7 1.2C2.8 9 2.3 11.5 2.5 14c1.5 1.1 3 1.8 4.6 2.2l.5-.7c-.5-.2-1-.5-1.5-.8l.3-.2c3.1 1.4 6.4 1.4 9.5 0l.3.2c-.5.3-1 .6-1.5.8l.5.7c1.6-.4 3.1-1.1 4.6-2.2.3-2.5-.2-5-1.6-7.5ZM9.3 13.6c-.6 0-1.1-.6-1.1-1.3 0-.7.5-1.3 1.1-1.3s1.1.6 1.1 1.3c0 .7-.5 1.3-1.1 1.3Zm5.4 0c-.6 0-1.1-.6-1.1-1.3 0-.7.5-1.3 1.1-1.3s1.1.6 1.1 1.3c0 .7-.5 1.3-1.1 1.3Z"/>
        </svg>
      </a>
    </div>
  </div>

  <div class="topbar">
    <div class="brand-text">
      <div class="title">Network Ad Blocker &amp; VPN Appliance</div>
      <div class="subtitle">Local control panel + quick links + device info.</div>
    </div>

    <nav class="nav">
      <a class="navlink" href="#home">Home</a>
      <a class="navlink" href="#wireguard">WireGuard</a>
      <a class="navlink" href="#links">Links</a>
    </nav>
  </div>
</header>
<div class="status-bar ${STATUS_CLASS}">${STATUS_TEXT}</div>
${UPDATE_AVAIL:+
<div class="updatebar">
  <div class="update-left">
    <span class="pill pill-warn pulse-warn">Update available</span>
    <span class="muted">Current: ${CURRENT_VER}</span>
    <span class="muted">Latest: ${LATEST_VER}</span>
  </div>
  <div class="update-right">
    <a class="btn" href="http://${IP}:9091/update">Update</a>
    <a class="btn btn-ghost" href="http://${IP}:9091/rollback">Rollback</a>
  </div>
</div>
}

<div class="top-grid">

  <div class="card equal-card">
    <h2>Device Info</h2>
    <div><b>Hostname:</b> <span id="live-hostname">${HOST}</span></div>
    <div><b>Serial:</b> ${SERIAL}</div>
    <div><b>IP Address:</b> <span id="live-ip">${IP}</span></div>
    <div><b>LAN Subnet (eth0):</b> ${LAN_SUBNET}</div>
    <div><b>Public IP:</b> ${PUB_IP}</div>
    <div><b>OS:</b> <span id="live-os">${OS}</span></div>
    <div><b>Kernel:</b> <span id="live-kernel">${KERNEL}</span></div>
    <div><b>Uptime:</b> ${UPTIME}</div>
    <div><b>Time:</b> ${NOW}</div>
  </div>

  <div class="card equal-card">
    <h2>Health</h2>
    <div><b>Overall:</b> <span class="pill ${HEALTH_PILL_CLASS} ${HEALTH_PULSE}">${HEALTH_LABEL}</span></div>
    <div><b>Temp:</b> <span id="cpu-temp">${CPU_TEMP}</span>°C</div>

    <div class="meter-row">
      <div class="meter-head"><span><b>CPU</b></span><span id="cpu-pct-text">${CPU_PCT}%</span></div>
      <div class="meter"><span id="cpu-bar" style="width:${CPU_PCT}%"></span></div>
    </div>

    <div class="meter-row">
      <div class="meter-head"><span><b>Memory</b></span><span id="mem-pct-text">${MEM_PCT}%</span></div>
      <div class="meter"><span id="mem-bar" style="width:${MEM_PCT}%"></span></div>
    </div>

    <div class="meter-row">
      <div class="meter-head"><span><b>Disk</b></span><span id="disk-pct-text">${DISK_PCT}%</span></div>
      <div class="meter"><span id="disk-bar" style="width:${DISK_PCT}%"></span></div>
    </div>
  </div>
</div>

<div class="grid">


<div class="card span-2">
  <h2>Network Services</h2>

  <div class="service-tiles">

    <div class="service-tile ${PH_PILL_CLASS/pill-/}">
      <div class="service-left">
        <div class="service-icon">🛡</div>
        <div class="service-info">
          <div class="service-name">Pi-hole</div>
          <div class="service-meta">
            Version: <span id="live-pihole">${PIHOLE_VERSION}</span>
          </div>
        </div>
      </div>
      <div class="service-right">
        <span class="pill ${PH_PILL_CLASS}">${PH_LABEL}</span>
        <span class="service-stat">${PH_DNS_LISTEN}</span>
        <span class="service-stat">Queries: <span id="ph-queries">${PH_Q}</span></span>
        <span class="service-stat">Blocked: <span id="ph-blocked">${PH_BLOCKED}</span> (<span id="ph-pct">${PH_PCT}</span>%)</span>
      </div>
    </div>

    <div class="service-tile ${WG_PILL_CLASS/pill-/}">
      <div class="service-left">
        <div class="service-icon">🔐</div>
        <div class="service-info">
          <div class="service-name">WireGuard</div>
          <div class="service-meta">
            Version: <span id="live-wireguard-ver">${WG_VER}</span>
          </div>
        </div>
      </div>
      <div class="service-right">
        <span class="pill ${WG_PILL_CLASS}">${WG_ACTIVE}</span>
        <span class="service-stat">${WG_PORT}</span>
        <span class="service-stat">Peers: <span id="wg-peers">${WG_PEERS}</span></span>
      </div>
    </div>

    <div class="service-tile ${KUMA_PILL_CLASS/pill-/}">
      <div class="service-left">
        <div class="service-icon">📈</div>
        <div class="service-info">
          <div class="service-name">Uptime Kuma</div>
          <div class="service-meta">
            Version: <span id="live-kuma-ver">${KUMA_VER}</span>
          </div>
        </div>
      </div>
      <div class="service-right">
        <span class="pill ${KUMA_PILL_CLASS}">${KUMA_ACTIVE}</span>
        <span class="service-stat">${KUMA_LISTEN}</span>
      </div>
    </div>

  </div>


  <p class="muted" style="margin-top:14px;">
    Render timer: <span class="pill ${RENDER_TIMER_PILL}">${RENDER_TIMER_ACTIVE}</span>
    • Update check timer: <span class="pill ${UPDATE_TIMER_PILL}">${UPDATE_TIMER_ACTIVE}</span>
  </p>
</div>


<div id="wireguard" class="card">
  <h2>WireGuard Clients</h2>

  <div style="display:flex; gap:8px; flex-wrap:wrap; margin-bottom:12px;">
    <input
      id="wg-client-name"
      type="text"
      placeholder="client name"
      style="flex:1; min-width:180px; border-radius:10px; border:1px solid var(--border); background:#0a0f1a; color:var(--text); padding:8px 12px;"
    >
    <button id="wg-create-btn" class="btn" type="button">Create Client</button>
  </div>

  <p class="muted" id="wg-create-status">No clients loaded yet.</p>

  <div id="wg-client-list" style="display:flex; flex-direction:column; gap:10px; margin-top:12px;"></div>

  <div id="wg-qr-panel" style="display:none; margin-top:16px;">
    <h3 style="margin-bottom:10px;">Client QR</h3>

    <div style="background:#fff; display:inline-block; padding:10px; border-radius:12px;">
      <img
        id="wg-qr-image"
        alt="WireGuard QR"
        style="display:block; max-width:260px; height:auto;"
      >
    </div>

    <p style="margin-top:10px;">
      <a id="wg-config-download" href="#" class="btn">Download Config</a>
    </p>
  </div>
</div>

 <div class="card">
     <h2>WireGuard CLI</h2> 
     <p>Default is <b>Full Tunnel</b>. Use these commands for manual configuration.</p>

     <h3>Add client</h3>
     <pre>sudo /opt/zwetow/bin/wg-add-client.sh phone</pre>

     <h3>Create Split Tunnel profile</h3>
     <pre>sudo /opt/zwetow/bin/wg-make-split.sh phone</pre>

     <h3>Create Full Tunnel profile</h3>
     <pre>sudo /opt/zwetow/bin/wg-make-full.sh phone</pre>

     <h3>Status</h3>
     <pre>sudo wg show</pre> 
 </div>

 <div id="links" class="card">
    <h2>Quick Links</h2>
    <p><a href="${ADMIN_URL}">Pi-hole Admin</a></p>
    <p><a href="${KUMA_URL}">Uptime Kuma</a></p>
    <p><a href="http://${IP}:9091/support">Download Support Bundle</a></p>
  </div>
</div>

<p class="muted" style="margin:18px 2px 0; font-size:12px;">
  Zwetow Appliance • Build ${BUILD} • Host ${HOST}
</p>
<p class="muted" id="live-last-update" style="margin:8px 2px 0; font-size:12px;">
  Live status refresh: waiting...
</p>
<script>

let lastRefreshTs = null;

function updateLastRefreshLabel() {
  const el = document.getElementById('live-last-update');
  if (!el || !lastRefreshTs) return;

  const diffSec = Math.max(0, Math.floor((Date.now() - lastRefreshTs) / 1000));
  el.textContent = 'Last refresh: ' + diffSec + 's ago';
}


async function refreshStatus() {
  try {
    const res = await fetch(
      'http://' + window.location.hostname + ':9091/status.json?_=' + Date.now(),
      { cache: 'no-store' }
    );

    if (!res.ok) {
      throw new Error('status fetch failed');
    }

    const data = await res.json();

    const setText = (id, value) => {
      const el = document.getElementById(id);
      if (el && value !== undefined && value !== null && value !== '') {
        el.textContent = value;
      }
    };

    setText('live-hostname', data.hostname);
    setText('live-ip', data.ip);
    setText('live-os', data.os);
    setText('live-kernel', data.kernel);
    setText('live-wireguard-ver', data.wireguard);

    if (data.pihole_core || data.pihole_web || data.pihole_ftl) {
      const piholeText = [data.pihole_core, data.pihole_web, data.pihole_ftl]
        .filter(Boolean)
        .join(' | ');
      setText('live-pihole', piholeText);
    }

	lastRefreshTs = Date.now();
	updateLastRefreshLabel();

  } catch (e) {
    console.error('refreshStatus failed:', e);
    const stamp = document.getElementById('live-last-update');
    if (stamp) {
      stamp.textContent = 'Last refresh failed: ' + new Date().toLocaleTimeString();
    }
  }
}

async function refreshMetrics() {
  try {
    const res = await fetch(
      'http://' + window.location.hostname + ':9091/metrics?_=' + Date.now(),
      { cache: 'no-store' }
    );

    if (!res.ok) {
      throw new Error('metrics fetch failed');
    }

    const m = await res.json();

    const setText = (id, value) => {
      const el = document.getElementById(id);
      if (el && value !== undefined && value !== null && value !== '') {
        el.textContent = value;
      }
    };

    const setWidth = (id, value) => {
      const el = document.getElementById(id);
      const num = Number(value);
      if (el && !Number.isNaN(num)) {
        const pct = Math.max(0, Math.min(100, num));
        el.style.width = pct + '%';
      }
    };

    setText('cpu-pct-text', m.cpu_percent);
    setText('mem-pct-text', m.memory_percent);
    setText('disk-pct-text', m.disk_percent);

    setWidth('cpu-bar', m.cpu_percent);
    setWidth('mem-bar', m.memory_percent);
    setWidth('disk-bar', m.disk_percent);

    setText('cpu-temp', m.cpu_temp_c);
    setText('wg-peers', m.wg_peer_count);
    setText('ph-queries', m.pihole_dns_queries_today);
    setText('ph-blocked', m.pihole_ads_blocked_today);
    setText('ph-pct', m.pihole_ads_percentage_today);
  } catch (e) {
    console.error('refreshMetrics failed:', e);
  }
}

refreshStatus();
refreshMetrics();

async function loadWireGuardClients() {
  try {
    const res = await fetch(
      'http://' + window.location.hostname + ':9091/wireguard/clients?_=' + Date.now(),
      { cache: 'no-store' }
    );

    if (!res.ok) {
      throw new Error('client list fetch failed');
    }

    const data = await res.json();
    const list = document.getElementById('wg-client-list');
    const status = document.getElementById('wg-create-status');

    if (!list) return;

    list.innerHTML = '';

    const clients = Array.isArray(data.clients) ? data.clients : [];

    if (status) {
      status.textContent = clients.length
        ? 'Loaded ' + clients.length + ' client' + (clients.length === 1 ? '' : 's') + '.'
        : 'No WireGuard clients yet.';
    }

    clients.forEach((name) => {
      const row = document.createElement('div');
      row.style.display = 'flex';
      row.style.alignItems = 'center';
      row.style.justifyContent = 'space-between';
      row.style.gap = '10px';
      row.style.flexWrap = 'wrap';
      row.style.padding = '12px 14px';
      row.style.border = '1px solid var(--border)';
      row.style.borderRadius = '12px';
      row.style.background = 'rgba(255,255,255,0.02)';

      const label = document.createElement('div');
      label.textContent = name;
      label.style.fontWeight = '700';

      const actions = document.createElement('div');
      actions.style.display = 'flex';
      actions.style.gap = '8px';
      actions.style.flexWrap = 'wrap';

      const qrBtn = document.createElement('button');
      qrBtn.type = 'button';
      qrBtn.className = 'btn';
      qrBtn.textContent = 'Show QR';
      qrBtn.onclick = () => showWireGuardQr(name);

      const dlLink = document.createElement('a');
      dlLink.className = 'btn btn-ghost';
      dlLink.textContent = 'Download Config';
      dlLink.href = 'http://' + window.location.hostname + ':9091/wireguard/client/' + encodeURIComponent(name) + '/config';

      actions.appendChild(qrBtn);
      actions.appendChild(dlLink);

      row.appendChild(label);
      row.appendChild(actions);
      list.appendChild(row);
    });
  } catch (e) {
    console.error('loadWireGuardClients failed:', e);
    const status = document.getElementById('wg-create-status');
    if (status) {
      status.textContent = 'Failed to load WireGuard clients.';
    }
  }
}

function showWireGuardQr(name) {
  const panel = document.getElementById('wg-qr-panel');
  const img = document.getElementById('wg-qr-image');
  const dl = document.getElementById('wg-config-download');

  if (!panel || !img || !dl) return;

  img.src = 'http://' + window.location.hostname + ':9091/wireguard/client/' + encodeURIComponent(name) + '/qr?_=' + Date.now();
  dl.href = 'http://' + window.location.hostname + ':9091/wireguard/client/' + encodeURIComponent(name) + '/config';
  dl.setAttribute('download', name + '.conf');
  panel.style.display = 'block';
}

async function createWireGuardClient() {
  const input = document.getElementById('wg-client-name');
  const status = document.getElementById('wg-create-status');
  if (!input) return;

  const name = input.value.trim();
  if (!name) {
    if (status) status.textContent = 'Enter a client name.';
    return;
  }

  try {
    const res = await fetch(
      'http://' + window.location.hostname + ':9091/wireguard/add-client?name=' + encodeURIComponent(name),
      { cache: 'no-store' }
    );

    const data = await res.json();

    if (!res.ok || data.error) {
      throw new Error(data.error || 'Failed to create client');
    }

    if (status) status.textContent = data.message || 'Client created.';
    input.value = '';
    await loadWireGuardClients();
    showWireGuardQr(name);
  } catch (e) {
    console.error('createWireGuardClient failed:', e);
    if (status) status.textContent = 'Failed to create client: ' + e.message;
  }
}

document.addEventListener('DOMContentLoaded', () => {
  const btn = document.getElementById('wg-create-btn');
  const input = document.getElementById('wg-client-name');

  if (btn) btn.addEventListener('click', createWireGuardClient);
  if (input) {
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') createWireGuardClient();
    });
  }

  loadWireGuardClients();
});

setInterval(refreshStatus, 15000);
setInterval(refreshMetrics, 60000);
setInterval(updateLastRefreshLabel, 1000);
</script>
</body>
</html>
EOF
