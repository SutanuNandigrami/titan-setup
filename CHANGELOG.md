# Changelog

All notable changes to titan-setup are documented here.

For full documentation see [README.md](README.md) and [USER_GUIDE.md](USER_GUIDE.md).

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
- 7 new CLI flags for unattended installs: `--ccflare-skip`, `--ccflare-port`, `--ccflare-host`, `--ccflare-proxy`, `--ccflare-loglevel`, `--ccflare-oauth`, `--ccflare-vertex`

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
