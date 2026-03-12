# Titan Setup

**One script. Fresh Ubuntu to fully armed Claude Code workstation.**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SutanuNandigrami/titan-setup/main/titan-setup.sh)
```

That's it. One command. Everything installs automatically.

**Options:**
```bash
# With custom engineer name
bash <(curl -fsSL https://raw.githubusercontent.com/SutanuNandigrami/titan-setup/main/titan-setup.sh) --name "Alice"

# Install on a VPS (creates dedicated user, installs Tailscale, hardens system)
bash <(curl -fsSL https://raw.githubusercontent.com/SutanuNandigrami/titan-setup/main/titan-setup.sh) --mode vps

# Specify Claude Code version (install/downgrade/reinstall)
bash <(curl -fsSL https://raw.githubusercontent.com/SutanuNandigrami/titan-setup/main/titan-setup.sh) --cc-version 1.0.0

# Disable Claude Code auto-updater
bash <(curl -fsSL https://raw.githubusercontent.com/SutanuNandigrami/titan-setup/main/titan-setup.sh) --no-autoupdate

# Preview without making changes
bash <(curl -fsSL https://raw.githubusercontent.com/SutanuNandigrami/titan-setup/main/titan-setup.sh) --dry-run

# Or clone and run locally
git clone https://github.com/SutanuNandigrami/titan-setup.git && cd titan-setup
./titan-setup.sh --name "Alice" --mode desktop
```

After install: `source ~/.bashrc && claude` to authenticate.

### Prerequisites
- **OS:** Ubuntu 22.04+ (or Debian-based)
- **Arch:** x86_64 or aarch64 (auto-detected)
- **Access:** `sudo` required for system packages and binary installs
- **Network:** Internet access for downloads
- **Time:** ~30-45 minutes on first run (Rust crates compile from source)
- **VPS mode:** Tailscale API key (`TS_AUTHKEY`) required for secure MagicDNS access

---

## Why Titan

Claude Code is powerful out of the box, but it wastes most of its context window on tool discovery. Every MCP server, every tool schema, every capability description eats tokens before you even ask a question. Titan takes a fundamentally different approach.

### The Problem with MCPs

MCP (Model Context Protocol) servers are the standard way to give Claude Code access to external tools — GitHub, databases, Docker, AWS, etc. Each MCP server injects its tool schemas into the context window at startup:

```
GitHub MCP:     ~8,000 tokens
Postgres MCP:   ~4,000 tokens
Docker MCP:     ~3,500 tokens
Fetch MCP:      ~2,000 tokens
...
A typical setup: 55,000-134,000 tokens before you type anything.
```

That's 25-67% of a 200K context window gone. You get fewer turns, worse recall, and degraded reasoning — all from tool overhead, not your actual work.

### CLI-over-MCP: The Core Idea

Every common MCP server has a CLI equivalent that's already installed on your system or can be. `gh` replaces GitHub MCP. `pgcli` replaces Postgres MCP. `docker` replaces Docker MCP. The difference: CLI tools cost **zero context tokens** because Claude Code already knows how to run shell commands via its built-in Bash tool.

The one exception is **episodic memory** — the `episodic-memory` plugin exposes MCP tools for semantic search across past Claude conversations. There is no CLI equivalent for this. Everything else is a CLI.

Instead of injecting 8,000 tokens of GitHub MCP schemas, Titan installs `gh` and teaches Claude to run `gh --help` when it needs to discover capabilities. The tool knowledge is lazy-loaded at runtime, not front-loaded at startup.

### What Titan Actually Does

Titan is a modularized bash script (~1860 lines) that transforms a fresh Ubuntu machine into a fully configured Claude Code workstation in one run. Static content (CLAUDE.md, agents, hooks, rules, skills, commands) is extracted to versioned repo files and installed via `install -Dm644/755`, keeping the script lean and updateable.

1. **155+ CLI tools** across 5 package managers (cargo, uv, bun, go, apt) — replacing every common MCP server
2. **Defense-in-depth safety** — 73 permission deny rules + PreToolUse hooks that block destructive commands (`rm -rf`, force push, `pip install`) before they execute
3. **Auto-linting pipeline** — every file write is async-linted (shellcheck for .sh, ruff for .py, hadolint for Dockerfile)
4. **Session persistence** — hooks automatically save/restore session state across conversations via handoff files and persistent memory
5. **Discovery-based skills** — 11 inline skills + 3 selective community skills, descriptions loaded at startup (~2-5K tokens)
6. **Audit trail** — every tool call logged to JSONL, desktop notifications, optional ntfy.sh alerts

### The Numbers

```
Titan startup cost:    ~1,700 tokens (CLAUDE.md + memory)
MCP equivalent:        55,000-134,000 tokens
Context savings:       98.5%+
Tools available:       155+ (vs ~20 typical MCP setup)
Safety rules:          73 deny rules + 17 hook-enforced blocks
```

You get **more tools with less overhead**, and the safety guardrails that MCPs don't provide.

### Design Principles

| Principle | What it means |
|-----------|--------------|
| **CLI over MCP** | Shell commands replace MCP servers — zero token overhead |
| **Discovery over documentation** | `--help` at runtime beats static docs at startup |
| **Hooks over instructions** | PreToolUse hooks _enforce_ rules; CLAUDE.md can only _suggest_ them |
| **Lazy over eager** | Skills, rules, commands load only when triggered |
| **Idempotent always** | Safe to re-run — every install checks before acting |

---

## What it installs

### Phase 1 — System Prerequisites
- APT packages: `jq`, `mtr`, `nmap`, `tmux`, `pandoc`, `direnv`, `entr`, `nikto`, `lynis`, `redis-tools`, `aria2`, `btop`, `build-essential`, `miller`, `inotify-tools`, `expect`, `asciinema`, `at`, `lnav`, `imagemagick`, `maim`, `xdotool`, `universal-ctags`, `chafa`, `libclang-dev`, `cmake`, `libxml2-dev`, `libcurl4-openssl-dev`
- Build dependencies: `libpulse-dev`, `libasound2-dev`, `libssl-dev`, `libdbus-1-dev`, `pkg-config` (for audio/cargo crates), `libpcre3-dev` (for comby)
- Linux tuning: inotify watchers (524288), file descriptor limits (65535)
- Git defaults: `main` branch, rebase pull, autocrlf input

### Phase 2 — Package Managers
| Manager | Replaces | Purpose |
|---------|----------|---------|
| **Rust/Cargo** | — | Rust CLI tools (rg, fd, bat, eza, etc.) + auto-updates via `rustup update` |
| **uv** | pip, pipx, pyenv, venv | Python CLI tools in isolated venvs |
| **bun** | npm, npx | JS CLI tools |
| **Go** | — | Go CLI tools (auto-upgrades when outdated) |
| **mise** | asdf, nvm, pyenv | Runtime version management |
| **Docker** | — | Container runtime (via get.docker.com) |

### Phase 3 — 155+ CLI Tools

**Python (via `uv tool install`):**
httpie, yq, semgrep, csvkit (12 commands), codespell, ansible-core (9 commands), ansible-lint, sqlmap, pgcli, litecli, awscli, ruff, ast-grep-cli, ccusage, sherlock-project, mitmproxy, cookiecutter, visidata

**Python (via `uv pip install`):**
sqlite-vec (local vector store / codebase indexing)

**JS (via `bun install -g`):**
trash-cli, tldr, prettier, repomix, gemini-cli, notebooklm-cli, kilocode, vercel, ccstatusline, @mermaid-js/mermaid-cli (mmdc), playwright

**Rust (via `cargo install`):**
ripgrep, fd-find, sd, eza, du-dust, bat, broot, zoxide, xsv, htmlq, git-cliff, git-absorb, git-delta, difftastic, onefetch, typos-cli, bandwhich, websocat, bore-cli, procs, bottom, hyperfine, pueue, watchexec-cli, just, starship, atuin, navi, choose, xh, mdbook, jnv, ouch, hurl, jwt-cli, oha, tree-sitter-cli, nu (nushell), recall (from git), parry (from git), spotify_player, claude-tmux (from git)

**Go (via `go install`):**
lazygit, dive, stern, glow, slides, mkcert, task, nuclei, ffuf, usql, grpcurl, actionlint, osv-scanner, hcloud, sops, doctl, doggo, age, claude-esp, gitleaks, gum, act, shfmt, gron, httpx, subfinder, dnsx, katana, cosign, crane, scc, dasel, claude-squad

**Binary downloads:**
kubectl, k9s, helm, terraform, packer, tflint, infracost, hadolint, duckdb, trivy, mc (MinIO), gh (GitHub CLI), fzf, shellcheck, yazi, lazydocker, ctop (v0.7.7 pinned), trufflehog (official script), dippy, infisical, cloudflared, syft, grype, step-cli, comby, runme

**Docker services (systemd user units):**
n8n (workflow automation — auto-starts on login, http://localhost:5678)

**Other:**
CLIProxyAPI (cloned to `~/tools/` — CLI proxy for API access)

### Phase 4 — Claude Code
- Native binary installer (auto-updates by default; `--no-autoupdate` flag disables via `DISABLE_AUTOUPDATER=1`)
- Claude Desktop (Linux, via community package) * — desktop mode only
- Claude Cowork Service (community package) * — desktop mode only

> \* Community packages from [patrickjaja.github.io](https://github.com/patrickjaja) — not official Anthropic releases. Review before installing.

### Phase 5 — `~/.claude/` Global Config

**CLAUDE.md** (~1200 tokens) — Tool routing tables, workflow rules, MCP replacement map, auto memory protocol, compaction protocol

**settings.json** — Hooks, permissions, environment, preferences:

*Environment variables (20+ total, zero context cost):*
- `PATH`: all tool directories injected as absolute paths for every session
- `CLAUDE_CODE_SUBAGENT_MODEL=haiku`: fast model for subagents (researcher uses Haiku by default)
- `CLAUDE_CODE_ENABLE_TASKS=1`: enable task list system for tracking work
- `CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS=8192`: large file read limit (tuned from 16000)
- `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90`: trigger compaction at 90% (tuned from 85)
- `CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1`: preserve working directory across commands
- `BASH_DEFAULT_TIMEOUT_MS=300000`: 5min default bash timeout (up from 2min)
- `BASH_MAX_TIMEOUT_MS=600000`: 10min max bash timeout
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`: reduce network noise
- `CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY=1`: no interruptions
- `CLAUDE_CODE_ENABLE_TELEMETRY=1`: OpenTelemetry export
- `CLAUDE_CODE_STATUSLINE=ccstatusline`: terminal status display
- `DISABLE_AUTOUPDATER=1`: prevents Claude Code auto-updates (only set if `--no-autoupdate` flag used)
- **VPS mode only:**
  - `TS_AUTHKEY`: Tailscale authentication key (required for VPS mode)
  - `TAILSCALE_PORT`: custom Tailscale port (optional, default 41641)

*Lifecycle hooks (16 events wired, all zero context cost):*
- `PreToolUse`: block destructive commands (rm -rf, force push, pip, npm, commits on main, chmod 777, kill -9, unsafe piping, infra/k8s/docker destruction)
- `PreToolUse` (file guard): block edits to .env, credentials, secrets, .pem, .key
- `PostToolUse` (lint): async auto-lint (shellcheck for .sh, ruff for .py, hadolint for Dockerfile)
- `PostToolUse` (audit): async JSONL logging of all tool calls
- `PostToolUseFailure`: async failure logging to `failures.jsonl`
- `Notification`: desktop notifications via `notify-send`
- `SubagentStop`: track subagent lifecycle in audit log + auto-unload agent slots if `AUTO_UNLOAD=true`
- `PreCompact`: auto-save session state before context compaction (JSONL pruning: >30 days, cap 15 sessions)
- `SessionStart`: display handoff + memory status + audit log rotation + show loaded agent slots
- `SessionEnd`: reliable final state capture at session termination (ntfy notification if `NTFY_URL` set)
- `UserPromptSubmit`: keyword-triggered memory injection (only on recall intent keywords)
- `TaskCompleted`: log task completions to audit trail
- `InstructionsLoaded`: track when CLAUDE.md/rules load
- `ConfigChange`: audit configuration changes mid-session
- `TeammateIdle`: track agent team coordination events
- `WorktreeCreate`/`WorktreeRemove`: reserved for future use

*Permissions:* 8 wildcard allow rules, 73 deny rules (Bash, Read, Edit, Write)

*Preferences & settings:*
- `cleanupPeriodDays: 30`: auto-delete conversation files >30 days old
- `model: opusplan`: Opus in plan mode (Shift+Tab), Sonnet in execution
- `showTurnDuration: true`: timing visibility per response
- `includeCoAuthoredBy: true`: auto-add Co-Authored-By to commits
- `respectGitignore: true`: respect .gitignore in file operations
- Tool search: `auto:5` threshold for deferred tool loading
- Plugin/marketplace config preserved across re-runs

**11 Inline Skills** (with `paths:` frontmatter for path-gated loading, ~203 lines always-on):
- `cli-tools` — Full reference for 155+ installed CLI tools by category
- `security-scan` — Pre-push, container, infra, network scanning workflows
- `git-workflow` — Branch naming, conventional commits, PR flow
- `infra-deploy` — Terraform, Ansible, Docker, K8s workflows
- `add-cli-tool` — Register new CLI tools across setup script + live config
- `tmux-control` — Create panes, send commands, read output, monitor processes
- `workspace` — `_workspace.json` convention, project auto-detection, `.envrc` templates
- `pueue-orchestrator` — Parallel task orchestration (lint + test + scan pipelines)
- `diagrams` — Generate architecture/flow/ER/sequence diagrams via mermaid-cli
- `deploy` — Auto-detect provider (Vercel/Docker/Terraform/K8s/Cloudflare), pre-deploy checks
- `process-supervisor` — Manage background services with systemd user units

**6 Conditional Rules** (loaded only when matching files are open, 0 tokens otherwise):
- `rules/python.md` — Type hints, ruff, uv, Python 3.10+ patterns
- `rules/shell.md` — shellcheck, set -euo pipefail, quoting rules
- `rules/terraform.md` — Plan before apply, tflint, infracost, state hygiene
- `rules/docker.md` — hadolint, trivy, syft/grype, multi-stage builds
- `rules/security.md` — Always active: gitleaks, no secrets, dependency scanning
- `rules/memory.md` — Always active: enforces memory discipline (write on debug fix, correction, decision)

**Memory/Context Management:**
- 3 hook scripts (`~/.claude/hooks/`) for automatic session state persistence
- `~/.claude/memory/handoff.md` — auto-generated cross-session state file (includes recent commits)
- `~/.claude/claudeignore-template` — copy to project roots to exclude build artifacts
- Enhanced `/catchup` command reads handoff.md + auto memory for warm-start
- CLAUDE.md compaction protocol preserves 7 critical context fields
- **Auto Memory Protocol** — mandatory rules for when Claude MUST write to persistent memory
- `rules/memory.md` — always-active rule enforcing memory discipline
- Session-start hook displays actual handoff content (not just "file exists")
- Audit log auto-rotation at 10MB (in session-start hook)

**GitHub Actions Integration:**
- `~/.claude/templates/claude-code-action.yml` — ready-to-use CI/CD template
- `/gh-action` command copies template and guides secret setup
- Auto code review on PRs, `@claude` mentions trigger agent in issues/comments

**Audit & Observability:**
- `~/.claude/logs/audit.jsonl` — async JSONL log of every tool call (timestamp, tool, input)
- Desktop notifications via `notify-send` on Notification lifecycle events
- ntfy.sh notification on session end (set `NTFY_URL` env var to enable)
- OpenTelemetry metrics export for usage tracking

**Community Skills** (selectively cloned from GitHub, with `paths:` path-gating):
- [obra/superpowers](https://github.com/obra/superpowers) — TDD, systematic debugging, brainstorming, verification before completion, writing plans (5 skills, ~150 lines always-on)
- [VibeSec](https://github.com/BehiSecc/VibeSec-Skill) — Web application security (OWASP Top 10, language-specific patterns) (1 skill, gated to .js/.ts/.py)
- [Trail of Bits modern-python](https://github.com/trailofbits/skills) — Modern Python best practices (1 skill, gated to .py files)
- [NotebookLM CLI](https://github.com/jacob-bd/notebooklm-cli) — Google NotebookLM skill (1 skill, optional)

> **v3.14 path-gating:** All community skills and 3 official plugins (episodic-memory, hookify, skill-creator) now have `paths:` frontmatter to reduce always-on context from 3,009 → 203 lines (~93% savings, ~42K tokens/turn). v3.6 removed full `trailofbits/skills` clone (60 SKILL.md / 71K lines) and full `hashicorp/agent-skills` clone (14 SKILL.md / 10K lines).

**11 Slash Commands** (loaded only when invoked):
- `/catchup` — Resume after /clear (reads git state + scratchpad + handoff.md)
- `/handoff` — Write session state to _handoff.md before ending
- `/ship` — Full pipeline: lint -> test -> scan -> commit -> push -> PR
- `/standup` — Generate standup from git history
- `/scan` — Security scan (secrets, vulns, IaC, containers)
- `/review` — Code review current branch against main
- `/tools` — List all installed CLI tools by package manager
- `/workspace-init` — Auto-detect project type, generate `_workspace.json` + `.envrc`
- `/remember` — Save knowledge to persistent memory across sessions
- `/gh-action` — Set up Claude Code GitHub Action for CI/CD integration
- `/context` — Pack repo into AI-optimized context file using repomix

**3 Built-In Subagents** (with model routing):
- `researcher` — Read-only codebase explorer (**Haiku** — fast, cheap for search tasks)
- `planner` — Architecture planning before implementation (**Opus** — deep reasoning)
- `reviewer` — Code review (correctness, security, style, performance, testing) (**Sonnet** — balanced)

**5 On-Demand Agent Slots** (v3.14):
- `slot-1`, `slot-2`, `slot-3` — **Haiku** (fast analysis/search/data wrangling)
- `slot-4` — **Sonnet** (balanced reasoning, general-purpose)
- `slot-5` — **Opus** (deep thinking, architecture, complex debugging)
- Each slot is a placeholder agent template that loads from agent-stash (~30 agents available)
- Managed via `agt` CLI: `agt search`, `agt load <agent>`, `agt unload`, `agt status`
- SessionStart hook shows loaded slots on stderr
- SubagentStop hook auto-unloads slots if `AUTO_UNLOAD=true`

**Model Routing:**
- Lead session: `opusplan` — Opus in plan mode (Shift+Tab), Sonnet in execution mode
- Subagent default: `CLAUDE_CODE_SUBAGENT_MODEL=haiku` (researcher uses Haiku by default)
- Per-agent overrides: `model:` field in agent frontmatter (haiku/sonnet/opus)
- Per-slot override: loaded agent inherits slot model (slot-1 = Haiku, slot-5 = Opus, etc.)

### Phase 5b — Claude Code Plugins
- [hookify](https://github.com/anthropics/claude-code-plugins) — Hook management and conversation analysis
- [code-review](https://github.com/anthropics/claude-code-plugins) — PR code review
- Marketplace: Anthropic official

> **Removed in v3.6:** `skill-creator` plugin (adds 6+ skills to startup context, only needed when authoring skills — install on-demand: `claude plugin install skill-creator`)

### Phase 6 — Shell Integration
- PATH: `~/.local/bin`, `~/.bun/bin`, `~/.cargo/bin`, `~/go/bin`, `/usr/local/go/bin`
- Prompts: starship
- Directory jumping: zoxide
- Shell history: atuin
- Env management: direnv
- Version management: mise
- Fuzzy finding: fzf
- Git diffs: delta (side-by-side, line numbers)
- Task queue: pueue daemon (auto-started)
- Pre-exec hooks: bash-preexec (required by atuin)

---

## Context Budget

```
Component           Startup cost     Notes
─────────────────── ──────────────── ──────────────────────────────────
System prompt        ~15K tokens     Built-in (unavoidable, includes tool defs)
CLAUDE.md (global)   ~800 tokens     Loaded every session
CLAUDE.md (project)  ~800 tokens     If present in project root
MEMORY.md            ~200 tokens     First 200 lines of auto memory
Skill descriptions   ~2-5K tokens    Name + description per skill (19 skills)
                                     NOTE: per bug #14882, full content may load
6 conditional rules  ~500 tokens     Loaded when matching file types are open
11 commands          0 tokens        Loaded only on /command invocation
3 agents             ~200 tokens     Descriptions in context, full on spawn
Hook scripts         0 tokens        External processes, never in context
settings.json        0 tokens        Parsed by harness, not injected
Audit log            0 tokens        Async JSONL, never loaded
CLI --help           0 tokens        Lazy-loaded at runtime
─────────────────── ──────────────── ──────────────────────────────────
Titan startup:       ~4-7K tokens    (excluding system prompt)

vs MCP equivalent:   55,000-134,000 tokens at startup
Savings:             94-97%
```

> **v3.5 had a hidden problem:** Full git clones of trailofbits (60 skills / 71K lines)
> and hashicorp (14 skills / 10K lines) were being auto-discovered by Claude Code,
> loading ~50-100K tokens at startup. Combined with `MAX_OUTPUT_TOKENS=64000` and
> `EFFORT_LEVEL=high`, this caused rapid 5-hour and weekly usage limit exhaustion.
> Fixed in v3.6 by selective skill installation and removing aggressive env vars.

---

## Package Manager Rules

```
Python CLIs -> uv tool install <pkg>
JS CLIs     -> bun install -g <pkg>
Rust CLIs   -> cargo install <crate>
Go CLIs     -> go install <path>@latest
System deps -> sudo apt install <pkg>

NEVER USE   -> pip install, npm install -g, sudo pip
```

The script blocks `pip install` and `npm install -g` at three levels:
1. **Permissions deny list** in settings.json (73 deny rules)
2. **PreToolUse hook** catches and redirects to uv/bun
3. **Your muscle memory** — this README reminds you

---

## Idempotent / Safe to Re-run

Every section checks before installing:
- `command -v <tool>` or `[ -f <path> ]` for binaries
- `uv tool list | grep` for Python tools
- `[ -d <dir> ]` for git-cloned skills
- Package managers skip already-installed packages
- Go and Rust toolchains auto-upgrade when outdated

Re-running the script will only install missing components.

---

## Post-Install Verification

```bash
source ~/.bashrc

# Check tool counts
echo "Cargo: $(ls ~/.cargo/bin/ | wc -l) tools"
echo "Go:    $(ls ~/go/bin/ | wc -l) tools"
echo "UV:    $(uv tool list 2>/dev/null | wc -l) tools"

# Check Claude Code
claude --version
claude doctor

# Check key tools
for cmd in rg fd bat eza jq yq gh docker kubectl terraform claude gitleaks; do
  printf "%-12s" "$cmd"
  command -v "$cmd" &>/dev/null && echo "✓ $(which $cmd)" || echo "✗ missing"
done
```

---

## For New Projects

The global `~/.claude/` config works everywhere. For project-specific needs, add a `CLAUDE.md` in the project root:

```markdown
# Project: my-app

## Architecture
- Next.js 15 app in src/
- PostgreSQL via Drizzle ORM
- Auth via Clerk

## Commands
- `bun dev` — dev server on :3000
- `bun test` — run tests
- `bun lint` — ESLint + Prettier

## Conventions
- Server components by default
- No `any` types
- All API routes in src/app/api/
```

---

## Changelog

### v3.14 (current) — Modularization, VPS mode, agent slots, token optimization

**Architecture:**
- **Modularized script** — Reduced from 3949 to 1863 lines. All static content (CLAUDE.md, agents, hooks, rules, skills, commands) extracted to `dot-claude/`, `bin/`, `config/` directories and installed via `install -Dm644/755` during script run
- **Dynamic installation** — Script clones repo at startup (`git clone --depth=1`) or uses `TITAN_REPO_FILES` env var for local testing
- **44 static files** — CLAUDE.md, 3 agents (researcher/planner/reviewer), 10 commands (/catchup, /handoff, /ship, etc.), 3 hooks (pre-compact, session-start, session-end, prompt-memory-inject), 5 rules (python, shell, terraform, docker, security/memory), 10 skills with path-gating, plus slot-template + agt CLI binary

**VPS Mode:**
- **New `--mode desktop|vps` flag** — Prompts interactively at startup if not supplied
- **Desktop mode** — Runs full install (default, same as before)
- **VPS mode** — Adds hardening + dedicated user creation:
  - Creates non-root `CLAUDE_USER` (default: `claude`, customizable via `--claude-user`)
  - Grants passwordless sudo, adds to docker group
  - Re-executes script under the new user (all installs in correct home dir)
  - Locks root account (`passwd -l root`) after setup
  - Installs Tailscale (mandatory — fails fast if `TS_AUTHKEY` not provided)
  - Hardens SSH: `PermitRootLogin no` (was `prohibit-password`)
  - UFW: opens 41641/udp for Tailscale, closes everything else
  - `tailscale serve --https` proxies n8n (5678) and better-ccflare (8080) with TLS
  - n8n/better-ccflare bound to 127.0.0.1 only — never exposed to network
  - Compliance audit: verifies root lock, PermitRootLogin setting, Tailscale, UFW rules
- **Desktop-only skipped on VPS** — maim, xdotool (X11), JetBrainsMono font, audio build deps, spotify_player, Claude Desktop GUI
- **VPS-skipped** — Claude Desktop and Claude Cowork Service are desktop-only; skipped in VPS mode
- **Supply chain allowlist extended** — Includes all repos added by titan-setup (Google Cloud, Aqua, HashiCorp, GitHub, Infisical, LaunchPad)

**Claude Code Flags:**
- **`--cc-version VERSION`** — Install specific Claude Code version (install/downgrade/reinstall). If set, always runs installer. If blank, skips install when claude already present. Prompts interactively if not supplied.
- **`--no-autoupdate`** — Patches `settings.json` post-write to add `DISABLE_AUTOUPDATER=1` env var (prevents auto-updates)

**Token Optimization (v3.14):**
- **Skill path-gating** — Added `paths:` frontmatter to all 10 skills + 3 community plugins (brainstorming, verification, writing-plans, episodic-memory, hookify, skill-creator). Reduces always-on context from 3,009 → 203 lines (~93% reduction, ~42K tokens/turn savings)
- **Restored `opusplan` model** — Was incorrectly changed to `claude-sonnet-4-6` in v3.13; reverted to official `opusplan` (Opus in plan mode, Sonnet in execution)
- **Plugin SKILL.md auto-patching** — New `_patch_plugin_skill()` function injects `paths:` into plugin SKILL.md files at install time (prevents 918+ always-on plugin lines)

**On-Demand Agent Slots (Phase B):**
- **agt CLI** — New binary at `~/.local/bin/agt` (included in modularized repo)
- **5 agent slots** — `~/.claude/agents/slot-1..5/` with model routing:
  - slot-1/2/3: Haiku (fast search/analysis)
  - slot-4: Sonnet (balanced reasoning)
  - slot-5: Opus (deep thinking)
- **Bootstrap agent-stash** — 30 pre-built agents (https://github.com/SutanuNandigrami/agent-stash) cloned on first run
- **agt commands** — `agt search`, `agt load`, `agt unload`, `agt status`, `agt info`, `agt refresh`, `agt build-index`
- **AUTO_UNLOAD hook** — SubagentStop hook unloads slots when `AUTO_UNLOAD=true` (prevents stale agent retention)
- **SessionStart summary** — Shows loaded slot agents on stderr at startup

**better-ccflare Improvements:**
- **Built from source** — No longer binary-only; cloned from source + patched to fix NULL constraint on account creation
- **Zero interactive prompts** — All menu prompts removed from script (configure post-install if needed)
- **Fallback service file path detection** — Resolves binary path at install time for systemd unit

**Bug Fixes:**
- **Trap overwrite** — Fixed line 1083 `trap EXIT` clobbering line 109's trap; now uses `_CLEANUP_DIRS` array + `_do_cleanup()` fn
- **Step function** — Fixed `step()` calling smallstep binary instead of printing status; renamed to `ok()`
- **Crontab pipefail** — Fixed `crontab -l | grep -v` exiting 1 on empty crontab (with set -euo pipefail in subshell); added `|| true`
- **agt manifest unload** — Fixed `grep -v | mv &&` race where mv never ran if grep exited 1; now `|| true` then separate `mv` line
- **Cargo reinstall** — Skip reinstall for already-installed crates (speeds up re-runs)
- **Mise activation** — Properly activate mise during script run; install Node via mise
- **uv PATH order** — Fixed uv tool PATH priority so installed tools take precedence
- **chmod redundancy** — Removed 6x `chmod +x` after `install -Dm755` (install sets mode atomically)
- **Better-ccflare dist path** — Check dist path before trying to build
- **Playwright chromium on VPS** — Removed desktop-only gate; chromium now installs on VPS too via `playwright install-deps chromium` (sudo for apt deps) + `playwright install chromium` (user download). Works fully headless.
- **Temp script perms** — Fixed `chmod a+rx` on temp script so `sudo -u titan` can read it
- **Process substitution crash** — `bash <(curl ...)` sets `$0=/dev/fd/63` (a pipe). When script did `exec sudo -u titan bash "$0"`, the new process couldn't access that fd. Script now self-materializes to `/tmp/titan-XXXXXX.sh` (`chmod a+rx`) and re-execs from the real file.

**Total: 155+ CLI tools, 11 inline skills + 3 community, 6 rules, 11 commands, 16 hook events, 5 agents (3 built-in + 5 slots), 3 plugins, 18+ env vars**

### v3.13 — Token optimization (model routing, JSONL prune, hook fixes)

- **Model routing** — Introduced subagent model selection (Haiku/Sonnet/Opus) for researcher/planner/reviewer agents
- **JSONL pruning** — Pre-compact script now prunes session files >30 days old, caps total at 15 main sessions
- **Hook fixes** — Fixed SessionStart matcher (was firing on every resume, wasting tokens); UserPromptSubmit hook now keyword-triggered instead of always-on
- **Impact** — Estimated 20-30% reduction in per-session token usage

### v3.12 (previous) — 8 bug fixes: verbose flag, install failures, ccflare overhaul

- **Added:** `--verbose`/`-v` flag — subprocess output silenced by default, routed to `/tmp/titan-setup-TIMESTAMP.log`
- **Fixed:** `claude-agent-sdk` on Ubuntu 24.04 — added `--break-system-packages` to pip3 install
- **Fixed:** `n8n` not starting — `loginctl enable-linger` + `usermod -aG docker` for systemd user service
- **Fixed:** `step-cli` — switched to `github.com/smallstep/cli/releases` (old `dl.smallstep.com` URL broken)
- **Fixed:** `runme` — use direct `latest/download` URL (GitHub API was returning null version)
- **Fixed:** `episodic-memory` — removed incorrect `bun install -g` (it's a plugin, installed via `claude plugin install`)
- **Fixed:** `better-ccflare` provider menu — removed non-existent `vertex-ai` mode; added all 9 real modes (console, bedrock, kilo, minimax, nanogpt, etc.); fixed double-prompt loop bug; dotenv noise suppressed
- **Fixed:** Backup config message — `warn` → `ok` (informational, not a warning)

### v3.5
- Fixed: PATH exports for cargo, uv, bun moved outside install if/else branches — tools were invisible on re-runs when already installed
- Fixed: Added `PATH` to Claude Code `settings.json` env block with expanded absolute paths — tools like `gitleaks` in `~/go/bin` are now discoverable in every Claude Code session without sourcing `.bashrc`
- Fixed: README audit — corrected permission counts (8 allow, 73 deny), command count (11 not 12), tool count (155+), CLAUDE.md token estimate (~1200), added missing tools/features
- Added: "Why Titan" section explaining CLI-over-MCP architecture and design principles
- Added: 8 new power env vars — `MAX_OUTPUT_TOKENS=64000`, `EFFORT_LEVEL=high`, `AUTOCOMPACT_PCT=85`, `BASH_TIMEOUT=5m/10m`, `MAINTAIN_PROJECT_CWD`, `DISABLE_NONESSENTIAL_TRAFFIC`, `DISABLE_FEEDBACK_SURVEY`
- Added: `SUBAGENT_MODEL=sonnet` — faster model for subagents while lead uses Opus
- Added: `ENABLE_TASKS=1` — task list system for tracking work across sessions
- Added: `FILE_READ_MAX_OUTPUT_TOKENS=16000` — larger file reads
- Added: 5 new lifecycle hooks — `SessionEnd`, `PostToolUseFailure`, `SubagentStop`, `TaskCompleted`, `TeammateIdle`
- Added: 2 audit hooks — `InstructionsLoaded`, `ConfigChange` for tracking config/rules changes
- Added: `teammateMode: tmux`, `showTurnDuration: true`, `includeCoAuthoredBy: true`, `respectGitignore: true`
- Added: `claude-agent-sdk` via uv — programmatic agent building
- Total: 155+ CLI tools, 11 skills, 6 rules, 11 commands, 13 hook events, 1 template, 3 agents, 3 plugins, 18 env vars

### v3.11 — better-ccflare: full setup wizard with CLI flags

- **Added:** Full provider account wizard during install — add Claude OAuth, Vertex AI, Z.ai, OpenAI-compatible (OpenRouter/Together/Ollama), or Anthropic-compatible accounts interactively with name/priority prompts
- **Added:** 7 new CLI flags for unattended installs: `--ccflare-skip`, `--ccflare-port`, `--ccflare-host`, `--ccflare-proxy`, `--ccflare-loglevel`, `--ccflare-oauth`, `--ccflare-vertex`
- **Added:** `--ccflare-skip` exits the entire better-ccflare section; all dashboard references suppressed
- **Added:** Port/host/loglevel flags flow through to systemd service file — no hardcoded 8080
- **Added:** Provider menu loops — add multiple providers in one run, or skip entirely to configure later
- **Changed:** Dashboard browser-open and SSH tunnel hint use `$CCFLARE_PORT` variable

### v3.10 — better-ccflare: multi-account Claude load balancer

- **Added:** `better-ccflare` install via `bun install -g` + systemd user service
- **Added:** Interactive y/N prompt for `ANTHROPIC_BASE_URL` in `~/.bashrc`
- **Added:** Dashboard launcher: GUI opens browser; headless VPS prints URLs + SSH tunnel command

### v3.9 — Context audit: skill scoping + JSONL pruning

- **Fixed:** 4 large skills (vibesec 758L, tdd 371L, nlm-cli 350L, systematic-debugging 296L) had no `paths:` frontmatter — per bug #14882, all skill content loads at startup; added `paths:` scoping so each skill only loads when relevant file types are open
- **Fixed:** `trailofbits-modern-python` had SKILL.md buried at `skills/modern-python/SKILL.md` — Claude Code couldn't load it; created root `SKILL.md` with proper `paths:` scoping for Python files
- **Added:** JSONL session file pruning to `pre-compact.sh` — deletes files >180 days old, caps total at 30; prevents unbounded disk accumulation
- **Impact:** Startup context reduced by up to 1,775 lines (vibesec+tdd+nlm+sysdbg) on typical non-web/non-test sessions; Python sessions now get modern-python guidance for the first time

### v3.8 — Smart memory: on-demand retrieval, zero startup cost

- **Fixed:** `SessionStart` hook `matcher: ""` fired on every startup AND every resume — changed to `matcher: "startup|compact"` (skips redundant resume firing, always fires post-compaction for amnesia prevention)
- **Fixed:** `UserPromptSubmit` hook `echo 'Success'` was injecting the word "Success" as context into every single prompt — replaced with keyword-triggered memory injection (`prompt-memory-inject.sh`)
- **Added:** `~/.claude/hooks/prompt-memory-inject.sh` — fires on EVERY prompt but injects memory content ONLY when recall-intent keywords detected (`recall`, `remember`, `last session`, `previously`, `we decided`, `history`, `memory`). Zero tokens on all other prompts.
- **Added:** `/recall` slash command — on-demand surface of MEMORY.md + topic files + handoff. No startup cost.
- **Removed:** Dead sqlite-vec / vectordb infrastructure — was installed but never connected to anything; vectordb dir was empty
- **Fixed:** Misleading `recall` cargo binary comment — it's a flashcard CLI (zippoxer/recall), not conversation search
- **Token cost:** Current session startup = 0 tokens from memory system. `/recall` = ~300 tokens only when invoked.

### v3.7.1 — Fix install breakages after claude update

- **Fixed:** `claude-agent-sdk` install — `uv pip install --system` blocked on Ubuntu 24.04 externally-managed Python; switched to `pip3 install --user`
- **Fixed:** `claude-squad` install — `go install github.com/smtg-ai/claude-squad@latest` fails due to go.mod module path mismatch (`claude-squad` ≠ `github.com/smtg-ai/claude-squad`); switched to binary download from GitHub releases
- **Note:** claude-squad was NOT removed by v3.6 — that removed the built-in `AGENT_TEAMS` env var; claude-squad is a separate tmux-based multi-agent tool

### v3.7 — Output verbosity + model call reduction

- **Removed:** `outputStyle: "explanatory"` — this actively instructed Claude to be verbose on every request AND injected mid-conversation reminders; removing it re-enables the default concise output mode
- **Removed:** `thinking: true` — enabled extended thinking globally, adding 1K–10K thinking tokens per turn; use `/think` or plan mode when extended reasoning is actually needed
- **Added:** `DISABLE_NON_ESSENTIAL_MODEL_CALLS=1` — suppresses AI-generated flavor text (spinner verbs, decorative status messages) that consume real model tokens
- **Impact:** Estimated 20-40% further reduction in per-turn output token cost; thinking mode is now opt-in

### v3.6 — Token Usage Optimization
- **Fixed:** Full `trailofbits/skills` git clone (60 SKILL.md / 71K lines) replaced with selective `modern-python` only (1 skill)
- **Fixed:** Full `hashicorp/agent-skills` git clone (14 SKILL.md / 10K lines) removed — covered by inline `infra-deploy` skill
- **Removed:** `CLAUDE_CODE_MAX_OUTPUT_TOKENS=64000` — was 2x default, each response could burn 64K tokens
- **Removed:** `CLAUDE_CODE_EFFORT_LEVEL=high` — forced extended thinking on every request regardless of complexity
- **Removed:** `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` — each teammate clones full context (~7x token usage)
- **Removed:** `teammateMode: tmux` — agent teams disabled by default
- **Removed:** `skill-creator` plugin — adds 6+ skills to startup context, install on-demand when needed
- **Removed:** `extraKnownMarketplaces` for trailofbits — individual plugins installable via `claude plugin marketplace add`
- **Added:** Cleanup step removes old full trailofbits/hashicorp clones on re-run
- **Fixed:** Context Budget section in README — was claiming "0 tokens" for skills, actual was 50-100K
- **Added:** `opusplan` as default model — Opus for planning (Shift+Tab), Sonnet for execution
- **Added:** Per-agent model routing — researcher (Haiku), planner (Opus), reviewer (Sonnet)
- **Impact:** ~60-70% reduction in per-session token usage, ~30-50% reduction in per-turn cost
- Total: 155+ CLI tools, 11 skills + 8 community, 6 rules, 11 commands, 13 hook events, 1 template, 3 agents, 2 plugins, 15 env vars

### v3.3
- Added: `claude-squad` (Go) — multi-agent terminal management with tmux
- Added: Async PostToolUse audit logging to `~/.claude/logs/audit.jsonl`
- Added: Async PostToolUse lint hooks (non-blocking file writes)
- Added: ntfy.sh notification on session stop (`NTFY_URL` env var)
- Added: OpenTelemetry telemetry export (`CLAUDE_CODE_ENABLE_TELEMETRY=1`)
- Added: Agent Teams support (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`)
- Added: GitHub Actions template (`~/.claude/templates/claude-code-action.yml`)
- Added: `/gh-action` command for CI/CD setup
- Added: `enabledPlugins` and `extraKnownMarketplaces` in settings.json heredoc (survives re-runs)
- Added: `logs/` and `templates/` directories in mkdir
- Total: 155+ CLI tools, 11 skills, 5 rules, 10 commands, 3 hooks, 1 template, 3 plugins

### v3.2
- Added: Memory/context management system (PreCompact, Stop, SessionStart hooks)
- Added: Auto-generated `~/.claude/memory/handoff.md` for cross-session state persistence
- Added: 5 conditional rules files (python, shell, terraform, docker, security)
- Added: `.claudeignore` template for project context hygiene
- Added: Enhanced CLAUDE.md compaction protocol (7 preserved fields)
- Added: 24 new CLI tools (18 + 6 from previous commit), removed tokei (superseded by scc)
- Added: `lnav`, `imagemagick`, `maim`, `xdotool` to system packages
- Added: `cookiecutter`, `visidata` (uv), `playwright` (bun), `nu`/nushell (cargo), `act` (go), `cloudflared` (binary)
- Added: universal-ctags, chafa (apt), tree-sitter-cli, hurl, jwt-cli, oha (cargo)
- Added: gron, httpx, subfinder, dnsx, katana, cosign, crane, scc, dasel (go)
- Added: repomix (bun), comby, runme (binary), syft, grype, step-cli (binary)
- Added: ouch, shfmt, prettier (previous commit)
- Added: 2 new skills — `deploy` (auto-detect provider), `process-supervisor` (systemd user units)
- Added: `/remember` command for persistent cross-session memory
- Updated: `/catchup` command reads handoff.md for warm-start
- Updated: Security-scan skill with recon pipeline and supply chain sections
- Total: 150+ CLI tools, 11 skills, 5 rules, 9 commands, 3 hooks, 3 plugins

### v3.0
- Added: CLI options `--name`, `--dry-run`, `--help` for public use
- Added: Architecture detection (x86_64/aarch64) for all binary downloads
- Added: `inotify-tools`, `expect`, `asciinema`, `at` to system packages
- Added: `mitmproxy` (uv), `mermaid-cli` (bun), `jnv` (cargo), `gum` (go)
- Added: `sqlite-vec` for local vector store / codebase indexing
- Added: 4 new skills — `tmux-control`, `workspace`, `pueue-orchestrator`, `diagrams`
- Added: `/workspace-init` command for project setup
- Added: `pueued` daemon auto-start in shell integration
- Added: `bash-preexec` download + source (fixes atuin history recording)
- Fixed: All downloads use temp dir instead of CWD
- Fixed: Version fetches validated before use (Go, lazydocker, shellcheck)
- Fixed: Unconditional success messages (k9s, helm, hadolint, fzf)
- Fixed: Bun/uv one-off installs now skip if already installed
- Fixed: Deprecated `apt-key` replaced with `signed-by` keyring for trivy
- Fixed: `--name` arg guard against missing value
- Fixed: `sd` fallback to `sed` if cargo install failed
- Security: Added disclaimer for `curl|bash` installs and community packages
- Removed: All hardcoded personal info (parameterized via `--name`)

### v2.3
- Fixed: `lazydocker` go install broken (Docker API conflict) -> binary release download
- Fixed: `mkcert` wrong Go module path (`github.com/FiloSottile/mkcert` -> `filippo.io/mkcert`)
- Fixed: `age` wrong Go module path (`github.com/FiloSottile/age` -> `filippo.io/age`)
- Fixed: `claude-tmux` wrong repo and language (`ngroeneveld` Go -> `nielsgroen/claude-tmux` Rust via cargo)
- Fixed: Script crash at "Claude Code ecosystem tools:" — double `||` failure + `set -e` killed the process
- Fixed: `# shellcheck` comment parsed as shellcheck directive -> reworded
- Security: Added `Write` deny rules for `~/.bashrc`, `~/.profile`, `~/.zshrc`, `~/.ssh/*`, `.env*`
- Security: Fixed newline bypass in PreToolUse hooks (`read` -> `read -r -d ''`)
- Security: Added branch check hook — blocks `git commit` on main/master
- Fixed: PostToolUse lint hook now triggers on `Edit|MultiEdit` too, not just `Write`
- Fixed: Notification hook uses direct variable instead of `xargs` (safer with metacharacters)
- Removed: `debug-protocol` inline skill (replaced by `systematic-debugging` from superpowers)
- Replaced: `tool-discovery` (39 lines) -> `cli-tools` (150 lines, full categorized reference)
- Replaced: `security-ops` (13 lines) -> `security-scan` (39 lines, structured workflows)
- Replaced: `infra-ops` (14 lines) -> `infra-deploy` (45 lines, step-by-step procedures)
- Removed: `owasp` skill (536 lines, massive overlap with vibesec)
- Security: Added `git checkout -- .` and `git checkout .` to deny list
- Fixed: PostToolUse lint hook now warns when linter binary is missing (was silent)
- Fixed: `/review` command now specifies the `reviewer` subagent
- Added: Project-level `CLAUDE.md` for titan context
- Security: Added `Bash(rm -r *)`, `Bash(git reset --hard *)`, `Bash(git clean -f*)` to deny list
- Security: Hook now catches `rm -r -f` and `rm --recursive` variants (not just `rm -rf`)
- Fixed: `dog` -> `doggo` in cli-tools skill (wrong tool name)
- Removed: Auto-generated `ansible` and `docker` junk skills (empty/meaningless content, covered by `infra-deploy` and `cli-tools`)
- Fixed: `dasel` removed from cli-tools skill (was never installed)
- Fixed: `gcloud` removed from cli-tools skill (was never installed)
- Added: `gitleaks` to Go installs (was referenced in CLAUDE.md/skills but never installed)
- Added: `miller` to apt installs (was referenced in CLAUDE.md/skills but never installed)
- Added: 15 missing tools to cli-tools skill (parry, sherlock, ruff, infisical, vercel, gemini-cli, claude-tmux, claude-esp, recall, ccusage, ccstatusline, dippy, spotify_player + new AI Tools category)
- Added: `add-cli-tool` inline skill — registers new CLI tools across setup script + live config in one operation

### v2.2
- Fixed: `spotify-tui` removed (abandoned, OpenSSL build broken) -> replaced with `spotify_player` (actively maintained)
- Fixed: `ccstatusline` was cargo (wrong) -> now `bun install -g` (it's an npm package)
- Fixed: `ctop` binary URL pinned to v0.7.7 (archived project, `/latest/` redirect broken)
- Fixed: `trufflehog` install script now runs with `sudo` (writes to `/usr/local/bin`)
- Fixed: `claude-tmux` tries `cmd/claude-tmux@latest` path first with fallback
- Fixed: `n8n` removed from bun (too large, it's a server) -> `docker pull n8nio/n8n`
- Fixed: `dippy` binary path corrected to `bin/dippy-hook` (not `bin/dippy`)
- Fixed: `skill-seekers` removed (generates static doc dumps, contradicts lazy-loading)
- Added: `spotify_player` with audio build dependencies (`libpulse-dev`, etc.)
- Added: `recall` via `cargo install --git` (NOT the crates.io package)
- Added: `parry` via `cargo install --git` (prompt injection scanner)
- Added: `sherlock-project`, `ccusage` via uv
- Added: `gemini-cli`, `notebooklm-cli`, `kilocode`, `vercel`, `ccstatusline` via bun
- Added: `infisical` CLI via official apt repo
- Added: `CLIProxyAPI` cloned to `~/tools/`
- Added: `notebooklm-cli` skill from GitHub

### v2.1
- Fixed: Go tools now skip if already installed (was reinstalling every run)
- Fixed: `slides` path corrected (`maaslalani/slides`, not `charmbracelet`)
- Fixed: `age` binary name extraction (was showing as `...`)
- Fixed: `trufflehog` uses official install script (go install doesn't work)
- Fixed: `ctop` uses binary download (project archived, go install fails)
- Fixed: Removed non-existent cargo crates (`recall`, `dippy`, `parry-ai`)
- Fixed: Git clones check if directory exists before cloning
- Fixed: `skill-seekers` wrapped in existence check
- Fixed: `apt autoremove` now has `-y` flag
- Fixed: Echo parentheses syntax error
- Fixed: `ansible-core` instead of `ansible` meta-package

### v2.0
- Replaced pip with uv, npm with bun
- CLI-over-MCP architecture (98.5% context savings)
- Hooks: safety guardrails + auto-linting
- Discovery-over-documentation skill design

### v1.0 (deprecated)
- Used pip install --break-system-packages
- Used npm install -g
- No existence checks, no idempotency
