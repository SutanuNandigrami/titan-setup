# Titan Setup

**One script. Fresh Ubuntu to fully armed Claude Code workstation.**

```bash
chmod +x titan-setup.sh
./titan-setup.sh
source ~/.bashrc
claude    # authenticate
```

That's it. No other scripts, no tar files, no manual steps.

---

## What it installs

### Phase 1 — System Prerequisites
- APT packages: `jq`, `mtr`, `nmap`, `tmux`, `pandoc`, `direnv`, `entr`, `nikto`, `lynis`, `redis-tools`, `aria2`, `btop`, `build-essential`, `miller`
- Linux tuning: inotify watchers (524288), file descriptor limits (65535)
- Git defaults: `main` branch, rebase pull, autocrlf input

### Phase 2 — Package Managers
| Manager | Replaces | Purpose |
|---------|----------|---------|
| **Rust/Cargo** | — | Rust CLI tools (rg, fd, bat, eza, etc.) |
| **uv** | pip, pipx, pyenv, venv | Python CLI tools in isolated venvs |
| **bun** | npm, npx | JS CLI tools |
| **Go** | — | Go CLI tools |
| **mise** | asdf, nvm, pyenv | Runtime version management |

### Phase 3 — 100+ CLI Tools

**Python (via `uv tool install`):**
httpie, yq, semgrep, csvkit (12 commands), codespell, ansible-core (9 commands), sqlmap, pgcli, litecli, awscli, ruff, ast-grep-cli, ccusage, sherlock-project

**JS (via `bun install -g`):**
trash-cli, tldr, gemini-cli, notebooklm-cli, kilocode, vercel, ccstatusline

**Rust (via `cargo install`):**
ripgrep, fd-find, sd, eza, du-dust, bat, broot, zoxide, xsv, htmlq, git-cliff, git-absorb, git-delta, difftastic, onefetch, typos-cli, bandwhich, websocat, bore-cli, procs, bottom, hyperfine, pueue, watchexec-cli, just, starship, atuin, navi, choose, xh, mdbook, tokei, recall (from git), parry (from git), spotify_player, claude-tmux (from git)

**Go (via `go install`):**
lazygit, dive, stern, glow, slides, mkcert, task, nuclei, ffuf, usql, grpcurl, actionlint, osv-scanner, hcloud, sops, doctl, doggo, age, claude-esp, gitleaks

**Binary downloads:**
kubectl, k9s, helm, terraform, packer, tflint, infracost, hadolint, duckdb, trivy, mc (MinIO), gh (GitHub CLI), fzf, shellcheck, yazi, lazydocker (binary release), ctop (v0.7.7 pinned), trufflehog (official script), dippy, infisical

**Docker images:**
n8n (workflow automation server)

### Phase 4 — Claude Code
- Native binary installer (auto-updates, no Node.js dependency)
- Claude Desktop (Linux, via community package)
- Claude Cowork Service

### Phase 5 — `~/.claude/` Global Config

**CLAUDE.md** (~800 tokens) — Tool routing tables, workflow rules, MCP replacement map

**settings.json** — Hooks, permissions, tool search optimization:
- PreToolUse hooks: block `rm -rf`, force push, `pip install`, `npm -g`, commits on main/master
- PostToolUse hooks: auto-lint on write/edit (shellcheck → .sh, ruff → .py, hadolint → Dockerfile)
- Permissions: 70+ allow rules, 22 deny rules (including Write denies for sensitive paths)
- Tool search: `auto:5` threshold for MCP lazy loading

**5 Inline Skills** (loaded on demand, 0 startup tokens):
- `cli-tools` — Full reference for 100+ installed CLI tools by category (162 lines)
- `security-scan` — Pre-push, container, infra, network scanning workflows (39 lines)
- `git-workflow` — Branch naming, conventional commits, PR flow
- `infra-deploy` — Terraform, Ansible, Docker, K8s workflows (45 lines)
- `add-cli-tool` — Register new CLI tools across setup script + live config (~90 lines)

