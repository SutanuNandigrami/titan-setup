---
name: cli-tools
description: Reference for 100+ installed CLI tools. Use when working with any CLI tool, searching files, processing data, managing containers, infrastructure, security scanning, or system monitoring.
---

# CLI Tool Arsenal

Run `<tool> --help` before first use. Never guess flags.

## Search & Find
`rg` (text search), `fd` (find files), `fzf` (fuzzy select), `ast-grep` (AST search), `comby` (structural replace), `ctags` (symbol index)

## Files & Viewing
`bat` (view+highlight), `eza` (list+git), `dust` (disk usage), `broot` (nav), `yazi` (file mgr), `zoxide` (smart cd), `ouch` (compress/extract)

## Data Wrangling
`jq` (JSON), `yq` (YAML/XML/TOML), `sd` (find/replace), `miller`/`xsv` (CSV), `htmlq` (HTML+CSS selectors), `csvkit`, `choose` (columns), `jnv` (interactive JSON), `gron` (greppable JSON), `dasel` (multi-format), `vd` (TUI spreadsheet), `nu` (structured shell)

## Git
`gh` (GitHub), `lazygit` (TUI), `delta` (diff pager), `difftastic` (structural diff), `git-cliff` (changelog), `gitleaks` (secrets), `git-absorb` (fixup), `onefetch` (stats)

## Code Quality
`semgrep` (SAST), `shellcheck` (sh lint), `ruff` (Python lint+fmt), `scc` (stats), `tree-sitter` (AST), `typos`/`codespell` (spelling), `hadolint` (Dockerfile), `actionlint` (GH Actions), `shfmt` (sh fmt), `prettier` (web fmt), `ansible-lint`

## Containers & K8s
`lazydocker` (TUI), `dive` (layers), `ctop` (metrics), `kubectl`, `k9s` (TUI), `helm`, `stern` (multi-pod logs), `crane` (images), `cosign` (signing)

## Infrastructure
`terraform`, `ansible`, `packer`, `tflint`, `infracost` (cost est), `sops`/`age` (encryption), `infisical` (secrets)

## Network & HTTP
`xh` (HTTP), `doggo` (DNS), `mtr` (trace), `bandwhich` (bw monitor), `websocat` (WS), `grpcurl` (gRPC), `oha` (load test), `hurl` (HTTP test chains), `bore`/`cloudflared` (tunnels), `mitmproxy` (intercept), `tailscale` (VPN)

## Security
`nmap`, `nuclei` (vuln scan), `trivy` (container/IaC scan), `osv-scanner` (deps), `nikto` (web scan), `ffuf` (fuzzing), `trufflehog` (secret history), `lynis` (system audit), `sqlmap` (SQLi), `parry` (LLM injection), `syft`/`grype` (SBOM+vuln), `step`/`jwt` (certs/JWT), `httpx`/`subfinder`/`dnsx`/`katana` (recon), `shannon-audit` (AI pentester)

## Databases
`duckdb` (SQL on files), `usql` (universal), `pgcli` (Postgres), `litecli` (SQLite), `redis-cli`

## System
`btop`/`btm` (monitor), `procs` (processes), `hyperfine` (bench), `pueue` (task queue), `watchexec`/`entr` (file watch)

## Dev Workflow
`just`/`task` (runners), `mise` (tool versions), `direnv` (.envrc), `mkcert` (local HTTPS), `gum` (pretty prompts), `mmdc` (mermaid), `cookiecutter` (scaffold), `act` (local GH Actions), `playwright` (browser), `repomix` (repo→AI), `lnav` (log viewer), `convert`/`chafa` (images)

## Cloud
`aws`, `hcloud` (Hetzner), `doctl` (DO), `mc` (S3), `vercel`, `gcloud`

## AI Tools
`rtk` (token optimizer), `better-ccflare` (API proxy), `nlm` (NotebookLM), `claude-squad` (parallel agents), `ccusage`/`ccstatusline`

## Docs & Terminal
`pandoc` (convert), `glow` (md render), `mdbook` (doc sites), `slides` (presentations), `tmux`, `atuin` (history), `tldr` (cheatsheets), `starship` (prompt), `trash-cli`

## Rules
1. Run `--help` before first use
2. Prefer modern tools over legacy
3. JSON→`jq`, YAML→`yq`, CSV→`xsv`/`miller`, SQL→`duckdb`
4. `shellcheck` before running, `gitleaks` before pushing
