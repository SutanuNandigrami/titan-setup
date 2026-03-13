---
name: cli-tools
description: Reference for 100+ installed CLI tools. Use when working with any CLI tool, searching files, processing data, managing containers, infrastructure, security scanning, or system monitoring.
---

# CLI Tool Arsenal

You have 100+ CLI tools installed. Before using any tool,
run `<tool> --help` or `<tool> -h` to learn its current syntax and flags.
Never guess flags — always check help first.

## Tool Reference by Task

**Search & Find:**
- `rg` (ripgrep) — fast recursive text search. Use over grep always.
- `fd` — find files by name/pattern. Use over `find` always.
- `fzf` — pipe anything into it for fuzzy selection.
- `ast-grep` — search code by AST structure, not text patterns.
- `comby` — structural search/replace that understands code syntax (strings, comments, blocks).
- `ctags` — generate symbol index. Run `ctags -R .` then query tags file for fast navigation.

**File Viewing & Management:**
- `bat` — view files with syntax highlighting. Use over `cat` for code.
- `eza` — list files with git status. Use over `ls`.
- `dust` — check disk usage visually. Use over `du`.
- `broot` — interactive directory navigation.
- `yazi` — full terminal file manager when needed.
- `zoxide` — smart directory jumping.
- `ouch` — universal compress/decompress (tar, zip, 7z, zstd, gz, xz, bz2).

**Text & Data Wrangling:**
- `jq` — JSON processing. Always use for JSON manipulation.
- `yq` — YAML/XML/TOML processing. Same syntax as jq.
- `sd` — find and replace in files. Use over `sed` for simple replacements.
- `miller` (mlr) — CSV/JSON tabular operations.
- `xsv` — fast CSV operations (stats, select, join, split).
- `htmlq` — extract data from HTML using CSS selectors.
- `csvkit` — CSV processing suite (csvlook, csvstat, csvsql).
- `choose` — select columns from output. Use over `cut`.
- `jnv` — interactive JSON viewer with jq filtering.
- `gron` — flatten JSON to greppable lines. `gron --ungron` reverses. Use to explore large API responses.
- `dasel` — unified query/modify for JSON, YAML, TOML, XML, CSV, HCL. One syntax for all formats.
- `vd` (visidata) — TUI spreadsheet for CSV, JSON, SQLite, Parquet.
- `nu` (nushell) — structured data shell, everything is a table.

**Git Operations:**
- `gh` — GitHub operations (PRs, issues, releases, actions). Always prefer over browser.
- `lazygit` — interactive git UI when complex operations needed.
- `delta` — git diff viewer. Already configured as git pager.
- `difftastic` — structural diffs when line-diff is insufficient.
- `git-cliff` — generate changelogs from conventional commits.
- `gitleaks` — scan for secrets before committing.
- `git-absorb` — auto-create fixup commits for review changes.
- `onefetch` — quick repo overview/stats.

**Code Quality:**
- `semgrep` — run static analysis. Use for security and correctness patterns.
- `shellcheck` — always lint shell scripts before execution.
- `ruff` — Python linter and formatter. Use over flake8/black.
- `scc` — codebase stats with complexity scoring and COCOMO estimates. Use over tokei.
- `tree-sitter` — parse code into ASTs. Build repo maps for context-efficient navigation.
- `typos` — spell check source code and docs.
- `codespell` — fix common misspellings.
- `hadolint` — lint Dockerfiles.
- `actionlint` — lint GitHub Actions workflows.
- `shfmt` — auto-format shell scripts (pairs with shellcheck).
- `prettier` — format YAML, JSON, Markdown, HTML, CSS consistently.
- `ansible-lint` — lint Ansible playbooks for best practices.

