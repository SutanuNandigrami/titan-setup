# Titan Setup

**One script. Fresh Ubuntu to fully armed Claude Code workstation.**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SutanuNandigrami/titan-setup/main/titan-setup.sh)
```

That's it. Everything installs automatically.

---

## Quick Start

```bash
# With your name
bash <(curl -fsSL .../titan-setup.sh) --name "Alice"

# VPS install (creates dedicated user, Tailscale, hardens SSH + firewall)
bash <(curl -fsSL .../titan-setup.sh) --mode vps --tailscale-key tskey-...

# Pin a specific Claude Code version
bash <(curl -fsSL .../titan-setup.sh) --cc-version 1.2.3

# Disable Claude Code auto-updates
bash <(curl -fsSL .../titan-setup.sh) --no-autoupdate

# Preview without making changes
bash <(curl -fsSL .../titan-setup.sh) --dry-run

# Clone and run locally
git clone https://github.com/SutanuNandigrami/titan-setup.git
cd titan-setup && ./titan-setup.sh --name "Alice" --mode desktop
```

After install: `source ~/.bashrc && claude` to authenticate.

### Prerequisites

| Requirement | Detail |
|-------------|--------|
| OS | Ubuntu 22.04+ (or Debian-based) |
| Architecture | x86_64 or aarch64 (auto-detected) |
| Access | `sudo` required |
| Network | Internet access for downloads |
| Time | ~30–45 min first run (Rust crates compile) |
| VPS mode | Tailscale auth key required (`--tailscale-key`) |

---

## Why Titan

Claude Code is powerful out of the box — but it wastes context before you type a word. MCP servers inject their full schema at startup:

```
GitHub MCP:     ~8,000 tokens
Postgres MCP:   ~4,000 tokens
Docker MCP:     ~3,500 tokens
Fetch MCP:      ~2,000 tokens
─────────────────────────────
Typical setup:  55,000–134,000 tokens before you ask anything
```

That's 25–67% of your 200K context window gone to tool overhead — fewer turns, worse recall, degraded reasoning.

### The Fix: CLI over MCP

Every common MCP server has a CLI equivalent. `gh` replaces GitHub MCP. `pgcli` replaces Postgres MCP. `docker` replaces Docker MCP. CLI tools cost **zero context tokens** because Claude Code already knows how to run shell commands.

Instead of injecting 8,000 tokens of GitHub schemas, Titan installs `gh` and teaches Claude to run `gh --help` at runtime. Tool knowledge is lazy-loaded, not front-loaded.

The one exception: `episodic-memory` (semantic search across past conversations — no CLI equivalent for this).

### The Numbers

```
Titan startup:   ~4–7K tokens   (CLAUDE.md + memory + skill descriptions)
MCP equivalent:  55–134K tokens
Savings:         94–97%
Tools:           155+ (vs ~20 in a typical MCP setup)
```

### Design Principles

| Principle | What it means |
|-----------|--------------|
| CLI over MCP | Shell commands replace MCP servers — zero token overhead |
| Discovery over docs | `--help` at runtime beats static schemas at startup |
| Hooks over instructions | `PreToolUse` hooks _enforce_ rules; CLAUDE.md can only _suggest_ |
| Lazy over eager | Skills, rules, commands load only when triggered |
| Idempotent always | Safe to re-run — every install checks before acting |

---

## What Gets Installed

### System Packages (apt)

`jq` · `mtr` · `nmap` · `tmux` · `pandoc` · `direnv` · `entr` · `nikto` · `lynis` · `redis-tools` · `aria2` · `btop` · `miller` · `inotify-tools` · `expect` · `asciinema` · `lnav` · `imagemagick` · `universal-ctags` · `chafa` + build dependencies for cargo crates

Desktop only: `maim` · `xdotool`

### Package Managers

| Manager | Replaces | Purpose |
|---------|----------|---------|
| **Rust / cargo** | — | Rust CLI tools + `rustup update` auto-upgrades |
| **uv** | pip · pipx · pyenv | Python CLI tools in isolated venvs |
| **bun** | npm · npx | JS CLI tools |
| **Go** | — | Go CLI tools |
| **mise** | asdf · nvm · pyenv | Runtime version management (Node, Python, Go) |
| **Docker** | — | Container runtime (via get.docker.com) |

### 155+ CLI Tools

**Python (uv):** httpie · yq · semgrep · csvkit · codespell · ansible-core · ansible-lint · sqlmap · pgcli · litecli · awscli · ruff · ast-grep-cli · ccusage · sherlock · mitmproxy · cookiecutter · visidata · notebooklm-mcp-cli (nlm)

**JS (bun):** trash-cli · tldr · prettier · repomix · gemini-cli · kilocode · vercel · ccstatusline · mermaid-cli (mmdc) · playwright · better-ccflare

**Rust (cargo):** ripgrep · fd-find · sd · eza · du-dust · bat · broot · zoxide · xsv · htmlq · git-cliff · git-absorb · git-delta · difftastic · onefetch · typos-cli · bandwhich · websocat · bore-cli · procs · bottom (btm) · hyperfine · pueue · watchexec-cli · just · starship · atuin · navi · choose · xh · mdbook · jnv · ouch · hurl · jwt-cli · oha · tree-sitter-cli · nu (nushell) · rtk · recall · parry · spotify_player · claude-tmux

**Go:** lazygit · dive · stern · glow · slides · mkcert · task · nuclei · ffuf · usql · grpcurl · actionlint · osv-scanner · hcloud · sops · doctl · doggo · age · gitleaks · gum · act · shfmt · gron · httpx · subfinder · dnsx · katana · cosign · crane · scc · dasel · claude-esp · claude-squad

**Binary releases:** kubectl · k9s · helm · terraform · packer · tflint · infracost · hadolint · duckdb · trivy · mc · gh · fzf · shellcheck · yazi · lazydocker · ctop · trufflehog · dippy · infisical · cloudflared · syft · grype · step-cli · comby · runme · tailscale (VPS)

**Docker services:** n8n workflow automation (systemd user unit, auto-starts at login on http://localhost:5678)

### Claude Code

- Native binary (auto-updates by default; `--no-autoupdate` disables via `DISABLE_AUTOUPDATER=1`)
- Claude Desktop + Claude Cowork Service — desktop mode only (community packages)

### `~/.claude/` Global Config

**CLAUDE.md** — Tool routing tables, workflow rules, MCP replacement map, auto memory protocol, compaction protocol

**settings.json:**

*20+ environment variables (zero context cost):*
- `PATH` — all tool dirs injected as absolute paths for every session
- `CLAUDE_CODE_SUBAGENT_MODEL=haiku` — fast model for subagents
- `CLAUDE_CODE_ENABLE_TASKS=1` — task list for tracking work
- `CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS=8192` — tuned file read limit
- `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90` — compact at 90% context
- `BASH_DEFAULT_TIMEOUT_MS=300000` / `BASH_MAX_TIMEOUT_MS=600000` — 5/10 min bash timeouts
- `ANTHROPIC_BASE_URL` — auto-set when better-ccflare is installed
- `DISABLE_AUTOUPDATER=1` — set when `--no-autoupdate` flag is used

*14 lifecycle hooks (zero context cost):*
- **PreToolUse** — blocks rm -rf, force push, pip/npm install, commits on main, chmod 777, kill -9, infra/docker/k8s destruction
- **PreToolUse (file guard)** — blocks edits to .env, credentials, secrets, .pem, .key
- **PreToolUse (RTK)** — compresses verbose command output 60–90% before it reaches context
- **PostToolUse (lint)** — async auto-lint on file writes (shellcheck / ruff / hadolint)
- **PostToolUse (audit)** — async JSONL logging of every tool call
- **PostToolUseFailure** — failure logging to `failures.jsonl`
- **Notification** — desktop notifications via `notify-send`
- **SubagentStop** — subagent lifecycle tracking + auto-unload agent slots
- **PreCompact** — saves session state + prunes old JSONL files before compaction
- **SessionStart** — displays handoff + memory status + loaded agent slots
- **SessionEnd** — final state capture + optional ntfy.sh notification
- **UserPromptSubmit** — keyword-triggered memory injection (zero cost on normal prompts)
- **TaskCompleted / InstructionsLoaded / ConfigChange / TeammateIdle** — audit logging (requires CC 2.1+)

*Permissions:* 8 allow rules · 73 deny rules (Bash, Read, Edit, Write)

*Preferences:* `model: opusplan` (Opus plan mode / Sonnet execution) · `effortLevel: medium` · `showTurnDuration: true` · `includeCoAuthoredBy: true`

**11 Inline Skills** (path-gated — only load for matching file types):
`cli-tools` · `security-scan` · `git-workflow` · `infra-deploy` · `add-cli-tool` · `tmux-control` · `workspace` · `pueue-orchestrator` · `diagrams` · `deploy` · `process-supervisor`

**Community Skills** (selectively installed, path-gated):
- [superpowers](https://github.com/obra/superpowers) — TDD, systematic debugging, brainstorming, verification, writing plans
- [VibeSec](https://github.com/BehiSecc/VibeSec-Skill) — Web app security (gated to .js/.ts/.py)
- [trailofbits modern-python](https://github.com/trailofbits/skills) — Modern Python (gated to .py)
- [NotebookLM CLI](https://github.com/jacob-bd/notebooklm-cli) — Google NotebookLM skill

**6 Conditional Rules** (0 tokens when not triggered):
`python.md` · `shell.md` · `terraform.md` · `docker.md` · `security.md` (always-on) · `memory.md` (always-on)

**11 Slash Commands** (0 tokens until invoked):
`/catchup` · `/handoff` · `/ship` · `/standup` · `/scan` · `/review` · `/tools` · `/workspace-init` · `/remember` · `/gh-action` · `/context`

**Agents:**
- `researcher` — read-only explorer (**Haiku**)
- `planner` — architecture planning (**Opus**)
- `reviewer` — code review: correctness, security, style, performance (**Sonnet**)

**5 On-Demand Agent Slots** (managed via `agt` CLI):
- `slot-1/2/3` — Haiku (fast search/analysis)
- `slot-4` — Sonnet (balanced reasoning)
- `slot-5` — Opus (deep thinking)

Slots load from [agent-stash](https://github.com/SutanuNandigrami/agent-stash) (~30 pre-built agents). `agt search <name>`, `agt load <agent>`, `agt unload`, `agt status`.

**Plugins:** hookify · code-review (Anthropic official)

### Shell Integration

PATH · starship prompt · zoxide (directory jumping) · atuin (searchable history) · direnv (auto-load .envrc) · mise (runtime versions) · fzf (fuzzy find) · delta (git diffs) · pueue daemon (auto-started)

---

## Context Budget

```
Component             Startup cost    Notes
──────────────────    ─────────────   ──────────────────────────────────────
System prompt         ~15K tokens     Built-in (unavoidable, includes tool defs)
CLAUDE.md (global)    ~800 tokens     Loaded every session
CLAUDE.md (project)   ~800 tokens     If present in project root
MEMORY.md             ~200 tokens     First 200 lines of auto memory
Skill descriptions    ~2–5K tokens    19 skills (path-gated, lazy full content)
6 conditional rules   ~500 tokens     Only when matching file types are open
11 commands           0 tokens        Loaded only on /command invocation
3 agents              ~200 tokens     Descriptions only; full content on spawn
Hooks, settings.json  0 tokens        External processes / parsed by harness
Audit log             0 tokens        Async JSONL, never loaded
CLI --help            0 tokens        Lazy-loaded at runtime
──────────────────    ─────────────   ──────────────────────────────────────
Titan startup:        ~4–7K tokens    (excluding system prompt)
MCP equivalent:       55–134K tokens
Savings:              94–97%
```

---

## Package Manager Rules

```
Python CLIs  →  uv tool install <pkg>
JS CLIs      →  bun install -g <pkg>
Rust CLIs    →  cargo install <crate>
Go CLIs      →  go install <path>@latest
System deps  →  sudo apt install <pkg>

