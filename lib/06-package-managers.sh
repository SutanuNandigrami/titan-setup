if phase_done "phase2" && ! $FORCE_UPDATES; then
  section "Phase 2/6 — Package Managers (cached ✓)"
else
  section "Phase 2/6 — Package Managers"

  # ─── Rust / Cargo ───
  if command -v cargo &>/dev/null; then
    ok "cargo already installed: $(cargo --version)"
  else
    echo "  Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || true
    # shellcheck source=/dev/null
    [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
    if command -v cargo &>/dev/null; then
      ok "cargo installed: $(cargo --version)"
    else
      fail "cargo install failed"; exit 1
    fi
  fi
  # Ensure cargo binaries are on PATH for the rest of this script (idempotent)
  # shellcheck source=/dev/null
  [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

  # ─── uv (replaces pip, pipx, venv, pyenv) ───
  if command -v uv &>/dev/null; then
    ok "uv already installed: $(uv --version)"
  else
    echo "  Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh || true
    export PATH="$HOME/.local/bin:$PATH"
    if command -v uv &>/dev/null; then
      ok "uv installed: $(uv --version)"
    else
      fail "uv install failed"; exit 1
    fi
  fi
  # Ensure uv/uvx binaries are on PATH for the rest of this script
  export PATH="$HOME/.local/bin:$PATH"

  # ─── bun (replaces npm, npx for CLI tools) ───
  if command -v bun &>/dev/null; then
    ok "bun already installed: $(bun --version)"
  else
    echo "  Installing bun..."
    curl -fsSL https://bun.sh/install | bash || true
    export PATH="$HOME/.bun/bin:$PATH"
    if command -v bun &>/dev/null; then
      ok "bun installed: $(bun --version)"
    else
      warn "bun install failed — will retry later or install manually"
    fi
  fi
  # Ensure bun globals are on PATH for the rest of this script
  export PATH="$HOME/.bun/bin:$PATH"

  # ─── Go ───
  GO_LATEST=$(curl -s https://go.dev/VERSION?m=text | head -1 || true)
  GO_NEED_INSTALL=false
  if command -v go &>/dev/null && ! $FORCE_UPDATES; then
    GO_CURRENT=$(go version | grep -oP '\d+\.\d+\.\d+' || true)
    GO_LATEST_VER=${GO_LATEST#go}
    if [[ -z "$GO_CURRENT" ]]; then
      warn "go version parse failed — reinstalling"
      GO_NEED_INSTALL=true
    else
      # Compare major.minor — upgrade if current < latest major.minor
      GO_CUR_MINOR=$(echo "$GO_CURRENT" | cut -d. -f1-2)
      GO_LAT_MINOR=$(echo "$GO_LATEST_VER" | cut -d. -f1-2)
      if [ "$(printf '%s\n%s' "$GO_CUR_MINOR" "$GO_LAT_MINOR" | sort -V | head -1)" != "$GO_LAT_MINOR" ]; then
        echo "  Go $GO_CURRENT is outdated (latest: $GO_LATEST_VER) — upgrading..."
        GO_NEED_INSTALL=true
      else
        ok "go already installed: $(go version)"
      fi
    fi
  else
    echo "  Installing Go..."
    GO_NEED_INSTALL=true
  fi
  if [ "$GO_NEED_INSTALL" = true ]; then
    if [[ -z "$GO_LATEST" ]]; then
      warn "Failed to fetch Go version — skipping"
    else
      wget -q -P "$WORKDIR" "https://go.dev/dl/${GO_LATEST}.linux-${ARCH_GO}.tar.gz" &&
        # Extract to temp dir first, then atomic swap (prevents broken state if tar fails)
        sudo tar -C "$WORKDIR" -xzf "$WORKDIR/${GO_LATEST}.linux-${ARCH_GO}.tar.gz" &&
        sudo rm -rf /usr/local/go &&
        sudo mv "$WORKDIR/go" /usr/local/go &&
        export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH" &&
        ok "go installed: $(go version)" || warn "go install failed"
    fi
  fi
  export GOPATH="$HOME/go"
  export PATH="/usr/local/go/bin:$GOPATH/bin:$PATH"

  # ─── mise (replaces asdf, nvm, pyenv for runtime versions) ───
  if command -v mise &>/dev/null; then
    ok "mise already installed"
  else
    echo "  Installing mise..."
    curl https://mise.run | sh || true
    export PATH="$HOME/.local/bin:$PATH"
    if command -v mise &>/dev/null; then
      ok "mise installed"
    else
      warn "mise install failed"
    fi
  fi
  # Activate mise in the current script session so shims (node, python, etc.) are on PATH.
  # .bashrc already has eval "$(mise activate bash)" via SHELL_BLOCK — this covers the script run itself.
  eval "$("$HOME/.local/bin/mise" activate bash 2>/dev/null)" 2>/dev/null || true
  # Install node LTS so bun postinstall scripts (puppeteer, mermaid-cli, etc.) can find `node`
  if ! command -v node &>/dev/null; then
    run_q mise use -g node@lts && ok "node (via mise)" || warn "node install failed — bun postinstalls may need node"
  fi

  # ─── Docker ───
  if command -v docker &>/dev/null; then
    ok "docker already installed: $(docker --version)"
  else
    echo "  Installing Docker..."
    if curl -fsSL https://get.docker.com | sh 2>/dev/null; then
      ok "docker installed: $(docker --version)"
    else
      warn "docker install failed — n8n and dive will still work if Docker is installed later"
    fi
  fi
  # Add current user to docker group (allows running without sudo)
  if command -v docker &>/dev/null && ! groups "$USER" | grep -q docker; then
    sudo usermod -aG docker "$USER" 2>/dev/null && ok "added $USER to docker group (re-login to take effect)" || true
  fi

  # ─── Letta resource check ───
  if ! $LETTA_SKIP; then
    _TOTAL_RAM_MB=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
    if ((_TOTAL_RAM_MB < 3072)); then
      warn "System has ${_TOTAL_RAM_MB}MB RAM — Letta+Ollama need ~2GB."
      echo "  Consider --letta-skip or adding swap:"
      echo "    sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile"
    fi
  fi

  phase_mark "phase2"
fi # end phase2 checkpoint

# ─── Unconditional PATH exports ───────────────────────────────────────────────
# These MUST run on every invocation (including cached re-runs) so that
# Phase 3+ tools can find cargo, bun, go, uv, and mise.
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.cargo/bin:$HOME/go/bin:/usr/local/go/bin:$PATH"
export GOPATH="$HOME/go"
# mise shims (needed for playwright/node)
[[ -d "$HOME/.local/share/mise/shims" ]] && export PATH="$HOME/.local/share/mise/shims:$PATH"
