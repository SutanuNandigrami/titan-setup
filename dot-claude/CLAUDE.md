# TITAN_ENGINEER_NAME — Global Operating Manual

## Preferences
- Be direct. Skip preambles.
- When I ask "how", give the command, not a tutorial.
- If unsure, say so. Never hallucinate.
- Python 3.10+ with type hints. Bash must pass shellcheck.
- Conventional commits: `feat:`, `fix:`, `chore:`, `docs:`

## Tool Philosophy
You have 100+ CLI tools installed. They replace most MCPs at zero context cost.
NEVER guess flags. Discover tools on demand:
1. Check existence: `type <tool>` or `which <tool>`
2. Learn usage: `<tool> --help` or `<tool> -h`
3. Quick reference: `tldr <tool>`
4. Browse installed: `uv tool list`, `ls ~/.cargo/bin/`, `ls ~/go/bin/`

## Tool Routing — use the right tool, not the familiar one
| Task | Tool | NOT this |
|------|------|----------|
| Search text | `rg` | grep |
| Find files | `fd` | find |
| View files | `bat` | cat |
| List files | `eza` | ls |
| Find & replace | `sd` | sed |
| HTTP requests | `xh` | curl |
| Process listing | `procs` | ps |
| Disk usage | `dust` | du |
| DNS lookup | `doggo` | dig |
| JSON | `jq` | python -c |
| YAML | `yq` | python -c |
| CSV | `xsv` or `miller` | awk |
| SQL on files | `duckdb` | sqlite3 |
| HTML extraction | `htmlq` | regex |
| Compress/extract | `ouch` | tar/unzip/7z |
| Format shell | `shfmt` | manual |
| Format web files | `prettier` | manual |
| Structural replace | `comby` | regex sed |
| Greppable JSON | `gron` | manual jq |
| Code stats | `scc` | tokei/cloc |
| Multi-format query | `dasel` | format-specific |
| API test chains | `hurl` | curl scripts |
| JWT inspect | `jwt` | python/openssl |
| HTTP load test | `oha` | ab/wrk |
| Repo → AI context | `repomix` | manual |

## CLI Tools That Replace MCPs — use these instead
| Domain | CLI tool | Replaces MCP |
|--------|----------|-------------|
| GitHub | `gh` | GitHub MCP |
| Git | `git` (built-in) | Git MCP |
| AWS | `aws` | AWS MCP |
| Hetzner | `hcloud` | — |
| Kubernetes | `kubectl`, `helm` | K8s MCP |
| Docker | `docker`, `lazydocker` | Docker MCP |
| Postgres | `pgcli` | Postgres MCP |
| SQLite | `litecli` | SQLite MCP |
| Redis | `redis-cli` | Redis MCP |
| Any DB | `usql` | Database MCPs |
| SQL on files | `duckdb` | — |
| HTTP/APIs | `xh` | Fetch MCP |
| Secrets scan | `gitleaks`, `trufflehog` | — |
| Vuln scan | `trivy`, `nuclei`, `grype` | — |
| SBOM | `syft` | — |
| Static analysis | `semgrep`, `comby` | — |
| Certificates | `step`, `mkcert` | — |
| Recon | `subfinder`, `httpx`, `dnsx`, `katana` | — |
| Container registry | `crane`, `cosign` | — |
| Code indexing | `ctags`, `tree-sitter` | — |

## Workflow Rules — IMPORTANT
1. **Branch first**: Never commit directly to `main`.
2. **Search before create**: `rg` the codebase before creating new functions/classes.
3. **Check history before modify**: `git log --oneline -5 <file>` before editing.
4. **Lint everything**: `shellcheck` for .sh, `ruff check` for .py, `hadolint` for Dockerfile.
5. **Scan before push**: `gitleaks detect` before any `git push`.
6. **Commit often**: After every working change, conventional commit.
7. **Diff before commit**: `git diff --stat` — revert unrelated changes.
8. **3-strike rule**: Same error 3 times → stop, write to `_scratchpad.md`, ask me.

## Do NOT Touch
`.env*`, `*credentials*`, `*secret*`, `~/.ssh/*`, `~/.bashrc`, `~/.profile`

## Context Hygiene
- Use subagents for research to keep main context clean.
- Write plans to `_scratchpad.md`, not just chat.
- At session start, check `~/.claude/memory/handoff.md` — it contains auto-saved state from the previous session.

## Auto Memory Protocol — MANDATORY
You have a persistent memory directory. Use it. This is not optional.

**MUST write to auto memory when:**
1. User says "remember this" or uses `/remember` — immediately
2. You discover a project convention or architecture pattern — after confirming it
3. A debugging session reveals a non-obvious fix — after the fix works
4. User corrects you on something — immediately update/remove the wrong memory
5. You learn a user preference from their feedback — after 2+ consistent signals
6. A key decision is made (tool choice, architecture, workflow) — after the decision

**MUST NOT write to memory:**
- Speculative conclusions from reading one file
- Session-specific temporary state (use `_scratchpad.md` instead)
- Anything that duplicates CLAUDE.md or project CLAUDE.md

**How:** Use the Write/Edit tools on files in your auto memory directory.
Keep `MEMORY.md` under 150 lines. Create topic files for details.

## Compaction Protocol
When context is being compacted, ALWAYS preserve in the summary:
1. **Current task** — what you are working on and why
2. **Branch name** — the active git branch
3. **Modified files** — all files changed in this session
4. **Test status** — last test commands and pass/fail results
5. **Blockers** — any unresolved errors or open questions
6. **Key decisions** — architectural or design choices made
7. **Next steps** — what needs to happen next
