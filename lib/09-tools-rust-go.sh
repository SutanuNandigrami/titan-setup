# ─── Rust tools via cargo ───
echo -e "\n  ${CYAN}Rust tools (cargo):${NC}"
echo "  This takes a while on first install (compiling from source)..."

# TLS/dbus build deps (needed by several crates on both modes)
run_q sudo apt-get install -y -qq libssl-dev libdbus-1-dev pkg-config || warn "some build deps failed"
# Audio build deps (only needed for spotify_player on desktop)
if [[ "$INSTALL_MODE" == "desktop" ]]; then
  run_q sudo apt-get install -y -qq libpulse-dev libasound2-dev || warn "audio build deps failed — spotify_player may not compile"
fi

# Update Rust first
run_q rustup update stable

# cargo-binstall — download pre-built binaries instead of compiling from source
# Reduces cargo phase from hours to minutes on VPS
if ! command -v cargo-binstall &>/dev/null; then
  echo -n "  cargo-binstall..."
  _binstall_url="https://github.com/cargo-bins/cargo-binstall/releases/latest/download/cargo-binstall-${ARCH_RUST}-unknown-linux-musl.tgz"
  if curl -fsSL "$_binstall_url" 2>>"$LOG_FILE" | tar -xz -C ~/.cargo/bin 2>>"$LOG_FILE"; then
    echo -e " ${GREEN}✓${NC}"
  else
    echo -e " ${YELLOW}⚠ (will compile from source)${NC}"
  fi
else
  ok "cargo-binstall (exists)"
fi

CARGO_CRATES=(
  ripgrep fd-find sd eza du-dust bat xsv htmlq
  git-absorb git-delta difftastic typos-cli
  websocat bore-cli procs hyperfine
  pueue watchexec-cli just choose
  xh ouch hurl jwt-cli oha
)

# rtk (Rust Token Killer) — build from source with null-fix patch for Vertex AI
if ! command -v rtk &>/dev/null || ! rtk gain &>/dev/null 2>&1; then
  echo -n "  rtk (Token Killer)..."
  _RTK_SRC="$WORKDIR/rtk-src"
  if run_q git clone --depth=1 https://github.com/rtk-ai/rtk "$_RTK_SRC" \
    && patch -p1 -d "$_RTK_SRC" < "$REPO_FILES/config/rtk/ccusage.patch" \
    && run_q cargo install --path "$_RTK_SRC"; then
    echo -e " ${GREEN}✓${NC}"
  else
    echo -e " ${YELLOW}⚠ rtk install failed${NC}"
  fi
else
  ok "rtk (exists)"
fi

CARGO_FAIL=0
_CARGO_LIST=$(cargo install --list 2>/dev/null)
for crate in "${CARGO_CRATES[@]}"; do
  if echo "$_CARGO_LIST" | grep -q "^${crate} v"; then
    echo "  $crate (installed) ✓"
    continue
  fi
  echo -n "  $crate..."
  if command -v cargo-binstall &>/dev/null && run_q cargo binstall --no-confirm --quiet "$crate"; then
    echo -e " ${GREEN}✓${NC}"
  elif run_q cargo install "$crate" --locked; then
    echo -e " ${GREEN}✓ (compiled)${NC}"
  else
    echo -e " ${YELLOW}⚠ failed (try: cargo binstall $crate)${NC}"
    ((CARGO_FAIL++)) || true
  fi
done

if [ $CARGO_FAIL -eq 0 ]; then
  ok "All cargo tools installed"
else
  warn "$CARGO_FAIL cargo crate(s) failed — re-run or install individually"
fi

ok "Cargo tools installed/updated"

# recall — spaced repetition flashcard CLI (zippoxer/recall)
if ! command -v recall &>/dev/null; then
  run_q cargo install --git https://github.com/zippoxer/recall && ok "recall" || warn "recall"
else ok "recall (exists)"; fi

# parry — prompt injection scanner
if ! command -v parry &>/dev/null; then
  run_q cargo install --git https://github.com/vaporif/parry && ok "parry" || warn "parry"
else ok "parry (exists)"; fi

# spotify_player — desktop only (Spotify TUI requires audio hardware)
if [[ "$INSTALL_MODE" == "desktop" ]]; then
  if ! command -v spotify_player &>/dev/null; then
    echo -n "  spotify_player..."
    if command -v cargo-binstall &>/dev/null && run_q cargo binstall --no-confirm --quiet spotify_player; then
      echo -e " ${GREEN}✓${NC}"
    elif run_q cargo install spotify_player --locked; then
      echo -e " ${GREEN}✓${NC} (compiled)"
    else
      echo -e " ${YELLOW}⚠ build failed — try: cargo binstall spotify_player${NC}"
    fi
  else ok "spotify_player (exists)"; fi
fi

