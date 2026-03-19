# Titan Setup

**One script. Fresh Ubuntu → fully armed Claude Code workstation.**

> **Note:** The authoritative source is [github.com/SutanuNandigrami/claude-titan-setup](https://github.com/SutanuNandigrami/claude-titan-setup). The old `titan-setup` repo is archived.

---

## Table of Contents

- [What Does This Do?](#what-does-this-do)
- [Quick Install](#quick-install)
- [After Install](#after-install)
- [Prerequisites](#prerequisites)
- [Why CLI Over MCP?](#why-cli-over-mcp)
- [What Gets Installed](#what-gets-installed)
- [Letta / Subconscious Memory](#letta--subconscious-memory)
- [VPS Mode](#vps-mode)
- [Context Budget](#context-budget)
- [For New Projects](#for-new-projects)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [Changelog](#full-changelog)
- [Tool Reference](#detailed-tool-reference)

---

## What Does This Do?

Titan is a single bash script that transforms a fresh Ubuntu system into a complete AI development workstation with **125+ CLI tools**, **Claude Code configuration**, **security hardening** (VPS mode), and **automated workflows**.

In plain English:

| What | How |
|------|-----|
| Installs 125+ tools | Python, Node, Rust, Go, Docker, Kubernetes tools, security scanners, terminal enhancers |
| Configures Claude Code | Sets up `~/.claude/` with hooks, skills, commands, agents, and token optimization |
| Adds smart safety | Permission rules, destructive command blocks, file guards, git protections |
| Runs idempotently | Safe to re-run — existing tools are skipped, missing ones are installed |

---

## Quick Install

### Local machine (desktop/laptop)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SutanuNandigrami/claude-titan-setup/main/titan-setup.sh)
```

**With your name:**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SutanuNandigrami/claude-titan-setup/main/titan-setup.sh) --name "Alice"
```

**Or clone and run locally:**
```bash
git clone https://github.com/SutanuNandigrami/claude-titan-setup.git
cd claude-titan-setup && ./titan-setup.sh --name "Alice"
```

### VPS / server (hardened mode)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SutanuNandigrami/claude-titan-setup/main/titan-setup.sh) --mode vps --tailscale-key tskey-...
```

### All options

**Core:**

| Flag | Description |
|------|-------------|
| `--name "Alice"` | Personalize your setup |
| `--mode desktop\|vps` | Installation profile (prompted interactively if omitted) |
| `--cc-version VERSION` | Pin a specific Claude Code version |
| `--no-autoupdate` | Disable Claude Code auto-updates |
| `--semgrep-token TOKEN` | Add Semgrep token for security scanning |
| `--no-semgrep` | Skip Semgrep setup (no prompt) |
| `--no-cozempic` | Skip cozempic context cleaner install |
| `--dry-run` | Preview what will happen without making changes |
| `-v`, `--verbose` | Log all output to `/tmp/titan-setup-<timestamp>.log` |
| `--version` | Show Titan version |

**VPS:**

| Flag | Description |
|------|-------------|
| `--tailscale-key KEY` | Tailscale auth key (required for VPS mode) |
| `--claude-user USER` | Non-root user for Claude Code (created if absent) |

**Services:**

| Flag | Description |
|------|-------------|
| `--ccflare-skip` | Skip better-ccflare proxy install |
| `--ccflare-port PORT` | better-ccflare port (default: 8080) |
| `--ccflare-host HOST` | better-ccflare bind address (default: 127.0.0.1) |
| `--semgrep-token TOKEN` | Semgrep App Token (enables semgrep plugin) |
| `--no-semgrep` | Skip Semgrep setup entirely |
| `--letta-skip` | Skip Letta server + claude-subconscious plugin |
| `--letta-port PORT` | Letta server port (default: 8283) |
| `--letta-password PASS` | Letta server password (auto-generated if omitted) |
| `--no-ollama` | Skip Ollama LLM server |
| `--letta-ctrl-skip` | Skip LettaCtrl web GUI |
| `--letta-ctrl-port PORT` | LettaCtrl port (default: 8284) |

---

## After Install

1. **Source your shell config:**
   ```bash
   source ~/.bashrc
   ```

2. **Authenticate with Claude:**
   ```bash
   claude auth login
   ```

3. **Verify the setup:**
   ```bash
   claude --version && claude doctor
   ```

4. **Verify installed plugins:**
   ```bash
   claude plugin list
   ```
   Titan installs: `hookify` · `code-review` · `skill-creator` · `episodic-memory` · `claude-subconscious` (if Letta enabled) · `cozempic` · `semgrep` (if token provided)

5. **Quick sanity check:**
   ```bash
   # Check tool counts
   echo "Cargo: $(ls ~/.cargo/bin/ 2>/dev/null | wc -l) tools"
   echo "Go:    $(ls ~/go/bin/ 2>/dev/null | wc -l) tools"
   echo "UV:    $(uv tool list 2>/dev/null | wc -l) tools"

   # Test key tools
   for cmd in rg fd bat eza jq gh docker kubectl terraform; do
     command -v "$cmd" &>/dev/null && echo "✓ $cmd" || echo "✗ $cmd missing"
   done
   ```

---

## Prerequisites

| Requirement | Detail |
|-------------|--------|
| OS | Ubuntu 22.04+ (Debian-based systems supported) |
| Architecture | x86_64 or aarch64/arm64 (auto-detected; a few tools are amd64-only and skip gracefully) |
| Permissions | `sudo` access required (non-root initial user is fine — OCI, AWS, Azure) |
| Network | Internet access for downloads (can be offline after first run) |
| Time | ~30–45 minutes first run (Rust crates compile) |
| VPS mode | Tailscale auth key required (`--tailscale-key`) |

---

## Why CLI Over MCP?

Claude Code is powerful out of the box — but typical setups waste context before you type a word. MCP servers inject tool schemas at startup:

```
GitHub MCP:     ~8,000 tokens
Postgres MCP:   ~4,000 tokens
Docker MCP:     ~3,500 tokens
Fetch MCP:      ~2,000 tokens
─────────────────────────────
Total overhead: 55,000–134,000 tokens before you ask anything
```

That's 25–67% of your 200K context window gone to tool schemas before reasoning even starts.

### The Better Way

Every common MCP server has a free, fast CLI equivalent that costs **zero context tokens**:

| MCP Server | CLI Alternative | Token Cost |
|------------|-----------------|-----------|
| GitHub MCP | `gh` (GitHub CLI) | 0 |
| Postgres MCP | `pgcli` | 0 |
| Docker MCP | `docker` | 0 |
| Fetch MCP | `xh` | 0 |
| File search | `rg` + `fd` | 0 |

Instead of injecting 55K tokens of schemas, Titan installs 125+ CLI tools and teaches Claude to run `<tool> --help` at runtime. Tool knowledge is discovered on-demand, not pre-loaded.

### The Result

```
Typical MCP setup:  55–134K tokens at startup
Titan setup:        ~4–7K tokens
Savings:            94–97%
More tools:         125+ vs ~20
Better recall:      Fewer turns consumed by overhead
```

---

## What Gets Installed

### System Packages (apt)

Standard utilities: `jq`, `mtr`, `nmap`, `tmux`, `pandoc`, `direnv`, `entr`, `nikto`, `lynis`, `redis-tools`, `aria2`, `btop`, `miller`, `inotify-tools`, `expect`, `asciinema`, `lnav`, `imagemagick`, `universal-ctags`, `chafa` + build dependencies for Rust/Go crates.

Desktop only: `maim`, `xdotool`.

### Package Managers

| Manager | Purpose |
|---------|---------|
| **Rust / cargo** | Rust CLI tools (ripgrep, fd, bat, etc.) + auto-upgrade |
| **uv** | Python CLI tools (semgrep, ansible, pgcli, etc.) |
| **bun** | JavaScript CLI tools (prettier, repomix, ccstatusline, etc.) |
| **Go** | Go CLI tools (dive, stern, glow, etc.) |
| **mise** | Runtime version management (Node, Python, Go, Ruby) |
| **Docker** | Container runtime |

### 125+ CLI Tools

**Python (uv):** yq · semgrep · ansible-core · ansible-lint · sqlmap · pgcli · ruff · ast-grep-cli · mitmproxy · cookiecutter · nlm · cozempic · ccusage · sherlock

**JS (bun):** trash-cli · tldr · prettier · repomix · gemini-cli · ccstatusline · mermaid-cli · playwright · kilocode · vercel

**Rust (cargo):** ripgrep · fd · sd · eza · dust · bat · xsv · htmlq · git-absorb · git-delta · difftastic · typos-cli · websocat · bore-cli · procs · hyperfine · pueue · watchexec · just · choose · xh · ouch · hurl · jwt-cli · oha · rtk · nushell · recall · parry · claude-tmux

**Go:** dive · stern · glow · mkcert · task · nuclei · ffuf · usql · grpcurl · actionlint · osv-scanner · hcloud · sops · doggo · gitleaks · act · shfmt · gron · httpx · subfinder · dnsx · katana · scc · age · ctop · claude-esp · claude-squad

**Binary:** kubectl · helm · gcloud · terraform · packer · tflint · infracost · hadolint · duckdb · trivy · mc · gh · shellcheck · step-cli · comby · cloudflared · infisical · dippy

**Docker services:** n8n (workflow automation, localhost:5678) · Letta (persistent memory, localhost:8283)

### Claude Code Configuration

**~/.claude/settings.json:**
- 20+ environment variables (zero token cost)
- 14 lifecycle hooks (permission enforcement, audit logging, auto-lint)
- 73 deny rules (blocks rm -rf, pip/npm install, commits to main, etc.)
- 8 allow rules for safe operations
- `opusplan` model (Opus in plan mode, Sonnet for execution)

**~/.claude/ directory:**

| Component | Count | Description |
|-----------|-------|-------------|
| Skills | 15 | Trimmed, self-contained (vibesec, cli-tools, modern-python, security-scan, etc.) |
| Plugins (MCP) | 5–7 | hookify, code-review, skill-creator, episodic-memory, claude-subconscious (if Letta), cozempic, semgrep (if token) |
| Hook events | 14 | PreToolUse (safety), PostToolUse (audit), SessionStart (memory), etc. |
| Conditional rules | 6 | Trigger on file type (Python, shell, terraform, docker, security) |
| Slash commands | 12 | `/ship`, `/scan`, `/review`, `/workspace-init`, `/remember`, etc. |
| Built-in agents | 3 | researcher (Haiku), planner (Opus), reviewer (Sonnet) |
| On-demand agent slots | 5 | Load from agent-stash library via `agt` CLI |

---

## Letta / Subconscious Memory

Titan optionally installs [Letta](https://github.com/letta-ai/letta) — a persistent memory server that gives Claude long-term memory across sessions via the `claude-subconscious` plugin.

| Service | Port | Purpose |
|---------|------|---------|
| Letta | 8283 | Memory server (Docker, bundles Postgres+pgvector) |
| Ollama | 11434 | Local embeddings (`nomic-embed-text`) |
| better-ccflare | 8080 | Claude load balancer proxy |
| LettaCtrl | 8284 | Web GUI for agents and memory blocks |

All services run as systemd user units. Credentials are auto-generated at `~/.config/letta/credentials`.

```bash
./titan-setup.sh --letta-skip       # Skip Letta entirely
./titan-setup.sh --no-ollama        # Skip Ollama only
./titan-setup.sh --letta-ctrl-skip  # Skip GUI only
```

---

## VPS Mode

VPS mode (`--mode vps`) adds server hardening, Tailscale networking, and service exposure on top of the standard workstation install.

**Hardening:** SSH password auth disabled, fail2ban, auditd, unattended-upgrades, APT repo allowlist, root account locked.

**Networking:** Tailscale (WireGuard) provides network-level isolation. SSH restricted to Tailscale IP. Services exposed via `tailscale serve` on HTTPS.

**Compliance:** Automated checks run at boot +5min and every 6h (`sudo /usr/local/bin/compliance_check.sh`).

**SSH resilience:** Install runs in a `titan-setup` tmux session. Reconnect after drop: `tmux attach -t titan-setup`.

---

## Context Budget

How much context Titan consumes at startup vs. a typical MCP setup:

```
Component             Startup cost    Notes
──────────────────    ─────────────   ──────────────────────────────────────
System prompt         ~15K tokens     Built-in (unavoidable, includes tool defs)
CLAUDE.md (global)    ~800 tokens     Loaded every session
CLAUDE.md (project)   ~800 tokens     If present in project root
MEMORY.md             ~200 tokens     First 200 lines of auto memory
Skill descriptions    ~2–3K tokens    15 skills (trimmed, self-contained)
Conditional rules     ~500 tokens     Only when matching file types are open
Slash commands        0 tokens        Loaded only on /command invocation
Built-in agents       ~200 tokens     Descriptions only
Hooks, settings       0 tokens        External processes / parsed by harness
──────────────────    ─────────────   ──────────────────────────────────────
Titan startup:        ~4–7K tokens    (excluding system prompt)
MCP equivalent:       55–134K tokens
Savings:              94–97%
```

Tools like `rg --help`, `fd --help`, `docker --help` load at runtime (0 tokens until invoked).

---

## For New Projects

The global `~/.claude/` config works everywhere. For project-specific context, create a `CLAUDE.md` in your project root:

```markdown
# Project: my-app

## Architecture
- Next.js 15 frontend in src/
- PostgreSQL backend via Drizzle ORM
- Auth via Clerk
- Hosted on Vercel

## Commands
- `bun dev` — dev server on :3000
- `bun test` — run tests
- `bun build` — production build

## Conventions
- Server components by default
- No `any` types in TypeScript
- All PRs require gitleaks scan
```

---

## Troubleshooting

### Script died mid-install

The script is **idempotent** — safe to re-run. Every install section checks before acting (`command -v`, `uv tool list`, etc.). Missing steps will be installed; existing tools are skipped.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SutanuNandigrami/claude-titan-setup/main/titan-setup.sh)
```

### Claude not found after install

Source your shell config:
```bash
source ~/.bashrc
claude --version
```

### Plugins not installing

Requires Claude authentication:
```bash
claude auth login
```

Then install plugins:
```bash
claude plugin marketplace add anthropic/claude-plugins-official
claude plugin install hookify code-review skill-creator
claude plugin marketplace add obra/superpowers-marketplace
claude plugin install episodic-memory
# semgrep — only if you have a token from semgrep.dev
claude plugin install semgrep
```

### RTK not working

Verify RTK is installed:
```bash
~/.cargo/bin/rtk gain
```

Or test directly:
```bash
which rtk && rtk --version
```

If missing, re-run titan-setup (Rust phase will re-install).

### VPS install fails with "Permission denied" on sudoers

Fixed in v3.17. On OCI, AWS, and Azure the initial SSH user (`ubuntu`, `ec2-user`) is not root. Re-run with the latest script:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SutanuNandigrami/claude-titan-setup/main/titan-setup.sh) --mode vps
```

### SSH disconnected during VPS install

Reconnect to the tmux session:
```bash
tmux attach -t titan-setup
```

The script runs inside a named `titan-setup` session and survives SSH drops. Log: `/tmp/titan-setup-<timestamp>.log`.

### Letta not starting

Check the systemd service:
```bash
systemctl --user status letta
journalctl --user -u letta -f
```

Postgres init can take 30–60s on first run. If the container keeps restarting, check Docker logs:
```bash
docker logs letta-server
```

### Tool missing that should be installed

Check if it's on the right PATH:
```bash
source ~/.bashrc
echo $PATH
```

Then verify the tool install location:
```bash
ls ~/.cargo/bin/ | grep <tool>   # Rust tools
ls ~/go/bin/ | grep <tool>       # Go tools
uv tool list | grep <tool>       # Python tools
```

If still missing, re-run titan-setup — idempotent installs pick up whatever was skipped.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for build instructions and development workflow.

---

## Full Changelog

All changes documented in [CHANGELOG.md](CHANGELOG.md). Key versions:

| Version | Highlights |
|---------|-----------|
| **v3.18** | GitHub Action security hardening — prompt injection prevention |
| **v3.17** | ARM64 fixes, VPS reliability, consistency audit, `--version` flag |
| **v3.16** | tmux resilience, Vertex AI RTK fix, Semgrep integration |
| **v3.15** | RTK token compression (60–90% reduction), 125+ tools |
| **v3.14** | Modularization, VPS mode, agent slots, path-gated skills |
| **v3.13** | Token optimization (JSONL pruning, per-agent model routing) |
| **v3.6** | Token savings (94–97% reduction vs. MCP) |

---

## Detailed Tool Reference

See [USER_GUIDE.md](USER_GUIDE.md) for comprehensive documentation of:
- 125+ CLI tools (what they do, example prompts)
- Built-in agents (researcher, planner, reviewer)
- Slash commands (`/ship`, `/scan`, `/review`, etc.)
- Claude Code ecosystem (ccusage, rtk, better-ccflare, ccstatusline)
- Security tools and scanning patterns
- Network and system monitoring
- Container and Kubernetes tools
- Best practices and workflows

---

**Built for security engineers and cloud operators. Ready for AI-accelerated development.**
