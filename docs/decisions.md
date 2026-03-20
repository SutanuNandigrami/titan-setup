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
