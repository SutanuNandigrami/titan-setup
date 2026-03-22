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

# Suppress interactive telemetry prompt on first cargo-binstall run
if [[ ! -f "$HOME/.cargo/binstall.toml" ]]; then
  printf '[telemetry]\nenabled = false\n' >"$HOME/.cargo/binstall.toml"
fi

# Core cargo crates (always installed)
CARGO_CRATES=(
  ripgrep fd-find sd eza du-dust bat xsv htmlq
  git-absorb git-delta difftastic typos-cli
  procs hyperfine pueue watchexec-cli just choose
  xh ouch
)
# Extended cargo crates (skipped with --minimal)
if ! $MINIMAL; then
  CARGO_CRATES+=(websocat bore-cli jwt-cli oha)
fi

# ── Parallel strategy: start RTK clone+patch while binstall runs ──────────
# RTK needs source build (patched); start clone in background, compile after binstall finishes.
_RTK_PID=""
_RTK_SRC="$WORKDIR/rtk-src"
if ! command -v rtk &>/dev/null || ! rtk gain &>/dev/null 2>&1; then
  echo -n "  rtk: cloning..."
  (git clone --depth=1 --quiet https://github.com/rtk-ai/rtk "$_RTK_SRC" 2>>"$LOG_FILE" &&
    patch -p1 -d "$_RTK_SRC" <"$REPO_FILES/config/rtk/ccusage.patch" >>"$LOG_FILE" 2>&1) &
  _RTK_PID=$!
  echo -e " ${GREEN}(background)${NC}"
else
  ok "rtk (exists)"
fi

CARGO_FAIL=0
_CARGO_LIST=$(cargo install --list 2>/dev/null)
for crate in "${CARGO_CRATES[@]}"; do
  if ! $FORCE_UPDATES && echo "$_CARGO_LIST" | grep -q "^${crate} v"; then
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

# Now compile RTK (clone+patch should be done by now)
if [[ -n "$_RTK_PID" ]]; then
  echo -n "  rtk (Token Killer)..."
  if wait "$_RTK_PID" && run_q cargo install --path "$_RTK_SRC"; then
    echo -e " ${GREEN}✓${NC}"
  else
    echo -e " ${YELLOW}⚠ rtk install failed${NC}"
  fi
fi

ok "Cargo tools installed/updated"

# ── Parallel cargo source builds (git-only crates) ───────────────────────
# These have no binstall binaries — compile in parallel to overlap CPU time.
_CARGO_GIT_PIDS=()
_CARGO_GIT_NAMES=()

_cargo_git_bg() {
  local name="$1" url="$2"
  shift 2
  if ! command -v "$name" &>/dev/null; then
    cargo install --git "$url" --quiet "$@" >>"$LOG_FILE" 2>&1 &
    _CARGO_GIT_PIDS+=($!)
    _CARGO_GIT_NAMES+=("$name")
  else
    ok "$name (exists)"
  fi
}

_cargo_git_bg "recall" "https://github.com/zippoxer/recall"
_cargo_git_bg "parry-guard" "https://github.com/vaporif/parry" --bin parry-guard

# Wait for all parallel cargo builds
for _i in "${!_CARGO_GIT_PIDS[@]}"; do
  if wait "${_CARGO_GIT_PIDS[$_i]}"; then
    ok "${_CARGO_GIT_NAMES[$_i]}"
  else
    warn "${_CARGO_GIT_NAMES[$_i]}"
  fi
done

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

