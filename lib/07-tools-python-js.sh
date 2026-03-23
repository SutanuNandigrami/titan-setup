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

# ─── opengrep — static analysis (self-contained binary, no Python needed) ───
# Replaces semgrep: LGPL 2.1 fork, no token required, better taint analysis
if command -v opengrep &>/dev/null && ! $FORCE_UPDATES; then
  ok "opengrep (exists)"
else
  case "$UNAME_ARCH" in
    x86_64) _og_bin="opengrep_manylinux_x86" ;;
    aarch64) _og_bin="opengrep_manylinux_aarch64" ;;
  esac
  if curl -fsSL "https://github.com/opengrep/opengrep/releases/latest/download/${_og_bin}" \
    -o /usr/local/bin/opengrep 2>>"$LOG_FILE"; then
    chmod +x /usr/local/bin/opengrep
    ok "opengrep $(opengrep --version 2>/dev/null | head -1 || true)"
  else
    warn "opengrep download failed (install manually: https://github.com/opengrep/opengrep)"
  fi
fi

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

BUN_TOOLS=("trash-cli" "tldr" "prettier" "repomix")
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

# vexp-cli — local-first context engine for AI coding agents (tree-sitter + dependency graph)
# Uses optional deps (@vexp/core-linux-x64 etc.) for platform-specific Rust binary — no postinstall needed
if ! $VEXP_SKIP && ! $MINIMAL; then
  if bun pm ls -g 2>/dev/null | grep -q "vexp-cli"; then
    ok "vexp-cli (exists)"
  else
    run_q bun install -g vexp-cli && ok "vexp-cli" || warn "vexp-cli (install manually: bun install -g vexp-cli)"
  fi
  # Verify vexp-core platform binary was installed via optional deps
  if command -v vexp &>/dev/null && vexp version &>/dev/null; then
    ok "vexp-core binary ($(vexp version 2>&1 | grep 'core:' | sed 's/.*: //' || echo 'ok'))"
  elif bun pm ls -g 2>/dev/null | grep -q "vexp-cli"; then
    warn "vexp-core binary missing — try: bun install -g @vexp/core-linux-$(uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/')"
  fi
fi

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

# ── n8n — workflow automation (native install via npm) ──────────────
# ADR-038: native npm install supersedes Docker (ADR-025 superseded)
# isolated-vm ARM64 fix shipped upstream (n8n PR #26765); Docker adds no value here
if $N8N_SKIP; then
  ok "n8n (skipped — --n8n-skip)"
elif $MINIMAL; then
  ok "n8n (skipped — minimal mode)"
else
  N8N_PORT="${N8N_PORT:-5678}"
  check_port "$N8N_PORT" "n8n" "n8n" || true

  # Migrate from Docker to native (idempotent on re-runs)
  if [[ -f "$HOME/.config/systemd/user/n8n.service" ]] &&
    grep -q 'docker' "$HOME/.config/systemd/user/n8n.service" 2>/dev/null; then
    systemctl --user stop n8n 2>/dev/null || true
    systemctl --user disable n8n 2>/dev/null || true
    docker rm -f n8n 2>/dev/null || true
    ok "n8n: migrated from Docker (container removed, data preserved in ~/.n8n)"
  fi

  # Resolve npm — prefer mise shim (Node 22) over system npm (may be Node 18)
  _NPM_BIN="$HOME/.local/share/mise/shims/npm"
  [[ ! -x "$_NPM_BIN" ]] && _NPM_BIN=$(command -v npm 2>/dev/null || echo "")
  if [[ -z "$_NPM_BIN" ]]; then
    warn "n8n skipped — npm not found (mise Node not installed?)"
  else
    # Prefer mise shim for n8n — bun-installed n8n fails at runtime (Node version mismatch)
    _N8N_BIN="$HOME/.local/share/mise/shims/n8n"
    if [[ ! -x "$_N8N_BIN" ]]; then
      "$_NPM_BIN" install -g n8n >>"$LOG_FILE" 2>&1 &&
        ok "n8n installed" ||
        warn "n8n install failed (check $LOG_FILE)"
      # After install, mise reshims automatically
    else
      ok "n8n already installed ($("$_N8N_BIN" --version 2>/dev/null || echo 'unknown'))"
    fi

    # Clean crash artifacts from previous failed runs
    rm -f "$HOME/.n8n/crash.journal" 2>/dev/null || true

    # systemd user service — Type=simple, direct exec (no Docker)
    mkdir -p "$HOME/.config/systemd/user"
    _TZ=$(cat /etc/timezone 2>/dev/null || echo UTC)
    cat >"$HOME/.config/systemd/user/n8n.service" <<SERVICEEOF
