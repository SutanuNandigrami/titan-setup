# n8n Docker → Native Install Migration — Feature Codemap
**Date**: 2026-03-23
**Status**: Shipped (feat/n8n-native-install)
**ADR**: ADR-038 (supersedes ADR-025)

---

## Problem

n8n ran as a Docker container managed by a `Type=oneshot + RemainAfterExit=yes` systemd unit (ADR-026). On ARM64 the image was pinned to v2.10.4 because the latest image's `isolated-vm` native addon segfaulted inside Alpine/musl containers (ADR-025).

This created three compounding problems:
1. ARM64 pin meant missing security patches and feature updates
2. Docker-in-systemd added ~25 MiB RAM overhead with no isolation benefit (n8n is a single Node.js process)
3. The `Type=oneshot` pattern from ADR-026 (correct for letta/ollama/ccflare) is unnecessary for n8n — it only runs one service with no shared-socket bootstrap

The upstream fix for the isolated-vm segfault shipped in n8n PR #26765 (backported to 2.11.x/2.12.x). The root cause was Alpine/musl, not ARM64.

---

## Architecture

### Before (Docker)
```
titan-setup.sh
  │
  └── lib/07-tools-python-js.sh
        ├── _N8N_IMAGE="n8nio/n8n:latest"
        ├── [ARM64] _N8N_IMAGE="n8nio/n8n:2.10.4"   ← pin
        ├── docker pull $_N8N_IMAGE
        └── systemd unit (Type=oneshot + RemainAfterExit=yes)
              └── ExecStart: docker run -d --restart unless-stopped n8n
```

### After (Native)
```
titan-setup.sh
  │
  └── lib/07-tools-python-js.sh
        ├── npm install -g n8n           ← mise Node 22.x
        │   (isolated-vm builds from source — no Alpine/musl)
        └── systemd unit (Type=simple)
              └── ExecStart: ~/.local/share/mise/shims/n8n start
```

---

## Migration Flow (on existing titan installs)

```
titan re-run on existing box
  │
  └── n8n block
        ├── detect: ~/.config/systemd/user/n8n.service contains "docker"?
        │     ├── YES → stop n8n service
        │     │         disable n8n service
        │     │         docker rm -f n8n      ← container removed
        │     │         ok "migrated from Docker (data preserved in ~/.n8n)"
        │     └── NO  → skip migration
        │
        ├── npm install -g n8n (or verify already installed)
        │
        └── write new Type=simple unit
              systemctl --user daemon-reload
              systemctl --user enable --now n8n
```

Data in `~/.n8n/` is **never touched** — it was the Docker volume mount path, and native n8n uses the same default. Credentials, workflows, and settings survive migration.

---

## Files Changed

| File | Change |
|------|--------|
| `lib/02-cli.sh` | Added `N8N_SKIP=false` default; `--n8n-skip` flag; `N8N_SKIP=true` in `--minimal` |
| `lib/07-tools-python-js.sh` | Replaced lines 146-226 (Docker block) with native npm install + Type=simple unit |
| `lib/16-finalize.sh` | Replaced `command -v docker` gates with `! $N8N_SKIP` for tailscale serve, VPS summary, desktop summary, credentials block |
| `docs/decisions.md` | Added ADR-038 |
| `test/session-review.bats` | Removed 14 Docker-specific n8n tests; added 11 native tests (N8N: prefix); updated KI minimal mode test; updated shared ARM tests to letta-only |
| `test/cli.bats` | Added `--n8n-skip` parser test |

---

## Test Coverage

**New tests (N8N: prefix in test/session-review.bats)**:
- `N8N: native install via npm (not Docker) — ADR-038`
- `N8N: systemd unit is Type=simple (not oneshot) — ADR-038`
- `N8N: ExecStart uses n8n binary path (no docker)`
- `N8N: no Docker image references in n8n block`
- `N8N: no ARM64 version pin for n8n (ADR-025 superseded)`
- `N8N: Docker-to-native migration block present`
- `N8N: N8N_SKIP flag in lib/07 and lib/02`
- `N8N: mise shim fallback for npm`
- `N8N: StartLimitIntervalSec in Unit section not Service`
- `N8N: finalize gates n8n on N8N_SKIP not docker check`
- `ADR: decisions.md has ADR-038 n8n native`

**Removed tests (Docker-specific, no longer valid)**:
- `R4: n8n service has After=docker.service`
- `R4: n8n uses detached docker`
- `ARM: n8n image pinned to 2.10.4 on aarch64`
- `ARM: n8n uses latest on non-aarch64`
- `ARM: _N8N_IMAGE variable used in docker pull`
- `ARM: _N8N_IMAGE variable used in systemd ExecStart`
- `ARM: n8n service uses Type=oneshot`
- `ARM: n8n service has RemainAfterExit=yes`
- `ARM: n8n uses --restart unless-stopped`
- `ARM: n8n has ExecStopPost for container cleanup`
- `ARM: StartLimitIntervalSec in Unit section not Service (n8n)`
- `ARM: no MemoryMax in docker services` (n8n half removed)
- `ARM: no docker run --rm in systemd services` (n8n half removed)
- `ADR: decisions.md has ADR-025 and ADR-026` → updated to allow superseded

---

## Verification

```bash
# Build and test
just build && just check

# Live - Oracle ARM
ssh titan@claude-1.magpie-lake.ts.net
# download and run titan with --mode vps
n8n --version
systemctl --user status n8n
curl -s http://127.0.0.1:5678/healthz

# Live - Hetzner x86
ssh titan@claude-6.magpie-lake.ts.net
# same verification

# Skip flag
bash titan-setup.sh --dry-run --mode desktop --n8n-skip
# → n8n not in output, no service created
```