# Helper: get latest release tag via redirect (avoids GitHub API rate limits)
# Defined here (before nushell) because it's first used below and again in the Go section.
_gh_latest_tag() {
  local url
  url=$(curl -sILo /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" 2>/dev/null) || true
  basename "$url" 2>/dev/null
}

# nushell — structured data shell (direct binary download; compiling takes 10-15 min)
if ! command -v nu &>/dev/null; then
  echo -n "  nu (nushell)..."
  _NU_VER=$(_gh_latest_tag "nushell/nushell")
  _NU_INSTALLED=false
  if [[ -n "$_NU_VER" ]]; then
    _NU_URL="https://github.com/nushell/nushell/releases/download/${_NU_VER}/nu-${_NU_VER}-${ARCH_RUST}-unknown-linux-musl.tar.gz"
    if curl -fsSL "$_NU_URL" -o "$WORKDIR/nu.tar.gz" 2>>"$LOG_FILE"; then
      tar -xzf "$WORKDIR/nu.tar.gz" -C "$WORKDIR" 2>>"$LOG_FILE"
      _NU_BIN=$(find "$WORKDIR" -maxdepth 2 -name "nu" -type f -perm -111 2>/dev/null | head -1)
      if [[ -n "$_NU_BIN" ]]; then
        install -m 0755 "$_NU_BIN" "$HOME/.cargo/bin/nu"
        echo -e " ${GREEN}✓${NC}"
        _NU_INSTALLED=true
      fi
    fi
  fi
  if ! $_NU_INSTALLED; then
    # Fallback: binstall → source compile
    if command -v cargo-binstall &>/dev/null && run_q cargo binstall --no-confirm --quiet nu; then
      echo -e " ${GREEN}✓ (binstall)${NC}"
    elif run_q cargo install nu --locked; then
      echo -e " ${GREEN}✓ (compiled)${NC}"
    else
      echo -e " ${YELLOW}⚠ build failed${NC}"
    fi
  fi
else ok "nu (exists)"; fi

# ─── Go tools (with existence checks — skip if already installed) ───
echo -e "\n  ${CYAN}Go tools:${NC}"

# ── Binary downloads for heaviest Go tools (saves ~15 min compile time) ──────
# These tools have 50-357 Go dependencies each; pre-built binaries are much faster.
_go_binary_install() {
  local name="$1" url="$2"
  if ! $FORCE_UPDATES && { command -v "$name" &>/dev/null || [ -f "$HOME/go/bin/$name" ]; }; then
    ok "$name (exists)"
    return 0
  fi
  echo -n "  $name (binary)..."
  local tmpf="$WORKDIR/${name}.tmp"
  if curl -fsSL "$url" -o "$tmpf" 2>>"$LOG_FILE"; then
    # Detect archive type and extract
    case "$url" in
      *.tar.gz | *.tgz)
        tar -xzf "$tmpf" -C "$WORKDIR" 2>>"$LOG_FILE"
        # Look for the binary in extracted files
        local bin
        bin=$(find "$WORKDIR" -maxdepth 2 -name "$name" -type f -perm -111 2>/dev/null | head -1)
        if [[ -z "$bin" ]]; then
          bin=$(find "$WORKDIR" -maxdepth 2 -name "$name" -type f 2>/dev/null | head -1)
        fi
        if [[ -n "$bin" ]]; then
          install -m 0755 "$bin" "$HOME/go/bin/$name"
          echo -e " ${GREEN}✓${NC}"
          return 0
        fi
        ;;
      *.zip)
        unzip -qo "$tmpf" -d "$WORKDIR/${name}_extract" 2>>"$LOG_FILE"
        local bin
        bin=$(find "$WORKDIR/${name}_extract" -maxdepth 2 -name "$name" -type f 2>/dev/null | head -1)
        if [[ -n "$bin" ]]; then
          install -m 0755 "$bin" "$HOME/go/bin/$name"
          echo -e " ${GREEN}✓${NC}"
          return 0
        fi
        ;;
    esac
    echo -e " ${YELLOW}⚠ extract failed${NC}"
    return 1
  else
    echo -e " ${YELLOW}⚠ download failed${NC}"
    return 1
  fi
}

mkdir -p "$HOME/go/bin"

