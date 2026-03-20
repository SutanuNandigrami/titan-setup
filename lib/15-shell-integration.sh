section "Phase 6/6 — Shell Integration"

# Build the shell config block
_BASH_BLOCK='
# ══════ Titan CLI Arsenal ══════
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.cargo/bin:$HOME/go/bin:/usr/local/go/bin:$PATH"
eval "$(direnv hook bash)"
eval "$(mise activate bash)"
export GIT_PAGER="delta"
command -v pueued &>/dev/null && pueued -d 2>/dev/null  # task queue daemon
# ══════════════════════════════'

_ZSH_BLOCK='
# ══════ Titan CLI Arsenal ══════
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.cargo/bin:$HOME/go/bin:/usr/local/go/bin:$PATH"
eval "$(direnv hook zsh)"
eval "$(mise activate zsh)"
export GIT_PAGER="delta"
command -v pueued &>/dev/null && pueued -d 2>/dev/null  # task queue daemon
# ══════════════════════════════'

if ! grep -q "Titan CLI Arsenal" "$HOME/.bashrc" 2>/dev/null; then
  echo "$_BASH_BLOCK" >>"$HOME/.bashrc"
  ok "Shell integration added to ~/.bashrc"
else
  ok "Shell integration already in ~/.bashrc"
fi

if [[ -f "$HOME/.zshrc" ]] && ! grep -q "Titan CLI Arsenal" "$HOME/.zshrc" 2>/dev/null; then
  echo "$_ZSH_BLOCK" >>"$HOME/.zshrc"
  ok "Shell integration added to ~/.zshrc"
elif [[ -f "$HOME/.zshrc" ]]; then
  ok "Shell integration already in ~/.zshrc"
fi

# Git pager config
git config --global core.pager delta 2>/dev/null || true
git config --global interactive.diffFilter "delta --color-only" 2>/dev/null || true
git config --global delta.navigate true 2>/dev/null || true
git config --global delta.line-numbers true 2>/dev/null || true
git config --global delta.side-by-side true 2>/dev/null || true
ok "Git delta pager configured"
