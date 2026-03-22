section "Phase 3/6 — 150+ CLI Tools"

# ── Parallel strategy: uv + bun install in background while cargo compiles in foreground ──
# uv, bun, and cargo use separate package managers with no shared state.
# Cargo is the bottleneck (~25-40 min); running uv/bun concurrently saves ~10-15 min.
_PHASE3_UV_LOG="$WORKDIR/phase3-uv.log"
_PHASE3_BUN_LOG="$WORKDIR/phase3-bun.log"

# ─── Python tools via uv (isolated venvs, zero system pollution) ───
echo -e "  ${CYAN}Python tools (uv):${NC}"

# Core Python tools (always installed)
UV_TOOLS=(
  "yq"           # yq — YAML/XML/TOML processor
  "semgrep"      # semgrep — static analysis
  "ansible-core" # ansible, ansible-playbook, ansible-galaxy + more
  "ansible-lint" # ansible-lint — linter for Ansible playbooks
  "pgcli"        # pgcli — Postgres with autocomplete
  "ruff"         # ruff — Python linter (replaces flake8+black+isort+pyflakes)
  "ast-grep-cli" # ast-grep, sg — structural code search
  "cozempic"     # cozempic — context bloat cleaner for Claude Code sessions
)
# Extended Python tools (skipped with --minimal)
if ! $MINIMAL; then
  UV_TOOLS+=(
    "sqlmap"             # sqlmap — SQL injection testing
    "mitmproxy"          # mitmproxy, mitmdump — HTTP/HTTPS proxy for debugging
    "cookiecutter"       # cookiecutter — project scaffolding from templates
    "notebooklm-mcp-cli" # nlm — Google NotebookLM CLI + MCP server
  )
fi

# Run uv tools in background (output to log, results shown after cargo phase)
(
  if $FORCE_UPDATES; then
    uv tool upgrade --all 2>/dev/null && echo "UV_UPGRADE=ok" || echo "UV_UPGRADE=warn"
  fi
  _uv_list=$(uv tool list 2>/dev/null)
  for tool in "${UV_TOOLS[@]}"; do
    if echo "$_uv_list" | grep -q "^${tool} "; then
      echo "UV_OK=$tool"
    elif uv tool install --force "$tool" &>/dev/null; then
      echo "UV_INSTALLED=$tool"
    else
      echo "UV_FAIL=$tool"
    fi
  done
) >"$_PHASE3_UV_LOG" 2>&1 &
_UV_PID=$!
echo "  uv tools installing in background (${#UV_TOOLS[@]} tools)..."

echo -e "\n  ${CYAN}Claude Code ecosystem tools (uv):${NC}"
command -v ccusage &>/dev/null && ok "ccusage (exists)" || { uv tool install ccusage 2>/dev/null && ok "ccusage" || warn "ccusage"; }
command -v sherlock &>/dev/null && ok "sherlock (exists)" || { uv tool install sherlock-project 2>/dev/null && ok "sherlock" || warn "sherlock"; }
# claude-agent-sdk is a library (not a CLI tool) — needs --break-system-packages on Ubuntu 24.04 externally-managed Python
_PYSITE="$HOME/.local/lib/python3.12/site-packages"
python3 -c "import claude_agent_sdk" 2>/dev/null && ok "claude-agent-sdk (exists)" ||
  { mkdir -p "$_PYSITE" && uv pip install --target "$_PYSITE" --quiet claude-agent-sdk 2>/dev/null &&
    ok "claude-agent-sdk" || warn "claude-agent-sdk (install manually: uv pip install --target ~/.local/lib/python3.12/site-packages claude-agent-sdk)"; }
unset _PYSITE

# sqlite-vec is installed to ~/.local/lib/python-libs/ as a memory library (used on-demand, not at startup)

# ─── JS tools via bun ───
echo -e "\n  ${CYAN}JS tools (bun):${NC}"

# Trust postinstall scripts for packages that need them (esbuild, puppeteer, canvas, etc.)
# Also skip puppeteer chromium download — we install chromium via playwright separately
cat >"$HOME/.bunfig.toml" <<'BUNFIG'
[install]
trustedDependencies = ["puppeteer", "esbuild", "@swc/core", "canvas", "node-gyp", "sharp", "fsevents"]

[install.scopes]
BUNFIG
export PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=1

BUN_TOOLS=("trash-cli" "tldr" "prettier" "repomix" "ccstatusline")
if $FORCE_UPDATES; then
  echo -e "  ${YELLOW}Force-updating all Bun tools...${NC}"
  for tool in "${BUN_TOOLS[@]}"; do
    run_q bun install -g "$tool" && ok "$tool (updated)" || warn "$tool update failed"
  done
else
  for tool in "${BUN_TOOLS[@]}"; do
    if bun pm ls -g 2>/dev/null | grep -q "$tool"; then
      ok "$tool (exists)"
    else
      echo -n "  Installing $tool..."
      run_q bun install -g "$tool" && echo -e " ${GREEN}✓${NC}" || echo -e " ${YELLOW}⚠${NC}"
    fi
  done
fi

