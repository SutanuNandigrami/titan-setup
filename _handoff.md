# Handoff — titan-setup

## Branch: `feat/power-tools` (PR #1 open)
- **Repo:** https://github.com/SutanuNandigrami/titan-setup
- **PR:** https://github.com/SutanuNandigrami/titan-setup/pull/1
- **Main:** 2 commits (initial + CLI options)
- **Feature branch:** 3 additional commits (hardening + 2 rounds of power tools)

## What's Completed

### Public release hardening (commit `d714189`)
- Removed all personal info (name parameterized via `--name` flag)
- Added `--name`, `--dry-run`, `--help` CLI options
- 16 bug/security fixes: temp dir for downloads, arch detection (x86_64/aarch64), version validation, apt-key deprecation, success message guards, idempotency for bun/uv installs, sd fallback

### Power tools round 1 (commit `ddae9ba`)
- **Tools:** inotify-tools, expect, asciinema, at, mitmproxy, mermaid-cli, jnv, gum, sqlite-vec
- **Skills:** tmux-control, workspace, pueue-orchestrator, diagrams
- **Commands:** /workspace-init
- **Config:** pueued auto-start in shell, tool permissions

### Power tools round 2 (commit `e977977`)
- **Tools:** lnav, imagemagick, maim, xdotool, cookiecutter, visidata, playwright, nushell, act, cloudflared
- **Skills:** deploy (auto-detect provider), process-supervisor (systemd user units)
- **Commands:** /remember (persistent cross-session memory)
- **Config:** permissions for systemctl --user, journalctl --user, all new tools

## Current State
- Working tree: **clean** (nothing uncommitted)
- shellcheck: **0 errors, 0 warnings**
- `--dry-run`: **passes**
- `--help`: **passes**
- No personal info: **verified** (grep returns 0)
- PR #1: **open**, not yet merged to main

## Totals
- 130+ CLI tools across apt/uv/bun/cargo/go/binary
- 11 inline skills (0 startup tokens each)
- 9 slash commands
- 3 Claude Code plugins (hookify, code-review, skill-creator)
- 2 subagents (researcher, planner)

## What's NOT Done / Next Steps
1. **Merge PR #1** to main — `gh pr merge 1 --merge` when ready
2. **Also update `~/titan/titan-setup.sh`** — the source copy at home dir is now behind. Run `cp /opt/projects/proj-01/titan-setup.sh ~/titan/` to sync
3. **Actually install the new tools** — the script was edited but not re-run. Run `./titan-setup.sh --name "Sutanu"` to install round 1+2 tools
4. **Test playwright chromium install** — may need `playwright install-deps` for headless browser dependencies
5. **Test nushell compile** — large Rust crate, may take 15+ min or fail on low memory
6. **Test cloudflared binary** — verify download URL works for the current latest release
7. **Consider adding a `--skip-heavy` flag** — to skip nushell/playwright/n8n on low-resource machines
8. **Git global identity** — only set repo-local. Run: `git config --global user.name "Sutanu" && git config --global user.email "sutanu.nandigrami@gmail.com"`

## Key Decisions Made
- **`sd` over `sed`** for template substitution (with sed fallback if sd missing)
- **`TITAN_ENGINEER_NAME` placeholder** in heredocs, replaced via `sd` post-write (because heredocs are single-quoted to preserve `$` in shell config)
- **Architecture vars** (`ARCH_AMD`, `ARCH_GO`, `ARCH_RUST`, `ARCH_FULL`) to handle download URL differences per tool
- **`mktemp -d` + trap cleanup** for all binary downloads instead of CWD
- **Playwright via bun** (not npm or pip) — consistent with the bun-for-JS-tools pattern
- **Nushell as separate install** (not in CARGO_CRATES array) — because it's a huge compile like spotify_player

## Files
- `titan-setup.sh` — main setup script (~2000 lines)
- `README.md` — full documentation with changelog
- `_scratchpad.md` — todo checklist (all items done)
- `_handoff.md` — this file