# ── Parallel version fetches (saves ~15s vs sequential) ─────────────────────
_VER_DIR=$(mktemp -d)
_gh_latest_tag "projectdiscovery/nuclei" >"$_VER_DIR/nuclei" &
_VF1=$!
_gh_latest_tag "gitleaks/gitleaks" >"$_VER_DIR/gitleaks" &
_VF2=$!
_gh_latest_tag "getsops/sops" >"$_VER_DIR/sops" &
_VF3=$!
_gh_latest_tag "google/osv-scanner" >"$_VER_DIR/osv-scanner" &
_VF4=$!
_gh_latest_tag "nektos/act" >"$_VER_DIR/act" &
_VF5=$!
# Wait only for version-fetch PIDs — bare 'wait' catches ALL background jobs
# including the UV background install from lib/07, which can crash set -e
wait "$_VF1" "$_VF2" "$_VF3" "$_VF4" "$_VF5" 2>/dev/null || true
_NUCLEI_VER=$(<"$_VER_DIR/nuclei")
_GITLEAKS_VER=$(<"$_VER_DIR/gitleaks")
_SOPS_VER=$(<"$_VER_DIR/sops")
_OSV_VER=$(<"$_VER_DIR/osv-scanner")
_ACT_VER=$(<"$_VER_DIR/act")
rm -rf "$_VER_DIR"

# nuclei (357 deps, ~7 min compile) — binary download
if [[ -n "$_NUCLEI_VER" && "$_NUCLEI_VER" != "latest" ]]; then
  _go_binary_install "nuclei" \
    "https://github.com/projectdiscovery/nuclei/releases/download/${_NUCLEI_VER}/nuclei_${_NUCLEI_VER#v}_linux_${ARCH_GO}.zip" ||
    true
fi
command -v nuclei &>/dev/null && ok "nuclei (exists)" ||
  { run_q go install "github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest" && ok "nuclei (compiled)" || warn "nuclei"; }

# gitleaks (64 deps) — binary download
if [[ -n "$_GITLEAKS_VER" && "$_GITLEAKS_VER" != "latest" ]]; then
  # gitleaks uses x64/arm64 naming
  _GL_ARCH="x64"
  [[ "$ARCH_FULL" == "aarch64" ]] && _GL_ARCH="arm64"
  _go_binary_install "gitleaks" \
    "https://github.com/gitleaks/gitleaks/releases/download/${_GITLEAKS_VER}/gitleaks_${_GITLEAKS_VER#v}_linux_${_GL_ARCH}.tar.gz" ||
    true
fi
command -v gitleaks &>/dev/null && ok "gitleaks (exists)" ||
  { run_q go install "github.com/zricethezav/gitleaks/v8@latest" && ok "gitleaks (compiled)" || warn "gitleaks"; }

# sops (89 deps) — standalone binary download
if [[ -n "$_SOPS_VER" && "$_SOPS_VER" != "latest" ]] && ! command -v sops &>/dev/null; then
  echo -n "  sops (binary)..."
  if curl -fsSL "https://github.com/getsops/sops/releases/download/${_SOPS_VER}/sops-${_SOPS_VER}.linux.${ARCH_GO}" -o "$HOME/go/bin/sops" 2>>"$LOG_FILE"; then
    chmod +x "$HOME/go/bin/sops"
    echo -e " ${GREEN}✓${NC}"
  else echo -e " ${YELLOW}⚠${NC}"; fi
fi
command -v sops &>/dev/null && ok "sops (exists)" ||
  { run_q go install "github.com/getsops/sops/v3/cmd/sops@latest" && ok "sops (compiled)" || warn "sops"; }

# osv-scanner (51 deps) — standalone binary download
if [[ -n "$_OSV_VER" && "$_OSV_VER" != "latest" ]] && ! command -v osv-scanner &>/dev/null; then
  echo -n "  osv-scanner (binary)..."
  if curl -fsSL "https://github.com/google/osv-scanner/releases/download/${_OSV_VER}/osv-scanner_linux_${ARCH_GO}" -o "$HOME/go/bin/osv-scanner" 2>>"$LOG_FILE"; then
    chmod +x "$HOME/go/bin/osv-scanner"
    echo -e " ${GREEN}✓${NC}"
  else echo -e " ${YELLOW}⚠${NC}"; fi
