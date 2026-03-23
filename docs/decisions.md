# Architecture Decision Records

Immutable once written. New decisions get new numbers; old ones get "Superseded" status.

---

## ADR-001: CLI-over-MCP (2026-02-15)
**Status**: Accepted
**Context**: Claude Code supports MCP servers for external tool integration, but each MCP server consumes context tokens on every turn (tool descriptions loaded into system prompt). Titan installs 150+ CLI tools.
**Decision**: Use CLI tools via Bash instead of MCP servers. CLI tools cost zero context tokens — they only appear when invoked. MCP descriptions are always present.
**Consequences**: Tools are discovered on-demand (`--help`, `tldr`). No MCP server management overhead. Trade-off: no structured tool schemas — Claude must parse CLI output.

## ADR-002: Telemetry env vars must be ABSENT, not zero (2026-03-19)
**Status**: Accepted
**Context**: `CLAUDE_CODE_ENABLE_TELEMETRY`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, and `DISABLE_NON_ESSENTIAL_MODEL_CALLS` — setting these to `0` or `false` does NOT disable them. CC checks for key existence, not value. Setting them to any value (even "0") breaks features like remote-control and voice.
**Decision**: Remove all three keys from settings.json entirely. Do not set them to any value.
**Consequences**: Remote-control and voice features work. Telemetry runs (acceptable trade-off). `DISABLE_NON_ESSENTIAL_MODEL_CALLS` is not even a real CC env var — it was cargo-culted from community configs.

## ADR-003: opusplan model config — user-owned key (2026-03-14, updated 2026-03-20)
**Status**: Accepted (revised)
**Context**: `opusplan` is a valid Claude Code model alias. It uses Opus in plan mode (Shift+Tab) and Sonnet for execution. v3.13 mistakenly changed it to `claude-sonnet-4-6`. Additionally, `/model` menu in CC overwrites the model key — and there's no way to type `opusplan` back via the menu.
**Decision**: `model` is user-owned, not titan-managed. Fresh installs get `opusplan` from template. If the user changes model via `/model`, their choice persists across re-runs. To restore opusplan: edit settings.json manually.
**Consequences**: Users who switch models don't get silently overridden on next titan run. Trade-off: if opusplan was accidentally changed, it won't auto-restore.

## ADR-004: No pipefail in CC hooks (2026-03-18)
**Status**: Accepted
**Context**: Claude Code hooks run shell commands. With `set -euo pipefail`, any non-zero exit in a pipe kills the hook. Common pattern: `grep | cut` where grep returns 1 on no match — this kills the entire hook chain.
**Decision**: Hooks must NOT use `set -euo pipefail`. Capture non-zero exits safely: `_rc=0; cmd || _rc=$?; case $_rc in`.
**Consequences**: Hooks are more resilient. Trade-off: silent failures possible if not handled explicitly. Each hook must handle its own error cases.

## ADR-005: hookify removed (2026-03-15)
**Status**: Accepted
**Context**: hookify was a Claude plugin that provided hook management. It had a broken `import core` statement and was functionally redundant with Titan's PreToolUse hooks in settings.json.
**Decision**: Remove hookify permanently. All hook behavior is managed via settings.json hook definitions.
**Consequences**: One fewer plugin to maintain. Hook behavior is centralized in settings.json. Plugin cache for hookify should be pruned on upgrade.

## ADR-006: settings.json merge, not clobber (2026-03-20)
**Status**: Planned (Phase 2)
**Context**: `install -Dm644` overwrites the live settings.json, losing runtime-injected values (LETTA_API_KEY, cozempic hooks). Six sequential `jq` calls create race conditions if CC is running.
**Decision**: Replace with single atomic Python merge script (`script/merge-settings.py`). Template keys win on titan-managed keys, live keys preserved for everything else. Single temp file + `mv` for atomicity.
**Consequences**: Safe to re-run. No loss of runtime state. Requires maintaining explicit `_TITAN_MANAGED_KEYS` list in merge script.