**Containers & Kubernetes:**
- `lazydocker` — Docker management UI.
- `dive` — analyze Docker image layers and size.
- `ctop` — live container metrics.
- `kubectl` — Kubernetes cluster operations.
- `k9s` — Kubernetes terminal UI.
- `helm` — Kubernetes package management.
- `stern` — tail logs from multiple pods simultaneously.
- `crane` — inspect/copy/mutate container images without Docker daemon.
- `cosign` — sign and verify container images (Sigstore supply chain security).

**Infrastructure:**
- `terraform` — infrastructure provisioning.
- `ansible` — configuration management and automation.
- `packer` — build machine images.
- `tflint` — lint Terraform files before apply.
- `infracost` — estimate cloud costs from Terraform plans.
- `sops` — encrypt/decrypt secret files.
- `age` — simple file encryption.
- `infisical` — secrets management platform CLI.

**Networking & HTTP/Proxy:**
- `xh` — HTTP requests. Use over curl for readability.
- `httpie` (http) — alternative HTTP client with JSON support.
- `doggo` — DNS lookups. Use over dig.
- `mtr` — network path diagnostics.
- `bandwhich` — see bandwidth usage by process.
- `websocat` — WebSocket client.
- `grpcurl` — interact with gRPC services.
- `oha` — HTTP load testing with real-time TUI. Use for API performance testing.
- `hurl` — declarative HTTP test chains with assertions. Use for API integration testing.
- `aria2c` — accelerated downloads.
- `bore` — expose local ports publicly (tunneling).
- `mitmproxy` — intercept/inspect/modify HTTP/HTTPS traffic.
- `cloudflared` — Cloudflare tunnels (persistent URLs, auth, HTTPS).
- `tailscale` — VPN mesh networking. `tailscale up`, `tailscale status`, `tailscale ssh`.

**Security & Scanning:**
- `nmap` — network and port scanning.
- `nuclei` — template-based vulnerability scanning.
- `trivy` — scan containers, IaC, and filesystems for vulns.
- `osv-scanner` — check dependencies against OSV database.
- `nikto` — web server vulnerability scanning.
- `ffuf` — web fuzzing (directories, parameters).
- `trufflehog` — deep secret scanning across git history.
- `lynis` — system security audit.
- `sqlmap` — SQL injection testing.
- `parry` — prompt injection scanner for LLM apps.
- `sherlock` — username search across social networks.
- `syft` — generate SBOMs for containers and filesystems.
- `grype` — vulnerability scanner (pairs with syft for full supply chain coverage).
- `step` — inspect/generate certificates, debug TLS issues.
- `jwt` — decode, encode, and validate JWTs from terminal.
- `httpx` — mass HTTP probing for live service discovery. Pairs with subfinder.
- `subfinder` — passive subdomain enumeration from 50+ sources.
- `dnsx` — bulk DNS resolution and wildcard detection.
- `katana` — web crawler with JS rendering. Finds endpoints ffuf misses.
- `shannon-audit` — autonomous AI web app pentester (wrapper for `~/tools/shannon`). Runs 4-phase multi-agent pipeline: recon → vuln analysis → exploitation → report. 1-1.5hr runtime, ~$50/audit. Usage: `shannon-audit start URL=https://target.com REPO=repo-name`. Check progress: `shannon-audit logs`. NEVER run on production or unauthorized targets.

**Databases:**
- `duckdb` — run SQL on local files (CSV, Parquet, JSON). Extremely powerful.
- `usql` — universal SQL client for any database.
- `pgcli` — Postgres with autocomplete.
- `litecli` — SQLite with autocomplete.
- `redis-cli` — Redis operations.

**System Monitoring:**
- `btop` — system resource monitor (apt).
- `btm` (bottom) — TUI process monitor with graphs. Use over htop for visual CPU/memory/network.
- `procs` — process viewer with search. Use over `ps`.
- `hyperfine` — benchmark commands with statistical analysis.
- `pueue` — queue and manage background tasks.
- `watchexec` — watch files and re-run commands on change.

