# Zwetow Network Appliance – Project Instructions

This repository contains the UI and control logic for the **Zwetow Network Ad Blocker & VPN Appliance**.

The appliance is designed to behave like a **consumer network device**, not a traditional Linux server.  
Changes should prioritize **stability, readability, and minimal dependencies**.

---

# Architecture Overview

The appliance is composed of several components:

### UI Dashboard
Rendered HTML interface for the appliance control panel.

Primary generator:
bin/render-index.sh


This script builds the main dashboard page using system data.

The dashboard is designed to:
- be lightweight
- require **no frontend frameworks**
- work entirely with **vanilla HTML, CSS, and JavaScript**

---

### Appliance API Server


bin/support-download-server.py


Runs on:


http://<device-ip>:9091


Endpoints include:

| Endpoint | Purpose |
|--------|--------|
| `/status.json` | Appliance system status |
| `/metrics` | CPU / memory / disk / temp metrics |
| `/support` | Download support bundle |
| `/update` | Trigger appliance update |
| `/rollback` | Rollback appliance version |
| `/wireguard/*` | WireGuard management |

This API **must remain stable** because the UI depends on it.

---

### Status Generation


bin/update-status.sh


Produces JSON consumed by the dashboard.

Contains:

- device info
- service status
- version information
- health indicators

---

### WireGuard Management

WireGuard is managed through several scripts:


bin/wg-setup.sh
bin/wg-add-client.sh
bin/wg-make-full.sh
bin/wg-make-split.sh


Functions include:

- creating clients
- generating configs
- generating QR codes
- listing peers

The UI interacts with these through the API server.

Do **not break compatibility** with these scripts.

---

### Support Bundle System


bin/zwetow-support-bundle.sh


Used for troubleshooting.

Includes:

- logs
- system info
- service status
- configuration snapshots

The bundle is downloaded through the API server.

---

### Update System

Update logic:


bin/zwetow-update.sh
bin/zwetow-check-update.sh
bin/zwetow-rollback.sh
bin/zwetow-deploy-tag.sh


Timer services:


systemd/zwetow-check-update.timer
systemd/zwetow-check-update.service


The UI surfaces update availability.

Update flow must remain intact.

---

### First Boot


bin/firstboot.sh


Responsible for:

- initial appliance configuration
- system preparation

A **future setup wizard** will be layered on top of this.

---

# UI Behavior

The dashboard uses two polling loops.

### Status refresh
Updates device info and service versions.

Current target:


15 seconds


### Metrics refresh
Updates CPU, memory, disk, and temperature.

Current target:


5–10 seconds


These should remain lightweight.

---

# Design Principles

When modifying the codebase:

### 1. Keep it appliance-like
This is meant to behave like:

- a router
- firewall
- NAS device

Avoid server-style complexity.

---

### 2. Prefer simple technologies

Allowed:

- Bash
- Python
- HTML
- CSS
- Vanilla JavaScript

Avoid introducing:

- Node frameworks
- React
- Angular
- heavy build systems

---

### 3. Minimize dependencies

The appliance should run on a **clean Debian-based system**.

Avoid adding packages unless absolutely necessary.

---

### 4. Preserve existing functionality

Do **not break**:

- dashboard rendering
- live status refresh
- metrics updates
- WireGuard client creation
- QR code generation
- support bundle downloads
- update / rollback system
- API server endpoints

---

### 5. Keep code readable

Code must remain easy to edit **directly on the appliance**.

Avoid:

- over abstraction
- complex frameworks
- unnecessary layering

Prefer:

- clear scripts
- obvious logic
- minimal magic

---

# Repository Structure


ui-repo/
├── bin/
│ ├── render-index.sh
│ ├── update-status.sh
│ ├── wg-add-client.sh
│ ├── support-download-server.py
│ ├── zwetow-update.sh
│ └── ...
│
├── systemd/
│ ├── zwetow-check-update.service
│ ├── zwetow-check-update.timer
│ └── zwetow-support-download.service
│
└── www/
(future static UI assets)


---

# Cleanup Priorities

Codex or contributors should focus on:

### Code cleanup
- remove duplicate CSS
- remove unused JavaScript
- simplify render scripts
- reduce redundant HTML

### Maintainability
- improve script structure
- document important flows
- simplify API responses where safe

### UI polish
- maintain consistent layout
- keep dashboard lightweight
- preserve dark theme

---

# Things That Must Not Change Without Careful Planning

Critical behavior includes:

- port **9091 API server**
- `/status.json` schema
- WireGuard QR generation
- support bundle creation
- update / rollback mechanism

Changes here can break deployed appliances.

---

# Future Planned Features

Planned improvements include:

### Setup Wizard
Guided configuration for:

- hostname
- admin email
- timezone
- WireGuard setup
- Pi-hole configuration

---

### Improved Monitoring
Possible additions:

- service restart buttons
- DNS stats charts
- uptime graphs

---

### Appliance Updates
Future improvements:

- signed update packages
- update channels
- staged rollouts

---

# Contribution Expectations

When making changes:

1. preserve existing functionality
2. keep the UI lightweight
3. document important logic
4. avoid introducing unnecessary complexity
5. explain major architectural changes

---

# Summary

This repository powers a **network appliance product**.

The primary goals are:

- stability
- simplicity
- maintainability
- appliance-style usability

Treat this system like **embedded software**, not a traditional web application.
