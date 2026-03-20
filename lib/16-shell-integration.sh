section "Phase 6/6 — Shell Integration"

# Build the shell config block
SHELL_BLOCK='
# ══════ Titan CLI Arsenal ══════
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.cargo/bin:$HOME/go/bin:/usr/local/go/bin:$PATH"
eval "$(direnv hook bash)"
eval "$(mise activate bash)"
export GIT_PAGER="delta"
command -v pueued &>/dev/null && pueued -d 2>/dev/null  # task queue daemon
# ══════════════════════════════'

if ! grep -q "Titan CLI Arsenal" ~/.bashrc 2>/dev/null; then
  echo "$SHELL_BLOCK" >>~/.bashrc
  ok "Shell integration added to ~/.bashrc"
else
  ok "Shell integration already present"
fi

# Git pager config
git config --global core.pager delta 2>/dev/null || true
git config --global interactive.diffFilter "delta --color-only" 2>/dev/null || true
git config --global delta.navigate true 2>/dev/null || true
git config --global delta.line-numbers true 2>/dev/null || true
git config --global delta.side-by-side true 2>/dev/null || true
ok "Git delta pager configured"
