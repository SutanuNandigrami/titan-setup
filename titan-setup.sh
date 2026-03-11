#!/usr/bin/env bash
set -euo pipefail

# ╔══════════════════════════════════════════════════════════════════╗
# ║  TITAN SETUP — Single Source of Truth                           ║
# ║  Fresh Ubuntu → fully armed Claude Code workstation             ║
# ║                                                                  ║
# ║  What this does:                                                 ║
# ║   1. System prerequisites + Linux tuning                        ║
# ║   2. Package managers: uv, bun, cargo, go, mise                ║
# ║   3. 100 CLI tools (zero pip, zero npm -g)                     ║
# ║   4. Claude Code CLI (native binary)                            ║
# ║   5. ~/.claude/ global config (skills, hooks, commands, agents) ║
# ║   6. Shell integration + verification                           ║
# ║                                                                  ║
# ║  Safe to re-run: skips already-installed components             ║
# ║                                                                  ║
# ║  Security note: This script uses curl|bash for several official  ║
# ║  installers (rustup, uv, bun, mise, docker, helm, etc). Review  ║
# ║  URLs before running. Two community packages (Claude Desktop,    ║
# ║  Claude Cowork) install from patrickjaja.github.io via sudo.     ║
# ╚══════════════════════════════════════════════════════════════════╝

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

section() { echo -e "\n${CYAN}═══ $1 ═══${NC}\n"; }
ok()      { echo -e "  ${GREEN}✓${NC} $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail()    { echo -e "  ${RED}✗${NC} $1"; }

# ─── CLI Options ───
ENGINEER_NAME=""
DRY_RUN=false

usage() {
  cat <<USAGE
Usage: $(basename "$0") [OPTIONS]

Options:
  --name NAME   Your name for Claude config (default: \$(whoami))
  --dry-run     Print what would be done without making changes
  -h, --help    Show this help message

Examples:
  $(basename "$0") --name "Alice"
  $(basename "$0") --dry-run
USAGE
  exit 0
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --name)    [[ $# -ge 2 ]] || { fail "--name requires a value"; usage; }; ENGINEER_NAME="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage ;;
    *) fail "Unknown option: $1"; usage ;;
  esac
done

# Default name from system if not provided
ENGINEER_NAME="${ENGINEER_NAME:-$(whoami)}"

if $DRY_RUN; then
  warn "Dry run mode — no changes will be made"
  echo "  Engineer name: $ENGINEER_NAME"
  echo "  Claude config: ~/.claude/"
  echo "  Shell integration: ~/.bashrc"
  exit 0
fi

# ─── Temp directory for downloads ───
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# ─── Architecture detection ───
UNAME_ARCH=$(uname -m)
case "$UNAME_ARCH" in
  x86_64)  ARCH_AMD="amd64"; ARCH_GO="amd64"; ARCH_RUST="x86_64"; ARCH_FULL="x86_64" ;;
  aarch64) ARCH_AMD="arm64"; ARCH_GO="arm64"; ARCH_RUST="aarch64"; ARCH_FULL="aarch64" ;;
  *) fail "Unsupported architecture: $UNAME_ARCH"; exit 1 ;;
esac

section "Phase 1/6 — System Prerequisites"

sudo apt update && sudo apt upgrade -y

sudo apt install -y \
  curl wget git build-essential unzip software-properties-common \
  lsb-release apt-transport-https gnupg ca-certificates \
  jq mtr nmap tmux pandoc direnv entr nikto lynis \
  redis-tools aria2 btop miller \
  inotify-tools expect asciinema at \
  lnav imagemagick maim xdotool \
  universal-ctags chafa \
  libclang-dev cmake libxml2-dev libcurl4-openssl-dev

sudo apt autoremove -y

# ─── JetBrains Mono Nerd Font (required for Powerline statusline) ───
if fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font"; then
  ok "JetBrainsMono Nerd Font already installed"
