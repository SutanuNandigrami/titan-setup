# Changelog

All notable changes to titan-setup are documented here.

For full documentation see [README.md](README.md) and [USER_GUIDE.md](USER_GUIDE.md).

---

### v3.21 — vexp-cli context engine integration (ADR-030)

**vexp-cli — local-first context engine for AI coding agents:**
- Installed via `bun install -g vexp-cli` with `trustedDependencies` for postinstall binary download
- Auto-configured as global MCP server in `settings.json` (stdio transport — CC spawns on demand)
- Uses tree-sitter AST parsing + dependency graphs + skeleton context for ~65% token reduction
- 11 MCP tools: `run_pipeline`, `get_context_capsule`, `get_impact_graph`, `search_logic_flow`, etc.
- Free tier: 2,000 nodes, 8 calls/day, 7 tools — works out of box, no license key needed
- Supports 30 languages (TypeScript, Python, Go, Rust, Bash, HCL, etc.)
- Binary verification: warns if vexp-core Rust binary missing after postinstall

**New CLI flag:**
- `--no-vexp` — skip vexp-cli install
- `--minimal` now also skips vexp-cli

**Architecture:**
- ADR-030: stdio transport over HTTP+SSE — no daemon, no port, no systemd service
- mcpServers key NOT in TITAN_MANAGED_BLOCKS — user-added MCP servers preserved across re-runs
- 170 bats tests (2 new for vexp-cli integration)

---

### v3.20 — ARM64 docker reliability, live testing overhaul, 168 tests

- Replaced ccstatusline with claude-lens: quota pace tracking, zero-config, no bun dependency (ADR-030)
- Added claudecodeui: web/mobile interface for Claude Code sessions, zero-config, systemd service (ADR-034)