NEVER:  pip install  |  npm install -g  |  sudo pip
```

These are blocked at three levels: the permissions deny list, the PreToolUse hook, and your own muscle memory.

---

## Idempotent / Safe to Re-run

Every install section checks before acting (`command -v`, `uv tool list`, `[ -d ]`). Re-running only installs missing components. Go and Rust toolchains auto-upgrade when outdated.

---

## Post-Install Verification

```bash
source ~/.bashrc

# Tool counts
echo "Cargo: $(ls ~/.cargo/bin/ | wc -l)"
echo "Go:    $(ls ~/go/bin/ | wc -l)"
echo "UV:    $(uv tool list 2>/dev/null | wc -l)"

# Claude Code
claude --version && claude doctor

# Key tools
for cmd in rg fd bat eza jq yq gh docker kubectl terraform claude gitleaks; do
  printf "%-12s" "$cmd"
  command -v "$cmd" &>/dev/null && echo "✓ $(which $cmd)" || echo "✗ missing"
done
```

---

## For New Projects

The global `~/.claude/` config works everywhere. For project-specific context, add a `CLAUDE.md` in the project root:

```markdown
# Project: my-app

## Architecture
- Next.js 15 in src/
- PostgreSQL via Drizzle ORM
- Auth via Clerk

## Commands
- `bun dev` — dev server on :3000
- `bun test` — run tests

## Conventions
- Server components by default
- No `any` types
```

---

## Changelog

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