else
  echo -n "  Installing JetBrainsMono Nerd Font..."
  FONT_DIR="$HOME/.local/share/fonts"
  mkdir -p "$FONT_DIR"
  TMPFONT=$(mktemp -d)
  curl -fsSL -o "$TMPFONT/JetBrainsMono.tar.xz" \
    "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz"
  tar -xf "$TMPFONT/JetBrainsMono.tar.xz" -C "$TMPFONT"
  cp "$TMPFONT"/*.ttf "$FONT_DIR/" 2>/dev/null || true
  fc-cache -f "$FONT_DIR" 2>/dev/null
  rm -rf "$TMPFONT"
  ok "JetBrainsMono Nerd Font installed"
fi

# Set Cosmic Terminal font if running on COSMIC desktop
if command -v cosmic-term &>/dev/null; then
  COSMIC_TERM_DIR="$HOME/.config/cosmic/com.system76.CosmicTerm/v1"
  mkdir -p "$COSMIC_TERM_DIR"
  echo '"JetBrainsMono Nerd Font"' > "$COSMIC_TERM_DIR/font_name"
  echo '14' > "$COSMIC_TERM_DIR/font_size"
  ok "Cosmic Terminal font set to JetBrainsMono Nerd Font 14"
fi

# ─── Linux tuning ───
section "Linux Tuning"

# Increase file watchers (needed for large projects)
if ! grep -q "fs.inotify.max_user_watches" /etc/sysctl.conf 2>/dev/null; then
  echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf
  echo "fs.inotify.max_user_instances=1024" | sudo tee -a /etc/sysctl.conf
  sudo sysctl -p
  ok "Increased inotify watchers to 524288"
else
  ok "inotify watchers already configured"
fi

# Increase file descriptor limits
if ! grep -q "nofile" /etc/security/limits.conf 2>/dev/null || ! grep -q "65535" /etc/security/limits.conf 2>/dev/null; then
  echo "* soft nofile 65535" | sudo tee -a /etc/security/limits.conf
  echo "* hard nofile 65535" | sudo tee -a /etc/security/limits.conf
  ok "Increased file descriptor limits"
else
  ok "File descriptor limits already configured"
fi

# Git config defaults
git config --global init.defaultBranch main 2>/dev/null || true
git config --global core.autocrlf input 2>/dev/null || true
git config --global pull.rebase true 2>/dev/null || true
ok "Git defaults set (main branch, rebase pull)"


section "Phase 2/6 — Package Managers"

# ─── Rust / Cargo ───
if command -v cargo &>/dev/null; then
  ok "cargo already installed: $(cargo --version)"
else
  echo "  Installing Rust..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  ok "cargo installed: $(cargo --version)"
fi
# Ensure cargo binaries are on PATH for the rest of this script
# shellcheck source=/dev/null
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

# ─── uv (replaces pip, pipx, venv, pyenv) ───
if command -v uv &>/dev/null; then
  ok "uv already installed: $(uv --version)"
else
  echo "  Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  ok "uv installed: $(uv --version)"
fi
# Ensure uv/uvx binaries are on PATH for the rest of this script
export PATH="$HOME/.local/bin:$PATH"

# ─── bun (replaces npm, npx for CLI tools) ───
if command -v bun &>/dev/null; then
  ok "bun already installed: $(bun --version)"
else
  echo "  Installing bun..."
  curl -fsSL https://bun.sh/install | bash
  ok "bun installed: $(bun --version)"
fi
# Ensure bun globals are on PATH for the rest of this script
export PATH="$HOME/.bun/bin:$PATH"

# ─── Go ───
GO_LATEST=$(curl -s https://go.dev/VERSION?m=text | head -1)
GO_NEED_INSTALL=false
if command -v go &>/dev/null; then
  GO_CURRENT=$(go version | grep -oP '\d+\.\d+\.\d+')
  GO_LATEST_VER=${GO_LATEST#go}
  # Compare major.minor — upgrade if current < latest major.minor
  GO_CUR_MINOR=$(echo "$GO_CURRENT" | cut -d. -f1-2)
  GO_LAT_MINOR=$(echo "$GO_LATEST_VER" | cut -d. -f1-2)
  if [ "$(printf '%s\n%s' "$GO_CUR_MINOR" "$GO_LAT_MINOR" | sort -V | head -1)" != "$GO_LAT_MINOR" ]; then
    echo "  Go $GO_CURRENT is outdated (latest: $GO_LATEST_VER) — upgrading..."
    GO_NEED_INSTALL=true
  else
    ok "go already installed: $(go version)"
  fi
else
  echo "  Installing Go..."
  GO_NEED_INSTALL=true
fi
if [ "$GO_NEED_INSTALL" = true ]; then
  if [[ -z "$GO_LATEST" ]]; then
    warn "Failed to fetch Go version — skipping"
  else
    wget -q -P "$WORKDIR" "https://go.dev/dl/${GO_LATEST}.linux-${ARCH_GO}.tar.gz"
    sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf "$WORKDIR/${GO_LATEST}.linux-${ARCH_GO}.tar.gz"
    export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"
    ok "go installed: $(go version)"
  fi
fi
export GOPATH="$HOME/go"
export PATH="/usr/local/go/bin:$GOPATH/bin:$PATH"

# ─── mise (replaces asdf, nvm, pyenv for runtime versions) ───
if command -v mise &>/dev/null; then
  ok "mise already installed"
else
  echo "  Installing mise..."
  curl https://mise.run | sh
  export PATH="$HOME/.local/bin:$PATH"
  ok "mise installed"
fi


# ─── Docker ───
if command -v docker &>/dev/null; then
  ok "docker already installed: $(docker --version)"
else
  echo "  Installing Docker..."
  if curl -fsSL https://get.docker.com | sh 2>/dev/null; then
    ok "docker installed: $(docker --version)"
  else
    warn "docker install failed — n8n, lazydocker, dive will still work if Docker is installed later"
  fi
fi
# Add current user to docker group (allows running without sudo)
if command -v docker &>/dev/null && ! groups "$USER" | grep -q docker; then
  sudo usermod -aG docker "$USER" 2>/dev/null && ok "added $USER to docker group (re-login to take effect)" || true
fi

section "Phase 3/6 — 100 CLI Tools"

# ─── Python tools via uv (isolated venvs, zero system pollution) ───
echo -e "  ${CYAN}Python tools (uv):${NC}"

UV_TOOLS=(
  "httpie"          # http, https — HTTP client
  "yq"              # yq — YAML/XML/TOML processor
  "semgrep"         # semgrep — static analysis
  "csvkit"          # csvlook, csvstat, csvsql + 9 more
  "codespell"       # codespell — spell checker for code
  "ansible-core"    # ansible, ansible-playbook, ansible-galaxy + more (NOT 'ansible' — that's the meta-pkg)
  "ansible-lint"    # ansible-lint — linter for Ansible playbooks
  "sqlmap"          # sqlmap — SQL injection testing
  "pgcli"           # pgcli — Postgres with autocomplete
  "litecli"         # litecli — SQLite with autocomplete
  "awscli"          # aws — AWS CLI
  "ruff"            # ruff — Python linter (replaces flake8+black+isort+pyflakes)
  "ast-grep-cli"    # ast-grep, sg — structural code search
  "mitmproxy"       # mitmproxy, mitmdump — HTTP/HTTPS proxy for debugging
  "cookiecutter"    # cookiecutter — project scaffolding from templates
  "visidata"        # vd — TUI spreadsheet for CSV, JSON, SQLite, Parquet
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
# claude-agent-sdk is a library (not a CLI tool) — install to user site-packages (uv pip --system blocked on Ubuntu 24.04 externally-managed Python)
python3 -c "import claude_agent_sdk" 2>/dev/null && ok "claude-agent-sdk (exists)" || { pip3 install --user --quiet claude-agent-sdk 2>/dev/null && ok "claude-agent-sdk" || warn "claude-agent-sdk (install manually: pip3 install --user claude-agent-sdk)"; }

# sqlite-vec for local vector store (used by codebase indexing)
if [[ ! -d "$HOME/.local/share/titan/vectordb" ]]; then
  mkdir -p "$HOME/.local/share/titan/vectordb"
  uv pip install --system sqlite-vec 2>/dev/null \
    || uv pip install sqlite-vec --target "$HOME/.local/lib/python-libs" 2>/dev/null \
    && ok "sqlite-vec" || warn "sqlite-vec (install manually: uv pip install sqlite-vec)"
else
  ok "sqlite-vec dir (exists)"
fi

# ─── JS tools via bun ───
echo -e "\n  ${CYAN}JS tools (bun):${NC}"

BUN_TOOLS=("trash-cli" "tldr" "prettier" "repomix" "ccstatusline")
for tool in "${BUN_TOOLS[@]}"; do
  if bun pm ls -g 2>/dev/null | grep -q "$tool"; then
    ok "$tool (exists)"
  else
    echo -n "  Installing $tool..."
    bun install -g "$tool" &>/dev/null && echo -e " ${GREEN}✓${NC}" || echo -e " ${YELLOW}⚠${NC}"
  fi
done

command -v gemini &>/dev/null && ok "gemini-cli (exists)" || { bun install -g @google/gemini-cli 2>/dev/null && ok "gemini-cli" || warn "gemini-cli"; }
command -v mmdc &>/dev/null && ok "mermaid-cli (exists)" || { bun install -g @mermaid-js/mermaid-cli 2>/dev/null && ok "mermaid-cli" || warn "mermaid-cli"; }

# playwright — browser automation and E2E testing
if ! bun pm ls -g 2>/dev/null | grep -q playwright; then
  bun install -g playwright 2>/dev/null && ok "playwright" || warn "playwright"
  # Install chromium browser (skip if no display or CI)
  if command -v playwright &>/dev/null; then
    playwright install chromium 2>/dev/null && ok "playwright chromium" || warn "playwright chromium (install manually: playwright install chromium)"
  fi
else
  ok "playwright (exists)"
fi

# n8n — workflow automation server (runs as systemd user service via docker)
if command -v docker &>/dev/null; then
  # Try without sudo first, fall back to sudo (user may not be in docker group yet)
  if docker pull n8nio/n8n:latest 2>/dev/null || sudo docker pull n8nio/n8n:latest 2>/dev/null; then
    ok "n8n docker image"
  else
    warn "n8n docker pull failed (check: sudo docker pull n8nio/n8n:latest)"
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
ExecStart=${DOCKER_BIN} run --rm --name n8n -p 5678:5678 -v %h/.n8n:/home/node/.n8n n8nio/n8n
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
else
  warn "n8n skipped — Docker not available (install failed earlier or not supported)"
fi
command -v nlm &>/dev/null && ok "notebooklm-cli (exists)" || { bun install -g notebooklm-cli 2>/dev/null && ok "notebooklm-cli" || warn "notebooklm-cli"; }
command -v kilocode &>/dev/null && ok "kilocode (exists)" || { bun install -g @kilocode/cli 2>/dev/null && ok "kilocode" || warn "kilocode"; }
command -v vercel &>/dev/null && ok "vercel (exists)" || { bun install -g vercel 2>/dev/null && ok "vercel" || warn "vercel"; }

# ─── Rust tools via cargo ───
echo -e "\n  ${CYAN}Rust tools (cargo):${NC}"
echo "  This takes a while on first install (compiling from source)..."

# Dependencies needed for spotify_player and other audio/TLS crates
sudo apt install -y libpulse-dev libasound2-dev libssl-dev libdbus-1-dev pkg-config || warn "some build deps failed — spotify_player may not compile"

# Update Rust first
rustup update stable

CARGO_CRATES=(
  ripgrep fd-find sd eza du-dust bat broot zoxide xsv htmlq
  git-cliff git-absorb git-delta difftastic onefetch typos-cli
  bandwhich websocat bore-cli procs bottom hyperfine
  pueue watchexec-cli just starship atuin navi choose
  xh mdbook jnv ouch hurl jwt-cli oha tree-sitter-cli
)

CARGO_FAIL=0
for crate in "${CARGO_CRATES[@]}"; do
  echo -n "  $crate..."
  if cargo install "$crate" &>/dev/null; then
    echo -e " ${GREEN}✓${NC}"
  elif cargo install "$crate" --locked &>/dev/null; then
    echo -e " ${GREEN}✓ (locked)${NC}"
  else
    echo -e " ${YELLOW}⚠ failed (try: cargo install $crate)${NC}"
    ((CARGO_FAIL++)) || true
  fi
done

if [ $CARGO_FAIL -eq 0 ]; then
  ok "All cargo tools installed"
else
  warn "$CARGO_FAIL cargo crate(s) failed — re-run or install individually"
fi

ok "Cargo tools installed/updated"

# recall — Claude/Codex conversation search (NOT the crates.io 'recall')
if ! command -v recall &>/dev/null; then
  cargo install --git https://github.com/zippoxer/recall 2>/dev/null && ok "recall" || warn "recall"
else ok "recall (exists)"; fi

# parry — prompt injection scanner
if ! command -v parry &>/dev/null; then
  cargo install --git https://github.com/vaporif/parry 2>/dev/null && ok "parry" || warn "parry"
else ok "parry (exists)"; fi

# spotify_player — actively maintained Spotify TUI (replaces abandoned spotify-tui)
if ! command -v spotify_player &>/dev/null; then
  echo -n "  spotify_player..."
  if cargo install spotify_player 2>/dev/null; then
    echo -e " ${GREEN}✓${NC}"
  elif cargo install spotify_player --locked 2>/dev/null; then
    echo -e " ${GREEN}✓${NC} (locked)"
  else
    echo -e " ${YELLOW}⚠ build failed — try: cargo install spotify_player manually${NC}"
  fi
else ok "spotify_player (exists)"; fi

# nushell — structured data shell (large compile, separate from batch)
if ! command -v nu &>/dev/null; then
  echo -n "  nu (nushell)..."
  if cargo install nu 2>/dev/null; then
    echo -e " ${GREEN}✓${NC}"
  elif cargo install nu --locked 2>/dev/null; then
    echo -e " ${GREEN}✓ (locked)${NC}"
  else
    echo -e " ${YELLOW}⚠ build failed — try: cargo install nu manually${NC}"
  fi
else ok "nu (exists)"; fi

# ─── Go tools (with existence checks — skip if already installed) ───
echo -e "\n  ${CYAN}Go tools:${NC}"

# Associative array: binary_name → install_path
# This lets us check if the binary exists before running go install
declare -A GO_MAP=(
  ["lazygit"]="github.com/jesseduffield/lazygit@latest"
  # lazydocker installed via binary below (go install fails due to Docker API conflict)
  #["lazydocker"]="github.com/jesseduffield/lazydocker@latest"
  ["dive"]="github.com/wagoodman/dive@latest"
  ["stern"]="github.com/stern/stern@latest"
  ["glow"]="github.com/charmbracelet/glow@latest"
  ["slides"]="github.com/maaslalani/slides@latest"
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
  ["doctl"]="github.com/digitalocean/doctl/cmd/doctl@latest"
  ["doggo"]="github.com/mr-karan/doggo/cmd/doggo@latest"
  ["gitleaks"]="github.com/zricethezav/gitleaks/v8@latest"
  ["gum"]="github.com/charmbracelet/gum@latest"
  ["act"]="github.com/nektos/act@latest"
  ["shfmt"]="mvdan.cc/sh/v3/cmd/shfmt@latest"
  ["gron"]="github.com/tomnomnom/gron@latest"
  ["httpx"]="github.com/projectdiscovery/httpx/cmd/httpx@latest"
  ["subfinder"]="github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
  ["dnsx"]="github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
  ["katana"]="github.com/projectdiscovery/katana/cmd/katana@latest"
  ["cosign"]="github.com/sigstore/cosign/v2/cmd/cosign@latest"
  ["crane"]="github.com/google/go-containerregistry/cmd/crane@latest"
  ["scc"]="github.com/boyter/scc/v3@latest"
  ["dasel"]="github.com/tomwright/dasel/v2/cmd/dasel@latest"
)

GO_FAILED=()
for name in "${!GO_MAP[@]}"; do
  if command -v "$name" &>/dev/null || [ -f "$HOME/go/bin/$name" ]; then
    ok "$name (exists)"
  else
    echo -n "  Installing $name..."
    if go install "${GO_MAP[$name]}" &>/dev/null; then
      echo -e " ${GREEN}✓${NC}"
    else
      # Retry once — go proxy connections can be flaky
      sleep 2
      if go install "${GO_MAP[$name]}" &>/dev/null; then
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
  go install filippo.io/age/cmd/...@latest &>/dev/null && echo -e " ${GREEN}✓${NC}" || echo -e " ${YELLOW}⚠${NC}"
fi

# lazydocker — go install broken (Docker API conflict), use binary release
if command -v lazydocker &>/dev/null; then
  ok "lazydocker (exists)"
else
  LAZYDOCKER_VERSION=$(curl -s https://api.github.com/repos/jesseduffield/lazydocker/releases/latest | jq -r .tag_name)
  if [[ -z "$LAZYDOCKER_VERSION" || "$LAZYDOCKER_VERSION" == "null" ]]; then
    warn "lazydocker — failed to fetch version"
  else
    curl -sL "https://github.com/jesseduffield/lazydocker/releases/download/${LAZYDOCKER_VERSION}/lazydocker_${LAZYDOCKER_VERSION#v}_Linux_${ARCH_FULL}.tar.gz" | tar xz -C "$WORKDIR" lazydocker \
      && sudo mv "$WORKDIR/lazydocker" /usr/local/bin/ && ok "lazydocker" || warn "lazydocker install failed"
  fi
fi

# ctop — archived project, go install broken, use pinned binary release
if command -v ctop &>/dev/null; then
  ok "ctop (exists)"
else
  echo -n "  Installing ctop (binary)..."
  sudo wget -qO /usr/local/bin/ctop "https://github.com/bcicen/ctop/releases/download/v0.7.7/ctop-0.7.7-linux-${ARCH_AMD}" 2>/dev/null \
    && sudo chmod +x /usr/local/bin/ctop && echo -e " ${GREEN}✓${NC}" || echo -e " ${YELLOW}⚠${NC}"
fi

# trufflehog — official install script (go install doesn't work for this project)
if command -v trufflehog &>/dev/null; then
  ok "trufflehog (exists)"
else
  echo -n "  Installing trufflehog (official script)..."
  curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sudo sh -s -- -b /usr/local/bin 2>/dev/null \
    && echo -e " ${GREEN}✓${NC}" || echo -e " ${YELLOW}⚠${NC}"
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
  bun install -g ccstatusline 2>/dev/null && ok "ccstatusline" || warn "ccstatusline"
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

# k9s
if ! command -v k9s &>/dev/null; then
  curl -sS https://webi.sh/k9s | sh 2>/dev/null \
    && ok "k9s" || warn "k9s install failed"
else ok "k9s (exists)"; fi

# helm
if ! command -v helm &>/dev/null; then
  curl -s https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash 2>/dev/null \
    && ok "helm" || warn "helm install failed"
else ok "helm (exists)"; fi

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
  sudo wget -qO /usr/local/bin/hadolint "https://github.com/hadolint/hadolint/releases/latest/download/hadolint-Linux-${ARCH_FULL}" \
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
else ok "trivy (exists)"; fi

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

# fzf
if ! command -v fzf &>/dev/null; then
  git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf 2>/dev/null \
    && yes | ~/.fzf/install --all --no-bash --no-zsh --no-fish 2>/dev/null \
    && ok "fzf" || warn "fzf install failed"
else ok "fzf (exists)"; fi

# ShellCheck linter (latest binary, apt version is ancient)

SHELLCHECK_VERSION=$(curl -s https://api.github.com/repos/koalaman/shellcheck/releases/latest | jq -r .tag_name)
if [[ -z "$SHELLCHECK_VERSION" || "$SHELLCHECK_VERSION" == "null" ]]; then
  warn "shellcheck — failed to fetch version, keeping existing"
elif ! command -v shellcheck &>/dev/null || [[ "$(shellcheck --version | grep version: | awk '{print $2}')" != "${SHELLCHECK_VERSION#v}" ]]; then
  wget -qO "$WORKDIR/shellcheck.tar.xz" "https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/shellcheck-${SHELLCHECK_VERSION}.linux.${ARCH_FULL}.tar.xz"
  tar xf "$WORKDIR/shellcheck.tar.xz" -C "$WORKDIR" && sudo mv "$WORKDIR/shellcheck-${SHELLCHECK_VERSION}/shellcheck" /usr/local/bin/ \
    && ok "shellcheck ($SHELLCHECK_VERSION)" || warn "shellcheck install failed"
else ok "shellcheck (exists)"; fi

# yazi (file manager — cargo build is broken due to rand_core conflict)
if ! command -v yazi &>/dev/null; then
  curl -sL -o "$WORKDIR/yazi.zip" "https://github.com/sxyazi/yazi/releases/latest/download/yazi-${ARCH_RUST}-unknown-linux-gnu.zip"
  unzip -qo "$WORKDIR/yazi.zip" -d "$WORKDIR"
  sudo mv "$WORKDIR/yazi-${ARCH_RUST}-unknown-linux-gnu/yazi" /usr/local/bin/
  sudo mv "$WORKDIR/yazi-${ARCH_RUST}-unknown-linux-gnu/ya" /usr/local/bin/
  ok "yazi"
else ok "yazi (exists)"; fi

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

# syft — SBOM generation for containers and filesystems
if ! command -v syft &>/dev/null; then
  curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sudo sh -s -- -b /usr/local/bin \
    && ok "syft" || warn "syft install failed"
else ok "syft (exists)"; fi

# grype — vulnerability scanner for containers and filesystems (pairs with syft)
if ! command -v grype &>/dev/null; then
  curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sudo sh -s -- -b /usr/local/bin \
    && ok "grype" || warn "grype install failed"
else ok "grype (exists)"; fi

# step-cli — certificate inspection, generation, and TLS debugging
if ! command -v step &>/dev/null; then
  STEP_VERSION=$(curl -s https://api.github.com/repos/smallstep/cli/releases/latest | jq -r '.tag_name' | sed 's/^v//')
  curl -sL -o "$WORKDIR/step-cli.deb" "https://dl.smallstep.com/gh-release/cli/gh-release-header/v${STEP_VERSION}/step-cli_${STEP_VERSION}_${ARCH_AMD}.deb" \
    && sudo dpkg -i "$WORKDIR/step-cli.deb" &>/dev/null \
    && ok "step-cli ${STEP_VERSION}" || warn "step-cli install failed"
else ok "step-cli (exists)"; fi

# comby — structural code search/replace that understands syntax
if ! command -v comby &>/dev/null; then
  sudo apt install -y libpcre3-dev 2>/dev/null
  echo "y" | bash <(curl -sL get.comby.dev) 2>/dev/null \
    && ok "comby" || warn "comby install failed"
else ok "comby (exists)"; fi

# runme — execute code blocks from Markdown runbooks
if ! command -v runme &>/dev/null; then
  RUNME_VERSION=$(curl -s https://api.github.com/repos/stateful/runme/releases/latest | jq -r '.tag_name' | sed 's/^v//')
  curl -sL -o "$WORKDIR/runme.tar.gz" "https://dl.runme.dev/runme/v${RUNME_VERSION}/runme_linux_${ARCH_AMD}.tar.gz" \
    && tar xzf "$WORKDIR/runme.tar.gz" -C "$WORKDIR" \
    && sudo install -m 0755 "$WORKDIR/runme" /usr/local/bin/runme \
    && ok "runme ${RUNME_VERSION}" || warn "runme install failed"
else ok "runme (exists)"; fi


section "Phase 4/6 — Claude Code CLI"

if command -v claude &>/dev/null; then
  ok "Claude Code already installed: $(claude --version 2>/dev/null || echo 'installed')"
  echo "  Run 'claude doctor' to verify health"
else
  echo "  Installing Claude Code native binary..."
  curl -fsSL https://claude.ai/install.sh | bash
  ok "Claude Code installed"
  echo ""
  echo "  After this script finishes:"
  echo "    1. Run: claude"
  echo "    2. Authenticate with your Anthropic account"
  echo "    3. Run: claude doctor   (to verify)"
fi

# ─── Claude Desktop ───
if ! command -v claude-desktop &>/dev/null && ! dpkg -l claude-desktop-bin &>/dev/null 2>&1; then
  echo "  Installing Claude Desktop..."
  curl -fsSL https://patrickjaja.github.io/claude-desktop-bin/install.sh | sudo bash
  sudo apt install -y claude-desktop-bin
  ok "Claude Desktop"
else
  ok "Claude Desktop (exists)"
fi

# ─── Claude Cowork Service ───
if ! dpkg -l claude-cowork-service &>/dev/null 2>&1; then
  echo "  Installing Claude Cowork Service..."
  curl -fsSL https://patrickjaja.github.io/claude-cowork-service/install.sh | sudo bash
  sudo apt install -y claude-cowork-service
  ok "Claude Cowork Service"
else
  ok "Claude Cowork Service (exists)"
fi


section "Phase 5/6 — Deploy ~/.claude/ Config"

# sd is required for template substitution (installed via cargo in Phase 3)
if ! command -v sd &>/dev/null; then
  warn "sd not found — falling back to sed for template substitution"
  sd() { sed -i "s|$1|$2|g" "$3"; }
fi

CLAUDE_DIR="$HOME/.claude"

# Backup existing
if [ -d "$CLAUDE_DIR/skills" ] || [ -d "$CLAUDE_DIR/commands" ] || [ -d "$CLAUDE_DIR/agents" ]; then
  BACKUP="$CLAUDE_DIR.backup.$(date +%s)"
  cp -r "$CLAUDE_DIR" "$BACKUP" 2>/dev/null || true
  warn "Backed up existing config to $BACKUP"
fi

mkdir -p "$CLAUDE_DIR"/{skills/cli-tools,skills/security-scan,skills/git-workflow,skills/infra-deploy,skills/add-cli-tool/references,skills/tmux-control,skills/workspace,skills/pueue-orchestrator,skills/diagrams,skills/deploy,skills/process-supervisor,commands,agents,hooks,memory,rules,logs,templates}

# ─── CLAUDE.md ───
cat > "$CLAUDE_DIR/CLAUDE.md" << 'CLAUDEMD'
# TITAN_ENGINEER_NAME — Global Operating Manual

## Preferences
- Be direct. Skip preambles.
- When I ask "how", give the command, not a tutorial.
- If unsure, say so. Never hallucinate.
- Python 3.10+ with type hints. Bash must pass shellcheck.
- Conventional commits: `feat:`, `fix:`, `chore:`, `docs:`

## Tool Philosophy
You have 100+ CLI tools installed. They replace most MCPs at zero context cost.
NEVER guess flags. Discover tools on demand:
1. Check existence: `type <tool>` or `which <tool>`
2. Learn usage: `<tool> --help` or `<tool> -h`
3. Quick reference: `tldr <tool>`
4. Browse installed: `uv tool list`, `ls ~/.cargo/bin/`, `ls ~/go/bin/`

## Tool Routing — use the right tool, not the familiar one
| Task | Tool | NOT this |
|------|------|----------|
| Search text | `rg` | grep |
| Find files | `fd` | find |
| View files | `bat` | cat |
| List files | `eza` | ls |
| Find & replace | `sd` | sed |
| HTTP requests | `xh` | curl |
| Process listing | `procs` | ps |
| Disk usage | `dust` | du |
| DNS lookup | `doggo` | dig |
| JSON | `jq` | python -c |
| YAML | `yq` | python -c |
| CSV | `xsv` or `miller` | awk |
| SQL on files | `duckdb` | sqlite3 |
| HTML extraction | `htmlq` | regex |
| Compress/extract | `ouch` | tar/unzip/7z |
| Format shell | `shfmt` | manual |
| Format web files | `prettier` | manual |
| Structural replace | `comby` | regex sed |
| Greppable JSON | `gron` | manual jq |
| Code stats | `scc` | tokei/cloc |
| Multi-format query | `dasel` | format-specific |
| API test chains | `hurl` | curl scripts |
| JWT inspect | `jwt` | python/openssl |
| HTTP load test | `oha` | ab/wrk |
| Repo → AI context | `repomix` | manual |

## CLI Tools That Replace MCPs — use these instead
| Domain | CLI tool | Replaces MCP |
|--------|----------|-------------|
| GitHub | `gh` | GitHub MCP |
| Git | `git` (built-in) | Git MCP |
| AWS | `aws` | AWS MCP |
| Hetzner | `hcloud` | — |
| Kubernetes | `kubectl`, `helm` | K8s MCP |
| Docker | `docker`, `lazydocker` | Docker MCP |
| Postgres | `pgcli` | Postgres MCP |
| SQLite | `litecli` | SQLite MCP |
| Redis | `redis-cli` | Redis MCP |
| Any DB | `usql` | Database MCPs |
| SQL on files | `duckdb` | — |
| HTTP/APIs | `xh` | Fetch MCP |
| Secrets scan | `gitleaks`, `trufflehog` | — |
| Vuln scan | `trivy`, `nuclei`, `grype` | — |
| SBOM | `syft` | — |
| Static analysis | `semgrep`, `comby` | — |
| Certificates | `step`, `mkcert` | — |
| Recon | `subfinder`, `httpx`, `dnsx`, `katana` | — |
| Container registry | `crane`, `cosign` | — |
| Code indexing | `ctags`, `tree-sitter` | — |

## Workflow Rules — IMPORTANT
1. **Branch first**: Never commit directly to `main`.
2. **Search before create**: `rg` the codebase before creating new functions/classes.
3. **Check history before modify**: `git log --oneline -5 <file>` before editing.
4. **Lint everything**: `shellcheck` for .sh, `ruff check` for .py, `hadolint` for Dockerfile.
5. **Scan before push**: `gitleaks detect` before any `git push`.
6. **Commit often**: After every working change, conventional commit.
7. **Diff before commit**: `git diff --stat` — revert unrelated changes.
8. **3-strike rule**: Same error 3 times → stop, write to `_scratchpad.md`, ask me.

## Do NOT Touch
`.env*`, `*credentials*`, `*secret*`, `~/.ssh/*`, `~/.bashrc`, `~/.profile`

## Context Hygiene
- Use subagents for research to keep main context clean.
- Write plans to `_scratchpad.md`, not just chat.
- At session start, check `~/.claude/memory/handoff.md` — it contains auto-saved state from the previous session.

## Auto Memory Protocol — MANDATORY
You have a persistent memory directory. Use it. This is not optional.

**MUST write to auto memory when:**
1. User says "remember this" or uses `/remember` — immediately
2. You discover a project convention or architecture pattern — after confirming it
3. A debugging session reveals a non-obvious fix — after the fix works
4. User corrects you on something — immediately update/remove the wrong memory
5. You learn a user preference from their feedback — after 2+ consistent signals
6. A key decision is made (tool choice, architecture, workflow) — after the decision

**MUST NOT write to memory:**
- Speculative conclusions from reading one file
- Session-specific temporary state (use `_scratchpad.md` instead)
- Anything that duplicates CLAUDE.md or project CLAUDE.md

**How:** Use the Write/Edit tools on files in your auto memory directory.
Keep `MEMORY.md` under 150 lines. Create topic files for details.

## Compaction Protocol
When context is being compacted, ALWAYS preserve in the summary:
1. **Current task** — what you are working on and why
2. **Branch name** — the active git branch
3. **Modified files** — all files changed in this session
4. **Test status** — last test commands and pass/fail results
5. **Blockers** — any unresolved errors or open questions
6. **Key decisions** — architectural or design choices made
7. **Next steps** — what needs to happen next
CLAUDEMD
sd 'TITAN_ENGINEER_NAME' "$ENGINEER_NAME" "$CLAUDE_DIR/CLAUDE.md"
ok "CLAUDE.md"

# ─── settings.json ───
cat > "$CLAUDE_DIR/settings.json" << 'SETTINGS'
{
  "env": {
    "ENGINEER_NAME": "TITAN_ENGINEER_NAME",
    "DEFAULT_BRANCH": "main",
    "ENABLE_TOOL_SEARCH": "auto:5",
    "CLAUDE_CODE_STATUSLINE": "ccstatusline",
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "85",
    "CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR": "1",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY": "1",
    "BASH_DEFAULT_TIMEOUT_MS": "300000",
    "BASH_MAX_TIMEOUT_MS": "600000",
    "CLAUDE_CODE_SUBAGENT_MODEL": "sonnet",
    "CLAUDE_CODE_ENABLE_TASKS": "1",
    "CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS": "16000",
    "DISABLE_NON_ESSENTIAL_MODEL_CALLS": "1",
    "PATH": "TITAN_PATH_PLACEHOLDER"
  },
  "preferences": {
    "cleanupPeriodDays": 365
  },
  "showTurnDuration": true,
  "includeCoAuthoredBy": true,
  "respectGitignore": true,
  "permissions": {
    "allow": [
      "Bash(*)",
      "Read(*)", "Edit(*)", "MultiEdit(*)", "Write(*)",
      "Glob(*)", "Grep(*)", "Skill(*)"
    ],
    "deny": [
      "Bash(rm -rf *)", "Bash(rm -r /*)", "Bash(rm -r *)", "Bash(rm --recursive *)",
      "Bash(git reset --hard *)", "Bash(git clean -f*)", "Bash(git clean -d*)",
      "Bash(chmod 777 *)", "Bash(chmod -R 777 *)",
      "Bash(curl * | bash)", "Bash(curl * | sh)", "Bash(curl *|bash)", "Bash(curl *|sh)",
      "Bash(wget * | bash)", "Bash(wget * | sh)", "Bash(wget *|bash)", "Bash(wget *|sh)",
      "Bash(git push * --force)", "Bash(git push -f *)", "Bash(git push --force*)",
      "Bash(git push * main)", "Bash(git push origin main)", "Bash(git push origin master)",
      "Bash(git checkout -- .)", "Bash(git checkout .)",
      "Bash(git restore .)", "Bash(git restore --staged .)",
      "Bash(terraform destroy *)", "Bash(terraform apply -auto-approve *)",
      "Bash(kubectl delete namespace *)", "Bash(kubectl delete -f *)",
      "Bash(docker system prune *)", "Bash(docker rm -f *)", "Bash(docker rmi -f *)",
      "Bash(pip install *)", "Bash(sudo pip *)", "Bash(npm install -g *)",
      "Bash(sudo rm *)", "Bash(sudo chmod *)", "Bash(sudo chown *)",
      "Bash(mkfs *)", "Bash(dd if=*)", "Bash(shred *)",
      "Bash(kill -9 *)", "Bash(killall *)", "Bash(pkill *)",
      "Bash(reboot*)", "Bash(shutdown*)", "Bash(systemctl reboot*)", "Bash(systemctl poweroff*)",
      "Bash(iptables *)", "Bash(ufw *)",
      "Read(~/.ssh/*)", "Read(~/.aws/credentials)", "Read(.env*)",
      "Read(*secret*)", "Read(*credential*)", "Read(*.pem)", "Read(*.key)",
      "Edit(~/.bashrc)", "Edit(~/.profile)", "Edit(~/.zshrc)",
      "Edit(~/.ssh/*)", "Edit(.env*)", "Edit(*secret*)", "Edit(*credential*)",
      "Write(~/.bashrc)", "Write(~/.profile)", "Write(~/.zshrc)",
      "Write(~/.ssh/*)", "Write(.env*)", "Write(*secret*)", "Write(*credential*)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_input.command // empty' | { read -r -d '' cmd || true; case \"$cmd\" in *'rm -rf'*|*'rm -r '*|*'rm --recursive'*) echo 'BLOCKED: Use trash-put instead of rm -r' >&2; exit 2;; *'rm -f '*) echo 'BLOCKED: Use trash-put for safe deletion' >&2; exit 2;; *'git push'*'--force'*|*'git push -f'*|*'git push --force'*) echo 'BLOCKED: Force push not allowed. Use a feature branch.' >&2; exit 2;; *'git push'*' main'*|*'git push'*' master'*) echo 'BLOCKED: Direct push to main/master. Push a feature branch and open a PR.' >&2; exit 2;; *'pip install'*|*'sudo pip'*|*'npm install -g'*) echo 'BLOCKED: Use uv tool install (Python) or bun install -g (JS) instead.' >&2; exit 2;; *'git commit'*) branch=$(git branch --show-current 2>/dev/null); if [ \"$branch\" = main ] || [ \"$branch\" = master ]; then echo \"BLOCKED: Cannot commit on $branch. Create a feature branch first.\" >&2; exit 2; fi;; *'git reset --hard'*) echo 'BLOCKED: git reset --hard destroys uncommitted work. Use git stash instead.' >&2; exit 2;; *'git clean -f'*|*'git clean -d'*) echo 'BLOCKED: git clean removes untracked files permanently.' >&2; exit 2;; *'chmod 777'*|*'chmod -R 777'*) echo 'BLOCKED: chmod 777 is a security risk.' >&2; exit 2;; *'sudo rm'*|*'sudo chmod'*|*'sudo chown'*) echo 'BLOCKED: sudo file operations need explicit user approval.' >&2; exit 2;; *'| bash'*|*'| sh'*|*'|bash'*|*'|sh'*) echo 'BLOCKED: Piping to shell is unsafe. Download and inspect first.' >&2; exit 2;; *'kill -9'*|*'killall '*|*'pkill '*) echo 'BLOCKED: Process killing needs explicit user approval.' >&2; exit 2;; *'docker system prune'*|*'docker rm -f'*) echo 'BLOCKED: Docker cleanup needs explicit user approval.' >&2; exit 2;; *'terraform destroy'*|*'terraform apply -auto-approve'*) echo 'BLOCKED: Destructive infra operations need explicit user approval.' >&2; exit 2;; *'kubectl delete'*) echo 'BLOCKED: Kubernetes deletion needs explicit user approval.' >&2; exit 2;; esac; exit 0; }",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_input.file_path // empty' | { read -r -d '' fp || true; case \"$fp\" in *.env*|*credentials*|*secret*|*.pem|*.key) echo 'Cannot edit secrets/credentials. Edit manually.' >&2; exit 2;; *) exit 0;; esac; }",
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_input.file_path // empty' | { read -r -d '' fp || true; case \"$fp\" in *.sh|*.bash) if command -v shellcheck &>/dev/null; then shellcheck \"$fp\" 2>&1 | head -20 || true; else echo 'warning: shellcheck not found, skipping lint' >&2; fi;; *.py) if command -v ruff &>/dev/null; then ruff check \"$fp\" 2>&1 | head -20 || true; else echo 'warning: ruff not found, skipping lint' >&2; fi;; Dockerfile*) if command -v hadolint &>/dev/null; then hadolint \"$fp\" 2>&1 | head -10 || true; else echo 'warning: hadolint not found, skipping lint' >&2; fi;; esac; }",
            "timeout": 15,
            "async": true
          }
        ]
      },
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "mkdir -p ~/.claude/logs && jq -c '{ts: (now | todate), tool: .tool_name, input: (.tool_input | tostring | .[0:200])}' >> ~/.claude/logs/audit.jsonl 2>/dev/null || true",
            "timeout": 5,
            "async": true
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "msg=$(jq -r '.message // \"Claude needs attention\"'); notify-send 'Claude Code' \"$msg\" 2>/dev/null || true",
            "timeout": 5
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/pre-compact.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/session-end.sh",
            "timeout": 10
          },
          {
            "type": "command",
            "command": "curl -sf -d \"Claude Code session ended: $(git branch --show-current 2>/dev/null || echo unknown)\" \"${NTFY_URL:-http://localhost:9999/null}\" 2>/dev/null || true",
            "timeout": 5,
            "async": true
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/session-start.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/session-end.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "PostToolUseFailure": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "mkdir -p ~/.claude/logs && jq -c '{ts: (now | todate), tool: .tool_name, error: (.error // .tool_input | tostring | .[0:300])}' >> ~/.claude/logs/failures.jsonl 2>/dev/null || true",
            "timeout": 5,
            "async": true
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "mkdir -p ~/.claude/logs && jq -c '{ts: (now | todate), event: \"subagent_stop\", agent: (.agent_name // \"unknown\")}' >> ~/.claude/logs/audit.jsonl 2>/dev/null || true",
            "timeout": 5,
            "async": true
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "echo 'Success' || true",
            "timeout": 3
          }
        ]
      }
    ],
    "TaskCompleted": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "mkdir -p ~/.claude/logs && jq -c '{ts: (now | todate), event: \"task_completed\", task: (.task_name // \"unknown\")}' >> ~/.claude/logs/audit.jsonl 2>/dev/null || true",
            "timeout": 5,
            "async": true
          }
        ]
      }
    ],
    "InstructionsLoaded": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "mkdir -p ~/.claude/logs && jq -c '{ts: (now | todate), event: \"instructions_loaded\", file: (.file_path // \"unknown\")}' >> ~/.claude/logs/audit.jsonl 2>/dev/null || true",
            "timeout": 5,
            "async": true
          }
        ]
      }
    ],
    "ConfigChange": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "mkdir -p ~/.claude/logs && jq -c '{ts: (now | todate), event: \"config_change\", file: (.file_path // \"unknown\")}' >> ~/.claude/logs/audit.jsonl 2>/dev/null || true",
            "timeout": 5,
            "async": true
          }
        ]
      }
    ],
    "TeammateIdle": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "mkdir -p ~/.claude/logs && jq -c '{ts: (now | todate), event: \"teammate_idle\", teammate: (.teammate_name // \"unknown\")}' >> ~/.claude/logs/audit.jsonl 2>/dev/null || true",
            "timeout": 5,
            "async": true
          }
        ]
      }
    ]
  },
  "enabledPlugins": {
    "hookify@claude-plugins-official": true,
    "code-review@claude-plugins-official": true
  },
  "model": "opusplan",
  "skipDangerousModePermissionPrompt": true,
  "statusLine": {
    "type": "command",
    "command": "ccstatusline",
    "padding": 0
  }
}
SETTINGS
sd 'TITAN_ENGINEER_NAME' "$ENGINEER_NAME" "$CLAUDE_DIR/settings.json"
TITAN_PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.cargo/bin:$HOME/go/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
sd 'TITAN_PATH_PLACEHOLDER' "$TITAN_PATH" "$CLAUDE_DIR/settings.json"
sd 'TITAN_HOME_PLACEHOLDER' "$HOME" "$CLAUDE_DIR/settings.json"
ok "settings.json"

# ccstatusline config is user-managed via `ccstatusline` TUI editor
# The script installs the binary (bun install -g ccstatusline) but does NOT
# write config — run `ccstatusline` interactively to customize
ok "ccstatusline (config is user-managed, run 'ccstatusline' to customize)"

# ─── Skills ───
# tool-discovery, security-ops, debug-protocol removed — replaced by better versions:
#   tool-discovery → cli-tools (150 lines, full tool reference)
#   security-ops   → security-scan (39 lines, structured workflows)
#   debug-protocol → systematic-debugging (from superpowers)

cat > "$CLAUDE_DIR/skills/cli-tools/SKILL.md" << 'SKILL'
---
name: cli-tools
description: Reference for 100+ installed CLI tools. Use when working with any CLI tool, searching files, processing data, managing containers, infrastructure, security scanning, or system monitoring.
---

# CLI Tool Arsenal

You have 100+ CLI tools installed. Before using any tool,
run `<tool> --help` or `<tool> -h` to learn its current syntax and flags.
Never guess flags — always check help first.

## Tool Reference by Task

**Search & Find:**
- `rg` (ripgrep) — fast recursive text search. Use over grep always.
- `fd` — find files by name/pattern. Use over `find` always.
- `fzf` — pipe anything into it for fuzzy selection.
- `ast-grep` — search code by AST structure, not text patterns.
- `comby` — structural search/replace that understands code syntax (strings, comments, blocks).
- `ctags` — generate symbol index. Run `ctags -R .` then query tags file for fast navigation.

**File Viewing & Management:**
- `bat` — view files with syntax highlighting. Use over `cat` for code.
- `eza` — list files with git status. Use over `ls`.
- `dust` — check disk usage visually. Use over `du`.
- `broot` — interactive directory navigation.
- `yazi` — full terminal file manager when needed.
- `zoxide` — smart directory jumping.
- `ouch` — universal compress/decompress (tar, zip, 7z, zstd, gz, xz, bz2).

**Text & Data Wrangling:**
- `jq` — JSON processing. Always use for JSON manipulation.
- `yq` — YAML/XML/TOML processing. Same syntax as jq.
- `sd` — find and replace in files. Use over `sed` for simple replacements.
- `miller` (mlr) — CSV/JSON tabular operations.
- `xsv` — fast CSV operations (stats, select, join, split).
- `htmlq` — extract data from HTML using CSS selectors.
- `csvkit` — CSV processing suite (csvlook, csvstat, csvsql).
- `choose` — select columns from output. Use over `cut`.
- `jnv` — interactive JSON viewer with jq filtering.
- `gron` — flatten JSON to greppable lines. `gron --ungron` reverses. Use to explore large API responses.
- `dasel` — unified query/modify for JSON, YAML, TOML, XML, CSV, HCL. One syntax for all formats.
- `vd` (visidata) — TUI spreadsheet for CSV, JSON, SQLite, Parquet.
- `nu` (nushell) — structured data shell, everything is a table.

**Git Operations:**
- `gh` — GitHub operations (PRs, issues, releases, actions). Always prefer over browser.
- `lazygit` — interactive git UI when complex operations needed.
- `delta` — git diff viewer. Already configured as git pager.
- `difftastic` — structural diffs when line-diff is insufficient.
- `git-cliff` — generate changelogs from conventional commits.
- `gitleaks` — scan for secrets before committing.
- `git-absorb` — auto-create fixup commits for review changes.
- `onefetch` — quick repo overview/stats.

**Code Quality:**
- `semgrep` — run static analysis. Use for security and correctness patterns.
- `shellcheck` — always lint shell scripts before execution.
- `ruff` — Python linter and formatter. Use over flake8/black.
- `scc` — codebase stats with complexity scoring and COCOMO estimates. Use over tokei.
- `tree-sitter` — parse code into ASTs. Build repo maps for context-efficient navigation.
- `typos` — spell check source code and docs.
- `codespell` — fix common misspellings.
- `hadolint` — lint Dockerfiles.
- `actionlint` — lint GitHub Actions workflows.
- `shfmt` — auto-format shell scripts (pairs with shellcheck).
- `prettier` — format YAML, JSON, Markdown, HTML, CSS consistently.

**Containers & Kubernetes:**
- `lazydocker` — Docker management UI.
- `dive` — analyze Docker image layers and size.
- `ctop` — live container metrics.
- `kubectl` — Kubernetes cluster operations.
- `k9s` — Kubernetes terminal UI.
- `helm` — Kubernetes package management.
- `stern` — tail logs from multiple pods simultaneously.
- `crane` — inspect/copy/mutate container images without Docker daemon.
- `cosign` — sign and verify container images (Sigstore supply chain security).

**Infrastructure:**
- `terraform` — infrastructure provisioning.
- `ansible` — configuration management and automation.
- `packer` — build machine images.
- `tflint` — lint Terraform files before apply.
- `infracost` — estimate cloud costs from Terraform plans.
- `sops` — encrypt/decrypt secret files.
- `age` — simple file encryption.
- `infisical` — secrets management platform CLI.

**Networking & HTTP/Proxy:**
- `xh` — HTTP requests. Use over curl for readability.
- `httpie` (http) — alternative HTTP client with JSON support.
- `doggo` — DNS lookups. Use over dig.
- `mtr` — network path diagnostics.
- `bandwhich` — see bandwidth usage by process.
- `websocat` — WebSocket client.
- `grpcurl` — interact with gRPC services.
- `oha` — HTTP load testing with real-time TUI. Use for API performance testing.
- `hurl` — declarative HTTP test chains with assertions. Use for API integration testing.
- `aria2c` — accelerated downloads.
- `bore` — expose local ports publicly (tunneling).
- `mitmproxy` — intercept/inspect/modify HTTP/HTTPS traffic.
- `cloudflared` — Cloudflare tunnels (persistent URLs, auth, HTTPS).

**Security & Scanning:**
- `nmap` — network and port scanning.
- `nuclei` — template-based vulnerability scanning.
- `trivy` — scan containers, IaC, and filesystems for vulns.
- `osv-scanner` — check dependencies against OSV database.
- `nikto` — web server vulnerability scanning.
- `ffuf` — web fuzzing (directories, parameters).
- `trufflehog` — deep secret scanning across git history.
- `lynis` — system security audit.
- `sqlmap` — SQL injection testing.
- `parry` — prompt injection scanner for LLM apps.
- `sherlock` — username search across social networks.
- `syft` — generate SBOMs for containers and filesystems.
- `grype` — vulnerability scanner (pairs with syft for full supply chain coverage).
- `step` — inspect/generate certificates, debug TLS issues.
- `jwt` — decode, encode, and validate JWTs from terminal.
- `httpx` — mass HTTP probing for live service discovery. Pairs with subfinder.
- `subfinder` — passive subdomain enumeration from 50+ sources.
- `dnsx` — bulk DNS resolution and wildcard detection.
- `katana` — web crawler with JS rendering. Finds endpoints ffuf misses.

**Databases:**
- `duckdb` — run SQL on local files (CSV, Parquet, JSON). Extremely powerful.
- `usql` — universal SQL client for any database.
- `pgcli` — Postgres with autocomplete.
- `litecli` — SQLite with autocomplete.
- `redis-cli` — Redis operations.

**System Monitoring:**
- `btop` — system resource monitor.
- `procs` — process viewer with search. Use over `ps`.
- `hyperfine` — benchmark commands with statistical analysis.
- `pueue` — queue and manage background tasks.
- `watchexec` — watch files and re-run commands on change.

**Development Workflow:**
- `just` — command runner (justfile). Prefer over Makefile for project tasks.
- `task` — alternative task runner (Taskfile.yml).
- `mise` — manage tool versions (Node, Python, Go, etc).
- `direnv` — auto-load .envrc per directory.
- `entr` — simple file watcher.
- `mkcert` — generate trusted local HTTPS certificates.
- `dippy` — auto-approve safe commands for Claude Code.
- `inotifywait` — watch files for changes and trigger commands.
- `expect` — automate interactive CLI tools.
- `gum` — pretty prompts, spinners, and styled output for scripts.
- `asciinema` — record terminal sessions for sharing.
- `mmdc` — render mermaid diagrams to PNG/SVG/PDF.
- `cookiecutter` — scaffold projects from templates.
- `act` — run GitHub Actions locally in Docker.
- `playwright` — browser automation, E2E testing, screenshots.
- `maim` — screenshot tool (capture screen regions).
- `xdotool` — automate X11 window/keyboard/mouse actions.
- `lnav` — structured log viewer with filtering and highlighting.
- `convert` (imagemagick) — resize, annotate, convert images.
- `chafa` — render images (PNG, JPG, GIF) in terminal.
- `repomix` — pack entire repo into AI-optimized single file with token counts.
- `runme` — execute code blocks directly from Markdown files.

**Cloud CLIs:**
- `aws` — AWS operations.
- `hcloud` — Hetzner Cloud operations.
- `doctl` — DigitalOcean operations.
- `mc` — S3-compatible object storage operations.
- `vercel` — Vercel deployment CLI.

**AI Tools:**
- `gemini-cli` — Google Gemini CLI.
- `claude-tmux` — Claude Code in tmux sessions.
- `claude-esp` — Claude ESP tool.
- `recall` — search Claude/Codex conversation history.
- `ccusage` — Claude Code usage stats tracker.
- `ccstatusline` — Claude Code status line.
- `claude-squad` — manage multiple AI terminal agents in parallel (tmux-based).

**Documentation:**
- `pandoc` — convert between document formats.
- `glow` — render markdown beautifully in terminal.
- `mdbook` — build documentation sites from markdown.
- `slides` — terminal presentations from markdown.

**Terminal Productivity:**
- `tmux` — terminal multiplexer. Use for persistent sessions.
- `atuin` — searchable shell history with context.
- `navi` — interactive cheatsheet for commands.
- `tldr` — simplified man pages. Check before reading full man pages.
- `starship` — informative shell prompt.
- `trash-cli` — safe file deletion to trash.
- `spotify_player` — Spotify TUI client.

## Rules
1. ALWAYS run `<tool> --help` before first use in a session.
2. Prefer modern tools over legacy equivalents.
3. Pipe freely between tools. The Unix philosophy applies.
4. For data tasks: JSON→`jq`, YAML→`yq`, CSV→`xsv`/`miller`, SQL-shaped→`duckdb`.
5. Always `shellcheck` any shell script before running.
6. Always `gitleaks detect` before pushing to remote.
7. For long-running tasks, use `pueue` to queue them.
8. When benchmarking, use `hyperfine` not manual timing.
SKILL
ok "skill: cli-tools"

cat > "$CLAUDE_DIR/skills/security-scan/SKILL.md" << 'SKILL'
---
name: security-scan
description: Security scanning and vulnerability assessment workflows. Use when performing security audits, scanning for vulnerabilities, checking dependencies, or hardening systems.
---

# Security Scanning Workflows

## Pre-Push Security Check
Before any push to remote, run this sequence:
1. `gitleaks detect --verbose` — scan for leaked secrets
2. `trivy fs --severity HIGH,CRITICAL .` — filesystem vulnerability scan
3. `osv-scanner --lockfile=<lockfile>` — dependency vulnerability check

## Container Security
1. `trivy image <image>` — scan container image
2. `syft <image>` — generate SBOM (Software Bill of Materials)
3. `grype <image>` — scan SBOM/image for known vulnerabilities
4. `crane manifest <image>` — inspect remote image without pulling
5. `cosign verify <image>` — verify image signature
6. `dive <image>` — check image layer efficiency
7. `hadolint Dockerfile` — lint Dockerfile for best practices

## Infrastructure Security
1. `trivy config .` — scan Terraform/CloudFormation for misconfigs
2. `tflint` — lint Terraform files
3. `semgrep --config auto .` — static analysis

## Network Reconnaissance
1. `subfinder -d <domain>` — passive subdomain enumeration
2. `dnsx -l subdomains.txt -resp` — bulk DNS resolution
3. `httpx -l hosts.txt -sc -title -tech-detect` — probe for live HTTP services
4. `katana -u <url>` — crawl with JS rendering for hidden endpoints
5. `nmap -sV -sC <target>` — service version detection
6. `nuclei -u <target>` — template-based vuln scanning
7. `nikto -h <target>` — web server scanning
8. `ffuf -u <url>/FUZZ -w <wordlist>` — directory fuzzing

## Supply Chain Security
1. `syft dir:.` — generate SBOM for project directory
2. `grype sbom:./sbom.json` — scan SBOM for known CVEs
3. `grype dir:.` — scan project directly for vulnerable dependencies

## TLS & Certificate Debugging
1. `step certificate inspect <cert.pem>` — view certificate details
2. `step certificate inspect https://<domain>` — inspect remote TLS cert
3. `step certificate create` — generate self-signed certs for testing

## System Hardening
1. `lynis audit system` — full system security audit
2. Review output and address findings by severity

## Rules
- NEVER scan targets you don't own or have authorization for
- Always use `--help` before running any security tool
- Report findings clearly with severity levels
- Suggest remediations alongside findings
SKILL
ok "skill: security-scan"

cat > "$CLAUDE_DIR/skills/git-workflow/SKILL.md" << 'SKILL'
---
name: git-workflow
description: Git branching, commit, and PR conventions. Use when creating branches, making commits, or opening PRs.
---
# Git Workflow
Branches: `feat/<desc>`, `fix/<desc>`, `chore/<desc>`, `docs/<desc>`
Commits: `<type>(<scope>): <description>` — types: feat, fix, docs, style, refactor, perf, test, chore, ci

## Before Commit
`git diff --stat` → revert unrelated → `shellcheck`/`ruff check` → `gitleaks detect`

## PR: `git push -u origin HEAD` → `gh pr create --fill`

Rules: never force push main, never commit to main, one change per commit, PRs under 400 lines.
SKILL
ok "skill: git-workflow"

cat > "$CLAUDE_DIR/skills/infra-deploy/SKILL.md" << 'SKILL'
---
name: infra-deploy
description: Infrastructure as Code workflows with Terraform, Ansible, Docker, and Kubernetes. Use when provisioning, configuring, deploying, or managing infrastructure.
---

# Infrastructure Workflows

## Terraform
1. `terraform fmt -recursive` — format all .tf files
2. `tflint` — lint for errors and best practices
3. `terraform validate` — syntax validation
4. `terraform plan -out=plan.tfplan` — preview changes (ALWAYS do this first)
5. `infracost breakdown --path=plan.tfplan` — estimate cost impact
6. Only after review: `terraform apply plan.tfplan`

NEVER run `terraform apply -auto-approve` or `terraform destroy` without explicit operator approval.

## Ansible
1. `ansible-lint` — lint playbooks
2. `ansible-playbook --check -i inventory site.yml` — dry run
3. `ansible-playbook -i inventory site.yml` — actual run

## Docker
1. `hadolint Dockerfile` — lint before building
2. `docker build -t <name>:<tag> .` — build image
3. `trivy image <name>:<tag>` — scan for vulnerabilities
4. `dive <name>:<tag>` — analyze layer efficiency
5. `docker compose up -d` — deploy

## Kubernetes
1. `kubectl get pods -A` — cluster overview
2. `k9s` — interactive management
3. `stern <pod-prefix>` — tail logs from multiple pods
4. `helm list -A` — check installed charts

## Hetzner Cloud
Run `hcloud --help` for available commands.
Common: `hcloud server list`, `hcloud server create`, `hcloud firewall list`

## Rules
- ALWAYS plan before apply
- ALWAYS scan images before deploying
- ALWAYS lint IaC files before committing
- Use `sops` or `age` for secrets, never plaintext
SKILL
ok "skill: infra-deploy"

cat > "$CLAUDE_DIR/skills/add-cli-tool/SKILL.md" << 'SKILL'
---
name: add-cli-tool
description: Add a new CLI tool to the titan setup and make it usable immediately. Use when installing a new CLI tool, registering a tool in the setup script, updating the tool inventory, or when the user says "add tool", "new CLI tool", "register tool", "install X to titan". Also triggers on "I installed X", "add X to the setup", or any request to add a CLI tool to the workstation.
---

# Add CLI Tool

This skill registers a new CLI tool across all required locations and makes it
usable in the current session — doing manually what `titan-setup.sh` would do
on a fresh machine.

## Step 1: Gather Information

Ask (or infer from context) these details:

| Field | Required | Example |
|-------|----------|---------|
| Tool name | Yes | `bore-cli` |
| Binary name | If different from tool name | `bore` |
| Install method | Yes | `cargo`, `go`, `uv`, `bun`, `apt`, `binary` |
| Install command | Yes | `cargo install bore-cli` |
| One-line description | Yes | `expose local ports publicly (tunneling)` |
| Category | Yes | One of the categories in cli-tools skill |
| Replaces legacy tool? | No | `replaces dig` → add to CLAUDE.md routing table |
| Replaces an MCP? | No | `replaces Fetch MCP` → add to CLAUDE.md MCP table |

## Step 2: Find titan-setup.sh

```bash
fd titan-setup.sh ~/ --max-depth 3 --type f
```

If not found, ask the user for the path. Store it for the rest of this operation.

## Step 3: Install the Tool NOW

Run the actual install command so the tool is available this session.

## Step 4: Verify Installation

```bash
command -v <binary> && echo "OK" || echo "FAILED"
<binary> --help | head -5
```

If install failed, stop and report the error. Do not proceed to file edits.

## Step 5: Update titan-setup.sh

Read `references/locations.md` for the exact grep anchors for each edit location.

**5a. Install section** — Add to the correct array or block:
- `cargo` → append to `CARGO_CRATES=( ... )` array
- `go` → add entry to `declare -A GO_MAP=( ... )` associative array
- `uv` → append to `UV_TOOLS=( ... )` array
- `bun` → append to `BUN_TOOLS=( ... )` array
- `apt` → append to the `sudo apt install -y \` line
- `binary` / `git` → add a new standalone block after the last binary download section

**5b. cli-tools heredoc** — Find the category header (e.g., `**Security & Scanning:**`)
inside the `cat > "$CLAUDE_DIR/skills/cli-tools/SKILL.md"` heredoc.
Append the tool entry as a new `- \`tool\` — description` line under that category.

IMPORTANT: Only edit within these specific sections. Do NOT modify any other
part of the script.

## Step 6: Update Live Files

Apply the SAME cli-tools edit to the live file — this makes the tool
discoverable by Claude in the current session without re-running the script:

```
~/.claude/skills/cli-tools/SKILL.md
```

Find the same category header and append the same line.

## Step 7: Conditional Updates

Only if applicable:

- **Replaces legacy tool** → Add row to `## Tool Routing` table in `~/.claude/CLAUDE.md`
  AND in the CLAUDE.md heredoc in titan-setup.sh
- **Replaces an MCP** → Add row to `## CLI Tools That Replace MCPs` table in
  `~/.claude/CLAUDE.md` AND in the CLAUDE.md heredoc in titan-setup.sh
- **Needs auto-permission** → Add `Bash(<binary> *)` to the `"allow"` array in BOTH:
  - The settings.json heredoc in titan-setup.sh
  - The live `~/.claude/settings.json`

## Step 8: Validate

```bash
bash -n <path-to-titan-setup.sh>
```

If syntax errors, fix them before proceeding.

## Step 9: Test Tool Call

Run a simple command with the tool to confirm Claude can invoke it:

```bash
<binary> --version
```

## Step 10: Summary

Report to the user:
- Tool installed: Yes/No
- Files updated: list each file touched
- Syntax check: pass/fail
- Tool callable: Yes/No

## Rules

1. NEVER modify parts of titan-setup.sh outside the specific install/heredoc sections.
2. ALWAYS update both the script AND the live file for every edit.
3. ALWAYS run `bash -n` after editing the script.
4. If the tool is already installed (`command -v` succeeds), skip Step 3 but still
   register it in all files if missing.
5. If the tool is already in the cli-tools skill, tell the user — no duplicate entries.
SKILL
ok "skill: add-cli-tool"

cat > "$CLAUDE_DIR/skills/add-cli-tool/references/locations.md" << 'LOCATIONS'
# Edit Locations in titan-setup.sh

Grep anchors for finding insertion points. These patterns survive line number shifts.

## Install Section Anchors

| Method | Grep pattern | How to edit |
|--------|-------------|-------------|
| cargo | `^CARGO_CRATES=(` | Add crate name to the array (space-separated) |
| cargo (git) | After `# spotify_player` block | Add new `if ! command -v` block |
| go | `^declare -A GO_MAP=(` | Add `["binary"]="module/path@latest"` entry |
| go (special) | After `# age —` block | Add new `if command -v` block |
| uv | `^UV_TOOLS=(` | Add package name to the array |
| bun | `^BUN_TOOLS=(` | Add package name to the array |
| apt | `sudo apt install -y` | Add package to the continued line |
| binary | After `# trufflehog —` block | Add new download block |

## cli-tools Heredoc Anchor

The heredoc starts with:
```
cat > "$CLAUDE_DIR/skills/cli-tools/SKILL.md" << 'SKILL'
```

Find the category header and append `- \`tool\` — description` before the
next blank line or next category header.

### Valid categories
Search & Find, File Viewing & Management, Text & Data Wrangling, Git Operations,
Code Quality, Containers & Kubernetes, Infrastructure, Networking & HTTP/Proxy,
Security & Scanning, Databases, System Monitoring, Development Workflow,
Cloud CLIs, AI Tools, Documentation, Terminal Productivity

## Live File Paths

| File | Path |
|------|------|
| cli-tools skill | `~/.claude/skills/cli-tools/SKILL.md` |
| CLAUDE.md | `~/.claude/CLAUDE.md` |
| settings.json | `~/.claude/settings.json` |

## CLAUDE.md Table Anchors

- Tool routing table: grep for last row of `## Tool Routing` table
- MCP replacement table: grep for last row of `## CLI Tools That Replace MCPs` table

## settings.json Allow List Anchor

Inside `"allow": [` block. Add `"Bash(<binary> *)"` after any existing
similar permission line.
LOCATIONS
ok "skill: add-cli-tool (references)"

# ─── Skill: tmux-control ───
cat > "$CLAUDE_DIR/skills/tmux-control/SKILL.md" << 'SKILL'
---
description: Control tmux sessions — create panes, run commands, read output, monitor processes
triggers:
  - tmux
  - terminal pane
  - run in background
  - monitor process
  - split pane
  - send keys
---

# tmux Control

Use tmux to run, monitor, and control background processes.

## Core Commands
```bash
# Session management
tmux new-session -d -s <name>          # create detached session
tmux list-sessions                      # list sessions
tmux kill-session -t <name>             # kill session

# Pane operations
tmux split-window -h -t <session>       # horizontal split
tmux split-window -v -t <session>       # vertical split
tmux select-pane -t <session>:<pane>    # switch pane

# Send commands to panes
tmux send-keys -t <session>:<pane> '<command>' Enter

# Capture pane output (read what's on screen)
tmux capture-pane -t <session>:<pane> -p          # current screen
tmux capture-pane -t <session>:<pane> -p -S -50   # last 50 lines

# Wait for command to finish (check if prompt returned)
tmux send-keys -t <session> 'echo DONE_MARKER' Enter
# Then capture-pane and grep for DONE_MARKER
```

## Patterns

### Run and monitor a dev server
```bash
tmux new-session -d -s dev
tmux send-keys -t dev 'npm run dev' Enter
sleep 2
tmux capture-pane -t dev -p  # check if started
```

### Run parallel tasks
```bash
tmux new-session -d -s work
tmux send-keys -t work 'make build' Enter
tmux split-window -h -t work
tmux send-keys -t work:0.1 'make test' Enter
```

### Read output from a running process
```bash
tmux capture-pane -t <session> -p -S -100  # last 100 lines
```

## Rules
1. Always use `-d` (detached) when creating sessions from Claude.
2. Use `capture-pane -p` to read output — never try to interact with TUI apps.
3. Name sessions descriptively: `dev`, `build`, `logs`, `deploy`.
4. Clean up: `tmux kill-session -t <name>` when done.
5. For interactive tools (htop, vim), tell the user to open them manually.
SKILL
ok "skill: tmux-control"

# ─── Skill: workspace ───
cat > "$CLAUDE_DIR/skills/workspace/SKILL.md" << 'SKILL'
---
description: Project workspace configuration — auto-detect commands, _workspace.json convention, .envrc templates
triggers:
  - workspace
  - project setup
  - _workspace.json
  - how to build
  - how to test
  - how to deploy
  - envrc
  - project config
---

# Workspace Configuration

## _workspace.json Convention
Projects can include a `_workspace.json` at the root:

```json
{
  "name": "my-app",
  "commands": {
    "dev": "bun dev",
    "build": "bun run build",
    "test": "bun test",
    "lint": "ruff check . && shellcheck **/*.sh",
    "deploy": "terraform apply -auto-approve"
  },
  "main_branch": "main",
  "language": "typescript",
  "framework": "next.js"
}
```

## Auto-Detection (when no _workspace.json exists)
Detect project type from files present:

| File | Type | Dev | Test | Lint |
|------|------|-----|------|------|
| `package.json` | Node/Bun | `bun dev` | `bun test` | `bun lint` |
| `pyproject.toml` | Python | `uv run dev` | `uv run pytest` | `ruff check .` |
| `Cargo.toml` | Rust | `cargo run` | `cargo test` | `cargo clippy` |
| `go.mod` | Go | `go run .` | `go test ./...` | `golangci-lint run` |
| `Makefile` | Make | `make dev` | `make test` | `make lint` |
| `justfile` | Just | `just dev` | `just test` | `just lint` |
| `Taskfile.yml` | Task | `task dev` | `task test` | `task lint` |
| `Dockerfile` | Docker | `docker compose up` | — | `hadolint Dockerfile` |
| `terraform/` | Terraform | — | `terraform plan` | `tflint` |

## .envrc Templates
When setting up a new project with `direnv`:

### Python
```bash
# .envrc
layout python3
export DATABASE_URL="postgres://localhost/myapp_dev"
```

### Node
```bash
# .envrc
use mise
export NODE_ENV=development
```

### General
```bash
# .envrc
dotenv_if_exists .env.local
PATH_add bin
```

## Workflow
1. Check for `_workspace.json` first.
2. If absent, auto-detect from project files.
3. Use detected commands for `/ship`, `/scan`, testing.
4. Suggest creating `_workspace.json` if project is complex.
5. Use `direnv allow` after creating `.envrc`.
SKILL
ok "skill: workspace"

# ─── Skill: pueue-orchestrator ───
cat > "$CLAUDE_DIR/skills/pueue-orchestrator/SKILL.md" << 'SKILL'
---
description: Parallel task orchestration with pueue — queue builds, tests, scans in parallel
triggers:
  - pueue
  - parallel tasks
  - task queue
  - run in parallel
  - background tasks
  - orchestrate
---

# Pueue Task Orchestrator

Use `pueue` to run multiple tasks in parallel with dependency management.

## Setup
```bash
pueued -d                    # start daemon (if not running)
pueue status                 # check status
pueue parallel 4             # allow 4 parallel tasks (default: 1)
```

## Core Operations
```bash
# Add tasks
pueue add -- 'ruff check .'                    # add to default group
pueue add --label "lint-py" -- 'ruff check .'  # with label
pueue add --after 0 -- 'bun test'              # run after task 0