**ARM64 Docker Services (PR #47 — ADR-025/026):**
- n8n pinned to `2.10.4` on aarch64 — `isolated-vm` in >=2.11.1 segfaults on ARM64 Alpine
- Systemd services switched from `Type=simple` + `docker run --rm` to `Type=oneshot` + `docker run -d --restart unless-stopped` — attached docker clients get SIGKILL'd (exit 137) on ARM64
- Removed `MemoryMax` from services (only limited docker CLI, not container)
- Fixed `StartLimitIntervalSec` placement (`[Unit]` not `[Service]`)
- Added `ExecStopPost` for container cleanup on service stop

**Live VPS Testing (PRs #39–#47):**
- Hetzner x86 (CPX22, Ubuntu 24.04): 16 bugs found and fixed — all 6 phases pass
- Oracle ARM (Ampere, Ubuntu 24.04): 2 bugs found and fixed — all 6 phases pass
- Fixes include: apt lock timeout, gpg dearmor hang, tailscaled wait, ufw/iptables fallback, docker GID propagation, read EOF guard, tmux detached mode

**Architecture:**
- Consolidated lib/12+13 → single `lib/12-plugins.sh` (ADR-024): 19 → 18 fragments
- 26 ADRs (ADR-011 through ADR-026)
- 168 bats tests (97 new regression tests from live testing)

**New CLI flags:**
- `--minimal` — 50 core tools in ~25 min (skips Letta, Ollama, n8n, extended tools)
- `--secrets-file PATH` — credential passing via file instead of CLI args
- `--fresh` — reset all phase checkpoints for clean re-install
- `--force-updates` — force upgrade all tools

---

### v3.19 — Idempotency overhaul, atomic settings merge, desktop bug fixes

**Idempotency (Phase 2 — settings.json atomic merge):**
- New `script/merge-settings.py`: replaces `install -Dm644` clobber + 6 sequential `jq` calls with single atomic Python merge
- Strategy: "Replace what we own, merge what we share, preserve what's theirs"
- Titan-managed keys always win, runtime-injected keys set via `--inject`, user-owned keys never overwritten
- `enabledPlugins` union merge: titan + user plugins both preserved
- `model` key is now user-owned: `/model` changes persist across re-runs (fresh installs get `opusplan`)
- Atomic write via temp file + `os.rename()` — safe even if CC is running
- Fallback: if merge fails, falls back to template overwrite

**Phase 3 — `--force-updates` flag + cleanup:**
- New `--force-updates` CLI flag: upgrades all tools instead of skip-if-exists default
  - UV: `uv tool upgrade --all`
  - Bun: `bun install -g` for all tools
  - Cargo: bypasses version check, triggers reinstall via binstall/compile
  - Go: bypasses binary existence check, re-downloads latest
- Claude Code: removed skip guard — always runs installer (it's idempotent)
- Targeted cleanup block: removes stale hookify plugin cache, renamed skills
- Running CC detection: warns before config changes

**Desktop bug fixes (Phase 1):**
- `agt build-index`: fixed xargs quoting error (deployed repo version with `sed` instead of `xargs`)
- CLI tool count: "155+" → "150+" in header, section title, and summary
- ccstatusline: auto-detects if installed, sets as statusLine command; else falls back to statusline-command.sh
- Removed `xdg-open` auto-opening of services (security risk) — prints URLs instead
- n8n: prints first-run setup info (no default password, first visitor becomes owner)
- Letta: prints API key from credentials file on screen (both VPS and desktop)
- letta-ctrl: prints auth token from ctrl-token file on screen

**cc-patch-thinking fix:**
- Uses atomic `os.rename()` instead of direct write — fixes "Text file busy" when CC is running
- SessionStart hook now successfully auto-patches on every startup

**Architecture Decision Records:**
- New `docs/decisions.md` with 10 ADRs: CLI-over-MCP, telemetry env vars, opusplan, hook pipefail, hookify removal, settings.json merge, skip-if-exists, selective skills, agent teams, idempotency categories

---

### v3.18 — GitHub Action security hardening, documentation overhaul

**GitHub Action security:**
- Restricted `@claude` trigger in GitHub Actions to repository owner and collaborators only — prevents prompt injection from anonymous external users filing issues with malicious `@claude` mentions
- Added `actor-permission` check (write access required) before the Claude Code action runs
- Security model: only users with repository write access can trigger automated Claude responses

**Documentation:**
- README: added table of contents, flag reference table, improved troubleshooting (PATH debugging steps, tool-not-found guide), changelog version table
- USER_GUIDE: added table of contents, Quick Start section, complete Slash Commands reference (all 11 commands documented with examples) — this section was previously missing
- CHANGELOG: added this entry

---

### v3.17 — ARM64 fixes, VPS reliability, consistency audit

**ARM64 (aarch64) compatibility — verified on OCI Ampere:**
- `claude-desktop-bin`, `comby`: skip with `⚠ skipped (amd64 only)` on ARM64 — no binaries available
- `lazydocker`: fixed archive naming — releases use `arm64` not `aarch64`
- `hadolint`: fixed URL — `Linux` → `linux` (case) and `aarch64` → `arm64`
- `runme`: fixed archive naming — `ARCH_FULL` (aarch64) → `ARCH_GO` (arm64)
- `claude-agent-sdk`: replaced missing `pip3`/`pip` with `uv pip install --target ~/.local/lib/python3.12/site-packages` — works on Ubuntu 24.04's externally-managed Python without root

**VPS reliability:**
- `needrestart`: add `kernelhints=-1` and `ucodehints=0` alongside `restart='a'` — fully suppresses the "Pending kernel upgrade" ncurses dialog during apt installs
- Sudoers write now uses `sudo tee` + `sudo chmod` — fixes "Permission denied" when initial VPS user is non-root (OCI ubuntu, AWS ec2-user, etc.) — was crashing script on any non-root cloud instance
- Semgrep token prompt no longer repeats: both tmux re-exec wrapper and VPS user re-exec now carry forward interactively-entered `SEMGREP_TOKEN` / `--no-semgrep`

**Consistency audit fixes:**
- Self-materialize URL: was pointing to archived `titan-setup` repo — fixed to `claude-titan-setup`
- Phase 3 header and startup banner: `100 CLI Tools` → `155+ CLI Tools`
- Added `SCRIPT_VERSION="v3.17"` constant — `--version` flag now works, version shown in summary
- CHANGELOG v3.11: corrected ccflare flag count (3 implemented: skip/port/host, not 7)
- Cargo PATH: `source ~/.cargo/env` moved inside the install branch so `cargo --version` doesn't fail on fresh installs

**Post-install UX:**
- `atuin login` hint added to next-steps (both VPS and desktop)

---

### v3.16 — Tmux resilience, Vertex AI RTK fix, semgrep integration

**Disconnect resilience:**
- Replaced `screen` with `tmux` for SSH-drop protection — script now re-execs inside a named tmux session at startup
- Reconnect after SSH drop: `tmux attach -t titan-setup`
- Log: `/tmp/titan-setup-<timestamp>.log`
- Removed `screen` from Phase 1 security packages

**ccstatusline config fix:**
- `config/ccstatusline/settings.json` was never committed to repo — caused `install` to fail mid-Phase 5, killing all subsequent steps (skills, hooks, agents, RTK, agt)
- ccstatusline install is now non-fatal (`|| warn` fallback)

**RTK: Vertex AI null-fix (built from source):**
- Vertex AI returns `null` for `totalCost`, `inputTokens`, `outputTokens`, `totalTokens` — serde panicked on deserialization
- RTK now built from source with `config/rtk/ccusage.patch` applied: adds `null_to_zero_u64`/`null_to_zero_f64` deserializers
- `rtk gain` no longer crashes when Vertex AI sessions are in the JSONL history

**Semgrep integration:**
- New flags: `--semgrep-token TOKEN` (unattended), `--no-semgrep` (skip)
- Interactive prompt during install with Enter-to-skip
- Token injected into settings.json `env.SEMGREP_APP_TOKEN` + `semgrep@claude-plugins-official` enabled in `enabledPlugins`
- semgrep plugin installed via `claude plugin install semgrep` when token provided
- semgrep `hooks.json` patched post-install: `post-tool-cli-scan` guarded with `git rev-parse --git-dir &>/dev/null && ... || true` — prevents hook failures outside git repos

**Verified on Oracle Cloud ARM64:** 4 vCPU / 24 GB RAM / 200 GB storage (aarch64)

---

### v3.15 — RTK token compression, settings fixes, tool coverage

**RTK (Rust Token Killer):**
- Installed from `github.com/rtk-ai/rtk` (NOT crates.io — name collision with Rust Type Kit)
- `rtk init -g --auto-patch` runs after settings.json write — appends RTK PreToolUse hook without clobbering existing hooks
- 60–90% token reduction on verbose outputs (git, docker, ls, grep, test runners); 71%+ observed in first session
- `rtk gain` / `rtk gain --graph` tracks savings history

**better-ccflare:**
- Fixed: binary not found after build — changed `bun --cwd repo run build:cli` to `bun --cwd repo/apps/cli run build`
- `ANTHROPIC_BASE_URL=http://127.0.0.1:PORT` now auto-written to settings.json env block after install (desktop + VPS)

**settings.json:**
- Fixed: `Bash(*)` → `Bash` in allow list (CC 2.0.73 rejected the old syntax)
- Fixed: All deny `*` → `:*` for prefix matching; middle-wildcard patterns retained (supported on CC 2.1+)
- Added: `effortLevel: medium` and `showTurnDuration: true`
- Note: `ConfigChange`, `InstructionsLoaded`, `TaskCompleted`, `TeammateIdle` require CC 2.1+ — older versions skip the entire settings.json file if unknown events are present; upgrade CC on VPS to activate all 14 hooks

**VPS hardening fixes:**
- Fixed: `sshd reload` → `restart` — `ListenAddress` binding requires socket rebind
- Fixed: `sshd_config.d/*.conf` drop-in patching — Hetzner cloud-init override was keeping password auth enabled
- Fixed: `tailscale up --reset --operator=$USER` — idempotent on re-runs
- Fixed: SSH port 22 closure moved to absolute last step so all output prints before session may drop

**Tool coverage:**
- Added `rtk` and `shannon-audit` to cli-tools skill and security-scan skill
- Added `tailscale`, `btm` (bottom), `ansible-lint`, `gcloud`, `better-ccflare`, `nlm`, `kilocode` to cli-tools skill (were installed but undocumented)

**Total: 156+ CLI tools · 14 hook events · 73 deny rules**

---

### v3.14 — Modularization, VPS mode, agent slots, token optimization

**Architecture:**
- Script reduced from ~3,949 to ~1,863 lines — all static content (CLAUDE.md, agents, hooks, rules, skills, commands) extracted to `dot-claude/` repo directory and installed via `install -Dm644/755`
- Script clones repo at startup (`git clone --depth=1`) or uses `TITAN_REPO_FILES` env var for local testing

**VPS mode (`--mode vps`):**
- Creates non-root `CLAUDE_USER` (default: `claude`, customizable via `--claude-user`)
- Grants passwordless sudo + docker group; re-executes script under new user
- Locks root account, hardens SSH (`PermitRootLogin no`)
- UFW: opens 41641/udp for Tailscale, closes everything else
- `tailscale serve --https` proxies n8n (5678) and better-ccflare (8080) with TLS — both bound to 127.0.0.1 only
- Compliance audit: verifies root lock, SSH config, Tailscale, UFW rules

**Claude Code flags:**
- `--cc-version VERSION` — install/downgrade/reinstall specific version
- `--no-autoupdate` — adds `DISABLE_AUTOUPDATER=1` to settings.json env block

**Token optimization:**
- Path-gating (`paths:` frontmatter) added to all 10 inline skills + 3 community plugins — always-on context: 3,009 → 203 lines (~93% reduction, ~42K tokens/turn)
- Restored `opusplan` as default model (was incorrectly changed to `claude-sonnet-4-6` in v3.13)
- Plugin SKILL.md auto-patching — injects `paths:` into plugin files at install time

**On-demand agent slots:**
- `agt` CLI at `~/.local/bin/agt` — search/load/unload/status/info/refresh/build-index
- 5 slots: slot-1/2/3 = Haiku, slot-4 = Sonnet, slot-5 = Opus
- Agent stash bootstrapped from [agent-stash](https://github.com/SutanuNandigrami/agent-stash) (~30 agents)
- SubagentStop hook auto-unloads slots when `AUTO_UNLOAD=true`

**Bug fixes:**
- Trap overwrite: `trap EXIT` at line 1083 was clobbering the one at line 109 — fixed with `_CLEANUP_DIRS` array + `_do_cleanup()` fn
- `step()` was calling the smallstep binary instead of printing status — renamed to `ok()`
- Crontab pipefail: `crontab -l | grep -v` exits 1 on empty crontab — added `|| true`
- agt manifest unload: `grep -v | mv &&` race where mv never ran — fixed with `|| true` + separate `mv` line
- Playwright chromium: now installs on VPS too (fully headless)
- Process substitution crash: script now self-materializes to `/tmp/titan-XXXXXX.sh` for `sudo -u titan` re-exec

**Total: 155+ CLI tools · 11 inline skills + community · 6 rules · 11 commands · 14 hook events · 5 agents + 5 slots**

---

### v3.13 — Token optimization: model routing, JSONL pruning, hook fixes

- Introduced per-agent model selection (Haiku / Sonnet / Opus) for researcher / planner / reviewer
- Pre-compact script prunes session JSONL files >30 days old, caps at 15 sessions
- Fixed SessionStart matcher (was firing on every resume); UserPromptSubmit hook is now keyword-triggered instead of always-on
- Estimated 20–30% reduction in per-session token usage

---

### v3.12 — Verbose flag, install fixes, better-ccflare overhaul

- Added `--verbose` / `-v` flag — subprocess output silenced by default, routed to `/tmp/titan-setup-TIMESTAMP.log`
- Fixed `claude-agent-sdk` on Ubuntu 24.04 — added `--break-system-packages` to pip3 install
- Fixed `n8n` not starting — `loginctl enable-linger` + `usermod -aG docker` for systemd user service
- Fixed `step-cli` — switched to `github.com/smallstep/cli/releases` (old URL broken)
- Fixed `runme` — use direct `latest/download` URL (GitHub API was returning null version)
- Fixed `episodic-memory` — removed incorrect `bun install -g` (it's a plugin, use `claude plugin install`)
- Fixed `better-ccflare` — removed non-existent `vertex-ai` mode; added all 9 real modes; suppressed dotenv noise

---

### v3.11 — better-ccflare: provider wizard + CLI flags

- Full provider account wizard during install (OAuth, Vertex AI, OpenAI-compatible, Anthropic-compatible, Bedrock, etc.)
- 3 CLI flags for unattended installs: `--ccflare-skip`, `--ccflare-port`, `--ccflare-host`

---

### v3.10 — better-ccflare: multi-account Claude load balancer

- Added `better-ccflare` install via bun + systemd user service
- Dashboard launcher: GUI opens browser; headless VPS prints URLs + SSH tunnel command

---

### v3.9 — Context audit: skill scoping + JSONL pruning

- Fixed 4 large skills (vibesec, tdd, nlm-cli, systematic-debugging) that had no `paths:` — all content was loading at startup per bug #14882
- JSONL session pruning: deletes files >180 days old, caps total at 30
- Startup context reduced by up to 1,775 lines on non-web/non-test sessions

---

### v3.8 — Smart memory: on-demand retrieval, zero startup cost

- Fixed `SessionStart` hook firing on every resume — changed matcher to `startup|compact`
- Fixed `UserPromptSubmit` hook injecting "Success" into every prompt — replaced with keyword-triggered `prompt-memory-inject.sh`
- Added `/recall` command — surfaces MEMORY.md + topic files + handoff on demand (0 tokens otherwise)
- Removed dead sqlite-vec / vectordb infrastructure

---

### v3.7 — Output verbosity + model call reduction

- Removed `outputStyle: "explanatory"` — was injecting verbose instructions into every turn
- Removed `thinking: true` — was adding 1K–10K thinking tokens per turn; use `/think` or plan mode when needed
- Added `DISABLE_NON_ESSENTIAL_MODEL_CALLS=1` — suppresses AI-generated spinner/status tokens
- Estimated 20–40% reduction in per-turn output token cost

---

### v3.6 — Token usage optimization

- Replaced full `trailofbits/skills` clone (60 SKILL.md / 71K lines) with selective `modern-python` only
- Removed full `hashicorp/agent-skills` clone (14 SKILL.md / 10K lines)
- Removed `MAX_OUTPUT_TOKENS=64000`, `EFFORT_LEVEL=high`, `EXPERIMENTAL_AGENT_TEAMS=1`, `teammateMode: tmux`, `skill-creator` plugin — all were burning tokens aggressively
- Added `opusplan` as default model (Opus for planning, Sonnet for execution)
- Added per-agent model routing (researcher = Haiku, planner = Opus, reviewer = Sonnet)
- ~60–70% reduction in per-session token usage; ~30–50% per-turn reduction

---

### v3.5 — PATH fixes + "Why Titan" + new env vars

- Fixed PATH exports for cargo/uv/bun moved outside if/else — tools were invisible on re-runs when already installed
- Fixed PATH injection into settings.json `env` block with absolute paths — tools discoverable in every CC session
- Added "Why Titan" section explaining CLI-over-MCP architecture
- Added 8 new env vars: `AUTOCOMPACT_PCT`, `BASH_TIMEOUT`, `MAINTAIN_PROJECT_CWD`, `DISABLE_NONESSENTIAL_TRAFFIC`, `DISABLE_FEEDBACK_SURVEY`, `SUBAGENT_MODEL`, `ENABLE_TASKS`, `FILE_READ_MAX_OUTPUT_TOKENS`

---

### v3.3 — Audit, observability, GitHub Actions

- Async PostToolUse audit logging to `~/.claude/logs/audit.jsonl`
- ntfy.sh notification on session stop (`NTFY_URL` env var)
- OpenTelemetry export (`CLAUDE_CODE_ENABLE_TELEMETRY=1`)
- GitHub Actions template + `/gh-action` command
- `enabledPlugins` + `extraKnownMarketplaces` in settings.json (survives re-runs)

---

### v3.2 — Memory + rules system

- Memory/context management: PreCompact, Stop, SessionStart hooks
- Auto-generated `~/.claude/memory/handoff.md` for cross-session state
- 5 conditional rules files (python, shell, terraform, docker, security)
- `.claudeignore` template for project context hygiene
- Enhanced CLAUDE.md compaction protocol (7 preserved fields)
- 24 new CLI tools added

---

### v3.0 — Public release

- CLI options: `--name`, `--dry-run`, `--help`
- Architecture detection (x86_64/aarch64) for all binary downloads
- 4 new skills: `tmux-control`, `workspace`, `pueue-orchestrator`, `diagrams`
- Security: supply chain allowlist, `curl|bash` disclaimers, community package warnings

---

### v2.3 — Security hardening + skill overhaul

- Write deny rules for `~/.bashrc`, `~/.profile`, `~/.zshrc`, `~/.ssh/*`, `.env*`
- Fixed newline bypass in PreToolUse hooks (`read -r -d ''`)
- Added branch check hook — blocks `git commit` on main/master
- Replaced weak skills (`tool-discovery`, `security-ops`, `infra-ops`) with full versions (`cli-tools`, `security-scan`, `infra-deploy`)
- Removed `owasp` skill (536 lines, overlapped with vibesec)
- Fixed `gcloud` and `dasel` — were in skill but never installed; now both are installed

---

### v2.2 — Tool fixes

- `spotify-tui` (abandoned) → `spotify_player` (actively maintained)
- `ccstatusline` was cargo install (wrong) → now `bun install -g`
- `ctop` binary URL pinned to v0.7.7 (archived project, `/latest/` broken)
- `trufflehog` install script runs with `sudo` (writes to `/usr/local/bin`)
- `n8n` removed from bun (too large for global install) → Docker pull
- Added `spotify_player`, `recall`, `parry`, `sherlock-project`, `ccusage`, `gemini-cli`, `notebooklm-cli`, `kilocode`, `vercel`
