# Session Handoff — Titan Setup

**Date:** 2026-03-17
**Branch:** `main` (feat/tool-audit merged)
**Repo:** github.com/SutanuNandigrami/titan-setup
**Script:** `/opt/projects/proj-01/titan-setup.sh` (~3200 lines)

---

## What Was Done This Session

### 1. LettaCtrl GUI — COMPLETE ✅

Built a single-page web dashboard for managing the Letta cross-session memory stack.

**Embedded as heredocs in `titan-setup.sh` (Phase 5b install block):**

**`~/.config/letta/letta-ctrl-server.js`** — Bun HTTP server (197 lines)
- Routes: `GET /`, `/api/status`, `/api/agents` (CRUD), `/api/agents/:id/blocks` (GET/PATCH), `/api/agents/:id/messages`, `/api/logs/:service` (SSE), `/api/svc/:name/:action`
- Reads Letta password from `~/.config/letta/credentials` (LETTA_SERVER_PASSWORD= line)
- Security: service name validated against SERVICES whitelist (prevents arbitrary systemctl); proxy errors return generic message
- `ollama` uses system-level systemctl (no `--user`); other 3 services use `--user`

**`~/.config/letta/letta-ctrl.html`** — Vanilla JS SPA (605 lines)
- Zinc Neutral theme: `#18181b` bg, `#27272a` cards, `#fafafa` text, `#34d399` green, `#a78bfa` accent, `#8b5cf6` purple
- 3 tabs: **Overview** (4-column service cards + metrics grid + log tail + agents strip), **Agents** (240px list + detail panel with Memory Blocks/Test Message/Info sub-tabs), **Logs** (SSE stream + filter)
- XSS fixes: `escHtml()` on agent IDs in onclick attrs; `rawLbl`/`jsLbl` pattern for block labels (raw for DOM IDs, `replace(/'/g,"\\'"`) for JS string attrs, `escHtml` for display text)
- Agent CRUD: create modal (name + model pre-filled `anthropic/claude-sonnet-4-6`), contenteditable memory blocks with PATCH save, test message, delete with confirm

**`~/.config/systemd/user/letta-ctrl.service`** — port 8284, `Restart=on-failure`, `After=letta.service`

**`titan-setup.sh` additions:**
- Variables: `LETTA_CTRL_SKIP=false`, `LETTA_CTRL_PORT=8284` (after `OLLAMA_SKIP`)
- CLI flags: `--letta-ctrl-skip`, `--letta-ctrl-port PORT`
- VPS reexec forwarding for both vars
- Phase 5b install block after claude-subconscious: writes both files + service + `systemctl --user enable/restart` + 12s health check loop
- Tailscale serve: `tailscale serve --bg --https="${LETTA_CTRL_PORT}"` (guarded by `!LETTA_CTRL_SKIP && !LETTA_SKIP`)
- Summary output: VPS `https://<hostname>:8284` and desktop `http://localhost:8284`

**Design docs:**
- Spec: `docs/superpowers/specs/2026-03-17-letta-ctrl-gui-design.md`
- Plan: `docs/superpowers/plans/2026-03-17-letta-ctrl-gui.md`

### 2. Tool Audit — COMPLETE ✅

Three-pass audit removing duplicate/dead-weight CLI tools. Fixed skill install paths broken by shell variable expansion. Synced README and USER_GUIDE.

### 3. Security Skills — COMPLETE ✅

4 new security skills added to `dot-claude/`.

---

## Current Service Status (dev machine)

| Service | Status | Port |
|---------|--------|------|
| letta | active | 8283 |
| better-ccflare | active | 8080 |
| ollama | active | 11434 (nomic-embed-text pulled) |
| letta-ctrl | **not installed** | 8284 (only in titan-setup.sh) |

`letta-ctrl` is not running on this dev machine — files exist at `~/.config/letta/` from standalone testing, but systemd unit was never created here. It works on machines that run `titan-setup.sh`.

---

## Immediate Next Steps

1. **Install letta-ctrl on dev machine** (optional, quick test):
   ```bash
   BUN_BIN=$(which bun)
   mkdir -p ~/.config/systemd/user
   cat > ~/.config/systemd/user/letta-ctrl.service <<EOF
   [Unit]
   Description=LettaCtrl — Letta management GUI
   After=letta.service

   [Service]
   Type=simple
   ExecStart=${BUN_BIN} run %h/.config/letta/letta-ctrl-server.js
   Environment="LETTA_CTRL_PORT=8284"
   Environment="LETTA_BASE_URL=http://127.0.0.1:8283"
   Restart=on-failure
   RestartSec=5

   [Install]
   WantedBy=default.target
   EOF
   systemctl --user daemon-reload && systemctl --user enable --now letta-ctrl
   curl -sf http://localhost:8284/api/status | jq keys
   # open http://localhost:8284
   ```

2. **Version bump** — titan-setup.sh is effectively v3.16 (LettaCtrl + security skills + tool audit). Update `TITAN_VERSION` variable if it exists.

3. **Check open PRs**: `gh pr list`

---

## Key Decisions Made This Session

| Decision | Rationale |
|----------|-----------|
| Zinc Neutral colour scheme | Chosen over Slate Dark / Indigo Charcoal — best readability |
| No auth on letta-ctrl | Tailscale ACL is the security boundary (by spec) |
| Bun stdlib only | No npm/node_modules — zero install friction |
| Port 8284 | 8283=letta, 8080=ccflare, 8081=socat proxy, 11434=ollama |
| ollama = system-level systemctl | Ollama installer creates `/etc/systemd/system/` unit, not user unit |
| Letta API path `/core-memory/blocks` | NOT `/memory/blocks` — corrected during spec review |
| rawLbl/jsLbl pattern for block labels | Avoids ID mismatch: DOM IDs need raw value, JS string attrs need quote-escaped value |
| Service whitelist in /api/svc | Prevents `systemctl restart ssh` or similar abuse |

---

## Untracked Files (do not commit)

- `.superpowers/brainstorm/204181-1773741818/.server-stopped` — brainstorm server artifact
- `agent-team-reset.sh` — local utility, not part of repo

---

## Git Log (last 8 commits on main)

```
513e552 chore: add .worktrees/ to gitignore
8fc5394 feat: add LettaCtrl GUI dashboard (letta-ctrl-server.js + letta-ctrl.html)
23c811a fix: correct skill install paths broken by shell variable expansion
829dfb9 docs: sync README and USER_GUIDE with tool audit cleanup
9f3fd60 feat: add 4 security skills + fix skill install paths + letta-ctrl flags
df6415e chore: third-pass tool audit — remove duplicates and dead weight
cb0374b fix: escape agent IDs and block labels in HTML attribute contexts (XSS)
573b86b chore: remove shell-integration-only and wrong-stack tools
```