# Groups (for organizing)
pueue group add build
pueue group add test
pueue add --group build -- 'make build'
pueue add --group test -- 'bun test'

# Monitor
pueue status                 # see all tasks
pueue log <id>               # see output of task
pueue follow <id>            # stream output live

# Control
pueue pause <id>             # pause task
pueue start <id>             # resume task
pueue kill <id>              # kill task
pueue clean                  # remove finished tasks
pueue reset                  # kill all, clean everything
```

## Orchestration Patterns

### Pre-push pipeline (parallel lint + test, then scan)
```bash
pueued -d 2>/dev/null || true
pueue parallel 3
LINT=$(pueue add --print-task-id -- 'ruff check . && shellcheck **/*.sh')
TEST=$(pueue add --print-task-id -- 'bun test')
pueue add --after "$LINT,$TEST" -- 'gitleaks detect --verbose'
pueue wait  # blocks until all done
pueue status
```

### Build + deploy with dependencies
```bash
BUILD=$(pueue add --print-task-id --label build -- 'docker build -t app .')
SCAN=$(pueue add --print-task-id --after "$BUILD" --label scan -- 'trivy image app')
pueue add --after "$SCAN" --label deploy -- 'docker push app'
```

### Parallel security scans
```bash
pueue parallel 5
pueue add --label secrets -- 'gitleaks detect --verbose'
pueue add --label deps -- 'osv-scanner -r .'
pueue add --label sast -- 'semgrep --config auto .'
pueue add --label container -- 'trivy image myapp:latest'
pueue add --label iac -- 'tflint --recursive'
pueue wait
```

## Rules
1. Always start `pueued -d` before adding tasks.
2. Set `pueue parallel N` based on task type (CPU-bound: nproc, IO-bound: higher).
3. Use `--print-task-id` to capture IDs for dependencies.
4. Use `pueue wait` to block until pipeline completes.
5. Check `pueue log <id>` for failures, not just exit codes.
6. Run `pueue clean` after reviewing results.
SKILL
ok "skill: pueue-orchestrator"

# ─── Skill: diagrams ───
cat > "$CLAUDE_DIR/skills/diagrams/SKILL.md" << 'SKILL'
---
description: Generate architecture and flow diagrams using mermaid-cli (mmdc)
triggers:
  - diagram
  - mermaid
  - architecture diagram
  - flow chart
  - sequence diagram
  - generate diagram
  - visualize
  - erd
  - class diagram
---

# Diagram Generation

Use `mmdc` (mermaid-cli) to render diagrams as PNG/SVG.

## Usage
```bash
# Write mermaid to file, then render
cat > /tmp/diagram.mmd << 'EOF'
graph TD
    A[Client] --> B[API Gateway]
    B --> C[Auth Service]
    B --> D[App Service]
    D --> E[(Database)]
