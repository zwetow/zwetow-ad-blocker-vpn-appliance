#!/usr/bin/env bash
set -euo pipefail

PUBLIC_OUT="/var/www/html/index.html"
PROTECTED_OUT="/var/www/html/zwetow/dashboard.html"

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
FORCE_SETUP_FILE="/opt/zwetow/state/force_setup"
SETUP_COMPLETE_FILE="/opt/zwetow/state/setup_complete"
WIZARD_TEST_MODE="false"
if [[ -f "$FORCE_SETUP_FILE" ]]; then
  WIZARD_TEST_MODE="true"
fi

if [[ -f "$FORCE_SETUP_FILE" || ! -f "$SETUP_COMPLETE_FILE" ]]; then
cat > "$PUBLIC_OUT" <<'EOF'
<!doctype html>
<html>
<head>
  <link rel="icon" href="data:,">
  <meta charset="utf-8">
  <title>Zwetow Appliance Setup</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    :root {
      --bg: #0b0f14;
      --panel: #0f172a;
      --panel2: #0b1220;
      --border: #243244;
      --text: #e6edf3;
      --muted: #9aa6b2;
      --accent: #f97316;
      --ok: #22c55e;
      --bad: #ef4444;
    }
    body {
      font-family: Arial, sans-serif;
      max-width: 860px;
      margin: 28px auto;
      padding: 0 16px;
      background: radial-gradient(1200px 600px at 20% 0%, rgba(125,211,252,0.08), transparent 55%),
                  radial-gradient(900px 500px at 90% 10%, rgba(239,68,68,0.06), transparent 55%),
                  var(--bg);
      color: var(--text);
    }
    .card {
      border: 1px solid var(--border);
      border-radius: 16px;
      background: linear-gradient(145deg, var(--panel), var(--panel2));
      box-shadow: 0 10px 28px rgba(0,0,0,0.35);
      padding: 18px;
    }
    h1 { margin: 0 0 6px 0; }
    .muted { color: var(--muted); }
    .steps {
      display: grid;
      grid-template-columns: repeat(9, 1fr);
      gap: 8px;
      margin: 14px 0 18px;
    }
    .step {
      text-align: center;
      font-size: 11px;
      border: 1px solid var(--border);
      border-radius: 999px;
      padding: 7px 4px;
      color: var(--muted);
      background: rgba(255,255,255,0.02);
    }
    .step.active {
      color: #fff;
      border-color: rgba(249,115,22,0.65);
      background: rgba(249,115,22,0.18);
    }
    .panel { display: none; }
    .panel.active { display: block; }
    label {
      display: block;
      font-weight: 700;
      margin: 12px 0 6px;
    }
    input, select {
      width: 100%;
      box-sizing: border-box;
      border: 1px solid var(--border);
      border-radius: 10px;
      background: #0a0f1a;
      color: var(--text);
      padding: 10px 12px;
      font: inherit;
    }
    .radios {
      display: flex;
      gap: 16px;
      margin-top: 8px;
    }
    .radios label {
      margin: 0;
      font-weight: 600;
      display: inline-flex;
      align-items: center;
      gap: 6px;
    }
    .actions {
      display: flex;
      justify-content: space-between;
      gap: 8px;
      margin-top: 18px;
    }
    .btn {
      border: 1px solid rgba(249,115,22,0.55);
      border-radius: 10px;
      background: linear-gradient(180deg, rgba(249,115,22,0.22), rgba(249,115,22,0.12));
      color: var(--text);
      padding: 9px 14px;
      font-weight: 700;
      cursor: pointer;
    }
    .btn:hover { border-color: rgba(249,115,22,0.85); }
    .btn-ghost {
      border: 1px solid var(--border);
      background: transparent;
    }
    .msg {
      margin-top: 12px;
      font-size: 13px;
      color: var(--muted);
      min-height: 18px;
      white-space: pre-line;
    }
    .msg.ok { color: var(--ok); }
    .msg.bad { color: var(--bad); }
    .update-box {
      border: 1px solid var(--border);
      border-radius: 12px;
      background: rgba(255,255,255,0.02);
      padding: 12px;
      margin-top: 8px;
    }
    .update-actions {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
      margin-top: 12px;
    }
    .inline-panel {
      margin-top: 12px;
      border: 1px solid var(--border);
      border-radius: 12px;
      background: rgba(255,255,255,0.02);
      padding: 12px;
    }
    .inline-panel h3 {
      margin: 0 0 8px 0;
      font-size: 15px;
    }
    .inline-actions {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
      margin-top: 10px;
    }
    .msg.warn { color: #f59e0b; }
    .warning-list {
      margin-top: 10px;
      padding: 10px 12px;
      border: 1px solid rgba(245,158,11,0.35);
      border-radius: 12px;
      background: rgba(69,26,3,0.20);
      color: #fcd34d;
      white-space: pre-line;
    }
    @media (max-width: 860px) {
      .steps { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <div class="card">
    <h1>Welcome to Zwetow Setup</h1>
    <p class="muted">Complete this one-time wizard to configure your appliance.</p>

    <div class="steps">
      <div class="step active">Welcome</div>
      <div class="step">Updates</div>
      <div class="step">Hostname</div>
      <div class="step">Timezone</div>
      <div class="step">Email</div>
      <div class="step">Admin Access</div>
      <div class="step">WireGuard</div>
      <div class="step">First Client</div>
      <div class="step">Finish</div>
    </div>

    <div class="panel active">
      <h2>Welcome</h2>
      <p>This wizard configures hostname, timezone, support email, appliance admin access, and WireGuard basics.</p>
    </div>

    <div class="panel">
      <h2>Appliance Updates</h2>
      <p class="muted">Check and optionally apply updates before continuing setup.</p>
      <div class="update-box">
        <div><b>Current version:</b> <span id="setup-current-version">unknown</span></div>
        <div><b>Latest version:</b> <span id="setup-latest-version">unknown</span></div>
        <div><b>Status:</b> <span id="setup-update-status">Not checked</span></div>
      </div>
      <div class="update-actions">
        <button id="setup-update-now" class="btn" type="button">Update Now</button>
        <button id="setup-update-skip" class="btn btn-ghost" type="button">Skip</button>
      </div>
      <p class="muted">If an update fails, you can continue setup.</p>
    </div>

    <div class="panel">
      <h2>Device Hostname</h2>
      <label for="hostname">Hostname</label>
      <input id="hostname" type="text" placeholder="zwetow-appliance">
      <p class="muted">Letters, numbers, and dashes only.</p>
    </div>

    <div class="panel">
      <h2>Timezone</h2>
      <label for="timezone">Timezone</label>
      <input id="timezone" type="text" placeholder="America/Chicago">
    </div>

    <div class="panel">
      <h2>Admin / Support Email</h2>
      <label for="admin_email">Email</label>
      <input id="admin_email" type="email" placeholder="admin@example.com">
    </div>

    <div class="panel">
      <h2>Admin Access</h2>
      <label for="admin_username">Admin Username</label>
      <input id="admin_username" type="text" placeholder="admin" autocomplete="username">

      <label for="admin_password">Admin Password</label>
      <input id="admin_password" type="password" placeholder="At least 10 characters" autocomplete="new-password">

      <label for="admin_password_confirm">Confirm Password</label>
      <input id="admin_password_confirm" type="password" placeholder="Repeat password" autocomplete="new-password">

      <p class="muted">These credentials seed the appliance admin login plus native AdGuard and Uptime Kuma admin access.</p>
    </div>

    <div class="panel">
      <h2>Enable WireGuard</h2>
      <div class="radios">
        <label><input type="radio" name="wg_enabled" value="yes"> Yes</label>
        <label><input type="radio" name="wg_enabled" value="no" checked> No</label>
      </div>
    </div>

    <div class="panel">
      <h2>Create First WireGuard Client (Optional)</h2>
      <label for="first_client">Client Name</label>
      <input id="first_client" type="text" placeholder="phone">
      <p class="muted">Only used if WireGuard is enabled.</p>
    </div>

    <div class="panel">
      <h2>Finish</h2>
      <p>Click <b>Complete Setup</b> to save configuration and mark setup complete.</p>
      <pre id="summary" style="background:#0a0f1a;border:1px solid var(--border);border-radius:12px;padding:12px;"></pre>
      <div id="wg-conflict-panel" class="inline-panel" style="display:none;">
        <h3>WireGuard Client Conflict</h3>
        <p class="muted">
          A first client name is set, but WireGuard is currently disabled.
          Choose how to continue.
        </p>
        <div class="inline-actions">
          <button id="wg-conflict-enable" class="btn" type="button">Enable WireGuard and create client</button>
          <button id="wg-conflict-skip" class="btn btn-ghost" type="button">Continue without client</button>
          <button id="wg-conflict-cancel" class="btn btn-ghost" type="button">Cancel and go back</button>
        </div>
      </div>
      <div id="setup-success-panel" class="inline-panel" style="display:none;">
        <h3>Setup Completed</h3>
        <p id="setup-success-text">Setup completed successfully.</p>
        <div id="setup-warning-list" class="warning-list" style="display:none;"></div>
        <p class="muted">
          Testing mode is still enabled (`force_setup`), so this wizard will continue to appear
          until that file is removed.
        </p>
        <div class="inline-actions">
          <button id="setup-success-reload" class="btn" type="button">Reload Wizard</button>
          <button id="setup-success-instructions-btn" class="btn btn-ghost" type="button">Show Dashboard Instructions</button>
        </div>
        <div id="setup-success-instructions" class="muted" style="display:none; margin-top:10px; white-space:pre-line;">
Remove testing mode on the appliance:
sudo rm -f /opt/zwetow/state/force_setup

Re-render dashboard page:
sudo /opt/zwetow/bin/render-index.sh

Then refresh this browser tab.
        </div>
      </div>
    </div>

    <div class="actions">
      <button id="saveBtn" class="btn btn-ghost" type="button">Save Progress</button>
      <div style="display:flex;gap:8px;">
        <button id="prevBtn" class="btn btn-ghost" type="button">Back</button>
        <button id="nextBtn" class="btn" type="button">Next</button>
      </div>
    </div>

    <div id="msg" class="msg"></div>
  </div>

  <script>
    const WIZARD_TEST_MODE = __WIZARD_TEST_MODE__;
    const panels = Array.from(document.querySelectorAll('.panel'));
    const steps = Array.from(document.querySelectorAll('.step'));
    const msg = document.getElementById('msg');
    const saveBtn = document.getElementById('saveBtn');
    const prevBtn = document.getElementById('prevBtn');
    const nextBtn = document.getElementById('nextBtn');
    const summaryEl = document.getElementById('summary');
    const updateNowBtn = document.getElementById('setup-update-now');
    const updateSkipBtn = document.getElementById('setup-update-skip');
    const currentVerEl = document.getElementById('setup-current-version');
    const latestVerEl = document.getElementById('setup-latest-version');
    const updateStateEl = document.getElementById('setup-update-status');
    const wgConflictPanel = document.getElementById('wg-conflict-panel');
    const wgConflictEnableBtn = document.getElementById('wg-conflict-enable');
    const wgConflictSkipBtn = document.getElementById('wg-conflict-skip');
    const wgConflictCancelBtn = document.getElementById('wg-conflict-cancel');
    const successPanel = document.getElementById('setup-success-panel');
    const successText = document.getElementById('setup-success-text');
    const successReloadBtn = document.getElementById('setup-success-reload');
    const successInstructionsBtn = document.getElementById('setup-success-instructions-btn');
    const successInstructions = document.getElementById('setup-success-instructions');
    const successWarningList = document.getElementById('setup-warning-list');

    let stepIndex = 0;
    const WIREGUARD_STEP_INDEX = 6;

    function apiBase() {
      return 'http://' + window.location.hostname + ':9091';
    }

    function getConfig() {
      const wgYes = document.querySelector('input[name="wg_enabled"][value="yes"]');
      return {
        hostname: (document.getElementById('hostname').value || '').trim(),
        timezone: (document.getElementById('timezone').value || '').trim(),
        admin_email: (document.getElementById('admin_email').value || '').trim(),
        admin_username: (document.getElementById('admin_username').value || '').trim(),
        admin_password: document.getElementById('admin_password').value || '',
        admin_password_confirm: document.getElementById('admin_password_confirm').value || '',
        wireguard_enabled: !!(wgYes && wgYes.checked),
        first_client: (document.getElementById('first_client').value || '').trim()
      };
    }

    function setMessage(text, cls) {
      msg.textContent = text || '';
      msg.className = 'msg' + (cls ? ' ' + cls : '');
    }

    function setWireguardEnabled(enabled) {
      const yes = document.querySelector('input[name="wg_enabled"][value="yes"]');
      const no = document.querySelector('input[name="wg_enabled"][value="no"]');
      if (!yes || !no) return;
      yes.checked = !!enabled;
      no.checked = !enabled;
    }

    function hideWireGuardConflictPanel() {
      if (wgConflictPanel) wgConflictPanel.style.display = 'none';
    }

    function showWireGuardConflictPanel() {
      if (wgConflictPanel) wgConflictPanel.style.display = 'block';
    }

    function showCompletionSuccessPanel() {
      if (successPanel) successPanel.style.display = 'block';
      if (nextBtn) nextBtn.disabled = true;
      if (saveBtn) saveBtn.disabled = true;
    }

    function renderCompletionWarnings(warnings) {
      if (!successWarningList) return;
      if (!Array.isArray(warnings) || !warnings.length) {
        successWarningList.style.display = 'none';
        successWarningList.textContent = '';
        return;
      }
      successWarningList.style.display = 'block';
      successWarningList.textContent = 'Warnings:\n- ' + warnings.join('\n- ');
    }

    function updateSummary() {
      if (!summaryEl) return;
      const c = getConfig();
      summaryEl.textContent = JSON.stringify({
        hostname: c.hostname,
        timezone: c.timezone,
        admin_email: c.admin_email,
        admin_username: c.admin_username,
        wireguard_enabled: c.wireguard_enabled,
        first_client: c.first_client
      }, null, 2);
    }

    function validateAdminAccess(config) {
      if (!config.admin_username) {
        throw new Error('Enter an admin username.');
      }
      if (config.admin_password.length < 10) {
        throw new Error('Admin password must be at least 10 characters.');
      }
      if (config.admin_password !== config.admin_password_confirm) {
        throw new Error('Admin password confirmation does not match.');
      }
    }

    function renderUpdateMeta(meta) {
      if (!meta) return;
      if (currentVerEl) currentVerEl.textContent = meta.current_version || 'unknown';
      if (latestVerEl) latestVerEl.textContent = meta.latest_version || 'unknown';
      if (updateStateEl) {
        updateStateEl.textContent = meta.update_available
          ? 'Update available'
          : 'No update flagged';
      }
    }

    function renderStep() {
      panels.forEach((panel, idx) => panel.classList.toggle('active', idx === stepIndex));
      steps.forEach((step, idx) => step.classList.toggle('active', idx === stepIndex));
      prevBtn.disabled = stepIndex === 0;
      nextBtn.textContent = stepIndex === panels.length - 1 ? 'Complete Setup' : 'Next';
      if (stepIndex === panels.length - 1) updateSummary();
    }

    async function loadExistingConfig() {
      try {
        const res = await fetch(apiBase() + '/setup/config?_=' + Date.now(), { cache: 'no-store' });
        if (!res.ok) throw new Error('Failed to load setup config');
        const data = await res.json();
        const cfg = data && data.config ? data.config : {};
        renderUpdateMeta(data && data.update ? data.update : null);

        if (cfg.hostname) document.getElementById('hostname').value = cfg.hostname;
        if (cfg.timezone) document.getElementById('timezone').value = cfg.timezone;
        if (cfg.admin_email) document.getElementById('admin_email').value = cfg.admin_email;
        if (cfg.admin_username) document.getElementById('admin_username').value = cfg.admin_username;
        if (cfg.first_client) document.getElementById('first_client').value = cfg.first_client;
        if (cfg.wireguard_enabled) {
          const yes = document.querySelector('input[name="wg_enabled"][value="yes"]');
          const no = document.querySelector('input[name="wg_enabled"][value="no"]');
          if (yes) yes.checked = true;
          if (no) no.checked = false;
        }
      } catch (err) {
        setMessage('Could not load previous setup values: ' + err.message, 'bad');
      }
      updateSummary();
    }

    async function runWizardUpdateNow() {
      if (updateStateEl) updateStateEl.textContent = 'Updating...';
      const res = await fetch(apiBase() + '/setup/update-now', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
      });
      const data = await res.json();
      renderUpdateMeta(data && data.update ? data.update : null);
      if (!res.ok || !data.ok) {
        setMessage('Update failed. You can continue setup.\n' + (data.detail || 'No detail.'), 'bad');
        if (updateStateEl) updateStateEl.textContent = 'Update failed';
        return;
      }
      setMessage('Update completed successfully.', 'ok');
      if (updateStateEl) updateStateEl.textContent = 'Update complete';
    }

    async function saveProgress() {
      const payload = getConfig();
      const res = await fetch(apiBase() + '/setup/save', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || 'Save failed');
      setMessage('Progress saved.', 'ok');
      updateSummary();
    }

    async function completeSetup() {
      const payload = getConfig();
      let res;
      let data;
      try {
        res = await fetch(apiBase() + '/setup/complete', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });
      } catch (err) {
        throw new Error('Network error while completing setup: ' + err.message);
      }
      try {
        data = await res.json();
      } catch (err) {
        throw new Error('Setup API returned an invalid response.');
      }
      if (!res.ok) {
        throw new Error(data.error || 'Setup completion failed');
      }
      if (!data || data.ok !== true) {
        throw new Error(data && data.error ? data.error : 'Setup completion was not confirmed');
      }

      const warnings = Array.isArray(data.warnings) ? data.warnings : [];
      if (successText) {
        successText.textContent = warnings.length
          ? 'Setup completed successfully with warnings.'
          : 'Setup completed successfully.';
      }
      renderCompletionWarnings(warnings);
      if (warnings.length) {
        setMessage('Setup completed with warnings. Review the notes below.', 'warn');
      } else {
        setMessage('Setup completed successfully.', 'ok');
      }
      if (WIZARD_TEST_MODE) {
        showCompletionSuccessPanel();
      } else {
        setTimeout(() => {
          window.location.href = '/';
        }, 700);
      }
    }

    saveBtn.addEventListener('click', async () => {
      try {
        await saveProgress();
      } catch (err) {
        setMessage(err.message, 'bad');
      }
    });

    prevBtn.addEventListener('click', () => {
      if (stepIndex > 0) {
        stepIndex -= 1;
        renderStep();
      }
    });

    nextBtn.addEventListener('click', async () => {
      if (stepIndex < panels.length - 1) {
        hideWireGuardConflictPanel();
        stepIndex += 1;
        renderStep();
        return;
      }
      const cfg = getConfig();
      try {
        validateAdminAccess(cfg);
      } catch (err) {
        setMessage(err.message, 'bad');
        return;
      }
      if (cfg.first_client && !cfg.wireguard_enabled) {
        showWireGuardConflictPanel();
        setMessage('Resolve the WireGuard client conflict before finishing.', 'bad');
        return;
      }
      try {
        hideWireGuardConflictPanel();
        await completeSetup();
      } catch (err) {
        setMessage(err.message, 'bad');
      }
    });

    if (updateNowBtn) {
      updateNowBtn.addEventListener('click', async () => {
        try {
          await runWizardUpdateNow();
        } catch (err) {
          setMessage('Update failed. You can continue setup: ' + err.message, 'bad');
          if (updateStateEl) updateStateEl.textContent = 'Update failed';
        }
      });
    }

    if (updateSkipBtn) {
      updateSkipBtn.addEventListener('click', () => {
        if (stepIndex < panels.length - 1) {
          hideWireGuardConflictPanel();
          stepIndex += 1;
          renderStep();
        }
      });
    }

    if (wgConflictEnableBtn) {
      wgConflictEnableBtn.addEventListener('click', async () => {
        setWireguardEnabled(true);
        hideWireGuardConflictPanel();
        setMessage('WireGuard enabled for setup completion.', 'ok');
        try {
          await completeSetup();
        } catch (err) {
          setMessage(err.message, 'bad');
        }
      });
    }

    if (wgConflictSkipBtn) {
      wgConflictSkipBtn.addEventListener('click', async () => {
        const firstClient = document.getElementById('first_client');
        if (firstClient) firstClient.value = '';
        hideWireGuardConflictPanel();
        setMessage('Continuing without creating a first client.', 'ok');
        try {
          await completeSetup();
        } catch (err) {
          setMessage(err.message, 'bad');
        }
      });
    }

    if (wgConflictCancelBtn) {
      wgConflictCancelBtn.addEventListener('click', () => {
        hideWireGuardConflictPanel();
        stepIndex = WIREGUARD_STEP_INDEX;
        renderStep();
      });
    }

    if (successReloadBtn) {
      successReloadBtn.addEventListener('click', () => window.location.reload());
    }

    if (successInstructionsBtn) {
      successInstructionsBtn.addEventListener('click', () => {
        if (!successInstructions) return;
        const isHidden = successInstructions.style.display === 'none';
        successInstructions.style.display = isHidden ? 'block' : 'none';
        successInstructionsBtn.textContent = isHidden ? 'Hide Dashboard Instructions' : 'Show Dashboard Instructions';
      });
    }

    loadExistingConfig();
    renderStep();
  </script>
</body>
</html>
EOF
sed -i "s/__WIZARD_TEST_MODE__/${WIZARD_TEST_MODE}/g" "$PUBLIC_OUT"
exit 0
fi

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

if [[ "$PH_STATUS" == "enabled" || "$PH_STATUS" == "OK" ]]; then
  PH_LABEL="active"
elif [[ "$PH_STATUS" == "disabled" || "$PH_STATUS" == "BAD" ]]; then
  PH_LABEL="inactive"
fi

PH_PILL_CLASS="pill-bad"
if [[ "$PH_STATUS" == "enabled" || "$PH_STATUS" == "OK" ]]; then
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


mkdir -p "$(dirname "$PROTECTED_OUT")"

cat > "$PROTECTED_OUT" <<EOF
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
    <a class="btn" href="/update">Update</a>
    <a class="btn btn-ghost" href="/rollback">Rollback</a>
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
    <p><a href="/apps/adguard/">AdGuard / DNS Admin</a></p>
    <p><a href="/apps/kuma/">Uptime Kuma</a></p>
    <p><a href="/admin/">Pi-hole</a></p>
    <p><a href="/support">Download Support Bundle</a></p>
    <p><a href="/logout">Log Out</a></p>
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
      '/status.json?_=' + Date.now(),
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
      '/metrics?_=' + Date.now(),
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
      '/wireguard/clients?_=' + Date.now(),
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
      dlLink.href = '/wireguard/client/' + encodeURIComponent(name) + '/config';

      const deleteBtn = document.createElement('button');
      deleteBtn.type = 'button';
      deleteBtn.className = 'btn btn-ghost';
      deleteBtn.textContent = 'Delete';
      deleteBtn.onclick = () => deleteWireGuardClient(name);

      actions.appendChild(qrBtn);
      actions.appendChild(dlLink);
      actions.appendChild(deleteBtn);

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

  img.src = '/wireguard/client/' + encodeURIComponent(name) + '/qr?_=' + Date.now();
  dl.href = '/wireguard/client/' + encodeURIComponent(name) + '/config';
  dl.setAttribute('download', name + '.conf');
  panel.style.display = 'block';
}