[Unit]
Description=n8n workflow automation
After=network-online.target
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=simple
ExecStart=${_N8N_BIN} start
Environment=N8N_PORT=${N8N_PORT}
Environment=N8N_SECURE_COOKIE=false
Environment=GENERIC_TIMEZONE=${_TZ}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
SERVICEEOF

    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable n8n 2>/dev/null || true
    systemctl --user start n8n 2>/dev/null || true
    ok "n8n service (http://127.0.0.1:${N8N_PORT})"
  fi
fi

# ─── claudecodeui — web/mobile interface for Claude Code sessions ───
# Browse Claude Code sessions, file explorer, git, terminal from any device
# Auto-discovers sessions from ~/.claude/ — zero config
if $CLAUDECODEUI_SKIP || $MINIMAL; then
  ok "claudecodeui (skipped)"
else
  # Check node version — also try mise shims (not on PATH when running as root)
  _NODE_BIN=$(command -v node 2>/dev/null || echo "")
  [[ -z "$_NODE_BIN" && -x "$HOME/.local/share/mise/shims/node" ]] && _NODE_BIN="$HOME/.local/share/mise/shims/node"
  _NODE_VER=$("$_NODE_BIN" --version 2>/dev/null | sed 's/^v//' | cut -d. -f1 || echo "0")
  if [[ "$_NODE_VER" -lt 22 ]]; then
    warn "claudecodeui requires Node.js v22+ (found: v${_NODE_VER}) — skipping"
  else
    if bun pm ls -g 2>/dev/null | grep -q '@siteboon/claude-code-ui'; then
      ok "claudecodeui (exists)"
    else
      echo -n "  Installing claudecodeui..."
      run_q bun install -g @siteboon/claude-code-ui && echo -e " ${GREEN}✓${NC}" || echo -e " ${YELLOW}⚠${NC}"
    fi
    # Rebuild native modules (better-sqlite3, node-pty) for node ABI.
    # bun compiles them for bun's ABI; systemd service runs via node → SIGSEGV without this.
    _CCUI_DIR=$(bun pm ls -g 2>/dev/null | grep '@siteboon/claude-code-ui' | awk '{print $NF}' || true)
    [[ -z "$_CCUI_DIR" ]] && _CCUI_DIR="$(dirname "$(dirname "$(readlink -f "$(command -v cloudcli 2>/dev/null)")")" 2>/dev/null)"
    if [[ -d "$_CCUI_DIR/../../node_modules/better-sqlite3" ]]; then
      _NATIVE_ROOT="$_CCUI_DIR/../../node_modules"
      for _mod in better-sqlite3 node-pty; do
        if [[ -d "$_NATIVE_ROOT/$_mod" && -f "$_NATIVE_ROOT/$_mod/binding.gyp" ]]; then
          (cd "$_NATIVE_ROOT/$_mod" && npm rebuild --silent 2>/dev/null) || true
        fi
      done
      ok "claudecodeui: native modules rebuilt for node"
    fi

    if command -v cloudcli &>/dev/null; then
      check_port "$CLAUDECODEUI_PORT" "claudecodeui" || true

      _CLOUDCLI_BIN=$(command -v cloudcli)
      mkdir -p "$HOME/.config/systemd/user"
      cat >"$HOME/.config/systemd/user/claudecodeui.service" <<SERVICEEOF
[Unit]
Description=Claude Code UI — web interface for Claude Code sessions
After=default.target
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
ExecStart=${_CLOUDCLI_BIN}
Restart=on-failure
RestartSec=5
Environment="HOST=127.0.0.1"
Environment="SERVER_PORT=${CLAUDECODEUI_PORT}"
Environment="CLAUDE_CLI_PATH=$(command -v claude 2>/dev/null || echo claude)"
Environment="PATH=${HOME}/.local/share/mise/shims:${HOME}/.local/bin:${HOME}/.bun/bin:/usr/local/bin:/usr/bin:/bin"

[Install]
WantedBy=default.target
SERVICEEOF

      systemctl --user daemon-reload 2>/dev/null || true
      systemctl --user enable claudecodeui 2>/dev/null || true
      systemctl --user start claudecodeui 2>/dev/null || true
      ok "claudecodeui service (http://127.0.0.1:${CLAUDECODEUI_PORT})"
    else
      warn "claudecodeui: cloudcli not found — check: bun install -g @siteboon/claude-code-ui"
    fi
  fi
fi