EOF

mmdc -i /tmp/diagram.mmd -o diagram.png          # PNG output
mmdc -i /tmp/diagram.mmd -o diagram.svg           # SVG output
mmdc -i /tmp/diagram.mmd -o diagram.png -w 1200   # custom width
mmdc -i /tmp/diagram.mmd -o diagram.pdf           # PDF output
```

## Diagram Types

### Architecture / System Design
```mermaid
graph TD
    LB[Load Balancer] --> S1[Server 1]
    LB --> S2[Server 2]
    S1 --> DB[(PostgreSQL)]
    S2 --> DB
    S1 --> Cache[(Redis)]
    S2 --> Cache
```

### Sequence Diagram
```mermaid
sequenceDiagram
    Client->>API: POST /login
    API->>Auth: validate(credentials)
    Auth-->>API: token
    API-->>Client: 200 OK {token}
```

### Entity Relationship
```mermaid
erDiagram
    USER ||--o{ ORDER : places
    ORDER ||--|{ LINE_ITEM : contains
    PRODUCT ||--o{ LINE_ITEM : "ordered in"
```

### Git Flow
```mermaid
gitgraph
    commit
    branch feature
    commit
    commit
    checkout main
    merge feature
    commit
```

### State Diagram
```mermaid
stateDiagram-v2
    [*] --> Draft
    Draft --> Review: submit
    Review --> Approved: approve
    Review --> Draft: request changes
    Approved --> Deployed: deploy
    Deployed --> [*]
```

### Flowchart (CI/CD Pipeline)
```mermaid
graph LR
    A[Push] --> B[Lint]
    A --> C[Test]
    B --> D{All Pass?}
    C --> D
    D -->|Yes| E[Build]
    D -->|No| F[Notify]
    E --> G[Deploy]
```

## Workflow
1. Write mermaid syntax to a `.mmd` file.
2. Render with `mmdc -i input.mmd -o output.png`.
3. For docs, use SVG: `mmdc -i input.mmd -o output.svg`.
4. Store diagrams in `docs/diagrams/` or project root.
5. Reference in README: `![Architecture](docs/diagrams/arch.png)`.

## Tips
- Use `graph TD` (top-down) or `graph LR` (left-right) for direction.
- Keep diagrams focused — one concept per diagram.
- Use descriptive node IDs: `DB[(PostgreSQL)]` not `A[(DB)]`.
- For large systems, break into multiple diagrams.
SKILL
ok "skill: diagrams"

# ─── Skill: deploy ───
cat > "$CLAUDE_DIR/skills/deploy/SKILL.md" << 'SKILL'
---
description: Deploy applications — auto-detect provider from project files, run the right deploy commands
triggers:
  - deploy
  - ship to production
  - push to prod
  - release
  - deploy to vercel
  - deploy to docker
  - terraform apply
  - helm upgrade
---

# Deploy Skill

Auto-detect deployment target from project files and run the correct commands.

## Provider Detection

| File/Dir | Provider | Deploy Command |
|----------|----------|---------------|
| `vercel.json` or `.vercel/` | Vercel | `vercel --prod` |
| `Dockerfile` + no k8s | Docker | `docker compose up -d --build` |
| `docker-compose.yml` | Docker Compose | `docker compose up -d --build` |
| `fly.toml` | Fly.io | `fly deploy` |
| `terraform/` or `*.tf` | Terraform | `terraform plan && terraform apply` |
| `k8s/` or `helm/` | Kubernetes | `helm upgrade` or `kubectl apply` |
| `serverless.yml` | Serverless | `serverless deploy` |
| `netlify.toml` | Netlify | `netlify deploy --prod` |
| `railway.json` | Railway | `railway up` |
| `Procfile` | Heroku-like | Platform-specific |

## Pre-Deploy Checklist
1. Run tests: detect from `_workspace.json` or auto-detect
2. Run linter: `ruff check .` / `bun lint` / `cargo clippy`
3. Scan secrets: `gitleaks detect --verbose`
4. Scan vulnerabilities: `trivy fs .` or `osv-scanner -r .`
5. Build: detect from project type
6. Deploy: run provider command

## Patterns

### Vercel
```bash
vercel --prod
```

### Docker + Registry
```bash
docker build -t registry.example.com/app:latest .
trivy image registry.example.com/app:latest
docker push registry.example.com/app:latest
```

### Terraform
```bash
cd terraform/
terraform init
terraform plan -out=tfplan
# Show plan and ask for confirmation
terraform apply tfplan
```

### Kubernetes (Helm)
```bash
helm upgrade --install app ./helm/app \
  --namespace production \
  --values helm/app/values-prod.yaml \
  --wait --timeout 5m
kubectl rollout status deployment/app -n production
```

### Cloudflare Tunnel (expose local)
```bash
cloudflared tunnel --url http://localhost:3000
```

## Rules
1. ALWAYS run pre-deploy checklist before deploying.
2. ALWAYS show the plan/diff and ask for confirmation before applying.
3. Never deploy directly to production without user confirmation.
4. Use `_workspace.json` deploy command if available.
5. For Terraform, always `plan` before `apply`.
6. Tag releases: `git tag v$(date +%Y%m%d.%H%M)` after successful deploy.
SKILL
ok "skill: deploy"

# ─── Skill: process-supervisor ───
cat > "$CLAUDE_DIR/skills/process-supervisor/SKILL.md" << 'SKILL'
---
description: Manage long-running processes with systemd user units — dev servers, daemons, watchers
triggers:
  - systemd
  - service
  - keep running
  - daemon
  - supervisor
  - background service
  - auto restart
  - user unit
---

# Process Supervisor (systemd user units)

Manage persistent background processes without root using systemd user units.

## Setup
```bash
# Enable lingering (services run even when logged out)
loginctl enable-linger $(whoami)

# Unit files go here
mkdir -p ~/.config/systemd/user/
```

## Creating a Service

### Template
```ini
# ~/.config/systemd/user/<name>.service
[Unit]
Description=<description>
After=network.target

[Service]
Type=simple
ExecStart=<command>
Restart=on-failure
RestartSec=5
WorkingDirectory=%h/<project-dir>
Environment=NODE_ENV=production

[Install]
WantedBy=default.target
```

### Example: Dev Server
```ini
[Unit]
Description=Next.js Dev Server
After=network.target

[Service]
Type=simple
ExecStart=/home/user/.bun/bin/bun dev
WorkingDirectory=%h/projects/my-app
Restart=on-failure

[Install]
WantedBy=default.target
```

### Example: File Watcher
```ini
[Unit]
Description=Auto-lint on file change

[Service]
Type=simple
ExecStart=/usr/bin/inotifywait -m -r -e modify --format '%%w%%f' src/ | while read f; do ruff check "$f" --fix 2>/dev/null; done
WorkingDirectory=%h/projects/my-app
Restart=on-failure

[Install]
WantedBy=default.target
```

## Management Commands
```bash
# Reload after creating/editing units
systemctl --user daemon-reload

# Start/stop/restart
systemctl --user start <name>
systemctl --user stop <name>
systemctl --user restart <name>

# Enable on boot
systemctl --user enable <name>

# Check status and logs
systemctl --user status <name>
journalctl --user -u <name> -f        # follow logs
journalctl --user -u <name> --since today

# List all user units
systemctl --user list-units --type=service

# Disable and remove
systemctl --user disable <name>
systemctl --user stop <name>
rm ~/.config/systemd/user/<name>.service
systemctl --user daemon-reload
```

## Rules
1. Always use `--user` flag — never create system-level services.
2. Use `%h` for home directory in unit files (expands automatically).
3. Set `Restart=on-failure` for services that should auto-recover.
4. Use `WorkingDirectory` to set the correct project path.
5. Run `daemon-reload` after any unit file changes.
6. Check `journalctl --user -u <name>` for debugging.
7. For one-off tasks, prefer `pueue` over systemd.
SKILL
ok "skill: process-supervisor"

# ─── Hook Scripts (Memory/Context Management) ───

cat > "$CLAUDE_DIR/hooks/pre-compact.sh" << 'HOOK'
#!/usr/bin/env bash
# PreCompact hook — auto-save session state before compaction
set -euo pipefail

MEMORY_DIR="$HOME/.claude/memory"
HANDOFF="$MEMORY_DIR/handoff.md"
mkdir -p "$MEMORY_DIR"

# Read input JSON from stdin
INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)

# Capture git state
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
MODIFIED=$(git diff --name-only HEAD 2>/dev/null || true)
STATUS=$(git status --porcelain 2>/dev/null | head -20 || true)
DIFF_STAT=$(git diff --stat 2>/dev/null | tail -5 || true)
RECENT_COMMITS=$(git log --oneline -10 2>/dev/null || true)

# Extract last assistant messages from transcript (if available)
LAST_CONTEXT=""
if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
  LAST_CONTEXT=$(tail -100 "$TRANSCRIPT" 2>/dev/null \
    | jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text // empty' 2>/dev/null \
    | tail -c 3000 || true)
fi

# Write handoff file
cat > "$HANDOFF" << EOF
---
timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
session_id: ${SESSION_ID}
branch: ${BRANCH}
trigger: pre-compact
---

# Session Handoff

## Branch
\`${BRANCH}\`

## Recent Commits
\`\`\`
${RECENT_COMMITS:-No commits}
\`\`\`

## Modified Files (uncommitted)
\`\`\`
${MODIFIED:-No modified files}
\`\`\`

## Git Status
\`\`\`
${STATUS:-Clean working tree}
\`\`\`

## Diff Summary
\`\`\`
${DIFF_STAT:-No changes}
\`\`\`

## Last Context
${LAST_CONTEXT:-No transcript context available}
EOF

exit 0
HOOK
chmod +x "$CLAUDE_DIR/hooks/pre-compact.sh"
ok "hook: pre-compact.sh"

cat > "$CLAUDE_DIR/hooks/session-end.sh" << 'HOOK'
#!/usr/bin/env bash
# Stop hook — capture final session state for next session
set -euo pipefail

MEMORY_DIR="$HOME/.claude/memory"
HANDOFF="$MEMORY_DIR/handoff.md"
mkdir -p "$MEMORY_DIR"

# Read input JSON from stdin
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null | head -c 2000)

# Capture git state
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
MODIFIED=$(git diff --name-only HEAD 2>/dev/null || true)
STATUS=$(git status --porcelain 2>/dev/null | head -20 || true)
DIFF_STAT=$(git diff --stat 2>/dev/null | tail -5 || true)
RECENT_COMMITS=$(git log --oneline -5 2>/dev/null || true)

# Write handoff file
cat > "$HANDOFF" << EOF
---
timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
session_id: ${SESSION_ID}
branch: ${BRANCH}
trigger: session-end
---

# Session Handoff

## Branch
\`${BRANCH}\`

## Recent Commits (this session)
\`\`\`
${RECENT_COMMITS:-No commits}
\`\`\`

## Modified Files (uncommitted)
\`\`\`
${MODIFIED:-No modified files}
\`\`\`

## Git Status
\`\`\`
${STATUS:-Clean working tree}
\`\`\`

## Diff Summary
\`\`\`
${DIFF_STAT:-No changes}
\`\`\`

## Last Assistant Message
${LAST_MSG:-No message captured}
EOF

exit 0
HOOK
chmod +x "$CLAUDE_DIR/hooks/session-end.sh"
ok "hook: session-end.sh"

cat > "$CLAUDE_DIR/hooks/session-start.sh" << 'HOOK'
#!/usr/bin/env bash
# SessionStart hook — load previous session state and memory reminders
set -euo pipefail

HANDOFF="$HOME/.claude/memory/handoff.md"

# Show handoff from previous session (if recent)
if [[ -f "$HANDOFF" ]]; then
  FILE_AGE=$(( $(date +%s) - $(stat -c %Y "$HANDOFF" 2>/dev/null || echo 0) ))
  if (( FILE_AGE < 86400 )); then
    echo "[Memory] Previous session handoff ($(( FILE_AGE / 60 ))m ago):" >&2
    head -30 "$HANDOFF" >&2
    echo "---" >&2
  fi
fi

# Remind about auto memory files
MEMORY_COUNT=$(find "$HOME/.claude/projects/" -name "MEMORY.md" 2>/dev/null | wc -l)
if (( MEMORY_COUNT > 0 )); then
  echo "[Memory] ${MEMORY_COUNT} project memory file(s) available." >&2
else
  echo "[Memory] No project memories yet. Use /remember or write to auto memory directory." >&2
fi

# Rotate audit log if over 10MB
AUDIT_LOG="$HOME/.claude/logs/audit.jsonl"
if [[ -f "$AUDIT_LOG" ]]; then
  AUDIT_SIZE=$(stat -c %s "$AUDIT_LOG" 2>/dev/null || echo 0)
  if (( AUDIT_SIZE > 10485760 )); then
    mv "$AUDIT_LOG" "${AUDIT_LOG}.$(date +%s).bak"
    echo "[Audit] Log rotated (was $(( AUDIT_SIZE / 1048576 ))MB)" >&2
  fi
fi

exit 0
HOOK
chmod +x "$CLAUDE_DIR/hooks/session-start.sh"
ok "hook: session-start.sh"

# ─── Status Line Script ───
cat > "$CLAUDE_DIR/statusline-command.sh" << 'STATUSLINE'
#!/usr/bin/env bash
# Claude Code statusLine command
# Mirrors PS1: user@host:dir (green/blue), plus model and context usage

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "?"')
model=$(echo "$input" | jq -r '.model.display_name // "?"')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

# Shorten home directory to ~
home="$HOME"
short_cwd="${cwd/#$home/~}"

# Build context indicator
if [ -n "$remaining" ]; then
  ctx_part=" [ctx:${remaining}%]"
else
  ctx_part=""
fi

# green=\033[01;32m  reset=\033[00m  blue=\033[01;34m  dim=\033[02m
printf '\033[01;32m%s@%s\033[00m:\033[01;34m%s\033[00m\033[02m  %s%s\033[00m' \
  "$(whoami)" "$(hostname -s)" "$short_cwd" "$model" "$ctx_part"
STATUSLINE
chmod +x "$CLAUDE_DIR/statusline-command.sh"
ok "statusline-command.sh"

# ─── .claudeignore Template ───

cat > "$CLAUDE_DIR/claudeignore-template" << 'IGNORE'
# Dependencies
node_modules/
.venv/
venv/
__pycache__/
*.pyc
.pnp.*

# Build output
dist/
build/
out/
.next/
.nuxt/
target/
coverage/
*.egg-info/

# Infrastructure state
.terraform/
*.tfstate
*.tfstate.backup
.terragrunt-cache/

# Version control internals
.git/

# IDE / OS
.idea/
.vscode/
*.swp
*.swo
.DS_Store
Thumbs.db

# Large / binary files
*.wasm
*.sqlite
*.db
*.zip
*.tar.gz
*.tgz

# Secrets (defense in depth)
.env
.env.*
*.pem
*.key
IGNORE
ok "template: claudeignore-template"

# ─── Conditional Rules ───

cat > "$CLAUDE_DIR/rules/python.md" << 'RULE'
---
paths: ["**/*.py", "**/pyproject.toml", "**/setup.py", "**/requirements*.txt"]
---
# Python Rules
- Use type hints on all function signatures
- Use `ruff check` and `ruff format` — never `black`, `flake8`, `isort`
- Use `uv` for package management — never `pip install`
- Prefer `pathlib.Path` over `os.path`
- Use `logging` module, never bare `print()` for diagnostics
- Docstrings on public functions (Google style)
- Target Python 3.10+ (use `match`, `X | Y` union types)
RULE
ok "rule: python.md"

cat > "$CLAUDE_DIR/rules/shell.md" << 'RULE'
---
paths: ["**/*.sh", "**/*.bash", "**/justfile"]
---
# Shell Rules
- Start scripts with `set -euo pipefail`
- Always quote variables: `"$var"` not `$var`
- Run `shellcheck` before executing any script
- Use `shfmt` for formatting
- Prefer `[[` over `[` for conditionals
- Use `command -v` not `which` for existence checks
- Arrays: `"${arr[@]}"` with quotes
RULE
ok "rule: shell.md"

cat > "$CLAUDE_DIR/rules/terraform.md" << 'RULE'
---
paths: ["**/*.tf", "**/*.tfvars", "**/*.hcl", "**/terraform/**"]
---
# Terraform Rules
- Always `terraform fmt` before commit
- Always `terraform plan` before `terraform apply` — never `-auto-approve` in production
- Run `tflint` and `trivy config .` before applying
- Use `infracost` to estimate cost impact
- One resource per file where practical
- Use modules for reusable infrastructure
- Secrets via `sops` or `infisical` — never plaintext in `.tf` files
- State files (`.tfstate`) must never be committed
RULE
ok "rule: terraform.md"

cat > "$CLAUDE_DIR/rules/docker.md" << 'RULE'
---
paths: ["**/Dockerfile*", "**/docker-compose*", "**/compose.yaml", "**/compose.yml"]
---
# Docker Rules
- Lint with `hadolint` before building
- Scan images with `trivy image` before pushing
- Generate SBOM with `syft` and scan with `grype`
- Use multi-stage builds to minimize image size
- Pin base image versions — no `:latest` in production
- Use `dive` to analyze layer efficiency
- Run as non-root user
- Verify signatures with `cosign verify` when pulling third-party images
RULE
ok "rule: docker.md"

cat > "$CLAUDE_DIR/rules/security.md" << 'RULE'
---
paths: ["**/*"]
---
# Security Rules (Always Active)
- Run `gitleaks detect` before any `git push`
- Never commit secrets, tokens, API keys, or credentials
- Never hardcode passwords — use env vars or secret managers (`sops`, `infisical`, `age`)
- Scan dependencies: `osv-scanner` or `grype dir:.`
- Review all `curl | bash` commands before execution
- Check TLS certs with `step certificate inspect` when debugging HTTPS issues
- Decode JWTs with `jwt decode <token>` — never trust unverified tokens
RULE
ok "rule: security.md"

cat > "$CLAUDE_DIR/rules/memory.md" << 'RULE'
---
paths: ["**/*"]
---
# Memory Discipline (Always Active)
- When you discover a non-obvious fix after debugging: write it to auto memory
- When user corrects you: immediately update or remove the wrong memory entry
- When a key architectural decision is made: record it in auto memory
- When user explicitly says "remember": use /remember or write directly to MEMORY.md
- NEVER write speculative or unverified conclusions to memory
- Check existing memory before writing — update, don't duplicate
RULE
ok "rule: memory.md"

# ─── /remember command ───
cat > "$CLAUDE_DIR/commands/remember.md" << 'CMD'
Save a piece of knowledge to persistent memory for use across sessions.

1. Find your auto memory directory (shown in system prompt as "persistent auto memory directory at ...")
2. Read `MEMORY.md` in that directory (create if missing)
3. Parse `$ARGUMENTS` — the user wants to remember this fact/preference/pattern
4. Check if a similar memory already exists — update it instead of duplicating
5. Categorize the memory:
   - **Preferences**: workflow, tool, style choices
   - **Patterns**: code patterns, naming conventions, architecture decisions
   - **Solutions**: fixes for recurring problems
   - **Project context**: key files, APIs, deployment targets
6. Append to the appropriate section in MEMORY.md
7. If MEMORY.md exceeds 150 lines, create topic-specific files and link from MEMORY.md
8. Confirm what was saved and where
CMD
ok "command: /remember"

# obra/superpowers (multiple useful skills)
if [ ! -d ~/.claude/skills/tdd ]; then
  git clone --depth 1 https://github.com/obra/superpowers.git /tmp/superpowers 2>/dev/null || true
  if [ -d /tmp/superpowers/skills ]; then
    cp -r /tmp/superpowers/skills/test-driven-development ~/.claude/skills/tdd 2>/dev/null || true
    cp -r /tmp/superpowers/skills/systematic-debugging ~/.claude/skills/systematic-debugging 2>/dev/null || true
    cp -r /tmp/superpowers/skills/brainstorming ~/.claude/skills/brainstorming 2>/dev/null || true
    cp -r /tmp/superpowers/skills/verification-before-completion ~/.claude/skills/verification-before-completion 2>/dev/null || true
    cp -r /tmp/superpowers/skills/writing-plans ~/.claude/skills/writing-plans 2>/dev/null || true
    ok "superpowers skills"
  else
    warn "superpowers clone failed"
  fi
  rm -rf /tmp/superpowers
else
  ok "superpowers skills (exist)"
fi

# Security skills
if [ ! -d ~/.claude/skills/vibesec ]; then
  git clone --depth 1 https://github.com/BehiSecc/VibeSec-Skill.git ~/.claude/skills/vibesec 2>/dev/null && ok "vibesec" || warn "vibesec"
else ok "vibesec (exists)"; fi

# Trail of Bits — selective install (modern-python only, not the full 60-skill repo)
# Full clone was 71K lines / 60 SKILL.md files — most never triggered (blockchain, fuzzing, etc.)
# Individual plugins can be installed on-demand via: claude plugin marketplace add trailofbits/skills
if [ ! -d ~/.claude/skills/trailofbits-modern-python ]; then
  git clone --depth 1 https://github.com/trailofbits/skills.git /tmp/trailofbits-skills 2>/dev/null
  if [ -d /tmp/trailofbits-skills/plugins/modern-python ]; then
    cp -r /tmp/trailofbits-skills/plugins/modern-python ~/.claude/skills/trailofbits-modern-python 2>/dev/null && ok "trailofbits: modern-python" || warn "trailofbits: modern-python"
  else
    warn "trailofbits: modern-python not found in repo"
  fi
  rm -rf /tmp/trailofbits-skills
else ok "trailofbits: modern-python (exists)"; fi

# Cleanup: remove full trailofbits/hashicorp clones from previous installs (token bloat)
# These dumped 60+14 SKILL.md files into context at startup (~81K lines)
if [ -d ~/.claude/skills/trailofbits ]; then
  rm -rf ~/.claude/skills/trailofbits
  ok "removed old trailofbits full clone (60 skills → 1 selective)"
fi
if [ -d ~/.claude/skills/hashicorp ]; then
  rm -rf ~/.claude/skills/hashicorp
  ok "removed old hashicorp full clone (14 skills → covered by infra-deploy)"
fi

# NotebookLM skill
if [ ! -d ~/.claude/skills/nlm-cli ]; then
  git clone --depth 1 https://github.com/jacob-bd/notebooklm-cli.git /tmp/nlm-cli 2>/dev/null
  cp -r /tmp/nlm-cli/nlm-cli-skill ~/.claude/skills/nlm-cli 2>/dev/null && ok "notebooklm skill" || warn "notebooklm skill"
  rm -rf /tmp/nlm-cli
else ok "notebooklm skill (exists)"; fi

# ─── Commands ───
cat > "$CLAUDE_DIR/commands/catchup.md" << 'CMD'
Read git branch, last 10 commits, `git status`, and if they exist: `_scratchpad.md` and `_handoff.md`.
Also check `~/.claude/memory/handoff.md` — this is auto-generated by session hooks and contains structured state from the last session. Prioritize it if present.
Also check your auto memory directory for `MEMORY.md` — it contains persistent knowledge from previous sessions.
Summarize: what branch, what's changed, any pending work, and what you remember. Then ask what to work on.
CMD
ok "command: /catchup"

cat > "$CLAUDE_DIR/commands/handoff.md" << 'CMD'
Create/update `_handoff.md` with: current task + branch, what's completed, what's in progress, blockers, next steps, test status, key decisions. Write it so a fresh session can continue with zero context. Then commit it.
CMD
ok "command: /handoff"

cat > "$CLAUDE_DIR/commands/ship.md" << 'CMD'
Run full pre-push pipeline:
1. Lint modified files (shellcheck for .sh, ruff for .py, hadolint for Dockerfile)
2. Run relevant tests
3. `gitleaks detect --verbose`
4. `git diff --stat` — verify all changes are intentional
5. Commit with conventional message if needed
6. `git push -u origin HEAD`
7. Ask if I want a PR, if yes: `gh pr create --fill`
Stop on any failure. $ARGUMENTS
CMD
ok "command: /ship"

cat > "$CLAUDE_DIR/commands/standup.md" << 'CMD'
Generate standup from `git log --oneline --since="yesterday"`, `git diff --stat main...HEAD`, and any `_scratchpad.md`/`_handoff.md`. Format: Yesterday, Today, Blockers. Keep brief. $ARGUMENTS
CMD
ok "command: /standup"

cat > "$CLAUDE_DIR/commands/scan.md" << 'CMD'
Run security scan on current project:
1. `gitleaks detect --verbose` — secrets
2. `trivy fs --severity HIGH,CRITICAL .` — filesystem vulns
3. If lockfile exists: `osv-scanner --lockfile=<detected lockfile>`
4. If Dockerfile exists: `hadolint Dockerfile`
5. If .tf files exist: `tflint` and `trivy config .`
Summarize findings by severity. Suggest fixes for critical/high. $ARGUMENTS
CMD
ok "command: /scan"

cat > "$CLAUDE_DIR/commands/review.md" << 'CMD'
Review current branch against main using the `reviewer` subagent:
1. `git diff main...HEAD` — review every changed file
2. Check: logic errors, security issues, style violations, missing tests, error handling
3. For each issue: file + line, severity (critical/warning/suggestion), what's wrong, how to fix
4. End with: APPROVE, REQUEST CHANGES, or NEEDS DISCUSSION
$ARGUMENTS
CMD
ok "command: /review"

cat > "$CLAUDE_DIR/commands/tools.md" << 'CMD'
List all installed CLI tools by package manager:
1. `uv tool list` — Python tools
2. `ls ~/.cargo/bin/ | sort` — Rust tools
3. `ls ~/go/bin/ | sort` — Go tools
4. `bun pm ls -g` — JS tools
Group by domain (search, data, git, security, infra, etc). If $ARGUMENTS provided, filter to matching keyword.
CMD
ok "command: /tools"

cat > "$CLAUDE_DIR/commands/workspace-init.md" << 'CMD'
Initialize workspace for the current project:
1. Detect project type from files (package.json, pyproject.toml, Cargo.toml, go.mod, etc.)
2. Create `_workspace.json` with detected commands (dev, build, test, lint, deploy)
3. If no `.envrc` exists, create one with `direnv` template for the project type
4. Run `direnv allow` if `.envrc` was created
5. Show the user the generated config and ask for adjustments
CMD
ok "command: /workspace-init"

cat > "$CLAUDE_DIR/commands/context.md" << 'CMD'
Pack the current repo into an AI-optimized context file using repomix:
1. Run `repomix` in the current directory (respects .gitignore)
2. Report: total files, token count, output path
3. If tokens > 100K, suggest: `repomix --include "src/**"` to narrow scope
4. If $ARGUMENTS provided, pass as `repomix --include "$ARGUMENTS"`
CMD
ok "command: /context"

# ─── GitHub Actions Template ───
cat > "$CLAUDE_DIR/templates/claude-code-action.yml" << 'TEMPLATE'
# Claude Code GitHub Action — auto code review and issue-to-PR
# Copy to .github/workflows/claude.yml and set ANTHROPIC_API_KEY secret
name: Claude Code
on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  issues:
    types: [opened, assigned]
  pull_request:
    types: [opened, synchronize]

jobs:
  claude:
    if: |
      (github.event_name == 'issue_comment' && contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'pull_request_review_comment' && contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'issues' && contains(github.event.issue.labels.*.name, 'claude')) ||
      (github.event_name == 'pull_request')
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
      issues: write
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          allowed_tools: "Read,Edit,Bash(ruff*),Bash(pytest*),Bash(shellcheck*),Bash(git diff*),Bash(git log*)"
TEMPLATE
ok "template: claude-code-action.yml"

cat > "$CLAUDE_DIR/commands/gh-action.md" << 'CMD'
Set up Claude Code GitHub Action for the current project:
1. Copy `~/.claude/templates/claude-code-action.yml` to `.github/workflows/claude.yml`
2. Tell the user to add `ANTHROPIC_API_KEY` as a GitHub secret: `gh secret set ANTHROPIC_API_KEY`
3. Explain: `@claude` in PR/issue comments triggers the agent, PRs get auto-reviewed
CMD
ok "command: /gh-action"

# ─── Agents ───
cat > "$CLAUDE_DIR/agents/researcher.md" << 'AGENT'
---
name: researcher
description: Read-only codebase explorer. Use for investigating code patterns, finding files, understanding architecture.
model: haiku
tools:
  - Read
  - Glob
  - Grep
  - Bash
---
You are a read-only research agent. Explore the codebase and report findings.
NEVER modify files. You CAN run: `rg`, `fd`, `bat`, `scc`, `git log`, `git diff`, `cat`, `head`, `tail`, `wc`, any `--help`.
Report: what you searched, what you found (paths + lines), patterns observed, recommendations.
AGENT
ok "agent: researcher"

cat > "$CLAUDE_DIR/agents/planner.md" << 'AGENT'
---
name: planner
description: Architecture planning agent. Explores codebase and produces implementation plans before code is written.
model: opus
tools:
  - Read
  - Glob
  - Grep
  - Bash
---
You are a planning agent. Analyze requirements, produce implementation plans. NEVER write code.
Process: understand requirement → explore with rg/fd/bat → identify affected files → check existing solutions → design approach.
Output: requirement summary, relevant files, step-by-step plan with paths, testing strategy, risks, complexity estimate.
AGENT
ok "agent: planner"

cat > "$CLAUDE_DIR/agents/reviewer.md" << 'AGENT'
---
name: reviewer
description: Code review agent. Reviews diffs, checks for bugs, security issues, style violations, and provides actionable feedback.
model: sonnet
tools:
  - Read
  - Glob
  - Grep
  - Bash
---

You are a code review agent. Review the changes in the current branch against main.

## Review Process
1. Run `git diff main...HEAD` to see all changes
2. For each changed file, review for:

### Correctness
- Logic errors, off-by-one, null/undefined handling
- Edge cases not covered
- Error handling gaps

### Security
- Hardcoded secrets or credentials
- SQL injection, XSS, command injection risks
- Insecure defaults

### Style
- Follows project conventions from CLAUDE.md
- Consistent naming, formatting
- Meaningful variable/function names

### Performance
- Unnecessary loops or database calls
- Missing caching opportunities
- Memory leaks

### Testing
- Are new code paths tested?
- Are edge cases covered?
- Do existing tests still pass?

## Output Format
For each issue found:
- **File**: path and line number
- **Severity**: critical / warning / suggestion
- **Issue**: what's wrong
- **Fix**: how to fix it

End with an overall assessment: APPROVE, REQUEST CHANGES, or NEEDS DISCUSSION.
AGENT
ok "agent: reviewer"

# CLIProxyAPI — proxy server for AI coding tools (clone, not a CLI install)
if [ ! -d ~/tools/CLIProxyAPI ]; then
  mkdir -p ~/tools
  git clone --depth 1 https://github.com/router-for-me/CLIProxyAPI.git ~/tools/CLIProxyAPI 2>/dev/null && ok "CLIProxyAPI (cloned to ~/tools/)" || warn "CLIProxyAPI"
else ok "CLIProxyAPI (exists)"; fi

# ─── Phase 5b — Claude Code Plugins ───
section "Phase 5b — Claude Code Plugins"
echo "  Installing official and community plugins..."

if ! command -v claude &>/dev/null; then
  warn "Claude CLI not found — skipping plugins"
elif ! claude auth status &>/dev/null 2>&1; then
  warn "Claude not authenticated — skipping plugins (run 'claude auth login' first)"
  echo "    After auth, run:"
  echo "    claude plugin marketplace add anthropic/claude-plugins-official"
  echo "    claude plugin install hookify"
  echo "    claude plugin install code-review"
else
  # Register official marketplace if not already registered
  claude plugin marketplace add anthropic/claude-plugins-official 2>/dev/null \
    && ok "official marketplace" || ok "official marketplace (exists)"

  # Install plugins from official marketplace
  claude plugin install hookify 2>/dev/null && ok "hookify" || warn "hookify"
  claude plugin install code-review 2>/dev/null && ok "code-review" || warn "code-review"
  # skill-creator removed — adds 6+ skills to context, only needed when authoring skills
  # Install on-demand if needed: claude plugin install skill-creator
fi


section "Phase 6/6 — Shell Integration"

# bash-preexec is required for atuin to record history
if [[ ! -f ~/.bash-preexec.sh ]]; then
  curl -sL https://raw.githubusercontent.com/rcaloras/bash-preexec/master/bash-preexec.sh -o ~/.bash-preexec.sh
  ok "bash-preexec downloaded"
else
  ok "bash-preexec already present"
fi

# Build the shell config block
SHELL_BLOCK='
# ══════ Titan CLI Arsenal ══════
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.cargo/bin:$HOME/go/bin:/usr/local/go/bin:$PATH"
eval "$(zoxide init bash)"
eval "$(starship init bash)"
eval "$(direnv hook bash)"
[[ -f ~/.bash-preexec.sh ]] && source ~/.bash-preexec.sh
eval "$(atuin init bash)"
eval "$(mise activate bash)"
[ -f ~/.fzf.bash ] && source ~/.fzf.bash
export GIT_PAGER="delta"
command -v pueued &>/dev/null && pueued -d 2>/dev/null  # task queue daemon
# ══════════════════════════════'

if ! grep -q "Titan CLI Arsenal" ~/.bashrc 2>/dev/null; then
  echo "$SHELL_BLOCK" >> ~/.bashrc
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


section "Setup Complete"

echo -e "
  ${GREEN}Everything is installed and configured.${NC}

  ${CYAN}What's running:${NC}
    Package managers: uv, bun, cargo, go, mise
    CLI tools:        ~100 across all managers
    Claude Code:      native binary (auto-updates)
    Config:           ~/.claude/ (skills, hooks, commands, agents)

  ${CYAN}Context budget (startup):${NC}
    CLAUDE.md:    ~1200 tokens (loaded every session)
    Skills:       ~2-5K tokens (descriptions at startup, full content on trigger)
    Rules:        ~500 tokens  (6 conditional rules)
    Commands:     0 tokens     (loaded on /command)
    Agents:       ~200 tokens  (descriptions only)
    CLI --help:   0 tokens     (lazy-loaded at runtime)
    Total:        ~2-7K tokens of 200K context window

  ${CYAN}Next steps:${NC}
    source ~/.bashrc
    claude                    # authenticate
    claude doctor             # verify health
    cd <your-project>
    /tools                    # see all installed tools
    /catchup                  # orient to the project

  ${CYAN}Package manager rules:${NC}
    Python CLIs → uv tool install <pkg>
    JS CLIs     → bun install -g <pkg>
    Rust CLIs   → cargo install <crate>
    Go CLIs     → go install <path>@latest
    ${RED}NEVER USE   → pip install, npm install -g, sudo pip${NC}
"