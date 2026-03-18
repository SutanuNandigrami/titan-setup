section "Phase 3/6 — 155+ CLI Tools"

# ─── Python tools via uv (isolated venvs, zero system pollution) ───
echo -e "  ${CYAN}Python tools (uv):${NC}"

UV_TOOLS=(
  "yq"              # yq — YAML/XML/TOML processor
  "semgrep"         # semgrep — static analysis
  "ansible-core"    # ansible, ansible-playbook, ansible-galaxy + more (NOT 'ansible' — that's the meta-pkg)
  "ansible-lint"    # ansible-lint — linter for Ansible playbooks
  "sqlmap"          # sqlmap — SQL injection testing
  "pgcli"           # pgcli — Postgres with autocomplete
  "ruff"            # ruff — Python linter (replaces flake8+black+isort+pyflakes)
  "ast-grep-cli"    # ast-grep, sg — structural code search
  "mitmproxy"       # mitmproxy, mitmdump — HTTP/HTTPS proxy for debugging
  "cookiecutter"    # cookiecutter — project scaffolding from templates
  "notebooklm-mcp-cli"  # nlm — Google NotebookLM CLI + MCP server
  "cozempic"            # cozempic — context bloat cleaner for Claude Code sessions
)

for tool in "${UV_TOOLS[@]}"; do
  if uv tool list 2>/dev/null | grep -q "^${tool} "; then
    ok "$tool (already installed)"
  else
    echo -n "  Installing $tool..."
    if uv tool install "$tool" &>/dev/null; then
      echo -e " ${GREEN}✓${NC}"
    else
      echo -e " ${YELLOW}⚠ failed (try: uv tool install $tool)${NC}"
    fi
  fi
done

echo -e "\n  ${CYAN}Claude Code ecosystem tools (uv):${NC}"
command -v ccusage &>/dev/null && ok "ccusage (exists)" || { uv tool install ccusage 2>/dev/null && ok "ccusage" || warn "ccusage"; }
command -v sherlock &>/dev/null && ok "sherlock (exists)" || { uv tool install sherlock-project 2>/dev/null && ok "sherlock" || warn "sherlock"; }
# claude-agent-sdk is a library (not a CLI tool) — needs --break-system-packages on Ubuntu 24.04 externally-managed Python
_PYSITE="$HOME/.local/lib/python3.12/site-packages"
python3 -c "import claude_agent_sdk" 2>/dev/null && ok "claude-agent-sdk (exists)" || \
  { mkdir -p "$_PYSITE" && uv pip install --target "$_PYSITE" --quiet claude-agent-sdk 2>/dev/null \
    && ok "claude-agent-sdk" || warn "claude-agent-sdk (install manually: uv pip install --target ~/.local/lib/python3.12/site-packages claude-agent-sdk)"; }
unset _PYSITE

# sqlite-vec is installed to ~/.local/lib/python-libs/ as a memory library (used on-demand, not at startup)

# ─── JS tools via bun ───
echo -e "\n  ${CYAN}JS tools (bun):${NC}"

# Trust postinstall scripts for packages that need them (esbuild, puppeteer, canvas, etc.)
# Also skip puppeteer chromium download — we install chromium via playwright separately
cat > "$HOME/.bunfig.toml" << 'BUNFIG'
[install]
trustedDependencies = ["puppeteer", "esbuild", "@swc/core", "canvas", "node-gyp", "sharp", "fsevents"]

[install.scopes]
BUNFIG
export PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=1

BUN_TOOLS=("trash-cli" "tldr" "prettier" "repomix" "ccstatusline")
for tool in "${BUN_TOOLS[@]}"; do
  if bun pm ls -g 2>/dev/null | grep -q "$tool"; then
    ok "$tool (exists)"
  else
    echo -n "  Installing $tool..."
    run_q bun install -g "$tool" && echo -e " ${GREEN}✓${NC}" || echo -e " ${YELLOW}⚠${NC}"
  fi
done

command -v gemini &>/dev/null && ok "gemini-cli (exists)" || { run_q bun install -g @google/gemini-cli && ok "gemini-cli" || warn "gemini-cli"; }
command -v mmdc &>/dev/null && ok "mermaid-cli (exists)" || { run_q bun install -g @mermaid-js/mermaid-cli && ok "mermaid-cli" || warn "mermaid-cli"; }

# playwright — browser automation and E2E testing
if ! bun pm ls -g 2>/dev/null | grep -q playwright; then
  run_q bun install -g playwright && ok "playwright" || warn "playwright"
  # Install chromium: apt deps need root, browser download runs as current user
  if command -v playwright &>/dev/null; then
    # install-deps uses apt-get; titan has NOPASSWD sudo so playwright's internal sudo call works
    sudo -E env "PATH=$PATH" "$(command -v playwright)" install-deps chromium >> "$LOG_FILE" 2>&1 || true
    run_q playwright install chromium && ok "playwright chromium" \
      || warn "playwright chromium (install manually: playwright install chromium)"
  fi
else
  ok "playwright (exists)"
fi

# n8n — workflow automation server (runs as systemd user service via docker)
if command -v docker &>/dev/null; then
  # Add user to docker group and ensure daemon is running
  sudo usermod -aG docker "$USER" 2>/dev/null || true
  sudo systemctl enable --now docker 2>/dev/null || true

  # Enable systemd linger so user services start at boot without login
  loginctl enable-linger "$USER" 2>/dev/null || true

  # Pull image — user is in docker group; fall back to sudo if socket isn't yet accessible
  if docker pull n8nio/n8n:latest >> "$LOG_FILE" 2>&1 \
      || sg docker -c "docker pull n8nio/n8n:latest" >> "$LOG_FILE" 2>&1 \
      || sudo docker pull n8nio/n8n:latest >> "$LOG_FILE" 2>&1; then
    ok "n8n docker image"
  else
    warn "n8n docker pull failed (check: docker pull n8nio/n8n:latest)"
  fi

  # Fix n8n data directory permissions (container runs as uid 1000)
  mkdir -p "$HOME/.n8n"
  if [ "$(stat -c %u "$HOME/.n8n" 2>/dev/null)" != "1000" ]; then
    sudo chown -R 1000:1000 "$HOME/.n8n" 2>/dev/null || chown -R 1000:1000 "$HOME/.n8n" 2>/dev/null || true
  fi

  # Create systemd user service for n8n
  mkdir -p "$HOME/.config/systemd/user"
  DOCKER_BIN=$(command -v docker)
  cat > "$HOME/.config/systemd/user/n8n.service" << SERVICEEOF
[Unit]
Description=n8n workflow automation
After=default.target

[Service]
Type=simple
ExecStartPre=-${DOCKER_BIN} rm -f n8n
ExecStart=${DOCKER_BIN} run --rm --name n8n -p 127.0.0.1:5678:5678 -v %h/.n8n:/home/node/.n8n n8nio/n8n
ExecStop=${DOCKER_BIN} stop n8n
Restart=on-failure
RestartSec=10

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