**Development Workflow:**
- `just` — command runner (justfile). Prefer over Makefile for project tasks.
- `task` — alternative task runner (Taskfile.yml).
- `mise` — manage tool versions (Node, Python, Go, etc).
- `direnv` — auto-load .envrc per directory.
- `entr` — simple file watcher.
- `mkcert` — generate trusted local HTTPS certificates.
- `dippy` — auto-approve safe commands for Claude Code.
- `inotifywait` — watch files for changes and trigger commands.
- `expect` — automate interactive CLI tools.
- `gum` — pretty prompts, spinners, and styled output for scripts.
- `asciinema` — record terminal sessions for sharing.
- `mmdc` — render mermaid diagrams to PNG/SVG/PDF.
- `cookiecutter` — scaffold projects from templates.
- `act` — run GitHub Actions locally in Docker.
- `playwright` — browser automation, E2E testing, screenshots.
- `maim` — screenshot tool (capture screen regions).
- `xdotool` — automate X11 window/keyboard/mouse actions.
- `lnav` — structured log viewer with filtering and highlighting.
- `convert` (imagemagick) — resize, annotate, convert images.
- `chafa` — render images (PNG, JPG, GIF) in terminal.
- `repomix` — pack entire repo into AI-optimized single file with token counts.
- `runme` — execute code blocks directly from Markdown files.

**Cloud CLIs:**
- `aws` — AWS operations.
- `hcloud` — Hetzner Cloud operations.
- `doctl` — DigitalOcean operations.
- `mc` — S3-compatible object storage operations.
- `vercel` — Vercel deployment CLI.
- `gcloud` — Google Cloud CLI (gcloud, gsutil, bq).

**AI Tools:**
- `gemini-cli` — Google Gemini CLI.
- `claude-tmux` — Claude Code in tmux sessions.
- `claude-esp` — Claude ESP tool.
- `recall` — search Claude/Codex conversation history.
- `ccusage` — Claude Code usage stats tracker.
- `ccstatusline` — Claude Code status line.
- `claude-squad` — manage multiple AI terminal agents in parallel (tmux-based).
- `rtk` — Rust Token Killer. Transparent CLI proxy that compresses command output 60-90% before it reaches context. Hook auto-rewrites commands (git, ls, grep, docker, etc.). Use `rtk gain` to check savings, `rtk gain --graph` for history, `rtk discover` to find missed opportunities. Do NOT prefix commands manually — hook handles it.
- `better-ccflare` — Claude API proxy. Routes Claude Code through a local relay (OAuth, Vertex AI, etc.). Activated via ANTHROPIC_BASE_URL in settings.json.
- `nlm` — Google NotebookLM CLI. Create notebooks, add sources, generate podcasts/reports/quizzes. Use `nlm --ai` for full docs. Requires `nlm login` (session expires ~20min).
- `kilocode` — Kilo Code CLI. AI coding assistant (VS Code extension backend).

**Documentation:**
- `pandoc` — convert between document formats.
- `glow` — render markdown beautifully in terminal.
- `mdbook` — build documentation sites from markdown.
- `slides` — terminal presentations from markdown.

**Terminal Productivity:**
- `tmux` — terminal multiplexer. Use for persistent sessions.
- `atuin` — searchable shell history with context.
- `navi` — interactive cheatsheet for commands.
- `tldr` — simplified man pages. Check before reading full man pages.
- `starship` — informative shell prompt.
- `trash-cli` — safe file deletion to trash.
- `spotify_player` — Spotify TUI client.

## Rules
1. ALWAYS run `<tool> --help` before first use in a session.
2. Prefer modern tools over legacy equivalents.
3. Pipe freely between tools. The Unix philosophy applies.
4. For data tasks: JSON→`jq`, YAML→`yq`, CSV→`xsv`/`miller`, SQL-shaped→`duckdb`.
5. Always `shellcheck` any shell script before running.
6. Always `gitleaks detect` before pushing to remote.
7. For long-running tasks, use `pueue` to queue them.
8. When benchmarking, use `hyperfine` not manual timing.
