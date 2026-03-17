# LettaCtrl GUI — Design Spec
**Date**: 2026-03-17
**Status**: Approved

---

## Overview

A single-page web dashboard for managing and monitoring the Letta cross-session memory stack. Served on `localhost` in desktop mode and via Tailscale in VPS mode. Installed and started by `titan-setup.sh`.

---

## Decisions

| Concern | Decision |
|---|---|
| Layout | Top nav + cards grid |
| Colour scheme | Zinc Neutral — `#18181b` bg, `#27272a` cards, `#fafafa` text, emerald status, purple accent |
| Stack | Vanilla JS single-file frontend + Bun HTTP backend server |
| Monitoring depth | Status dot + RAM/CPU + uptime + live log tail (last 20 lines, SSE stream) per service |
| Agent operations | Full CRUD: list, create, delete, edit memory blocks, send test message |
| Auth | None — Tailscale ACL is the boundary |

---

## Architecture

```
~/.config/letta/letta-ctrl-server.js   ← Bun HTTP server (single file)
~/.config/letta/letta-ctrl.html        ← Frontend (single file, vanilla JS)

titan-setup.sh installs both files, creates systemd user service:
  ~/.config/systemd/user/letta-ctrl.service
  Port: 8284 (LETTA_CTRL_PORT, configurable via --letta-ctrl-port)
```

### Request flow

```
Browser
  ├── GET /                   → serves letta-ctrl.html
  ├── GET /api/status         → polls systemd (systemctl show) for 4 services
  ├── GET /api/agents         → proxies GET http://127.0.0.1:8283/v1/agents
  ├── POST /api/agents        → proxies POST /v1/agents
  ├── DELETE /api/agents/:id  → proxies DELETE /v1/agents/:id
  ├── GET /api/agents/:id/blocks            → proxies GET /v1/agents/:id/core-memory/blocks
  ├── PATCH /api/agents/:id/blocks/:label  → proxies PATCH /v1/agents/:id/core-memory/blocks/:label
  ├── POST /api/agents/:id/messages    → proxies POST /v1/agents/:id/messages
  └── GET /api/logs/:service  → SSE stream of `journalctl --user -u <service> -f -n 20`
```

The backend reads `~/.config/letta/credentials` at startup for `LETTA_SERVER_PASSWORD`. No credentials are exposed to the frontend — all Letta API calls are proxied server-side.

---

## Files

| File | Purpose |
|---|---|
| `~/.config/letta/letta-ctrl-server.js` | Bun server: static serving + API proxy + SSE log streaming + systemd status |
| `~/.config/letta/letta-ctrl.html` | Single-page app: vanilla JS, no build step, inlined CSS |
| `~/.config/systemd/user/letta-ctrl.service` | Systemd user unit, `Restart=on-failure` |

No npm packages. No node_modules. Bun stdlib only (`Bun.serve`, `Bun.spawn`, `node:child_process`).

---

## UI Sections

### Top nav (always visible)
- Logo: `⬡ LettaCtrl`
- Tabs: Overview · Agents · Logs
- Right: 4 individual health pills (one per service), pulsing green dot when active, red when dead. Updates every 5s.

### Overview tab
**Service cards grid (4 columns)**
Each card:
- Coloured top border: emerald (active) / red (dead)
- Service name + port badge
- Metrics grid (2×2): RAM, CPU, Uptime, service-specific stat (health/model/accounts/fix)
  - Metric values: `20px bold` — numbers dominate visually
- Log tail: last 3–4 lines, colour-coded by recency and severity (old=dim, recent=medium, error=red bold)
- Actions: Restart + Stop (or Start if dead)

**Agents strip** — compact chips below service grid. Click navigates to Agents tab.

### Agents tab
Split layout: 240px agent list (left) + detail panel (right).

**Agent list**: name, model, block count. `+ New` button opens create modal.

**Detail panel tabs**:
- **Memory Blocks** — all blocks as editable `contenteditable` divs with token counter and Save button per block
- **Test Message** — text input + Send button, response rendered below
- **Info** — agent ID, model, endpoint, embedding config, import date

**Create modal**: name field + model selector (pre-filled with `anthropic/claude-sonnet-4-6`) + confirm button.

**Delete**: red button in detail header, confirmation prompt before DELETE call.

### Logs tab
Left: 4 service selector buttons. Right: live SSE log stream panel with filter input. `journalctl --user -u <service> -f -n 20` piped as SSE. Log lines colour-coded: `ok`=emerald, `info`=grey, `warn`=amber, `err`=red bold.

---

## titan-setup.sh Integration

### CLI flags
```
--letta-ctrl-skip         Skip LettaCtrl GUI install
--letta-ctrl-port PORT    Port (default: 8284)
```

### Phase 5b — after existing claude-subconscious plugin block
1. Write `letta-ctrl-server.js` to `~/.config/letta/`
2. Write `letta-ctrl.html` to `~/.config/letta/`
3. Create `~/.config/systemd/user/letta-ctrl.service`
4. `systemctl --user enable letta-ctrl && systemctl --user start letta-ctrl`
5. Health check: `curl -sf http://127.0.0.1:8284/`

### VPS mode — Tailscale serve
```bash
tailscale serve --bg --https="${LETTA_CTRL_PORT}" "http://localhost:${LETTA_CTRL_PORT}"
```

### Summary output
Add to post-install block:
```
LettaCtrl GUI : http://localhost:8284
             (VPS: https://<hostname>:8284 via Tailscale)
```

---

## Service Status API

`GET /api/status` returns JSON polled every 5s by the frontend:

```json
{
  "letta":          { "active": true,  "memory_mb": 412, "cpu_pct": 0.3, "uptime": "6h 14m" },
  "ollama":         { "active": true,  "memory_mb": 318, "cpu_pct": 0.1, "uptime": "6h 14m" },
  "better-ccflare": { "active": true,  "memory_mb": 89,  "cpu_pct": 0.0, "uptime": "6h 14m" },
  "ccflare-docker-proxy": { "active": true, "memory_mb": 11, "cpu_pct": 0.0, "uptime": "6h 12m" }
}
```

Data source:
- `letta`, `better-ccflare`, `ccflare-docker-proxy`: `systemctl --user show <unit> --property=ActiveState,MemoryCurrent,CPUUsageNSec,ActiveEnterTimestamp`
- `ollama`: `systemctl show ollama --property=...` (system-level service, installed by Ollama's own installer — no `--user`)

---

## Colour Tokens (Zinc Neutral)

| Token | Value | Usage |
|---|---|---|
| `--bg` | `#18181b` | Page background |
| `--surface` | `#27272a` | Cards, panels |
| `--border` | `#3f3f46` | Card borders |
| `--text` | `#fafafa` | Primary text |
| `--muted` | `#71717a` | Labels, secondary |
| `--accent` | `#a78bfa` | Metric numbers, badges |
| `--green` | `#34d399` | Active status, OK |
| `--red` | `#f87171` | Dead status, errors |
| `--amber` | `#fbbf24` | Warnings |
| `--purple` | `#8b5cf6` | Logo, nav active, save buttons |

---

## Out of Scope

- Authentication (Tailscale ACL is the boundary)
- Multi-user / multi-Letta-instance
- Letta conversation history viewer
- betterccflare account management (separate tool)
- Mobile layout optimisation