# nushell — structured data shell (large compile; binstall saves ~10 min)
if ! command -v nu &>/dev/null; then
  echo -n "  nu (nushell)..."
  if command -v cargo-binstall &>/dev/null && run_q cargo binstall --no-confirm --quiet nu; then
    echo -e " ${GREEN}✓${NC}"
  elif run_q cargo install nu --locked; then
    echo -e " ${GREEN}✓ (compiled)${NC}"
  else
    echo -e " ${YELLOW}⚠ build failed — try: cargo binstall nu${NC}"
  fi
else ok "nu (exists)"; fi

# ─── Go tools (with existence checks — skip if already installed) ───
echo -e "\n  ${CYAN}Go tools:${NC}"

# Associative array: binary_name → install_path
# This lets us check if the binary exists before running go install
declare -A GO_MAP=(
  ["dive"]="github.com/wagoodman/dive@latest"
  ["stern"]="github.com/stern/stern@latest"
  ["glow"]="github.com/charmbracelet/glow@latest"
  ["mkcert"]="filippo.io/mkcert@latest"
  ["task"]="github.com/go-task/task/v3/cmd/task@latest"
  ["nuclei"]="github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
  ["ffuf"]="github.com/ffuf/ffuf/v2@latest"
  ["usql"]="github.com/xo/usql@latest"
  ["grpcurl"]="github.com/fullstorydev/grpcurl/cmd/grpcurl@latest"
  ["actionlint"]="github.com/rhysd/actionlint/cmd/actionlint@latest"
  ["osv-scanner"]="github.com/google/osv-scanner/cmd/osv-scanner@latest"
  ["hcloud"]="github.com/hetznercloud/cli/cmd/hcloud@latest"
  ["sops"]="github.com/getsops/sops/v3/cmd/sops@latest"
  ["doggo"]="github.com/mr-karan/doggo/cmd/doggo@latest"
  ["gitleaks"]="github.com/zricethezav/gitleaks/v8@latest"
  ["act"]="github.com/nektos/act@latest"
  ["shfmt"]="mvdan.cc/sh/v3/cmd/shfmt@latest"
  ["gron"]="github.com/tomnomnom/gron@latest"
  ["httpx"]="github.com/projectdiscovery/httpx/cmd/httpx@latest"
  ["subfinder"]="github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
  ["dnsx"]="github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
  ["katana"]="github.com/projectdiscovery/katana/cmd/katana@latest"
  ["scc"]="github.com/boyter/scc/v3@latest"
)

GO_FAILED=()
for name in "${!GO_MAP[@]}"; do
  if command -v "$name" &>/dev/null || [ -f "$HOME/go/bin/$name" ]; then
    ok "$name (exists)"
  else
    echo -n "  Installing $name..."
    if run_q go install "${GO_MAP[$name]}"; then
      echo -e " ${GREEN}✓${NC}"
    else
      # Retry once — go proxy connections can be flaky
      sleep 2
      if run_q go install "${GO_MAP[$name]}"; then
        echo -e " ${GREEN}✓ (retry)${NC}"
      else
        GO_FAILED+=("$name")
        echo -e " ${YELLOW}⚠ failed: go install ${GO_MAP[$name]}${NC}"
      fi
    fi
  fi
done

