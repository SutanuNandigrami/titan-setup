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

# Preview without making changes
bash <(curl -fsSL https://raw.githubusercontent.com/SutanuNandigrami/titan-setup/main/titan-setup.sh) --dry-run

# Or clone and run locally
git clone https://github.com/SutanuNandigrami/titan-setup.git && cd titan-setup
./titan-setup.sh --name "Alice"
```

After install: `source ~/.bashrc && claude` to authenticate.

### Prerequisites
- **OS:** Ubuntu 22.04+ (or Debian-based)
- **Arch:** x86_64 or aarch64 (auto-detected)
- **Access:** `sudo` required for system packages and binary installs
- **Network:** Internet access for downloads
- **Time:** ~30-45 minutes on first run (Rust crates compile from source)

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

Every MCP server has a CLI equivalent that's already installed on your system or can be. `gh` replaces GitHub MCP. `pgcli` replaces Postgres MCP. `docker` replaces Docker MCP. The difference: CLI tools cost **zero context tokens** because Claude Code already knows how to run shell commands via its built-in Bash tool.

Instead of injecting 8,000 tokens of GitHub MCP schemas, Titan installs `gh` and teaches Claude to run `gh --help` when it needs to discover capabilities. The tool knowledge is lazy-loaded at runtime, not front-loaded at startup.

### What Titan Actually Does

Titan is a single bash script (~2800 lines) that transforms a fresh Ubuntu machine into a fully configured Claude Code workstation in one run:

1. **155+ CLI tools** across 5 package managers (cargo, uv, bun, go, apt) — replacing every common MCP server
2. **Defense-in-depth safety** — 73 permission deny rules + PreToolUse hooks that block destructive commands (`rm -rf`, force push, `pip install`) before they execute
3. **Auto-linting pipeline** — every file write is async-linted (shellcheck for .sh, ruff for .py, hadolint for Dockerfile)
4. **Session persistence** — hooks automatically save/restore session state across conversations via handoff files and persistent memory
5. **Discovery-based skills** — 11 inline skills and 5 community skill sets loaded on demand, not at startup
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
- Native binary installer (auto-updates, no Node.js dependency)
- Claude Desktop (Linux, via community package) *
- Claude Cowork Service *

> \* Community packages from [patrickjaja.github.io](https://github.com/patrickjaja) — not official Anthropic releases. Review before installing.

### Phase 5 — `~/.claude/` Global Config

**CLAUDE.md** (~1200 tokens) — Tool routing tables, workflow rules, MCP replacement map, auto memory protocol, compaction protocol

**settings.json** — Hooks, permissions, environment, preferences:
- `PATH` env: all tool directories (`~/.cargo/bin`, `~/go/bin`, `~/.bun/bin`, `~/.local/bin`) injected as absolute paths so tools are discoverable in every Claude Code session
- PreToolUse hooks: block `rm -rf`, force push, `pip install`, `npm -g`, commits on main/master, `chmod 777`, `kill -9`, unsafe piping, destructive infra/k8s/docker operations
- PostToolUse hooks: async auto-lint on write/edit (shellcheck for .sh, ruff for .py, hadolint for Dockerfile)
- PostToolUse audit hook: async JSONL logging of all tool calls to `~/.claude/logs/audit.jsonl`
- Notification hook: desktop notifications via `notify-send`
- PreCompact hook: auto-saves session state (branch, files, context) to `~/.claude/memory/handoff.md`
- Stop hook: captures final state + sends ntfy notification (configurable via `NTFY_URL` env var)
- SessionStart hook: displays handoff content + memory status + audit log rotation
- Permissions: 8 wildcard allow rules, 73 deny rules (Bash, Read, Edit, Write — covering destructive commands, sensitive files, credential paths)
- Preferences: `thinking: true`, `outputStyle: explanatory`, `cleanupPeriodDays: 365`
- Tool search: `auto:5` threshold for deferred tool loading
- OpenTelemetry export: `CLAUDE_CODE_ENABLE_TELEMETRY=1`
- Agent Teams: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` for parallel Claude instances in git worktrees
- Status line: `CLAUDE_CODE_STATUSLINE=ccstatusline` for terminal status display
- Plugin/marketplace config preserved across re-runs (`enabledPlugins`, `extraKnownMarketplaces`)

**11 Inline Skills** (loaded on demand, 0 startup tokens):
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

**Community Skills** (cloned from GitHub):
- [obra/superpowers](https://github.com/obra/superpowers) — TDD, systematic debugging, brainstorming, verification before completion, writing plans
- [VibeSec](https://github.com/BehiSecc/VibeSec-Skill) — Web application security (OWASP Top 10, language-specific patterns)
- [HashiCorp](https://github.com/hashicorp/agent-skills) — Terraform agent skills
- [Trail of Bits](https://github.com/trailofbits/skills) — Security analysis skills
- [NotebookLM CLI](https://github.com/jacob-bd/notebooklm-cli) — Google NotebookLM skill

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

**3 Subagents:**
- `researcher` — Read-only codebase explorer
- `planner` — Architecture planning before implementation
- `reviewer` — Code review (correctness, security, style, performance, testing)

### Phase 5b — Claude Code Plugins
- [hookify](https://github.com/anthropics/claude-code-plugins) — Hook management and conversation analysis
- [code-review](https://github.com/anthropics/claude-code-plugins) — PR code review
- [skill-creator](https://github.com/anthropics/claude-code-plugins) — Create and optimize skills
- Marketplaces: Anthropic official + Trail of Bits

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
CLAUDE.md:          ~1200 tokens (loaded every session, includes memory protocol + compaction)
settings.json:      0 tokens    (parsed by harness, not injected into context)
11 inline skills:   0 tokens    (loaded on demand by relevance, ~800 lines total)
6 conditional rules: 0 tokens   (loaded only when matching file types are open)
community skills:   0 tokens    (loaded on demand)
11 commands:        0 tokens    (loaded on /command)
1 template:         0 tokens    (copied on /gh-action)
3 hook scripts:     0 tokens    (fire at lifecycle events, output stays external)
3 agents:           0 tokens    (loaded on spawn)
audit log:          0 tokens    (async JSONL, never loaded into context)
CLI --help:         0 tokens    (lazy-loaded at runtime)
MEMORY.md:          ~200 tokens (loaded every session, persistent project knowledge)
handoff.md:         ~300 tokens (shown by session-start hook, cross-session state)
─────────────────────────────────────
Total startup:      ~1,700 tokens of 200,000

vs MCP equivalent: 55,000-134,000 tokens at startup
Savings:            98.5%+
```

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

### v3.5 (current)
- Fixed: PATH exports for cargo, uv, bun moved outside install if/else branches — tools were invisible on re-runs when already installed
- Fixed: Added `PATH` to Claude Code `settings.json` env block with expanded absolute paths — tools like `gitleaks` in `~/go/bin` are now discoverable in every Claude Code session without sourcing `.bashrc`
- Fixed: README audit — corrected permission counts (8 allow, 73 deny), command count (11 not 12), tool count (155+), CLAUDE.md token estimate (~1200), added missing tools/features
- Added: "Why Titan" section explaining CLI-over-MCP architecture and design principles
- Total: 155+ CLI tools, 11 skills, 6 rules, 11 commands, 3 hooks, 1 template, 3 agents, 3 plugins

### v3.4
- Added: **Auto Memory Protocol** — mandatory rules in CLAUDE.md for when Claude MUST write to persistent memory
- Added: `rules/memory.md` — always-active conditional rule enforcing memory discipline
- Added: Session-start hook now displays actual handoff content (not just "file exists") + memory count
- Added: Audit log auto-rotation at 10MB (in session-start hook)
- Added: Recent commits captured in handoff.md (both pre-compact and session-end)
- Added: `/context` command — pack repo with repomix for AI-optimized context
- Fixed: `/remember` command — removed hardcoded path, now uses dynamic auto memory directory
- Fixed: `/catchup` command — now reads auto memory + handoff.md
- Fixed: Cargo crates failing randomly — added `libclang-dev`, `cmake`, `libxml2-dev`, `libcurl4-openssl-dev` to apt deps
- Fixed: Cargo install now falls back to `--locked` before giving up
- Fixed: n8n permission error (`~/.n8n` owned by root) — now fixes ownership to uid 1000
- Changed: n8n runs as systemd user service (auto-starts, survives reboots, http://localhost:5678)
- Added: `reviewer` agent to script (was live-only, would be lost on re-run)
- Fixed: Superpowers skills updated to match upstream repo (root-cause-tracing/defense-in-depth -> verification-before-completion/writing-plans)
- Fixed: Live config fully synced with script (CLAUDE.md, cli-tools, security-scan, researcher agent)
- Total: 155+ CLI tools, 11 skills, 6 rules, 11 commands, 3 hooks, 1 template, 3 agents, 3 plugins

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