**Community Skills** (cloned from GitHub):
- [obra/superpowers](https://github.com/obra/superpowers) — TDD, systematic debugging, root cause tracing, defense in depth, brainstorming
- [VibeSec](https://github.com/BehiSecc/VibeSec-Skill) — Web application security (OWASP Top 10, language-specific patterns)
- [HashiCorp](https://github.com/hashicorp/agent-skills) — Terraform agent skills
- [Trail of Bits](https://github.com/trailofbits/skills) — Security analysis skills
- [NotebookLM CLI](https://github.com/jacob-bd/notebooklm-cli) — Google NotebookLM skill

**7 Slash Commands** (loaded only when invoked):
- `/catchup` — Resume after /clear (reads git state + scratchpad)
- `/handoff` — Write session state to _handoff.md before ending
- `/ship` — Full pipeline: lint → test → scan → commit → push → PR
- `/standup` — Generate standup from git history
- `/scan` — Security scan (secrets, vulns, IaC, containers)
- `/review` — Code review current branch against main
- `/tools` — List all installed CLI tools by package manager

**2 Subagents:**
- `researcher` — Read-only codebase explorer
- `planner` — Architecture planning before implementation

### Phase 6 — Shell Integration
- PATH: `~/.local/bin`, `~/.bun/bin`, `~/.cargo/bin`, `~/go/bin`
- Prompts: starship
- Directory jumping: zoxide
- Shell history: atuin
- Env management: direnv
- Version management: mise
- Fuzzy finding: fzf
- Git diffs: delta (side-by-side, line numbers)

---

## Context Budget

```
CLAUDE.md:        ~800 tokens  (loaded every session)
settings.json:    0 tokens     (parsed by harness)
5 inline skills:  0 tokens     (loaded on demand by relevance, ~340 lines total)
community skills: 0 tokens     (loaded on demand)
7 commands:       0 tokens     (loaded on /command)
2 agents:         0 tokens     (loaded on spawn)
CLI --help:       0 tokens     (lazy-loaded at runtime)
─────────────────────────────────────
Total startup:    ~800 tokens of 200,000

vs MCP equivalent: 55,000-134,000 tokens at startup
Savings:           98.5%+
```

---

## Package Manager Rules

```
Python CLIs → uv tool install <pkg>
JS CLIs     → bun install -g <pkg>
Rust CLIs   → cargo install <crate>
Go CLIs     → go install <path>@latest
System deps → sudo apt install <pkg>

NEVER USE   → pip install, npm install -g, sudo pip
```

The script blocks `pip install` and `npm install -g` at three levels:
1. **Permissions deny list** in settings.json
2. **PreToolUse hook** catches and redirects to uv/bun
3. **Your muscle memory** — this README reminds you

---

## Idempotent / Safe to Re-run

Every section checks before installing:
- `command -v <tool>` or `[ -f <path> ]` for binaries
- `uv tool list | grep` for Python tools
- `[ -d <dir> ]` for git-cloned skills
- Package managers skip already-installed packages

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
for cmd in rg fd bat eza jq yq gh docker kubectl terraform claude; do
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

### v2.3 (current)
- Fixed: `lazydocker` go install broken (Docker API conflict) → binary release download
- Fixed: `mkcert` wrong Go module path (`github.com/FiloSottile/mkcert` → `filippo.io/mkcert`)
- Fixed: `age` wrong Go module path (`github.com/FiloSottile/age` → `filippo.io/age`)
- Fixed: `claude-tmux` wrong repo and language (`ngroeneveld` Go → `nielsgroen/claude-tmux` Rust via cargo)
- Fixed: Script crash at "Claude Code ecosystem tools:" — double `||` failure + `set -e` killed the process
- Fixed: `# shellcheck` comment parsed as shellcheck directive → reworded
- Security: Added `Write` deny rules for `~/.bashrc`, `~/.profile`, `~/.zshrc`, `~/.ssh/*`, `.env*`
- Security: Fixed newline bypass in PreToolUse hooks (`read` → `read -r -d ''`)
- Security: Added branch check hook — blocks `git commit` on main/master
- Fixed: PostToolUse lint hook now triggers on `Edit|MultiEdit` too, not just `Write`
- Fixed: Notification hook uses direct variable instead of `xargs` (safer with metacharacters)
- Removed: `debug-protocol` inline skill (replaced by `systematic-debugging` from superpowers)
- Replaced: `tool-discovery` (39 lines) → `cli-tools` (150 lines, full categorized reference)
- Replaced: `security-ops` (13 lines) → `security-scan` (39 lines, structured workflows)
- Replaced: `infra-ops` (14 lines) → `infra-deploy` (45 lines, step-by-step procedures)
- Removed: `owasp` skill (536 lines, massive overlap with vibesec)
- Security: Added `git checkout -- .` and `git checkout .` to deny list
- Fixed: PostToolUse lint hook now warns when linter binary is missing (was silent)
- Fixed: `/review` command now specifies the `reviewer` subagent
- Added: Project-level `CLAUDE.md` for titan context
- Security: Added `Bash(rm -r *)`, `Bash(git reset --hard *)`, `Bash(git clean -f*)` to deny list
- Security: Hook now catches `rm -r -f` and `rm --recursive` variants (not just `rm -rf`)
- Fixed: `dog` → `doggo` in cli-tools skill (wrong tool name)
- Removed: Auto-generated `ansible` and `docker` junk skills (empty/meaningless content, covered by `infra-deploy` and `cli-tools`)
- Fixed: `dasel` removed from cli-tools skill (was never installed)
- Fixed: `gcloud` removed from cli-tools skill (was never installed)
- Added: `gitleaks` to Go installs (was referenced in CLAUDE.md/skills but never installed)
- Added: `miller` to apt installs (was referenced in CLAUDE.md/skills but never installed)
- Added: 15 missing tools to cli-tools skill (parry, sherlock, ruff, infisical, vercel, gemini-cli, claude-tmux, claude-esp, recall, ccusage, ccstatusline, dippy, spotify_player + new AI Tools category)
- Fixed: Duplicate "Removed: owasp skill" changelog entry
- Added: `add-cli-tool` inline skill — registers new CLI tools across setup script + live config in one operation

### v2.2
- Fixed: `spotify-tui` removed (abandoned, OpenSSL build broken) → replaced with `spotify_player` (actively maintained)
- Fixed: `ccstatusline` was cargo (wrong) → now `bun install -g` (it's an npm package)
- Fixed: `ctop` binary URL pinned to v0.7.7 (archived project, `/latest/` redirect broken)
- Fixed: `trufflehog` install script now runs with `sudo` (writes to `/usr/local/bin`)
- Fixed: `claude-tmux` tries `cmd/claude-tmux@latest` path first with fallback
- Fixed: `n8n` removed from bun (too large, it's a server) → `docker pull n8nio/n8n`
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