if [ ${#GO_FAILED[@]} -gt 0 ]; then
  warn "${#GO_FAILED[@]} Go tool(s) failed (likely network): ${GO_FAILED[*]}"
  echo "    Retry later: for t in ${GO_FAILED[*]}; do go install \${GO_MAP[\$t]}; done"
fi

# age — special case: go install cmd/... installs 'age' and 'age-keygen'
if command -v age &>/dev/null || [ -f "$HOME/go/bin/age" ]; then
  ok "age (exists)"
else
  echo -n "  Installing age..."
  run_q go install filippo.io/age/cmd/...@latest && echo -e " ${GREEN}✓${NC}" || echo -e " ${YELLOW}⚠${NC}"
fi


# ctop — archived project, go install broken, use pinned binary release
if command -v ctop &>/dev/null; then
  ok "ctop (exists)"
else
  echo -n "  Installing ctop (binary)..."
  sudo wget -qO /usr/local/bin/ctop "https://github.com/bcicen/ctop/releases/download/v0.7.7/ctop-0.7.7-linux-${ARCH_AMD}" 2>/dev/null \
    && sudo chmod +x /usr/local/bin/ctop && echo -e " ${GREEN}✓${NC}" || echo -e " ${YELLOW}⚠${NC}"
fi


echo -e "\n  ${CYAN}Claude Code ecosystem tools:${NC}"
# claude-tmux — Rust TUI for managing Claude Code tmux sessions
if ! command -v claude-tmux &>/dev/null; then
  cargo install --git https://github.com/nielsgroen/claude-tmux 2>/dev/null && ok "claude-tmux" || warn "claude-tmux"
else ok "claude-tmux (exists)"; fi
# claude-esp
if ! command -v claude-esp &>/dev/null; then
  go install github.com/phiat/claude-esp@latest 2>/dev/null && ok "claude-esp" || warn "claude-esp"
else ok "claude-esp (exists)"; fi
# ccstatusline — Claude Code status line (npm/bun package, NOT cargo)
if ! command -v ccstatusline &>/dev/null; then
  run_q bun install -g ccstatusline && ok "ccstatusline" || warn "ccstatusline"
else ok "ccstatusline (exists)"; fi
# claude-squad — manage multiple AI terminal agents in parallel
# Note: go install fails due to go.mod module path mismatch — use binary release instead
if ! command -v claude-squad &>/dev/null; then
  CSVER=$(curl -sf https://api.github.com/repos/smtg-ai/claude-squad/releases/latest | jq -r '.tag_name')
  mkdir -p "$HOME/.local/bin"
  curl -sfL "https://github.com/smtg-ai/claude-squad/releases/download/${CSVER}/claude-squad_${CSVER#v}_linux_${ARCH_AMD}.tar.gz" -o /tmp/cs.tar.gz \
    && tar -xzf /tmp/cs.tar.gz -C "$HOME/.local/bin" claude-squad \
    && chmod +x "$HOME/.local/bin/claude-squad" \
    && rm -f /tmp/cs.tar.gz \
    && ok "claude-squad" || warn "claude-squad"
else ok "claude-squad (exists)"; fi


# ─── Binary installs (no package manager available) ───
echo -e "\n  ${CYAN}Binary installs:${NC}"

# kubectl
if ! command -v kubectl &>/dev/null; then
  curl -sL -o "$WORKDIR/kubectl" "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH_AMD}/kubectl"
  sudo install -o root -g root -m 0755 "$WORKDIR/kubectl" /usr/local/bin/kubectl
  ok "kubectl"
else ok "kubectl (exists)"; fi


# helm
if ! command -v helm &>/dev/null; then
  curl -s https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash 2>/dev/null \
    && ok "helm" || warn "helm install failed"
else ok "helm (exists)"; fi

# gcloud CLI
if ! command -v gcloud &>/dev/null; then
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg 2>/dev/null
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null
  sudo apt update -qq && sudo apt install -y -qq google-cloud-cli
  ok "gcloud"
else ok "gcloud (exists)"; fi

# terraform + packer
if ! command -v terraform &>/dev/null; then
  wget -qO- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg 2>/dev/null
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt update -qq && sudo apt install -y -qq terraform packer
  ok "terraform + packer"
else ok "terraform (exists)"; fi

# tflint
if ! command -v tflint &>/dev/null; then
  curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash 2>/dev/null
  ok "tflint"
else ok "tflint (exists)"; fi

# infracost
if ! command -v infracost &>/dev/null; then
  curl -fsSL https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh | sh 2>/dev/null
  ok "infracost"
else ok "infracost (exists)"; fi

# hadolint
if ! command -v hadolint &>/dev/null; then
  sudo wget -qO /usr/local/bin/hadolint "https://github.com/hadolint/hadolint/releases/latest/download/hadolint-linux-${ARCH_FULL/aarch64/arm64}" \
    && sudo chmod +x /usr/local/bin/hadolint \
    && ok "hadolint" || warn "hadolint install failed"
else ok "hadolint (exists)"; fi

# duckdb
if ! command -v duckdb &>/dev/null; then
  curl -sL -o "$WORKDIR/duckdb.zip" "https://github.com/duckdb/duckdb/releases/latest/download/duckdb_cli-linux-${ARCH_AMD}.zip"
  unzip -qo "$WORKDIR/duckdb.zip" -d "$WORKDIR" && sudo mv "$WORKDIR/duckdb" /usr/local/bin/
  ok "duckdb"
else ok "duckdb (exists)"; fi

# trivy
if ! command -v trivy &>/dev/null; then
  wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo gpg --dearmor -o /usr/share/keyrings/trivy.gpg 2>/dev/null
  echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/trivy.list >/dev/null
  sudo apt update -qq && sudo apt install -y -qq trivy
  ok "trivy"
else
  # migrate legacy key if sources.list lacks signed-by (suppresses apt deprecation warning)
  if ! grep -q 'signed-by' /etc/apt/sources.list.d/trivy.list 2>/dev/null; then
    wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo gpg --dearmor -o /usr/share/keyrings/trivy.gpg 2>/dev/null
    echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/trivy.list >/dev/null
    ok "trivy (key migrated)"
  else
    ok "trivy (exists)"
  fi
fi

# mc (MinIO client)
if ! command -v mc &>/dev/null; then
  curl -sL -o "$WORKDIR/mc" "https://dl.min.io/client/mc/release/linux-${ARCH_AMD}/mc"
  chmod +x "$WORKDIR/mc" && sudo mv "$WORKDIR/mc" /usr/local/bin/
  ok "mc"
else ok "mc (exists)"; fi

# GitHub CLI
if ! command -v gh &>/dev/null; then
  sudo mkdir -p -m 755 /etc/apt/keyrings
  wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt update -qq && sudo apt install -y -qq gh
  ok "gh"
else ok "gh (exists)"; fi

# ShellCheck linter (latest binary, apt version is ancient)

SHELLCHECK_VERSION=$(curl -s https://api.github.com/repos/koalaman/shellcheck/releases/latest | jq -r .tag_name)
if [[ -z "$SHELLCHECK_VERSION" || "$SHELLCHECK_VERSION" == "null" ]]; then
  warn "shellcheck — failed to fetch version, keeping existing"
elif ! command -v shellcheck &>/dev/null || [[ "$(shellcheck --version | grep version: | awk '{print $2}')" != "${SHELLCHECK_VERSION#v}" ]]; then
  wget -qO "$WORKDIR/shellcheck.tar.xz" "https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/shellcheck-${SHELLCHECK_VERSION}.linux.${ARCH_FULL}.tar.xz"
  tar xf "$WORKDIR/shellcheck.tar.xz" -C "$WORKDIR" && sudo mv "$WORKDIR/shellcheck-${SHELLCHECK_VERSION}/shellcheck" /usr/local/bin/ \
    && ok "shellcheck ($SHELLCHECK_VERSION)" || warn "shellcheck install failed"
else ok "shellcheck (exists)"; fi


# Dippy — auto-approve safe commands for Claude Code (brew preferred, fallback to clone)
if ! command -v dippy &>/dev/null && ! [ -f "$HOME/.local/bin/dippy" ]; then
  if command -v brew &>/dev/null; then
    brew tap ldayton/dippy 2>/dev/null && brew install dippy 2>/dev/null && ok "dippy" || warn "dippy"
  else
    if [ ! -d "$HOME/tools/dippy" ]; then
      mkdir -p "$HOME/tools"
      git clone --depth 1 https://github.com/ldayton/Dippy.git "$HOME/tools/dippy" 2>/dev/null
    fi
    if [ -f "$HOME/tools/dippy/bin/dippy-hook" ]; then
      chmod +x "$HOME/tools/dippy/bin/dippy-hook"
      mkdir -p "$HOME/.local/bin"
      ln -sf "$HOME/tools/dippy/bin/dippy-hook" "$HOME/.local/bin/dippy"
      ok "dippy (from source -> ~/.local/bin/dippy)"
    else
      warn "dippy — clone succeeded but bin/dippy-hook not found. Install Linuxbrew: https://brew.sh"
    fi
  fi
else ok "dippy (exists)"; fi

# Infisical — secret management CLI
if ! command -v infisical &>/dev/null; then
  curl -1sLf 'https://artifacts-cli.infisical.com/setup.deb.sh' | sudo -E bash 2>/dev/null
  sudo apt-get install -y infisical 2>/dev/null && ok "infisical" || warn "infisical"
else ok "infisical (exists)"; fi

# cloudflared — Cloudflare tunnels
if ! command -v cloudflared &>/dev/null; then
  curl -sL -o "$WORKDIR/cloudflared" "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH_AMD}" \
    && sudo install -m 0755 "$WORKDIR/cloudflared" /usr/local/bin/cloudflared \
    && ok "cloudflared" || warn "cloudflared install failed"
else ok "cloudflared (exists)"; fi


# step-cli — certificate inspection, generation, and TLS debugging
# Uses versionless asset name (step-cli_amd64.deb) so latest/download works reliably
if ! command -v step &>/dev/null; then
  curl -fsSL -o "$WORKDIR/step-cli.deb" \
    "https://github.com/smallstep/cli/releases/latest/download/step-cli_${ARCH_AMD}.deb" \
    && sudo dpkg -i "$WORKDIR/step-cli.deb" 2>/dev/null \
    && ok "step-cli" || warn "step-cli install failed"
else ok "step-cli (exists)"; fi

# comby — structural code search/replace that understands syntax (amd64 only — no aarch64 binary)
if [[ "$ARCH_AMD" == "amd64" ]]; then
  if ! command -v comby &>/dev/null; then
    sudo apt install -y libpcre3-dev libev4 2>/dev/null
    echo "y" | bash <(curl -sL get.comby.dev) 2>/dev/null \
      && ok "comby" || warn "comby install failed"
  else ok "comby (exists)"; fi
else warn "comby: skipped (amd64 only, detected ${ARCH_AMD})"; fi



