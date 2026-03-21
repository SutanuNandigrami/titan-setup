section "Phase 4/6 — Claude Code CLI"

# Always run installer — it's idempotent (installs if missing, updates if older, noop if current)
echo "  Installing/updating Claude Code${CC_VERSION:+ v${CC_VERSION}} (native binary)..."
if [[ -n "$CC_VERSION" ]]; then
  curl -fsSL https://claude.ai/install.sh | bash -s "$CC_VERSION" || true
else
  curl -fsSL https://claude.ai/install.sh | bash || true
fi
if command -v claude &>/dev/null; then
  ok "Claude Code${CC_VERSION:+ v${CC_VERSION}}: $(claude --version 2>/dev/null || echo 'installed')"
else
  warn "Claude Code install failed — install manually: curl -fsSL https://claude.ai/install.sh | bash"
fi

# ─── Claude Desktop (desktop only — Electron GUI app, x86_64 only) ───
if [[ "$INSTALL_MODE" == "desktop" ]] && [[ "$ARCH_AMD" == "amd64" ]]; then
  if ! command -v claude-desktop &>/dev/null && ! dpkg -l claude-desktop-bin &>/dev/null 2>&1; then
    echo "  Installing Claude Desktop..."
    if curl -fsSL https://patrickjaja.github.io/claude-desktop-bin/install.sh | sudo bash &&
      sudo apt-get install -y claude-desktop-bin; then
      ok "Claude Desktop"
    else
      warn "Claude Desktop install failed"
    fi
  else
    ok "Claude Desktop (exists)"
  fi

  # ─── Claude Cowork Service (desktop only — community package, x86_64 only) ───
  if ! dpkg -l claude-cowork-service &>/dev/null 2>&1; then
    echo "  Installing Claude Cowork Service..."
    if curl -fsSL https://patrickjaja.github.io/claude-cowork-service/install.sh | sudo bash &&
      sudo apt-get install -y claude-cowork-service; then
      ok "Claude Cowork Service"
    else
      warn "Claude Cowork Service install failed"
    fi
  else
    ok "Claude Cowork Service (exists)"
  fi
elif [[ "$INSTALL_MODE" == "desktop" ]] && [[ "$ARCH_AMD" != "amd64" ]]; then
  warn "Claude Desktop: skipped (amd64 only, detected ${ARCH_AMD})"
fi

section "Phase 5/6 — Deploy ~/.claude/ Config"