command -v gemini &>/dev/null && ok "gemini-cli (exists)" || { run_q bun install -g @google/gemini-cli && ok "gemini-cli" || warn "gemini-cli"; }
command -v mmdc &>/dev/null && ok "mermaid-cli (exists)" || { run_q bun install -g @mermaid-js/mermaid-cli && ok "mermaid-cli" || warn "mermaid-cli"; }

# playwright — browser automation and E2E testing
# Ensure node is on PATH (mise shims may not be sourced in non-interactive context)
command -v node &>/dev/null || export PATH="$HOME/.local/share/mise/shims:$PATH"
if ! bun pm ls -g 2>/dev/null | grep -q playwright; then
  run_q bun install -g playwright && ok "playwright" || warn "playwright"
  # Install chromium: apt deps need root, browser download runs as current user
  if command -v playwright &>/dev/null; then
    # install-deps uses apt-get; titan has NOPASSWD sudo so playwright's internal sudo call works
    sudo -E env "PATH=$PATH" "$(command -v playwright)" install-deps chromium >>"$LOG_FILE" 2>&1 || true
    run_q playwright install chromium && ok "playwright chromium" ||
      warn "playwright chromium (install manually: playwright install chromium)"
  fi
else
  ok "playwright (exists)"
fi

# n8n — workflow automation server (runs as systemd user service via docker)
# Pin to 2.10.4 on ARM64 — isolated-vm segfaults on aarch64 Alpine (github.com/n8n-io/n8n/issues/26858)
_N8N_IMAGE="n8nio/n8n:latest"
[[ "$(uname -m)" == "aarch64" ]] && _N8N_IMAGE="n8nio/n8n:2.10.4"

if $MINIMAL; then
  ok "n8n (skipped — minimal mode)"
elif command -v docker &>/dev/null; then
  check_port 5678 "n8n" "n8n" || true
  # Add user to docker group and ensure daemon is running
  sudo systemctl enable --now docker 2>/dev/null || true

  # Enable systemd linger so user services start at boot without login
  loginctl enable-linger "$USER" 2>/dev/null || true

  # Ensure docker group membership is active in the systemd user manager.
  # usermod adds the group but user@.service may have started before docker
  # group existed. Check if systemd --user's process has the docker GID;
  # if not, restart it so child services (n8n, letta) can access the socket.
  sudo usermod -aG docker "$USER" 2>/dev/null || true
  _SYSD_PID=$(pgrep -u "$(id -u)" -f 'systemd --user' | head -1 || true)
  _DOCKER_GID=$(getent group docker | cut -d: -f3 || true)
  if [[ -n "$_SYSD_PID" && -n "$_DOCKER_GID" ]] &&
    ! grep -qw "$_DOCKER_GID" "/proc/$_SYSD_PID/status" 2>/dev/null; then
    sudo systemctl restart "user@$(id -u).service" 2>/dev/null || true
  fi

  # Pull image — skip if already present (idempotent re-run)
  # Use /usr/bin/sg explicitly — ast-grep-cli installs an 'sg' binary that shadows it
  if docker image inspect "$_N8N_IMAGE" &>/dev/null ||
    sudo docker image inspect "$_N8N_IMAGE" &>/dev/null; then
    ok "n8n docker image (exists: $_N8N_IMAGE)"
  elif docker pull "$_N8N_IMAGE" >>"$LOG_FILE" 2>&1 ||
    /usr/bin/sg docker -c "docker pull $_N8N_IMAGE" >>"$LOG_FILE" 2>&1 ||
    sudo docker pull "$_N8N_IMAGE" >>"$LOG_FILE" 2>&1; then
    ok "n8n docker image ($_N8N_IMAGE)"
  else
    warn "n8n docker pull failed (check: docker pull $_N8N_IMAGE)"
  fi

  # Fix n8n data directory permissions (container runs as uid 1000)
  mkdir -p "$HOME/.n8n"
  if [ "$(stat -c %u "$HOME/.n8n" 2>/dev/null)" != "1000" ]; then
    sudo chown -R 1000:1000 "$HOME/.n8n" 2>/dev/null || chown -R 1000:1000 "$HOME/.n8n" 2>/dev/null || true
  fi

  # Create systemd user service for n8n
  # Use detached docker + Type=oneshot — attached docker clients get SIGKILL'd
  # on ARM64 under systemd user sessions (exit 137 crash loop)
  mkdir -p "$HOME/.config/systemd/user"
  DOCKER_BIN=$(command -v docker)
  cat >"$HOME/.config/systemd/user/n8n.service" <<SERVICEEOF
[Unit]
Description=n8n workflow automation
After=docker.service default.target
Wants=docker.service
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=-${DOCKER_BIN} rm -f n8n
ExecStart=${DOCKER_BIN} run -d --name n8n --restart unless-stopped -p 127.0.0.1:5678:5678 -v %h/.n8n:/home/node/.n8n ${_N8N_IMAGE}
ExecStop=${DOCKER_BIN} stop n8n
ExecStopPost=-${DOCKER_BIN} rm -f n8n

[Install]
WantedBy=default.target
SERVICEEOF

  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable n8n 2>/dev/null || true
  systemctl --user start n8n 2>/dev/null || true
  ok "n8n service (systemctl --user status n8n | http://localhost:5678)"
  # docker group is applied via sg above — no re-login required
else
  warn "n8n skipped — Docker not available (install failed earlier or not supported)"
fi
