# Contributing to Titan Setup

Titan is built from modular shell fragments assembled at build time. **Never edit `titan-setup.sh` directly** — it is generated.

## Source of Truth

```
lib/
├── 00-header.sh          # Version, banner, colors
├── 01-common.sh          # Helper functions (ok, warn, fail, run_q, section)
├── 02-cli.sh             # CLI option parsing and usage()
├── 03-vps-reexec.sh      # VPS user creation and re-exec
├── 04-vps-harden.sh      # SSH, fail2ban, auditd, compliance
├── 05-prerequisites.sh   # apt packages, build deps
├── 06-package-managers.sh # Rust, uv, bun, Go, mise, Docker
├── 06b-repo-files.sh     # Clone titan repo early for REPO_FILES
├── 07-tools-python-js.sh # Python/JS tools, n8n, playwright
├── 08-tools-letta.sh     # Ollama, Letta, better-ccflare, billing proxy
├── 09-tools-rust-go.sh   # Cargo crates, Go tools, binary installs
├── 10-claude-code.sh     # Claude Code install + config
├── 11-deploy-config.sh   # Deploy ~/.claude/ files from dot-claude/
├── 12-plugins.sh         # Plugin marketplace, installs, config
├── 13-plugins-letta-ctrl.sh # LettaCtrl GUI install
├── 14-plugins-cleanup.sh # Plugin cache cleanup
├── 15-shell-integration.sh # PATH exports, bashrc integration
└── 16-finalize.sh        # Summary, compliance check, tmux cleanup
```
*(18 fragments total)*

## Build & Test

```bash
just build       # Assemble lib/*.sh → titan-setup.sh
just test        # Run 168 bats tests
just lint        # shellcheck on all fragments
just smoke       # Quick syntax check
just check       # lint + test (CI runs this on every PR)
```

## Workflow

1. Edit the relevant `lib/*.sh` fragment
2. Run `just build` to regenerate `titan-setup.sh`
3. Run `just check` to lint + test
4. Commit both the fragment and the generated `titan-setup.sh`