fi
command -v osv-scanner &>/dev/null && ok "osv-scanner (exists)" ||
  { run_q go install "github.com/google/osv-scanner/cmd/osv-scanner@latest" && ok "osv-scanner (compiled)" || warn "osv-scanner"; }

# act (46 deps) — binary download
if [[ -n "$_ACT_VER" && "$_ACT_VER" != "latest" ]]; then
  _go_binary_install "act" \
    "https://github.com/nektos/act/releases/download/${_ACT_VER}/act_Linux_${ARCH_FULL}.tar.gz" ||
    true
fi
command -v act &>/dev/null && ok "act (exists)" ||
  { run_q go install "github.com/nektos/act@latest" && ok "act (compiled)" || warn "act"; }

# ── Parallel go install for remaining tools ──────────────────────────────────
# These are lighter tools — run them all in parallel with background jobs.
# Core Go tools (always installed)
declare -A GO_MAP=(
  ["dive"]="github.com/wagoodman/dive@latest"
  ["stern"]="github.com/stern/stern@latest"
  ["glow"]="github.com/charmbracelet/glow@latest"
  ["task"]="github.com/go-task/task/v3/cmd/task@latest"
  ["usql"]="github.com/xo/usql@latest"
  ["actionlint"]="github.com/rhysd/actionlint/cmd/actionlint@latest"
  ["hcloud"]="github.com/hetznercloud/cli/cmd/hcloud@latest"
  ["doggo"]="github.com/mr-karan/doggo/cmd/doggo@latest"
  ["shfmt"]="mvdan.cc/sh/v3/cmd/shfmt@latest"
  ["scc"]="github.com/boyter/scc/v3@latest"
)
# Extended Go tools (skipped with --minimal)
if ! $MINIMAL; then
  GO_MAP+=(
    ["mkcert"]="filippo.io/mkcert@latest"
    ["ffuf"]="github.com/ffuf/ffuf/v2@latest"
    ["grpcurl"]="github.com/fullstorydev/grpcurl/cmd/grpcurl@latest"
    ["gron"]="github.com/tomnomnom/gron@latest"
    ["httpx"]="github.com/projectdiscovery/httpx/cmd/httpx@latest"
    ["subfinder"]="github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
    ["dnsx"]="github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
    ["katana"]="github.com/projectdiscovery/katana/cmd/katana@latest"
  )
fi

_GO_PIDS=()
_GO_NAMES=()
_GO_SKIPPED=0

for name in "${!GO_MAP[@]}"; do
  if command -v "$name" &>/dev/null || [ -f "$HOME/go/bin/$name" ]; then
    ok "$name (exists)"
    ((_GO_SKIPPED++)) || true
  else
    go install "${GO_MAP[$name]}" >>"$LOG_FILE" 2>&1 &
    _GO_PIDS+=($!)
    _GO_NAMES+=("$name")
  fi
done

