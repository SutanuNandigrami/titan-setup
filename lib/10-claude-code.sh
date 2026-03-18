section "Phase 4/6 — Claude Code CLI"

if command -v claude &>/dev/null && [[ -z "$CC_VERSION" ]]; then
  ok "Claude Code already installed: $(claude --version 2>/dev/null || echo 'installed')"
  echo "  Run 'claude doctor' to verify health"
else
  echo "  Installing Claude Code${CC_VERSION:+ v${CC_VERSION}} (native binary)..."
  if [[ -n "$CC_VERSION" ]]; then
    curl -fsSL https://claude.ai/install.sh | bash -s "$CC_VERSION"
  else
    curl -fsSL https://claude.ai/install.sh | bash
  fi
  ok "Claude Code installed${CC_VERSION:+ v${CC_VERSION}}"
  echo ""
  echo "  After this script finishes:"
  echo "    1. Run: claude"
  echo "    2. Authenticate with your Anthropic account"
  echo "    3. Run: claude doctor   (to verify)"
fi

# ─── Claude Desktop (desktop only — Electron GUI app, x86_64 only) ───
if [[ "$INSTALL_MODE" == "desktop" ]] && [[ "$ARCH_AMD" == "amd64" ]]; then
  if ! command -v claude-desktop &>/dev/null && ! dpkg -l claude-desktop-bin &>/dev/null 2>&1; then
    echo "  Installing Claude Desktop..."
    curl -fsSL https://patrickjaja.github.io/claude-desktop-bin/install.sh | sudo bash
    sudo apt install -y claude-desktop-bin
    ok "Claude Desktop"
  else
    ok "Claude Desktop (exists)"
  fi

  # ─── Claude Cowork Service (desktop only — community package, x86_64 only) ───
  if ! dpkg -l claude-cowork-service &>/dev/null 2>&1; then
    echo "  Installing Claude Cowork Service..."
    curl -fsSL https://patrickjaja.github.io/claude-cowork-service/install.sh | sudo bash
    sudo apt install -y claude-cowork-service
    ok "Claude Cowork Service"
  else
    ok "Claude Cowork Service (exists)"
  fi
elif [[ "$INSTALL_MODE" == "desktop" ]] && [[ "$ARCH_AMD" != "amd64" ]]; then
  warn "Claude Desktop: skipped (amd64 only, detected ${ARCH_AMD})"
fi


section "Phase 5/6 — Deploy ~/.claude/ Config"