async function deleteWireGuardClient(name) {
  const status = document.getElementById('wg-create-status');
  const panel = document.getElementById('wg-qr-panel');
  const img = document.getElementById('wg-qr-image');
  const dl = document.getElementById('wg-config-download');

  if (!name) return;
  if (!confirm('Delete WireGuard client "' + name + '" from this appliance?')) {
    return;
  }

  try {
    if (status) status.textContent = 'Deleting client ' + name + '...';

    const res = await fetch('/wireguard/delete-client', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: name })
    });
    const data = await res.json();

    if (!res.ok || data.error) {
      throw new Error(data.error || 'Failed to delete client');
    }

    if (panel && panel.style.display !== 'none' && dl && dl.getAttribute('download') === name + '.conf') {
      panel.style.display = 'none';
      if (img) img.removeAttribute('src');
      dl.removeAttribute('href');
      dl.removeAttribute('download');
    }

    if (status) status.textContent = data.message || ('Client deleted: ' + name);
    await loadWireGuardClients();
  } catch (e) {
    console.error('deleteWireGuardClient failed:', e);
    if (status) status.textContent = 'Failed to delete client: ' + e.message;
  }
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
      '/wireguard/add-client?name=' + encodeURIComponent(name),
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

cat > "$PUBLIC_OUT" <<EOF
<!doctype html>
<html>
<head>
  <link rel="icon" href="data:,">
  <meta charset="utf-8">
  <title>Zwetow Appliance</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="refresh" content="0; url=http://${IP}:9091/">
  <style>
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      background: #0b0f14;
      color: #e6edf3;
      font-family: Arial, sans-serif;
      padding: 20px;
    }
    .card {
      max-width: 480px;
      border: 1px solid #243244;
      border-radius: 18px;
      background: linear-gradient(145deg, #0f172a, #0b1220);
      box-shadow: 0 10px 28px rgba(0,0,0,0.35);
      padding: 22px;
    }
    a { color: #7dd3fc; }
  </style>
</head>
<body>
  <div class="card">
    <h1 style="margin-top:0;">Zwetow Appliance</h1>
    <p>The dashboard is now protected by the central appliance login.</p>
    <p><a href="http://${IP}:9091/">Continue to login</a></p>
  </div>
</body>
</html>
EOF