if [[ ${#_GO_PIDS[@]} -gt 0 ]]; then
  echo "  Installing ${#_GO_PIDS[@]} Go tools in parallel..."
fi

GO_FAILED=()
for _i in "${!_GO_PIDS[@]}"; do
  if wait "${_GO_PIDS[$_i]}"; then
    ok "${_GO_NAMES[$_i]}"
  else
    GO_FAILED+=("${_GO_NAMES[$_i]}")
    warn "${_GO_NAMES[$_i]}"
  fi
done

if [ ${#GO_FAILED[@]} -gt 0 ]; then
  warn "${#GO_FAILED[@]} Go tool(s) failed (likely network): ${GO_FAILED[*]}"
  echo "    Retry: for t in ${GO_FAILED[*]}; do go install \${GO_MAP[\$t]}; done"
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
  curl -fsSL "https://github.com/bcicen/ctop/releases/download/v0.7.7/ctop-0.7.7-linux-${ARCH_AMD}" -o "$WORKDIR/ctop" 2>>"$LOG_FILE" &&
    sudo install -m 0755 "$WORKDIR/ctop" /usr/local/bin/ctop && echo -e " ${GREEN}✓${NC}" || echo -e " ${YELLOW}⚠${NC}"
fi

echo -e "\n  ${CYAN}Claude Code ecosystem tools:${NC}"
# claude-tmux — Rust TUI for managing Claude Code tmux sessions
if ! command -v claude-tmux &>/dev/null; then
  cargo install --git https://github.com/nielsgroen/claude-tmux --locked 2>>"$LOG_FILE" && ok "claude-tmux" || warn "claude-tmux"
else ok "claude-tmux (exists)"; fi
# claude-esp
if ! command -v claude-esp &>/dev/null; then
  go install github.com/phiat/claude-esp@latest 2>/dev/null && ok "claude-esp" || warn "claude-esp"
else ok "claude-esp (exists)"; fi
# claude-squad — manage multiple AI terminal agents in parallel
# Note: go install fails due to go.mod module path mismatch — use binary release instead
if ! command -v claude-squad &>/dev/null; then
  CSVER=$(_gh_latest_tag "smtg-ai/claude-squad")
  if [[ -n "$CSVER" && "$CSVER" != "null" ]]; then
    mkdir -p "$HOME/.local/bin"
    curl -sfL "https://github.com/smtg-ai/claude-squad/releases/download/${CSVER}/claude-squad_${CSVER#v}_linux_${ARCH_AMD}.tar.gz" -o /tmp/cs.tar.gz &&
      tar -xzf /tmp/cs.tar.gz -C "$HOME/.local/bin" claude-squad &&
      chmod +x "$HOME/.local/bin/claude-squad" &&
      rm -f /tmp/cs.tar.gz &&
      ok "claude-squad" || warn "claude-squad"
  else
    warn "claude-squad (failed to fetch version)"
  fi
else ok "claude-squad (exists)"; fi

# ─── Binary installs (no package manager available) ───
echo -e "\n  ${CYAN}Binary installs:${NC}"

# kubectl
if ! command -v kubectl &>/dev/null; then
  curl -sL -o "$WORKDIR/kubectl" "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH_AMD}/kubectl" &&
    sudo install -o root -g root -m 0755 "$WORKDIR/kubectl" /usr/local/bin/kubectl &&
    ok "kubectl" || warn "kubectl install failed"
else ok "kubectl (exists)"; fi

# helm
if ! command -v helm &>/dev/null; then
  curl -s https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash 2>/dev/null &&
    ok "helm" || warn "helm install failed"
else ok "helm (exists)"; fi

# gcloud CLI
if ! command -v gcloud &>/dev/null; then
  # Download key to temp file first — piping to gpg --dearmor hangs if curl fails
  _GPG_TMP="$WORKDIR/gcloud.gpg"
  if curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg -o "$_GPG_TMP" 2>/dev/null; then
    sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg < "$_GPG_TMP" 2>/dev/null || true
  fi
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" |
    sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null
  apt_update --force && sudo apt-get install -y -qq google-cloud-cli &&
    ok "gcloud" || warn "gcloud install failed"
else ok "gcloud (exists)"; fi

# terraform + packer
if ! command -v terraform &>/dev/null; then
  _GPG_TMP="$WORKDIR/hashicorp.gpg"
  if wget -qO "$_GPG_TMP" https://apt.releases.hashicorp.com/gpg 2>/dev/null; then
    sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg < "$_GPG_TMP" 2>/dev/null || true
  fi
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  apt_update --force && sudo apt-get install -y -qq terraform packer &&
    ok "terraform + packer" || warn "terraform/packer install failed"
else ok "terraform (exists)"; fi

# tflint
if ! command -v tflint &>/dev/null; then
  curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash 2>/dev/null &&
    ok "tflint" || warn "tflint install failed"
else ok "tflint (exists)"; fi

# infracost
if ! command -v infracost &>/dev/null; then
  curl -fsSL https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh | sh 2>/dev/null &&
    ok "infracost" || warn "infracost install failed"
else ok "infracost (exists)"; fi

# hadolint
if ! command -v hadolint &>/dev/null; then
  sudo wget -qO /usr/local/bin/hadolint "https://github.com/hadolint/hadolint/releases/latest/download/hadolint-linux-${ARCH_FULL/aarch64/arm64}" &&
    sudo chmod +x /usr/local/bin/hadolint &&
    ok "hadolint" || warn "hadolint install failed"
else ok "hadolint (exists)"; fi

# duckdb
if ! command -v duckdb &>/dev/null; then
  curl -sL -o "$WORKDIR/duckdb.zip" "https://github.com/duckdb/duckdb/releases/latest/download/duckdb_cli-linux-${ARCH_AMD}.zip" &&
    unzip -qo "$WORKDIR/duckdb.zip" -d "$WORKDIR" && sudo mv "$WORKDIR/duckdb" /usr/local/bin/ &&
    ok "duckdb" || warn "duckdb install failed"
else ok "duckdb (exists)"; fi

# trivy
if ! command -v trivy &>/dev/null; then
  _GPG_TMP="$WORKDIR/trivy.gpg"
  if wget -qO "$_GPG_TMP" https://aquasecurity.github.io/trivy-repo/deb/public.key 2>/dev/null; then
    sudo gpg --dearmor -o /usr/share/keyrings/trivy.gpg < "$_GPG_TMP" 2>/dev/null || true
  fi
  echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/trivy.list >/dev/null
  apt_update --force && sudo apt-get install -y -qq trivy &&
    ok "trivy" || warn "trivy install failed"
else
  # migrate legacy key if sources.list lacks signed-by (suppresses apt deprecation warning)
  if ! grep -q 'signed-by' /etc/apt/sources.list.d/trivy.list 2>/dev/null; then
    _GPG_TMP="$WORKDIR/trivy.gpg"
    if wget -qO "$_GPG_TMP" https://aquasecurity.github.io/trivy-repo/deb/public.key 2>/dev/null; then
      sudo gpg --dearmor -o /usr/share/keyrings/trivy.gpg < "$_GPG_TMP" 2>/dev/null || true
    fi
    echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/trivy.list >/dev/null
    ok "trivy (key migrated)"
  else
    ok "trivy (exists)"
  fi
fi

# mc (MinIO client)
if ! command -v mc &>/dev/null; then
  curl -sL -o "$WORKDIR/mc" "https://dl.min.io/client/mc/release/linux-${ARCH_AMD}/mc" &&
    chmod +x "$WORKDIR/mc" && sudo mv "$WORKDIR/mc" /usr/local/bin/ &&
    ok "mc" || warn "mc (MinIO client) install failed"
else ok "mc (exists)"; fi

# GitHub CLI
if ! command -v gh &>/dev/null; then
  sudo mkdir -p -m 755 /etc/apt/keyrings
  wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null || true
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  apt_update --force && sudo apt-get install -y -qq gh &&
    ok "gh" || warn "gh install failed"
else ok "gh (exists)"; fi

# ShellCheck linter (latest binary, apt version is ancient)

SHELLCHECK_VERSION=$(_gh_latest_tag "koalaman/shellcheck")
if [[ -z "$SHELLCHECK_VERSION" || "$SHELLCHECK_VERSION" == "null" ]]; then
  warn "shellcheck — failed to fetch version, keeping existing"
elif ! command -v shellcheck &>/dev/null || [[ "$(shellcheck --version | grep version: | awk '{print $2}')" != "${SHELLCHECK_VERSION#v}" ]]; then
  wget -qO "$WORKDIR/shellcheck.tar.xz" "https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/shellcheck-${SHELLCHECK_VERSION}.linux.${ARCH_FULL}.tar.xz" &&
    tar xf "$WORKDIR/shellcheck.tar.xz" -C "$WORKDIR" && sudo mv "$WORKDIR/shellcheck-${SHELLCHECK_VERSION}/shellcheck" /usr/local/bin/ &&
    ok "shellcheck ($SHELLCHECK_VERSION)" || warn "shellcheck install failed"
else ok "shellcheck (exists)"; fi

# Dippy — auto-approve safe commands for Claude Code (brew preferred, fallback to clone)
if ! command -v dippy &>/dev/null && ! [ -f "$HOME/.local/bin/dippy" ]; then
  if command -v brew &>/dev/null; then
    brew tap ldayton/dippy 2>/dev/null && brew install dippy 2>/dev/null && ok "dippy" || warn "dippy"
  else
    if [ ! -d "$HOME/tools/dippy" ]; then
      mkdir -p "$HOME/tools"
      git clone --depth 1 https://github.com/ldayton/Dippy.git "$HOME/tools/dippy" 2>>"$LOG_FILE"
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
  curl -1sLf 'https://artifacts-cli.infisical.com/setup.deb.sh' | sudo -E bash 2>/dev/null || true
  sudo apt-get install -y infisical 2>/dev/null && ok "infisical" || warn "infisical"
else ok "infisical (exists)"; fi

# cloudflared — Cloudflare tunnels
if ! command -v cloudflared &>/dev/null; then
  curl -sL -o "$WORKDIR/cloudflared" "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH_AMD}" &&
    sudo install -m 0755 "$WORKDIR/cloudflared" /usr/local/bin/cloudflared &&
    ok "cloudflared" || warn "cloudflared install failed"
else ok "cloudflared (exists)"; fi

# step-cli — certificate inspection, generation, and TLS debugging
# Uses versionless asset name (step-cli_amd64.deb) so latest/download works reliably
if ! command -v step &>/dev/null; then
  curl -fsSL -o "$WORKDIR/step-cli.deb" \
    "https://github.com/smallstep/cli/releases/latest/download/step-cli_${ARCH_AMD}.deb" &&
    sudo dpkg -i "$WORKDIR/step-cli.deb" 2>/dev/null &&
    ok "step-cli" || warn "step-cli install failed"
else ok "step-cli (exists)"; fi

# comby — structural code search/replace that understands syntax (amd64 only — no aarch64 binary)
if [[ "$ARCH_AMD" == "amd64" ]]; then
  if ! command -v comby &>/dev/null; then
    sudo apt-get install -y libpcre3-dev libev4 2>/dev/null || true
    echo "y" | bash <(curl -sL get.comby.dev) 2>/dev/null &&
      ok "comby" || warn "comby install failed"
  else ok "comby (exists)"; fi
else warn "comby: skipped (amd64 only, detected ${ARCH_AMD})"; fi

# ── Wait for background uv tools + show results ──────────────────────────
if [[ -n "${_UV_PID:-}" ]]; then
  echo -e "\n  ${CYAN}Background uv tools results:${NC}"
  wait "$_UV_PID" 2>/dev/null || true
  while IFS='=' read -r status tool; do
    case "$status" in
      UV_OK) ok "$tool (already installed)" ;;
      UV_INSTALLED) ok "$tool" ;;
      UV_FAIL) warn "$tool (uv install failed)" ;;
      UV_UPGRADE) [[ "$tool" == "ok" ]] && ok "uv tool upgrade --all" || warn "uv tool upgrade failed" ;;
    esac
  done <"$_PHASE3_UV_LOG"
fi
