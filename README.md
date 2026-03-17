# Titan Setup

**One script. Fresh Ubuntu to fully armed Claude Code workstation.**

> **Note:** This repo has moved. The authoritative source is now [github.com/SutanuNandigrami/claude-titan-setup](https://github.com/SutanuNandigrami/claude-titan-setup). The old `titan-setup` repo is archived.

---

## What Does This Do?

Titan is a single bash script that transforms a fresh Ubuntu system into a complete AI development workstation with **155+ CLI tools**, **Claude Code configuration**, **security hardening** (VPS mode), and **automated workflows**. 

In plain English:

- **Installs everything you need** — Python, Node, Rust, Go, Docker, Kubernetes tools, security scanners, terminal enhancers, plus 110+ other CLI utilities
- **Sets up Claude Code** — configures `~/.claude/` with hooks, skills, commands, agents, and token optimization
- **Adds smart safety** — permission rules, destructive command blocks, file guards, git protections
- **Works offline** — runs idempotently (safe to re-run), doesn't require constant internet

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

### Advanced options

```bash
# Pin a specific Claude Code version
./titan-setup.sh --cc-version 1.2.3

# Disable Claude Code auto-updates
./titan-setup.sh --no-autoupdate

# Provide semgrep token (for security scanning integration)
./titan-setup.sh --semgrep-token scu_... 

# Skip semgrep (no prompt)
./titan-setup.sh --no-semgrep

# Preview without making changes
./titan-setup.sh --dry-run

# Verbose output to file
./titan-setup.sh --verbose
```

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

3. **Install semgrep plugin (if you have a token):**
   ```bash
   claude plugin install semgrep
   ```

4. **Verify the setup:**
   ```bash
   claude --version && claude doctor
   ```

5. **Optional: sync shell history across machines:**
   ```bash
   atuin login
   ```

---

## Prerequisites

| Requirement | Detail |
|-------------|--------|
| OS | Ubuntu 22.04+ (Debian-based systems supported) |
| Architecture | x86_64 or aarch64 (auto-detected) |
| Permissions | `sudo` access required |
| Network | Internet access for downloads (can be offline after first run) |
| Time | ~30–45 minutes first run (Rust crates compile) |
| VPS mode | Tailscale auth key required (`--tailscale-key`) |

---

## Why CLI Over MCP?

Claude Code is powerful out of the box — but it wastes context before you type a word. Typical setups inject multiple MCP servers at startup:

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
| Fetch MCP | `xh` (httpie) | 0 |
| File search | `rg` + `fd` | 0 |

Instead of injecting 55K tokens of schemas, Titan installs 155+ CLI tools and teaches Claude to run `<tool> --help` at runtime. Tool knowledge is discovered on-demand, not pre-loaded.

### The Result

```
Typical MCP setup:  55–134K tokens at startup
Titan setup:        ~4–7K tokens
Savings:            94–97%
More tools:         155+ vs ~20
Better recall:      Fewer turns consumed by overhead
```

---

## What Gets Installed

Titan installs four categories of tools: system packages, package managers, **155+ CLI tools**, and Claude Code configuration. Here's what you get:

### System Packages (apt)

Standard utilities: `jq`, `mtr`, `nmap`, `tmux`, `pandoc`, `direnv`, `entr`, `nikto`, `lynis`, `redis-tools`, `aria2`, `btop`, `miller`, `inotify-tools`, `expect`, `asciinema`, `lnav`, `imagemagick`, `universal-ctags`, `chafa` + build dependencies for Rust/Go crates.

Desktop only: `maim`, `xdotool`.

### Package Managers

| Manager | Purpose |
|---------|---------|
| **Rust / cargo** | Rust CLI tools (ripgrep, fd, bat, etc.) + auto-upgrade |
| **uv** | Python CLI tools (semgrep, ansible, pgcli, etc.) |
| **bun** | JavaScript CLI tools (prettier, repomix, ccstatusline, etc.) |
| **Go** | Go CLI tools (lazygit, dive, stern, etc.) |
| **mise** | Runtime version management (Node, Python, Go, Ruby) |
| **Docker** | Container runtime |

### 155+ CLI Tools

**Python (uv):** httpie · yq · semgrep · csvkit · codespell · ansible-core · sqlmap · pgcli · awscli · ruff · ast-grep-cli · sherlock · mitmproxy · visidata · nlm (NotebookLM)

**JS (bun):** trash-cli · tldr · prettier · repomix · gemini-cli · ccstatusline · playwright · vercel

**Rust (cargo):** ripgrep · fd · sd · eza · bat · zoxide · xsv · htmlq · git-cliff · difftastic · ouch · hurl · jwt-cli · oha · rtk (Rust Token Killer, now built from source with Vertex AI null-fix)

**Go:** lazygit · dive · glow · mkcert · task · nuclei · ffuf · usql · gitleaks · gum · act · shfmt · gron · httpx · subfinder · dnsx · katana · cosign · crane · dasel

**Binary:** kubectl · k9s · helm · terraform · duckdb · trivy · gh · fzf · shellcheck · yazi · lazydocker · trufflehog · syft · grype · step-cli · comby · cloudflared

**Docker services:** n8n (workflow automation, localhost:5678)

### Claude Code Configuration

**~/.claude/settings.json:**
- 20+ environment variables (zero token cost)
- 14 lifecycle hooks (permission enforcement, audit logging, auto-lint)
- 73 deny rules (blocks rm -rf, pip/npm install, commits to main, etc.)
- Permissions: 8 allow rules for safe operations
- `opusplan` model (Opus in plan mode, Sonnet for execution)

**~/.claude/ directory:**
- `CLAUDE.md` — tool routing, workflow rules, auto memory protocol
- **11 inline skills** (path-gated, load only for matching files) — cli-tools, security-scan, git-workflow, infra-deploy, etc.
- **Community skills** — superpowers, modern-python, NotebookLM, VibeSec (selectively installed, path-gated)
- **14 hook events** — PreToolUse (safety), PostToolUse (audit), SessionStart (memory), etc.
- **6 conditional rules** — trigger on file type (Python, shell, terraform, docker, security)
- **11 slash commands** — `/ship`, `/scan`, `/review`, `/workspace-init`, `/remember`, etc.
- **3 built-in agents** — researcher (Haiku), planner (Opus), reviewer (Sonnet)
- **5 on-demand agent slots** — load from agent-stash library via `agt` CLI

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
claude plugin install semgrep
claude plugin install code-review
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

### SSH disconnected during VPS install

Reconnect to the tmux session:
```bash
tmux attach -t titan-setup
```

The script runs inside a named `titan-setup` session and survives SSH drops. Log: `/tmp/titan-setup-<timestamp>.log`.

---

## Full Changelog

All changes documented in [CHANGELOG.md](CHANGELOG.md). Key versions:

- **v3.16** — tmux resilience, Vertex AI RTK fix, semgrep integration
- **v3.15** — RTK token compression (60–90% reduction)
- **v3.14** — modularization, VPS mode, agent slots
- **v3.13** — token optimization (JSONL pruning)
- **v3.6** — token savings (94–97% reduction)

---

## Detailed Tool Reference

See [USER_GUIDE.md](USER_GUIDE.md) for comprehensive documentation of:
- 155+ CLI tools (what they do, example prompts)
- Built-in agents (researcher, planner, reviewer)
- Claude Code ecosystem (ccusage, rtk, better-ccflare, ccstatusline)
- Security tools and scanning patterns
- Network and system monitoring
- Container and Kubernetes tools
- Best practices and workflows

---

## Post-Install Verification

```bash
source ~/.bashrc

# Check tool installation counts
echo "Cargo: $(ls ~/.cargo/bin/ 2>/dev/null | wc -l) tools"
echo "Go:    $(ls ~/go/bin/ 2>/dev/null | wc -l) tools"
echo "UV:    $(uv tool list 2>/dev/null | wc -l) tools"

# Claude Code status
claude --version && echo "✓ Claude Code installed"

# Test key tools
for cmd in rg fd bat eza jq gh docker kubectl terraform; do
  command -v "$cmd" &>/dev/null && echo "✓ $cmd" || echo "✗ $cmd missing"
done
```

---

**Built for security engineers and cloud operators. Ready for AI-accelerated development.**