## ADR-007: Skip-if-exists for tools (2026-02-20)
**Status**: Accepted
**Context**: Tool installs (`cargo install`, `go install`, `uv tool install`) are slow and network-dependent. Re-running the script should not re-download everything.
**Decision**: Default behavior: `command -v X && skip`. Add `--force-updates` flag for explicit upgrade opt-in. Exception: Claude Code always runs installer (it's already idempotent — installs if missing, updates if older, noop if current).
**Consequences**: Fast re-runs (~2min vs ~30min). Trade-off: tools stay at installed version until explicit upgrade. `--force-updates` planned for Phase 3.

## ADR-008: Selective skill install (2026-03-10)
**Status**: Accepted
**Context**: Full `git clone` of community skill repos is fatal for token usage. trailofbits repo had 60 SKILL.md files / 71K lines. Skills load FULL content at startup (bug #14882), not just descriptions.
**Decision**: Never `git clone` full skill repos. Cherry-pick only needed SKILL.md files. All skills must have `paths:` frontmatter for lazy-loading.
**Consequences**: Skills load only when matching files are open. Always-on content dropped 93% (3009 → 203 lines). New skills must be individually vetted before inclusion.

## ADR-009: Agent Teams OFF by default (2026-03-16)
**Status**: Accepted
**Context**: Claude Code's `teammateMode: tmux` enables multi-agent collaboration but costs 7x tokens per teammate. Each teammate runs a full Claude instance.
**Decision**: Agent Teams disabled by default. Enable on-demand only for specific tasks that clearly benefit from parallelism.
**Consequences**: Single-agent is the default workflow. Users can enable teammates when needed. On-demand agent slots (`agt`) provide a lighter-weight alternative for specialist tasks.

## ADR-010: Category-based idempotency strategy (2026-03-20)
**Status**: Accepted
**Context**: titan-setup.sh was designed as a first-run installer, not an updater. Re-running causes stale caches, config overwrites, and service misconfiguration.
**Decision**: Four categories: REPLACE (files we own — always overwrite), MERGE (shared state like settings.json — atomic merge), SKIP (tools — install only if missing), CLEANUP (known stale artifacts — targeted removal, not manifest diffing).
**Consequences**: Safe re-runs. No manifest diffing complexity. Cleanup is explicit (add entries as items are removed). `--force-updates` for tool upgrades, `--clean-cache` for aggressive cleanup.

## ADR-011: Parallel network operations (2026-03-20)
**Status**: Accepted
**Context**: Version detection for binary downloads (nuclei, gitleaks, sops, osv-scanner, act) ran sequentially — each `_gh_latest_tag` call is ~3s, totaling ~15s. External skill repos (superpowers, vibesec, trailofbits) also cloned sequentially (~15s total). Both are pure I/O with no dependencies.
**Decision**: Batch all GitHub version fetches into parallel background jobs, wait once. Clone all external skill repos in parallel, then process results sequentially. Use temp dir for version results to avoid variable scoping issues with background jobs.
**Consequences**: ~30s saved on fresh install. No risk of write conflicts (version fetches are read-only; skill clones go to separate directories). Pattern can be extended to future network-heavy operations.

## ADR-012: Settings merge must never clobber user config (2026-03-20)
**Status**: Accepted
**Context**: When `merge-settings.py` fails (Python error, malformed JSON, etc.), the fallback was `install -Dm644` which overwrites `~/.claude/settings.json` with the template. This destroys: user's model choice (violates ADR-003), user-owned env vars, user-installed plugins, any runtime state.
**Decision**: If merge fails AND a settings.json already exists, preserve the existing file and warn. Only use template overwrite on truly fresh installs (no existing file). Never silently clobber user configuration.
**Consequences**: A failed merge requires manual intervention rather than silent data loss. Fresh installs still get the template. Users see a clear warning explaining what happened.

## ADR-013: SSH lockdown must validate before restart (2026-03-20)
**Status**: Accepted
**Context**: VPS mode locks SSH to Tailscale IP by writing `ListenAddress $TS_IP` to sshd_config and restarting sshd. If `$TS_IP` is empty (Tailscale failed) or sshd_config is invalid, the restart could lock the user out permanently.
**Decision**: Validate `$TS_IP` is non-empty before any SSH changes. Run `sshd -t` to validate config before restarting. If validation fails, revert the ListenAddress change.
**Consequences**: No SSH lockouts from invalid config. Users see a warning if Tailscale IP is missing. Trade-off: one extra sshd -t call (~100ms).

## ADR-014: Cached apt-get update (2026-03-20)
**Status**: Accepted
**Context**: `apt-get update` was called 4-6 times across phases (prerequisites, VPS hardening, gcloud, terraform, trivy, gh). Each call adds 5-10s even when the cache is fresh from the previous call seconds ago.
**Decision**: Single `apt_update()` helper that runs `apt-get update -qq` once and sets a flag. Subsequent calls are no-ops. Defined in lib/01-common.sh, available to all fragments.
**Consequences**: ~20-40s saved on fresh install. Trade-off: if a new apt source is added mid-script, the cache won't refresh automatically (acceptable — new sources are added before their first use, and the initial update runs before any source additions).

## ADR-015: Hooks must never use set -euo pipefail (2026-03-20)
**Status**: Accepted
**Context**: Claude Code hooks run as subprocesses. `set -euo pipefail` causes hooks to abort on ANY non-zero exit, including `grep` not matching (exit 1), piped commands failing midway, and unset variables. Three hooks (session-start, session-end, pre-compact) were using `set -euo pipefail`, causing spurious hook errors in production.
**Decision**: Hooks must NOT use `set -euo pipefail`. Instead, guard individual commands: `cmd || _rc=$?` or `cmd || true`. Hooks must always exit 0 unless they need to signal a fatal condition.
**Consequences**: Hooks are resilient to partial failures. Trade-off: bugs may be silent — use explicit error logging (`echo "[Hook] error: ..." >&2`) for critical paths.

## ADR-016: Temp files must use WORKDIR or mktemp, never hardcoded /tmp paths (2026-03-20)
**Status**: Accepted
**Context**: Multiple jq mutations in plugin config used hardcoded paths like `/tmp/_cc_settings.json`. If two script instances run concurrently, they overwrite each other's temp files, corrupting JSON configs.
**Decision**: All temp files must use either `$WORKDIR` (per-session unique directory) or `mktemp`. Never use hardcoded `/tmp/filename` patterns.
**Consequences**: Safe concurrent execution. Trade-off: slightly more verbose code.

## ADR-017: Destructive operations must be atomic (2026-03-20)
**Status**: Accepted
**Context**: Go installation deleted `/usr/local/go` before extracting the new tar. If extraction failed (disk full, corrupted download), the system was left without Go and no recovery path.
**Decision**: Extract/build to a temp location first, then atomic swap (rm old + mv new). Applied to: Go installation, settings.json merge, binary downloads.
**Consequences**: System state is never left broken mid-operation. Trade-off: requires temp disk space for the new version alongside the old one during swap.

## ADR-018: Service systemd dependencies and resource limits (2026-03-20)
**Status**: Accepted
**Context**: Docker-based services (n8n, Letta) had no `After=docker.service` dependency — they'd fail on reboot if Docker wasn't ready. No `MemoryMax` limits meant services could OOM-kill each other on 2-4GB VPS. No journald limits meant logs could fill disk in days.
**Decision**: All Docker-based services declare `After=docker.service Wants=docker.service`. Resource limits: n8n 512MB, Letta 1GB, ccflare 256MB. Journald: 500MB SystemMaxUse, 7-day retention. All services get `StartLimitBurst=5` to prevent infinite restart loops.
**Consequences**: Services start in correct order after reboot. OOM kills are directed at the service exceeding its limit, not random. Disk usage is bounded. Trade-off: services may be killed if they legitimately need more RAM (user can override via systemd drop-in).

## ADR-019: Network binding — never 0.0.0.0 for internal proxies (2026-03-20)
**Status**: Accepted
**Context**: ccflare-billing-proxy was binding to `0.0.0.0:8081` to allow Docker containers to reach it. This exposed an unauthenticated API proxy to the entire network — anyone could POST to `/v1/messages` and consume Anthropic API quota.
**Decision**: Internal proxies bind to Docker bridge IP (`172.17.0.1`) instead of `0.0.0.0`. Docker containers access via `host.docker.internal` which resolves to the bridge IP. Only services explicitly designed for external access (none currently) may bind to `0.0.0.0`.
**Consequences**: Proxy is unreachable from external network. Docker containers still reach it via bridge. Trade-off: if Docker bridge IP changes (non-default config), the proxy becomes unreachable — user must update systemd env.

## ADR-020: Phase checkpoints for resume capability (2026-03-20)
**Status**: Accepted
**Context**: Install takes 45-80 minutes. If it fails at Phase 3 and user re-runs, Phases 1-2 re-execute unnecessarily (5-20 minutes wasted). No state tracking existed.
**Decision**: Write marker files to `~/.titan-progress/<phase>` after each phase completes. On re-run, skip completed phases unless `--force-updates` or `--fresh` is passed. Phase 1 (prerequisites) and Phase 2 (package managers) get checkpoints. Phase 3+ always runs (tool installs are already idempotent via `command -v` checks).
**Consequences**: Re-runs after Phase 3 failure skip 5-20 minutes of redundant work. `--fresh` resets all checkpoints for clean re-install. Trade-off: if system state changes between runs (e.g., apt sources modified), stale checkpoint may skip needed updates — `--fresh` resolves this.

## ADR-021: --minimal flag for reduced install (2026-03-20)
**Status**: Accepted
**Context**: Full install includes 150+ tools and 4 services (n8n, Letta, Ollama, ccflare). Many tools are nice-to-have but rarely used daily (sqlmap, mitmproxy, bore-cli, etc.). Services consume ~2GB RAM at idle. Fresh install takes 45-80 min.
**Decision**: Add `--minimal` flag that installs ~50 core tools in ~25 min. Skips: Letta, Ollama, n8n, cozempic. Skips extended tool lists (sqlmap, mitmproxy, cookiecutter, bore-cli, websocat, hurl, jwt-cli, oha, mkcert, ffuf, grpcurl, security recon tools). Core tools always installed: ripgrep, fd, sd, bat, eza, delta, just, xh, jq, yq, opengrep, ruff, ansible, etc.
**Consequences**: 50% faster install. 75% less idle RAM. Users who need specific tools can install on-demand (`uv tool install sqlmap`). Full install remains the default.

## ADR-022: --secrets-file for credential passing (2026-03-20)
**Status**: Accepted
**Context**: Secrets (TAILSCALE_KEY, LETTA_PASSWORD) were passed via CLI args, visible in `ps aux`, shell history, and install logs. An observer on the same machine during install could read all credentials.
**Decision**: Add `--secrets-file PATH` flag. File format: `KEY=value` (one per line, # comments). Supported keys: TAILSCALE_KEY, LETTA_PASSWORD. File should be mode 0600. CLI arg passing still works (backward compatible).
**Consequences**: Secrets no longer visible in process list or shell history. Log files still show commands but not the secret values. Trade-off: user must create a temp file.

## ADR-023: Parallel Phase 3 — uv tools run concurrently with cargo (2026-03-20)
**Status**: Accepted
**Context**: Phase 3 installs tools sequentially: uv (10-15 min) → bun (3 min) → cargo (25-40 min) → go (8 min). uv and cargo use completely separate package managers with no shared state.
**Decision**: Run uv tools in a background subshell while cargo compiles in the foreground. Background output goes to a log file; results are displayed after cargo finishes. This overlaps ~10-15 min of uv install time with cargo compile time.
**Consequences**: ~10-15 min saved on fresh install. No output interleaving (background uses structured log format). Trade-off: uv errors are reported delayed (after cargo finishes, not in real-time).

## ADR-025: Pin n8n to 2.10.4 on ARM64 (2026-03-22)
**Status**: Accepted
**Context**: n8n >=2.11.1 includes `isolated-vm` which ships prebuilt native binaries incompatible with ARM64 Alpine (musl). The container segfaults immediately on aarch64, creating a crash loop. x86_64 is unaffected. See github.com/n8n-io/n8n/issues/26858.
**Decision**: Set `_N8N_IMAGE` dynamically: `n8nio/n8n:2.10.4` on `aarch64`, `n8nio/n8n:latest` on x86_64. Used in docker pull, image inspect, and the systemd service ExecStart.
**Consequences**: ARM64 deployments get a stable n8n. Trade-off: ARM users miss new n8n features until upstream fixes isolated-vm on aarch64 Alpine. Must periodically check if newer versions resolve the issue.

## ADR-026: Detached docker for systemd user services (2026-03-22)
**Status**: Accepted
**Context**: `docker run --rm` (attached mode) under systemd user sessions on ARM64 exits with SIGKILL (137) approximately 10 seconds after container startup. The docker client process gets killed, which also kills the container due to `--rm`. This creates a crash loop (n8n restarted 5+ times, letta reached restart counter 59). Running the same container with `docker run -d` (detached) works fine — the container stays up indefinitely.
**Decision**: Switch n8n and letta systemd services from `Type=simple` + `docker run --rm` to `Type=oneshot` + `RemainAfterExit=yes` + `docker run -d --restart unless-stopped`. Use `ExecStopPost` to clean up containers on service stop. Move `StartLimitIntervalSec` to `[Unit]` section (systemd ignores it in `[Service]`). Remove `MemoryMax` — it only limited the docker client process, not the container.
**Consequences**: Both services start reliably on ARM64 and x86_64. Docker's own `--restart unless-stopped` handles container crashes. Trade-off: `systemctl --user status` shows `active (exited)` instead of `active (running)` since systemd doesn't track the container PID — use `docker ps` to check actual container status.

## ADR-027: Unconditional PATH exports after phase checkpoints (2026-03-22)
**Status**: Accepted
**Context**: Phase 2 (Package Managers) installs rustup, bun, Go, uv and exports their PATH. On re-run, Phase 2 is skipped via checkpoint cache — but the PATH exports lived inside the skipped block. This caused `rustup: command not found` and bun tool failures on re-run.
**Decision**: Add unconditional PATH exports after the phase2 `fi` block: cargo env, `.local/bin`, `.bun/bin`, `.cargo/bin`, `go/bin`, `/usr/local/go/bin`, and mise shims. These run on every invocation regardless of cache state.
**Consequences**: Re-runs work correctly without `--fresh`. Trade-off: slight redundancy on first run (PATH exported twice). The pattern "PATH exports OUTSIDE checkpoint blocks" is now enforced.

## ADR-028: Tailscale serve reset before reconfiguring (2026-03-22)
**Status**: Accepted
**Context**: `tailscale serve` binds rules to the current MagicDNS hostname. If the hostname changes between installs (e.g., server reimaged, hostname collision), stale rules remain active under the old hostname. New rules are added but old ones linger, causing confusion.
**Decision**: Run `tailscale serve reset` before configuring serve rules. This clears all existing rules and re-adds only current ones.
**Consequences**: Clean serve state on every run. Trade-off: momentary service interruption during re-run (rules cleared then re-added). Acceptable since re-runs are infrequent.

## ADR-029: Replace Semgrep with Opengrep (2026-03-23)
**Status**: Accepted
**Context**: Semgrep CE moved critical features (advanced taint analysis, cross-function tracking) behind a paid Pro tier. Opengrep is an LGPL 2.1 fork (v1.16.5) backed by 10+ AppSec organizations, offering these features freely. It ships as a self-contained binary (no Python dependency), requires no authentication token, and is 100% compatible with Semgrep rule format.
**Decision**: Replace semgrep with opengrep. Remove semgrep CLI install (uv), Claude Code plugin, `--semgrep-token`/`--no-semgrep` flags, `SEMGREP_APP_TOKEN` env var, interactive token prompt, and all hook patching. Install opengrep as a direct binary download to `/usr/local/bin/opengrep` with x86_64/aarch64 support. Drop the Claude Code semgrep plugin entirely — on-demand `opengrep scan` via the security-scan skill is sufficient (no auto-scan hooks needed).
**Consequences**: Simpler install (no token, no Python, no plugin patching). One fewer uv tool. CLI commands change from `semgrep --config auto .` to `opengrep scan -f auto .`. Existing semgrep rules remain compatible.

## ADR-030: Replace ccstatusline with claude-lens (2026-03-23)
**Status**: Accepted
**Context**: ccstatusline required bun (Node.js runtime), a 156-line JSON config file, and a 138-line bash fallback script — three moving parts. claude-lens is a single ~165-line bash script with only jq as dependency (already in Phase 1). It provides quota pace tracking (delta from expected consumption rate) which ccstatusline did not. CC v2.1.80+ sends usage data via stdin, eliminating network overhead.
**Decision**: Remove ccstatusline from BUN_TOOLS, delete its config directory and fallback script. Ship claude-lens.sh in dot-claude/, deploy via `install -Dm755`. Remove CLAUDE_CODE_STATUSLINE env var (ccstatusline-specific). Point statusLine.command to ~/.claude/claude-lens.sh.
**Consequences**: One fewer bun dependency. Zero-config status line (no ~/.config/ccstatusline/). Quota pace tracking gives users actionable insight. Trade-off: loses ccstatusline's Powerline theme and multi-line TUI config — acceptable since quota visibility is more valuable.

## ADR-031: LettaCtrl GUI hardening — 8 fixes (2026-03-23)
**Status**: Accepted
**Context**: Code audit of the LettaCtrl web dashboard (letta-ctrl-server.js + letta-ctrl.html) found 8 issues: CPU always 0, misleading RAM for Docker services, empty card log tails, SSE auth bypass via EventSource, hardcoded SVC_EXTRA values, full grid re-render flicker, wrong Letta API field name in agent creation, and memory block DOM ID collisions with special characters.
**Decision**: (1) Add `getDockerStats()` using `docker stats --no-stream` for real container memory/CPU on Docker services; use `CPUUsageNSec` delta for native services. (2) New `GET /api/logtail/:service` endpoint for card log tails. (3) `checkAuth()` accepts `?token=` query param alongside Bearer header (EventSource can't send headers). (4) Replace misleading static SVC_EXTRA with generic Status. (5) `updateSvcGrid()` does targeted DOM updates after first render. (6) `createAgent()` uses `model:` not `llm:` per current Letta API. (7) `safeId()` sanitizes memory block labels for DOM IDs.
**Consequences**: Dashboard shows accurate container metrics. SSE log streaming is authenticated in desktop mode. No more UI flicker. Agent creation works with current Letta API. Trade-off: `docker stats` adds ~100ms latency per poll for Docker services; acceptable at 5s interval.

## ADR-032: LettaCtrl security hardening + stability (2026-03-23)
**Status**: Accepted
**Context**: Second audit of LettaCtrl found XSS vectors (unsanitized agent names/models in DOM, inline JS strings in onclick handlers, unescaped token in HTML injection, HTML paste via contenteditable), a Bun crash (ReadableStream controller double-close on SSE idle timeout), block labels with `/` breaking server routes, polling interval stacking, and missing UX polish (no Escape key, no debounce, no name truncation).
**Decision**: (1) `JSON.stringify()` for token injection into HTML. (2) `escHtml()` on all 12 agent data DOM insertions. (3) `data-*` attributes replace inline JS onclick strings. (4) `contenteditable="plaintext-only"`. (5) `encodeURIComponent(label)` on frontend + `decodeURIComponent()` on server for block labels. (6) `closed` flag guards SSE ReadableStream controller + `idleTimeout: 255` on Bun.serve. (7) EventSource `onerror` closes stream and shows reconnect message. (8) Recursive `setTimeout` replaces `setInterval` + `beforeunload` cleanup. (9) Escape key closes modal. (10) 150ms debounce on log filter. (11) CSS `text-overflow:ellipsis` on agent names. (12) Warn on startup if `LETTA_PASSWORD` is empty.
**Consequences**: All known XSS vectors closed. Server survives SSE disconnect without crash. Polling cannot stack. Block labels with special chars work. Trade-off: `plaintext-only` contenteditable not supported in Firefox <125 (acceptable — dashboard targets Chromium-based browsers on dev machines).

## ADR-033: Unified context system + skill auto-activation (2026-03-23)
**Status**: Accepted
**Context**: Titan's /handoff and /catchup commands were minimal (1 and 4 lines respectively). Sessions lost context on reset. Skills only activated via `paths:` frontmatter (file pattern matching), not by prompt content. Inspired by claude-code-infrastructure-showcase (diet103) which provides TypeScript-based skill auto-activation and dev-docs patterns.
**Decision**: (1) Enhance /handoff with structured sections (task, completed, in-progress, key decisions, blockers, task checklist, next steps, test status). Enhance /catchup to read richer handoff + git state + memory. (2) Add pure bash `skill-suggest.sh` UserPromptSubmit hook that matches prompt keywords against a built-in skill registry and suggests relevant skills. Zero token cost on no match. No TypeScript/npm dependency — pure bash + jq + grep.
**Consequences**: Better session continuity. Skills surface based on what users ask, not just what files are open. Trade-off: second UserPromptSubmit hook adds ~3s latency on keyword match (none on miss).

## ADR-034: claudecodeui — web interface for Claude Code sessions (2026-03-23)
**Status**: Accepted
**Context**: Claude Code is CLI-only. Remote access requires SSH + tmux. claudecodeui (@siteboon/claude-code-ui) provides a zero-config web/mobile interface that auto-discovers sessions from ~/.claude/. Requires Node.js v22+ (installed via mise). Runs as HTTP+WebSocket server. GPL v3.0 license.
**Decision**: Install via bun install -g. Run as systemd user service (Type=simple, not Docker). Bind to 127.0.0.1 (ADR-019). Expose via Tailscale serve on HTTPS. Skip in --minimal mode. CLI flags: --claudecodeui-skip, --claudecodeui-port PORT. Default port 3001.
**Consequences**: Web/mobile access to Claude Code sessions from any device on tailnet. Zero config. Trade-off: one more bun package + one systemd service. Node v22+ guard skips gracefully on older runtimes.

## ADR-024: Consolidate split plugin fragments (2026-03-20)
**Status**: Accepted
**Context**: lib/12-plugins-install.sh and lib/13-plugins-config.sh shared an if/fi block across the fragment boundary. This was a maintenance landmine — editing one file could break the other without any indication.
**Decision**: Merge into single `lib/12-plugins.sh`. Renumber subsequent fragments (14→13, 15→14, 16→15, 17→16). Total fragments: 19→18.
**Consequences**: All if/fi blocks are self-contained within a single file. No cross-fragment dependencies. Slightly larger file (~160 lines) but much easier to maintain.


## ADR-031: vexp-cli as global MCP server via stdio transport (2026-03-23)
**Status**: Accepted
**Context**: vexp-cli provides tree-sitter AST parsing, dependency graphs, and skeleton context for token-efficient code understanding. Ships 11 MCP tools (run_pipeline, get_context_capsule, get_impact_graph, etc.). Two transport options: stdio (on-demand, CC manages lifecycle) and HTTP+SSE (persistent daemon on port 7821).
**Decision**: Install via `bun install -g vexp-cli` (uses optional deps `@vexp/core-linux-x64` etc. for platform binary — no postinstall). Configure as global MCP server in settings.json using stdio transport (`vexp mcp`). Injected via jq post-merge. Skip with `--minimal` or `--no-vexp`. mcpServers key NOT in TITAN_MANAGED_BLOCKS — user-added MCP servers preserved across re-runs.
**Consequences**: Zero-touch UX — CC spawns `vexp mcp` on demand, no systemd service or port management. Trade-off: ~2s cold start per session for Rust daemon startup. ARM64 supported via `@vexp/core-linux-arm64` optional dep; binary verification warns if missing.

## ADR-035: Canonicalize $0 + desktop HOME override (2026-03-23)
**Status**: Accepted
**Context**: Four interrelated bugs when running titan-setup.sh in desktop mode: (1) `cd repo && sudo bash ./titan-setup.sh` — relative `$0` breaks tmux re-launch (CWD changes to /root under sudo). (2) `sudo bash titan-setup.sh` sets HOME=/root — all services, configs, cargo/bun installs go to wrong location. (3) System node (v18) found instead of mise's v22 — tools like claudecodeui skipped. (4) `bash <(curl ...)` already handled by self-materialization but relative paths were not.
**Decision**: (1) Add `$0` canonicalization via `readlink -f` + `exec` in `lib/00-header.sh` right after self-materialization — guarantees `$0` is absolute for all downstream code (tmux wrapper, VPS re-exec). (2) In `lib/02-cli.sh`, desktop mode running as root overrides HOME to target user's home via `getent passwd` and prepends PATH with mise/cargo/bun/go shims. (3) claudecodeui node check falls back to `~/.local/share/mise/shims/node`. (4) claude-subconscious plugin's `/dev/tty` crash patched after install. (5) Hook `>&2` removed (CC 2.1.81 treats stderr as hook error).
**Consequences**: Single `sudo bash titan-setup.sh` works from any CWD, any invocation pattern (curl pipe, relative path, absolute path, VPS, desktop). All tools/services install to correct user home. Trade-off: extra `exec` on startup adds ~5ms for relative-path invocations.

## ADR-036: Letta password rotation — restart container on re-run (2026-03-23)
**Status**: Accepted
**Context**: titan-setup.sh regenerates LETTA_SERVER_PASSWORD via `openssl rand` on every re-run where `--letta-password` is not passed. The new key is written to `~/.config/letta/credentials` and `docker.env`, and injected into `settings.json`. However, if the `letta-server` Docker container is already running, `systemctl start letta` is a no-op (Type=oneshot + RemainAfterExit=yes). The container retains the old `LETTA_SERVER_PASSWORD`, causing 401 on every claude-subconscious hook call, even though credentials and settings.json agree on the new key.
**Decision**: Before `systemctl start letta`, inspect the running container's env with `docker inspect letta-server --format '{{range .Config.Env}}{{println .}}{{end}}'`. If `LETTA_SERVER_PASSWORD` differs from `$LETTA_PASSWORD`, issue `systemctl --user restart letta` so the container is recreated with the new `docker.env`. Only restart when a mismatch is detected — no unnecessary container churn on normal re-runs.
**Consequences**: Password rotation is idempotent. Re-runs always leave container, credentials, and settings.json in agreement. Trade-off: one extra `docker inspect` call per letta setup (negligible). Requires docker CLI available, which is already a hard dependency for letta service setup.
