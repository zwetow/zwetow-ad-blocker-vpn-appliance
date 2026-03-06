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
UPDATE_AVAIL="$(cat /opt/zwetow/state/UPDATE_AVAILABLE 2>/dev/null || true)"
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

WG_VER="$(wg --version 2>/dev/null | awk '{print $2}' || echo 'not installed')"
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

KUMA_ACTIVE="$(systemctl is-active uptime-kuma 2>/dev/null || echo 'inactive')"
KUMA_PILL_CLASS="pill-bad"
if [[ "$KUMA_ACTIVE" == "active" ]]; then
  KUMA_PILL_CLASS="pill-ok"
fi
KUMA_LISTEN="3001 (not listening)"
if ss -ltnp 2>/dev/null | grep -qE ':(3001)\s'; then
  KUMA_LISTEN="3001 (listening)"
fi

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
  height: 100%;
  width: 0%;
  background: linear-gradient(90deg, var(--accent), var(--accent2));
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

.grid {
  display: grid;
  grid-template-columns: 1fr;
  gap: 14px;
}

@media (min-width: 860px) {
  .grid {
    grid-template-columns: 1fr 1fr;
    align-items: start;
  }
  .span-2 { grid-column: span 2; }
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
  height:30px;
  padding:0 10px;
  border-radius:10px;
  border:1px solid var(--border);
  background: rgba(31,41,55,0.35);
  color: var(--text);
  text-decoration:none;
  font-weight:700;
  font-size:12px;
}

.btn:hover{
  border-color: var(--borderHover);
  transform: translateY(-1px);
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
      <div class="subtitle">Local landing page + quick links + device info.</div>
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
<div class="grid">
  <div id="home" class="card span-2">
    <h2>Device Info</h2>
    <div><b>Hostname:</b> ${HOST}</div>
    <div><b>IP Address:</b> ${IP}</div>
    <div><b>LAN Subnet (eth0):</b> ${LAN_SUBNET}</div>
    <div><b>Uptime:</b> ${UPTIME}</div>
    <div><b>Time:</b> ${NOW}</div>
    <div><b>Public IP:</b> ${PUB_IP}</div>
    <div><b>Serial:</b> ${SERIAL}</div>
    <div><b>OS:</b> ${OS}</div>
    <div><b>Kernel:</b> ${KERNEL}</div>
    <div><b>Pi-hole:</b> ${PIHOLE_VERSION}</div>

    <h3>Services</h3>
    <div><b>Uptime Kuma:</b> <span class="pill ${KUMA_PILL_CLASS}">${KUMA_ACTIVE}</span> • ${KUMA_LISTEN}</div>
    <div> <b>Pi-hole:</b> <span class="pill ${PH_PILL_CLASS}">${PH_LABEL}</span> • ${PH_DNS_LISTEN} • <b>Queries today:</b> ${PH_Q} • <b>Blocked:</b> ${PH_BLOCKED} (${PH_PCT}%)</div>
    <div><b>WireGuard:</b> ${WG_VER} • <span class="pill ${WG_PILL_CLASS}">${WG_ACTIVE}</span> • ${WG_PORT}</div>
    <div><b>WireGuard peers:</b> ${WG_PEERS}</div>

    <h3>Health</h3>
    <div><b>Overall:</b> <span class="pill ${HEALTH_PILL_CLASS} ${HEALTH_PULSE}">${HEALTH_LABEL}</span></div>
    <div><b>Temp:</b> ${CPU_TEMP}°C</div>

    <div class="meter-row">
      <div class="meter-head"><span><b>CPU</b></span><span>${CPU_PCT}%</span></div>
      <div class="meter"><span style="width:${CPU_PCT}%"></span></div>
    </div>

    <div class="meter-row">
      <div class="meter-head"><span><b>Memory</b></span><span>${MEM_PCT}%</span></div>
      <div class="meter"><span style="width:${MEM_PCT}%"></span></div>
    </div>

    <div class="meter-row">
      <div class="meter-head"><span><b>Disk</b></span><span>${DISK_PCT}%</span></div>
      <div class="meter"><span style="width:${DISK_PCT}%"></span></div>
    </div>

    <p class="muted">Auto-updates on boot + every 5 minutes.</p>
  </div>

  <div id="links" class="card">
    <h2>Quick Links</h2>
    <p><a href="${ADMIN_URL}">Pi-hole Admin</a></p>
    <p><a href="${KUMA_URL}">Uptime Kuma</a></p>
    <p><a href="http://${IP}:9091/support">Download Support Bundle</a></p>
  </div>

  <div id="wireguard" class="card">
    <h2>WireGuard</h2>
    <p>Default is <b>Full Tunnel</b>. Use the commands below to create a split tunnel profile if you want.</p>

    <h3>Add a client (Full Tunnel default)</h3>
    <pre>sudo /opt/zwetow/bin/wg-add-client.sh phone</pre>

    <h3>Create Split Tunnel profile (LAN only)</h3>
    <pre>sudo /opt/zwetow/bin/wg-make-split.sh phone</pre>

    <h3>Create Full Tunnel profile</h3>
    <pre>sudo /opt/zwetow/bin/wg-make-full.sh phone</pre>

    <h3>Status</h3>
    <pre>sudo wg show</pre>
  </div>
</div>
<p class="muted" style="margin:18px 2px 0; font-size:12px;">
  Zwetow Appliance • Build ${BUILD} • Host ${HOST}
</p>
</body>
</html>
EOF
