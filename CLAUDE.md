# Titan Setup — Developer Guide

## What This Is
Bash installer that transforms fresh Ubuntu into a complete AI dev workstation.
Installs 150+ CLI tools, Claude Code, services (Letta, n8n, Ollama), and deploys
`dot-claude/` → `~/.claude/` (settings, hooks, skills, rules, agents).

## Architecture
```
titan-setup.sh          ← assembled monolith (DO NOT edit directly)
lib/00-header.sh        ← shebang, version, self-materialization
lib/01-common.sh        ← helpers: ok(), warn(), fail(), section(), phase_done/mark(), apt_update()
lib/02-cli.sh           ← CLI option parsing (--name, --mode, --dry-run, --minimal, etc.)
lib/03-vps-reexec.sh    ← VPS sudo/user creation
lib/04-vps-harden.sh    ← Tailscale, SSH hardening, fail2ban, auditd
lib/05-prerequisites.sh ← system packages, journald limits, fonts
lib/06-package-managers.sh ← rustup, uv, bun, Go, mise, Docker
lib/06b-repo-files.sh   ← inline config stashing (TITAN_REPO_FILES)
lib/07-tools-python-js.sh ← Python tools (uv), JS tools (bun)
lib/08-tools-letta.sh   ← Letta server, Ollama, better-ccflare
lib/09-tools-rust-go.sh ← Rust tools (cargo), Go tools, binary downloads
lib/10-claude-code.sh   ← Claude Code CLI install
lib/11-deploy-config.sh ← Deploy ~/.claude/ from dot-claude/
lib/12-plugins.sh       ← Claude Code plugins
lib/13-plugins-letta-ctrl.sh ← Letta control plane web UI
lib/14-plugins-cleanup.sh ← Plugin cleanup/summary
lib/15-shell-integration.sh ← Shell config, PATH, verification
```

**Build:** `just build` assembles lib/*.sh → titan-setup.sh. Never edit titan-setup.sh directly.
**Test:** `just test` runs all bats tests. `just check` = full CI (lint+fmt+build+test+smoke).
**Smoke:** `just smoke` = `bash titan-setup.sh --dry-run --mode desktop --name test`

## set -e Safety — CRITICAL
This project uses `set -euo pipefail`. Every command that can fail MUST be guarded.
Unguarded commands silently kill the entire script. This has caused regressions 3 times.

```bash
# SAFE patterns:
curl -fsSL ... | bash || true                              # swallow failure
curl -fsSL ... && ok "done" || warn "failed"               # report outcome
VAR=$(curl -s ... | jq -r '.tag' || true)                  # guard pipeline
if curl -fsSL ... | bash; then ok "yes"; else warn "no"; fi # conditional

# DEADLY — never write these in lib/*.sh:
curl -fsSL ... | bash                     # network fail = script dies
sudo apt-get install -y pkg               # missing pkg = script dies
VAR=$(curl -s ... | jq -r '.tag')         # pipefail = script dies
```

Multiline: guard goes on the FINAL line of a pipe/continuation chain, not the first.
Never call `api.github.com` directly — 60 req/hr rate limit. Use `_gh_latest_tag()`.
`test/set-e-safety.bats` catches violations automatically.

## Bug Fixes Require Regression Tests
Every bug fix MUST include a test in `test/*.bats` that catches the class of bug.
Commit fix + test together. Run `just test` before committing — zero failures.
Verify the test catches the bug *before* your fix, passes *after*.
Reduce false positives in grep-based tests by excluding guarded lines
(`||`, `&&`, `if`, continuations ending in `|` or `\`).

## Helpers (lib/01-common.sh)
- `ok "msg"` / `warn "msg"` / `fail "msg"` — colored status output (✓/⚠/✗)
- `section "Phase N — Name"` — cyan phase banner
- `phase_done "phaseN"` / `phase_mark "phaseN"` — idempotent checkpoint system
- `apt_update` — cached apt-get update (runs once per session via `_APT_UPDATED`)
- `check_port 8080 "service"` — warn if port already bound
- `run_q cmd...` — run quietly (stdout/stderr suppressed)

## Conventions
- **Variables:** `_PREFIXED` for internal, `UPPERCASE` for public flags
- **Phases are idempotent:** each checks `~/.titan-progress/` before re-running
- **`--force-updates`** overrides phase checkpoints
- **Hooks (dot-claude/hooks/) must NOT use `set -euo pipefail`** — crash = broken session
- **After editing lib/*.sh:** always `just build && just test`

## Key Test Files
| File | Tests |
|------|-------|
| `test/set-e-safety.bats` | Unguarded curl/wget/systemctl/sysctl, api.github.com calls |
| `test/session-review.bats` | Regression guards from past review sessions |
| `test/shellcheck.bats` | shellcheck on all scripts |
| `test/smoke.bats` | --dry-run execution |
| `test/structure.bats` | File presence, agt structure, titan-setup patterns |
| `test/syntax.bats` | bash -n on all scripts |
| `test/templates.bats` | CLAUDE.md.tmpl/settings.json validation |

## dot-claude/ (deployed to ~/.claude/)
- `CLAUDE.md.tmpl` — global operating manual (applies to ALL projects, not just titan)
- `settings.json` — 73 deny rules, hooks, env vars, permissions
- `skills/` — 15 self-contained skill files
- `hooks/` — session-start, session-end, pre-compact, prompt-memory-inject
- `rules/` — 7 path-gated rules (shell, python, docker, terraform, security, memory, skill-authoring)
- `agents/` — researcher (Haiku), planner (Opus), reviewer (Sonnet)
- `commands/` — /review, /tools, /gh-action

## Remember: `just build && just test` after every lib/*.sh change. Guard every failable command.
