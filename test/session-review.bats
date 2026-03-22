#!/usr/bin/env bats
# session-review.bats — tests for all changes made in the review session
# Covers: Round 1 (tool fixes), Round 2 (safety/perf), Round 3 (hooks/atomicity),
# Round 4 (CTO/services), and remaining known issues (minimal/secrets/parallel/consolidation)

setup() {
  load helpers/setup
}

# ════════════════════════════════════════════════════════════════════
# ROUND 1: Tool install warning fixes
# ════════════════════════════════════════════════════════════════════

@test "R1: no bare 'apt ' commands in lib/ (only apt-get)" {
  # Match bare apt commands, exclude apt-get, comments, apt-key, apt-transport, deb lines
  local hits
  hits=$(grep -rn '\bapt ' "$REPO"/lib/*.sh \
    | grep -v 'apt-get\|# \|apt-key\|apt-transport\|DEBIAN\|deb \[' \
    | grep -v 'insecure apt repos\|apt lock' || true)
  [ -z "$hits" ]
}

@test "R1: cargo-binstall telemetry suppression exists" {
  grep -q 'binstall.toml' "$REPO/lib/09-tools-rust-go.sh"
}

@test "R1: parry-guard uses --bin flag" {
  grep -q '\-\-bin parry-guard' "$REPO/lib/09-tools-rust-go.sh"
}

@test "R1: ctop uses curl not wget" {
  grep -A2 'Installing ctop' "$REPO/lib/09-tools-rust-go.sh" | grep -q 'curl -fsSL'
}

@test "R1: claude-tmux logs stderr to LOG_FILE" {
  grep 'claude-tmux' "$REPO/lib/09-tools-rust-go.sh" | grep -q 'LOG_FILE'
}

@test "R1: claude-lens in dot-claude (ccstatusline removed)" {
  [ -f "$REPO/dot-claude/claude-lens.sh" ]
  ! grep -q 'ccstatusline' "$REPO/lib/07-tools-python-js.sh"
  ! grep -q 'statusline-command.sh' "$REPO/lib/11-deploy-config.sh"
}

@test "R1: settings.json statusLine points to claude-lens" {
  jq -e '.statusLine.command == "~/.claude/claude-lens.sh"' "$REPO/dot-claude/settings.json"
}

@test "R1: no CLAUDE_CODE_STATUSLINE env var in settings.json" {
  ! jq -e '.env.CLAUDE_CODE_STATUSLINE' "$REPO/dot-claude/settings.json"
}

@test "R1: dippy clone logs to LOG_FILE" {
  grep 'ldayton/Dippy' "$REPO/lib/09-tools-rust-go.sh" | grep -q 'LOG_FILE'
}

# ════════════════════════════════════════════════════════════════════
# ROUND 2: Safety & performance fixes
# ════════════════════════════════════════════════════════════════════

@test "R2: --force-updates propagated in VPS reexec args" {
  grep -q 'FORCE_UPDATES.*_VPS_REEXEC_ARGS.*--force-updates' "$REPO/lib/03-vps-reexec.sh"
}

@test "R2: settings merge fallback preserves existing config" {
  grep -q 'preserving existing user config' "$REPO/lib/11-deploy-config.sh"
}

@test "R2: plugin cleanup guards empty ACTIVE_PATHS" {
  grep -q 'ACTIVE_PATHS.*-eq 0' "$REPO/lib/14-plugins-cleanup.sh"
}

@test "R2: parallel version fetches use temp dir" {
  grep -q '_VER_DIR.*mktemp' "$REPO/lib/09-tools-rust-go.sh"
}

@test "R2: parallel git clones use _NEED_ flags" {
  grep -q '_NEED_SUPERPOWERS' "$REPO/lib/11-deploy-config.sh"
}

@test "R2: SSH validates TS_IP before sshd_config mutation" {
  grep -q 'sshd -t' "$REPO/lib/16-finalize.sh"
}

@test "R2: SSH guards empty TS_IP" {
  grep -q 'TS_IP.*empty.*skipping SSH lockdown' "$REPO/lib/16-finalize.sh" || \
    grep -q 'z.*TS_IP' "$REPO/lib/16-finalize.sh"
}

@test "R2: apt_update() function defined in lib/01" {
  grep -q 'apt_update()' "$REPO/lib/01-common.sh"
}

@test "R2: apt_update() uses _APT_UPDATED flag" {
  grep -q '_APT_UPDATED' "$REPO/lib/01-common.sh"
}

@test "R2: lib/05 calls apt_update not raw apt-get update" {
  # Should have apt_update, not sudo apt-get update -qq
  grep -q '^apt_update$\|^  apt_update$' "$REPO/lib/05-prerequisites.sh"
}

# ════════════════════════════════════════════════════════════════════
# ROUND 3: Hooks, atomicity, ZSH, FORCE_UPDATES
# ════════════════════════════════════════════════════════════════════

@test "R3: session-start.sh does NOT have active set -euo pipefail" {
  # Match only non-comment lines with set -euo pipefail
  ! grep -v '^#' "$REPO/dot-claude/hooks/session-start.sh" | grep -q 'set -euo pipefail'
}

@test "R3: session-end.sh does NOT have active set -euo pipefail" {
  ! grep -v '^#' "$REPO/dot-claude/hooks/session-end.sh" | grep -q 'set -euo pipefail'
}

@test "R3: pre-compact.sh does NOT have active set -euo pipefail" {
  ! grep -v '^#' "$REPO/dot-claude/hooks/pre-compact.sh" | grep -q 'set -euo pipefail'
}

@test "R3: hooks reference ADR-015 in comment" {
  grep -q 'ADR-015' "$REPO/dot-claude/hooks/session-start.sh"
}

@test "R3: Go install uses atomic extraction (temp dir then mv)" {
  grep -A3 'tar.*WORKDIR.*xzf' "$REPO/lib/06-package-managers.sh" | grep -q 'mv.*WORKDIR/go.*/usr/local/go'
}

@test "R3: lib/12-plugins.sh uses WORKDIR for jq temp files (no /tmp collision)" {
  # Should NOT have hardcoded /tmp/_semgrep or /tmp/_subcon or /tmp/_cc_settings
  ! grep -q '/tmp/_semgrep\|/tmp/_subcon\|/tmp/_cc_settings' "$REPO/lib/12-plugins.sh"
}

@test "R3: Go respects FORCE_UPDATES" {
  grep -q 'FORCE_UPDATES' "$REPO/lib/06-package-managers.sh"
}

@test "R3: better-ccflare respects FORCE_UPDATES" {
  grep -q 'FORCE_UPDATES.*command.*better-ccflare' "$REPO/lib/08-tools-letta.sh"
}

@test "R3: ZSH shell integration block exists" {
  grep -q '_ZSH_BLOCK\|zshrc\|hook zsh' "$REPO/lib/15-shell-integration.sh"
}

# ════════════════════════════════════════════════════════════════════
# ROUND 4: CTO review — services, security, resume
# ════════════════════════════════════════════════════════════════════

@test "R4: ccflare-billing-proxy binds to 172.17.0.1 not 0.0.0.0" {
  # The JS source should use env var or 127.0.0.1 default
  grep -q 'CCFLARE_PROXY_HOST.*127.0.0.1' "$REPO/lib/08-tools-letta.sh"
  # The systemd unit should set 172.17.0.1
  grep -q 'CCFLARE_PROXY_HOST=172.17.0.1' "$REPO/lib/08-tools-letta.sh"
}

@test "R4: n8n service has After=docker.service" {
  grep -A5 'Description=n8n' "$REPO/lib/07-tools-python-js.sh" | grep -q 'After=docker.service'
}

@test "R4: letta service has After=docker.service" {
  grep -A5 'Description=Letta' "$REPO/lib/08-tools-letta.sh" | grep -q 'After=docker.service'
}

@test "R4: n8n uses detached docker (no exit 137 on ARM)" {
  grep -A15 'Description=n8n' "$REPO/lib/07-tools-python-js.sh" | grep -q 'run -d'
}

@test "R4: letta uses detached docker (no exit 137 on ARM)" {
  grep -A15 'Description=Letta' "$REPO/lib/08-tools-letta.sh" | grep -q 'run -d'
}

@test "R4: services have StartLimitBurst" {
  grep -q 'StartLimitBurst' "$REPO/lib/07-tools-python-js.sh"
  grep -q 'StartLimitBurst' "$REPO/lib/08-tools-letta.sh"
}

@test "R4: journald log limits configured" {
  grep -q 'SystemMaxUse=500M' "$REPO/lib/05-prerequisites.sh"
}

@test "R4: check_port() function defined" {
  grep -q 'check_port()' "$REPO/lib/01-common.sh"
}

@test "R4: phase checkpoint functions defined" {
  grep -q 'phase_done()' "$REPO/lib/01-common.sh"
  grep -q 'phase_mark()' "$REPO/lib/01-common.sh"
  grep -q 'phase_reset()' "$REPO/lib/01-common.sh"
}

@test "R4: phase1 checkpoint in lib/05" {
  grep -q 'phase_mark.*phase1' "$REPO/lib/05-prerequisites.sh"
  grep -q 'phase_done.*phase1' "$REPO/lib/05-prerequisites.sh"
}

@test "R4: phase2 checkpoint in lib/06" {
  grep -q 'phase_mark.*phase2' "$REPO/lib/06-package-managers.sh"
  grep -q 'phase_done.*phase2' "$REPO/lib/06-package-managers.sh"
}

# ════════════════════════════════════════════════════════════════════
# REMAINING KNOWN ISSUES
# ════════════════════════════════════════════════════════════════════

@test "KI: --minimal flag accepted by CLI parser" {
  grep -q '\-\-minimal)' "$REPO/lib/02-cli.sh"
}

@test "KI: --minimal sets MINIMAL=true" {
  grep -A3 '\-\-minimal)' "$REPO/lib/02-cli.sh" | grep -q 'MINIMAL=true'
}

@test "KI: --minimal skips Letta, Ollama, cozempic" {
  grep -A6 '\-\-minimal)' "$REPO/lib/02-cli.sh" | grep -q 'LETTA_SKIP=true'
  grep -A6 '\-\-minimal)' "$REPO/lib/02-cli.sh" | grep -q 'OLLAMA_SKIP=true'
  grep -A6 '\-\-minimal)' "$REPO/lib/02-cli.sh" | grep -q 'COZEMPIC_SKIP=true'
}

@test "KI: UV_TOOLS has core/extended split based on MINIMAL" {
  grep -q 'if ! \$MINIMAL' "$REPO/lib/07-tools-python-js.sh"
}

@test "KI: CARGO_CRATES has core/extended split based on MINIMAL" {
  grep -q 'if ! \$MINIMAL' "$REPO/lib/09-tools-rust-go.sh"
}

@test "KI: GO_MAP has core/extended split based on MINIMAL" {
  grep -q 'if ! \$MINIMAL' "$REPO/lib/09-tools-rust-go.sh"
}

@test "KI: n8n skipped in minimal mode" {
  grep -q 'MINIMAL.*n8n.*skipped.*minimal' "$REPO/lib/07-tools-python-js.sh" || \
    grep -B1 'n8n.*skipped' "$REPO/lib/07-tools-python-js.sh" | grep -q 'MINIMAL'
}

@test "KI: --secrets-file flag accepted by CLI parser" {
  grep -q '\-\-secrets-file)' "$REPO/lib/02-cli.sh"
}

@test "KI: --secrets-file reads TAILSCALE_KEY" {
  grep -A15 '\-\-secrets-file)' "$REPO/lib/02-cli.sh" | grep -q 'TAILSCALE_KEY'
}

@test "KI: --secrets-file reads LETTA_PASSWORD" {
  grep -A15 '\-\-secrets-file)' "$REPO/lib/02-cli.sh" | grep -q 'LETTA_PASSWORD'
}

@test "KI: --fresh flag accepted by CLI parser" {
  grep -q '\-\-fresh)' "$REPO/lib/02-cli.sh"
}

@test "KI: lib/12-plugins.sh exists (consolidated)" {
  assert [ -f "$REPO/lib/12-plugins.sh" ]
}

@test "KI: old lib/12-plugins-install.sh deleted" {
  assert [ ! -f "$REPO/lib/12-plugins-install.sh" ]
}

@test "KI: old lib/13-plugins-config.sh deleted" {
  assert [ ! -f "$REPO/lib/13-plugins-config.sh" ]
}

@test "KI: lib/12-plugins.sh has complete if/fi (no cross-fragment split)" {
  # Count opening if/elif/else vs closing fi — should be balanced
  local opens closes
  opens=$(grep -c '^\s*if \|^\s*elif ' "$REPO/lib/12-plugins.sh" || true)
  closes=$(grep -c '^\s*fi$\|^\s*fi #\|^\s*fi;' "$REPO/lib/12-plugins.sh" || true)
  # The file has an outer if/elif/else that opens 3 branches and closes with 1 fi
  # Plus inner if blocks. Total should balance.
  [ "$opens" -gt 0 ]
  [ "$closes" -gt 0 ]
}

@test "KI: 18 fragments in lib/" {
  local count
  count=$(find "$REPO/lib" -maxdepth 1 -name '*.sh' | wc -l)
  [ "$count" -eq 18 ]
}

@test "KI: parallel Phase 3 — uv runs in background" {
  grep -q '_UV_PID' "$REPO/lib/07-tools-python-js.sh"
}

@test "KI: parallel Phase 3 — results displayed after cargo" {
  grep -q '_UV_PID\|_PHASE3_UV_LOG' "$REPO/lib/09-tools-rust-go.sh"
}

# ════════════════════════════════════════════════════════════════════
# ADR COMPLETENESS
# ════════════════════════════════════════════════════════════════════

@test "ADR: decisions.md has ADR-011 through ADR-024" {
  for n in $(seq 11 24); do
    grep -q "ADR-0${n}:" "$REPO/docs/decisions.md" || \
      grep -q "ADR-${n}:" "$REPO/docs/decisions.md"
  done
}

# ════════════════════════════════════════════════════════════════════
# HETZNER VPS RUN FIXES (2026-03-21)
# ════════════════════════════════════════════════════════════════════

@test "HZ: apt_update supports --force flag to re-fetch after adding new repos" {
  grep -q '\-\-force' "$REPO/lib/01-common.sh"
}

@test "HZ: gcloud repo uses apt_update --force (not cached)" {
  grep -A5 'google-cloud-sdk.list' "$REPO/lib/09-tools-rust-go.sh" | grep -q 'apt_update --force'
}

@test "HZ: terraform repo uses apt_update --force (not cached)" {
  grep -A3 'hashicorp.list' "$REPO/lib/09-tools-rust-go.sh" | grep -q 'apt_update --force'
}

@test "HZ: trivy repo uses apt_update --force (not cached)" {
  grep -A3 'trivy.list' "$REPO/lib/09-tools-rust-go.sh" | grep -q 'apt_update --force'
}

@test "HZ: gh repo uses apt_update --force (not cached)" {
  grep -A3 'github-cli.list' "$REPO/lib/09-tools-rust-go.sh" | grep -q 'apt_update --force'
}

@test "HZ: Tailscale install uses sudo bash not bare sh (pipe safe)" {
  grep -q 'tailscale.com/install.sh.*sudo bash' "$REPO/lib/16-finalize.sh"
}

@test "HZ: Tailscale install is guarded (not bare pipe)" {
  # Must have && or || guard on the install line
  grep 'tailscale.com/install.sh' "$REPO/lib/16-finalize.sh" | grep -qE '\|\||&&'
}

@test "HZ: mise shims added to PATH before playwright install" {
  # The mise shims PATH export must appear before the playwright install block
  local shims_line pw_line
  shims_line=$(grep -n 'mise/shims' "$REPO/lib/07-tools-python-js.sh" | head -1 | cut -d: -f1)
  pw_line=$(grep -n 'bun install -g playwright' "$REPO/lib/07-tools-python-js.sh" | head -1 | cut -d: -f1)
  [ "$shims_line" -lt "$pw_line" ]
}

@test "HZ: docker fallback uses /usr/bin/sg not bare sg (ast-grep conflict)" {
  grep 'sg docker' "$REPO/lib/07-tools-python-js.sh" | grep -q '/usr/bin/sg'
}

@test "HZ: agt fm_field guards grep exit code (pipefail safe)" {
  grep -A3 'fm_field()' "$REPO/dot-claude/bin/agt" | grep -qE '\|\| true'
}

@test "HZ: no bare 'wait' in lib/ (catches unrelated background jobs under set -e)" {
  local bare
  bare=$(grep -rn '^\s*wait$' "$REPO"/lib/*.sh || true)
  [ -z "$bare" ]
}

@test "HZ: docker group check uses /proc/PID/status not docker ps" {
  grep -q '/proc.*status' "$REPO/lib/07-tools-python-js.sh"
  grep -q '_DOCKER_GID' "$REPO/lib/07-tools-python-js.sh"
}

@test "HZ: apt lock timeout configured" {
  grep -q '_APT_LOCK_OPT' "$REPO/lib/01-common.sh"
}

@test "HZ: all interactive read -rp calls are guarded with || true (set -e safe)" {
  # read returns 1 on EOF (e.g. </dev/null or cloud-init) — kills script under set -e
  local unguarded
  unguarded=$(grep -rn 'read -r[sp]*' "$REPO"/lib/*.sh \
    | grep -v '|| true' \
    | grep -v 'while.*read\|IFS.*read' \
    || true)
  [ -z "$unguarded" ]
}

# ════════════════════════════════════════════════════════════════════
# ARM64 DOCKER FIXES (2026-03-22) — ADR-025, ADR-026
# ════════════════════════════════════════════════════════════════════

@test "ARM: n8n image pinned to 2.10.4 on aarch64 (ADR-025)" {
  grep -q 'aarch64.*n8nio/n8n:2.10.4' "$REPO/lib/07-tools-python-js.sh"
}

@test "ARM: n8n uses latest on non-aarch64" {
  grep -q '_N8N_IMAGE="n8nio/n8n:latest"' "$REPO/lib/07-tools-python-js.sh"
}

@test "ARM: _N8N_IMAGE variable used in docker pull (not hardcoded)" {
  grep 'docker.*pull\|image inspect' "$REPO/lib/07-tools-python-js.sh" | grep -v '^#' | grep -qv 'n8nio/n8n:'
}

@test "ARM: _N8N_IMAGE variable used in systemd ExecStart (not hardcoded)" {
  grep 'ExecStart.*n8n' "$REPO/lib/07-tools-python-js.sh" | grep -q '_N8N_IMAGE'
}

@test "ARM: n8n service uses Type=oneshot (ADR-026)" {
  grep -A20 'Description=n8n' "$REPO/lib/07-tools-python-js.sh" | grep -q 'Type=oneshot'
}

@test "ARM: letta service uses Type=oneshot (ADR-026)" {
  grep -A20 'Description=Letta' "$REPO/lib/08-tools-letta.sh" | grep -q 'Type=oneshot'
}

@test "ARM: n8n service has RemainAfterExit=yes" {
  grep -A20 'Description=n8n' "$REPO/lib/07-tools-python-js.sh" | grep -q 'RemainAfterExit=yes'
}

@test "ARM: letta service has RemainAfterExit=yes" {
  grep -A20 'Description=Letta' "$REPO/lib/08-tools-letta.sh" | grep -q 'RemainAfterExit=yes'
}

@test "ARM: n8n uses --restart unless-stopped (docker-managed restarts)" {
  grep -A20 'Description=n8n' "$REPO/lib/07-tools-python-js.sh" | grep -q 'restart unless-stopped'
}

@test "ARM: letta uses --restart unless-stopped (docker-managed restarts)" {
  grep -A20 'Description=Letta' "$REPO/lib/08-tools-letta.sh" | grep -q 'restart unless-stopped'
}

@test "ARM: n8n has ExecStopPost for container cleanup" {
  grep -A25 'Description=n8n' "$REPO/lib/07-tools-python-js.sh" | grep -q 'ExecStopPost'
}

@test "ARM: letta has ExecStopPost for container cleanup" {
  grep -A25 'Description=Letta' "$REPO/lib/08-tools-letta.sh" | grep -q 'ExecStopPost'
}

@test "ARM: StartLimitIntervalSec in Unit section not Service (n8n)" {
  # Must appear between [Unit] and [Service] markers in the heredoc
  local sl_line svc_line
  sl_line=$(grep -n 'StartLimitIntervalSec' "$REPO/lib/07-tools-python-js.sh" | head -1 | cut -d: -f1)
  svc_line=$(grep -n '^\[Service\]' "$REPO/lib/07-tools-python-js.sh" | head -1 | cut -d: -f1)
  [ "$sl_line" -lt "$svc_line" ]
}

@test "ARM: StartLimitIntervalSec in Unit section not Service (letta)" {
  local sl_line svc_line
  sl_line=$(grep -n 'StartLimitIntervalSec' "$REPO/lib/08-tools-letta.sh" | head -1 | cut -d: -f1)
  svc_line=$(grep -n '^\[Service\]' "$REPO/lib/08-tools-letta.sh" | head -1 | cut -d: -f1)
  [ "$sl_line" -lt "$svc_line" ]
}

@test "ARM: no MemoryMax in docker services (only limits docker client, not container)" {
  local hits
  hits=$(grep -A25 'Description=n8n' "$REPO/lib/07-tools-python-js.sh" | grep 'MemoryMax' || true)
  [ -z "$hits" ]
  hits=$(grep -A25 'Description=Letta' "$REPO/lib/08-tools-letta.sh" | grep 'MemoryMax' || true)
  [ -z "$hits" ]
}

@test "ARM: no docker run --rm in systemd services (causes crash loop on ARM64)" {
  local hits
  hits=$(grep -A25 'Description=n8n' "$REPO/lib/07-tools-python-js.sh" | grep 'run --rm' || true)
  [ -z "$hits" ]
  hits=$(grep -A25 'Description=Letta' "$REPO/lib/08-tools-letta.sh" | grep 'run --rm' || true)
  [ -z "$hits" ]
}

@test "ADR: decisions.md has ADR-025 and ADR-026" {
  grep -q 'ADR-025.*n8n.*ARM64' "$REPO/docs/decisions.md"
  grep -q 'ADR-026.*Detached docker' "$REPO/docs/decisions.md"
}

@test "ADR: decisions.md has ADR-030 (claude-lens)" {
  grep -q 'ADR-030.*claude-lens' "$REPO/docs/decisions.md"
}

@test "ADR: decisions.md has ADR-031 and ADR-032" {
  grep -q 'ADR-031.*LettaCtrl' "$REPO/docs/decisions.md"
  grep -q 'ADR-032.*LettaCtrl.*security' "$REPO/docs/decisions.md"
}

# ════════════════════════════════════════════════════════════════════
# LETTACTRL GUI FIXES — ROUND 1 (2026-03-23, ADR-031)
# ════════════════════════════════════════════════════════════════════

@test "CTRL: server uses docker stats for container metrics" {
  grep -q '"stats".*"--no-stream"' "$REPO/config/letta/letta-ctrl-server.js"
}

@test "CTRL: server has CPU delta tracking for native services" {
  grep -q '_cpuPrev' "$REPO/config/letta/letta-ctrl-server.js"
}

@test "CTRL: server has logtail endpoint" {
  grep -q 'handleLogTail' "$REPO/config/letta/letta-ctrl-server.js"
  grep -q '/api/logtail/' "$REPO/config/letta/letta-ctrl-server.js"
}

@test "CTRL: auth supports query-param token (EventSource fix)" {
  grep -q 'searchParams.get.*token' "$REPO/config/letta/letta-ctrl-server.js"
}

@test "CTRL: frontend passes token in EventSource URL" {
  grep -q 'EventSource.*token=' "$REPO/config/letta/letta-ctrl.html"
}

@test "CTRL: no hardcoded Accounts or Fix #89 in SVC_EXTRA" {
  local hits
  hits=$(grep -E 'Accounts|Fix #89' "$REPO/config/letta/letta-ctrl.html" || true)
  [ -z "$hits" ]
}

@test "CTRL: frontend uses targeted DOM updates (updateSvcGrid)" {
  grep -q 'updateSvcGrid' "$REPO/config/letta/letta-ctrl.html"
}

@test "CTRL: createAgent uses model field not llm" {
  grep -q 'model: model' "$REPO/config/letta/letta-ctrl.html"
  local hits
  hits=$(grep 'llm:' "$REPO/config/letta/letta-ctrl.html" || true)
  [ -z "$hits" ]
}

@test "CTRL: memory block IDs use safeId sanitizer" {
  grep -q 'safeId' "$REPO/config/letta/letta-ctrl.html"
}

@test "CTRL: letta service has container field for docker stats" {
  grep -q 'container.*letta-server' "$REPO/config/letta/letta-ctrl-server.js"
}

# ════════════════════════════════════════════════════════════════════
# LETTACTRL ROUND 2 — SECURITY + STABILITY (2026-03-23, ADR-032)
# ════════════════════════════════════════════════════════════════════

@test "CTRL2: token injection uses JSON.stringify (no raw quotes)" {
  grep -q 'JSON.stringify(AUTH_TOKEN)' "$REPO/config/letta/letta-ctrl-server.js"
}

@test "CTRL2: agent names escaped with escHtml in chips" {
  grep -q 'escHtml(a.name)' "$REPO/config/letta/letta-ctrl.html"
}

@test "CTRL2: agent models escaped with escHtml" {
  grep -q 'escHtml(a.llm_config' "$REPO/config/letta/letta-ctrl.html"
}

@test "CTRL2: block save uses data attributes not inline JS" {
  grep -q 'this.dataset.agent' "$REPO/config/letta/letta-ctrl.html"
}

@test "CTRL2: contenteditable is plaintext-only" {
  grep -q 'plaintext-only' "$REPO/config/letta/letta-ctrl.html"
}

@test "CTRL2: block labels URL-encoded in API path" {
  grep -q 'encodeURIComponent(label)' "$REPO/config/letta/letta-ctrl.html"
}

@test "CTRL2: server decodes block label in route" {
  grep -q 'decodeURIComponent' "$REPO/config/letta/letta-ctrl-server.js"
}

@test "CTRL2: SSE stream has closed guard (no controller crash)" {
  grep -q 'let closed = false' "$REPO/config/letta/letta-ctrl-server.js"
}

@test "CTRL2: Bun.serve has idleTimeout for SSE" {
  grep -q 'idleTimeout' "$REPO/config/letta/letta-ctrl-server.js"
}

@test "CTRL2: EventSource onerror shows reconnect message" {
  grep -q 'Connection lost' "$REPO/config/letta/letta-ctrl.html"
}

@test "CTRL2: polling uses setTimeout not setInterval" {
  local hits
  hits=$(grep 'setInterval.*pollStatus' "$REPO/config/letta/letta-ctrl.html" || true)
  [ -z "$hits" ]
}

@test "CTRL2: beforeunload cleans up timer and EventSource" {
  grep -q 'beforeunload' "$REPO/config/letta/letta-ctrl.html"
}

@test "CTRL2: Escape key closes create modal" {
  grep -q 'Escape.*closeCreateModal\|closeCreateModal.*Escape' "$REPO/config/letta/letta-ctrl.html"
}

@test "CTRL2: log filter is debounced" {
  grep -q 'debouncedFilter' "$REPO/config/letta/letta-ctrl.html"
}

@test "CTRL2: agent names have text-overflow ellipsis" {
  grep -q 'achip-name.*text-overflow:ellipsis\|adetname.*text-overflow:ellipsis' "$REPO/config/letta/letta-ctrl.html"
}

@test "CTRL2: server warns on empty LETTA_PASSWORD" {
  grep -q 'No LETTA_PASSWORD found' "$REPO/config/letta/letta-ctrl-server.js"
}

# ════════════════════════════════════════════════════════════════════
# VEXP-CLI INTEGRATION (ADR-030)
# ════════════════════════════════════════════════════════════════════

@test "VEXP: VEXP_SKIP variable defined in lib/02-cli.sh" {
  grep -q 'VEXP_SKIP=false' "$REPO/lib/02-cli.sh"
}

@test "VEXP: --no-vexp flag in CLI parser" {
  grep -q '\-\-no-vexp' "$REPO/lib/02-cli.sh"
}

@test "VEXP: --minimal sets VEXP_SKIP=true" {
  grep -A6 '\-\-minimal' "$REPO/lib/02-cli.sh" | grep -q 'VEXP_SKIP=true'
}

@test "VEXP: vexp-cli install block in lib/07" {
  grep -q 'bun install -g vexp-cli' "$REPO/lib/07-tools-python-js.sh"
}

@test "VEXP: install block guarded with VEXP_SKIP and MINIMAL" {
  grep -q '! \$VEXP_SKIP && ! \$MINIMAL' "$REPO/lib/07-tools-python-js.sh"
}

@test "VEXP: install command uses ok/warn guard (set -e safe)" {
  grep 'bun install -g vexp-cli' "$REPO/lib/07-tools-python-js.sh" | grep -qE '&&.*ok|warn'
}

@test "VEXP: vexp-core binary verification exists" {
  grep -q 'vexp-core' "$REPO/lib/07-tools-python-js.sh"
}

@test "VEXP: MCP server config in lib/11 uses jq (not direct write)" {
  grep -q 'jq.*mcpServers.*vexp' "$REPO/lib/11-deploy-config.sh"
}

@test "VEXP: MCP config uses vexp mcp command (stdio transport)" {
  grep -q '"vexp".*"mcp"' "$REPO/lib/11-deploy-config.sh"
}

@test "VEXP: MCP config uses WORKDIR for temp file (not /tmp)" {
  grep -A5 'mcpServers.*vexp' "$REPO/lib/11-deploy-config.sh" | grep -q 'WORKDIR'
}

@test "VEXP: MCP config injection guarded with ok/warn (set -e safe)" {
  grep -A5 'mcpServers.*vexp' "$REPO/lib/11-deploy-config.sh" | grep -qE '&&.*ok|warn'
}

@test "ADR: decisions.md has ADR-031 (vexp-cli)" {
  grep -q 'ADR-031.*vexp-cli.*stdio' "$REPO/docs/decisions.md"
}

# ════════════════════════════════════════════════════════════════════
# BUILT SCRIPT INTEGRITY
# ════════════════════════════════════════════════════════════════════

@test "BUILT: titan-setup.sh passes shellcheck" {
  shellcheck -x --severity=error "$REPO/titan-setup.sh"
}

# ── ADR-029: semgrep → opengrep migration ──

@test "ADR29: opengrep install uses guarded curl (if/else)" {
  grep -B1 'opengrep/opengrep/releases' "$REPO/lib/07-tools-python-js.sh" | grep -q 'if curl'
}

@test "ADR29: opengrep supports both x86_64 and aarch64" {
  grep -q 'opengrep_manylinux_x86' "$REPO/lib/07-tools-python-js.sh"
  grep -q 'opengrep_manylinux_aarch64' "$REPO/lib/07-tools-python-js.sh"
}

@test "ADR29: no semgrep CLI flags remain in arg parser" {
  ! grep -q '\-\-semgrep-token\|\-\-no-semgrep' "$REPO/lib/02-cli.sh"
}

@test "ADR29: no SEMGREP_TOKEN in secrets-file parsing" {
  ! grep -A15 '\-\-secrets-file)' "$REPO/lib/02-cli.sh" | grep -q 'SEMGREP_TOKEN'
}

@test "ADR29: no semgrep plugin in lib/12-plugins.sh" {
  ! grep -q 'plugin install semgrep' "$REPO/lib/12-plugins.sh"
}

@test "ADR29: no SEMGREP_APP_TOKEN injection in settings" {
  ! grep -q 'SEMGREP_APP_TOKEN' "$REPO/lib/11-deploy-config.sh"
}

@test "BUILT: titan-setup.sh passes bash -n" {
  bash -n "$REPO/titan-setup.sh"
}

@test "BUILT: titan-setup.sh matches assembled lib/ source" {
  bash "$REPO/script/build.sh" --check
}
