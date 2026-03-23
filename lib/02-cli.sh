# ─── CLI Options ───
ENGINEER_NAME=""
INSTALL_MODE=""
TAILSCALE_KEY=""
_TAILSCALE_FAILED=false
CLAUDE_USER=""
TS_HOSTNAME=""
CC_VERSION=""
CC_NO_AUTOUPDATE=""
CC_ASKED=false
DRY_RUN=false
VERBOSE=false
CCFLARE_SKIP=false
CCFLARE_PORT=8080
CCFLARE_HOST="127.0.0.1"
CCFLARE_PROXY_PORT=8081 # billing proxy port (Bun-based; Docker containers reach via host.docker.internal:8081)
LETTA_SKIP=false
LETTA_PORT=8283
LETTA_PASSWORD=""
OLLAMA_SKIP=false
LETTA_CTRL_SKIP=false
LETTA_CTRL_PORT=8284
COZEMPIC_SKIP=false
VEXP_SKIP=false
CLAUDECODEUI_SKIP=false
CLAUDECODEUI_PORT=3001
N8N_SKIP=false
FORCE_UPDATES=false
MINIMAL=false

usage() {
  cat <<USAGE
Usage: $(basename "$0") [OPTIONS]

Options:
  --name NAME              Your name for Claude config (default: \$(whoami))
  --mode desktop|vps       Installation profile (prompted interactively if omitted)
  --tailscale-key KEY      Tailscale auth key (required for VPS mode, prompted if omitted)
  --claude-user USER       Non-root user for Claude Code in VPS mode (created if absent, prompted if omitted)
  --cc-version VERSION     Install specific Claude Code version (e.g. 2.1.58; default: latest)
  --no-autoupdate          Disable Claude Code auto-updater (adds DISABLE_AUTOUPDATER=1 to settings.json)
  --dry-run                Print what would be done without making changes
  -v, --verbose            Show all subprocess output (default: quiet, logs to file)

  better-ccflare proxy options:
  --ccflare-skip           Skip better-ccflare install entirely
  --ccflare-port PORT      Proxy port (default: 8080)
  --ccflare-host HOST      Bind address (default: 127.0.0.1)

  letta / subconscious options:
  --letta-skip             Skip Letta server + claude-subconscious plugin
  --letta-port PORT        Letta server port (default: 8283)
  --letta-password PASS    Letta server password (auto-generated if omitted)
  --no-ollama              Skip Ollama install (use OPENAI_API_KEY for embeddings instead)
  --letta-ctrl-skip        Skip LettaCtrl GUI (default: install if Letta is installed)
  --letta-ctrl-port PORT   LettaCtrl server port (default: 8284)
  --no-cozempic            Skip cozempic install (context bloat cleaner)
  --no-vexp                Skip vexp-cli install (context engine)
  --claudecodeui-skip      Skip Claude Code UI web interface
  --claudecodeui-port PORT Claude Code UI port (default: 3001)
  --n8n-skip               Skip n8n workflow automation install

  --force-updates          Force upgrade all tools (uv, bun, cargo, go, binaries)
  --version                Show script version
  -h, --help               Show this help message

Examples:
  $(basename "$0") --name "Alice" --mode desktop
  $(basename "$0") --name "Alice" --mode vps
  $(basename "$0") --name "Alice" --ccflare-skip
  $(basename "$0") --dry-run
USAGE
  exit 0
}

_ORIG_ARGS=("$@")

while [[ $# -gt 0 ]]; do
  case $1 in
    --name)
      [[ $# -ge 2 ]] || {
        fail "--name requires a value"
        usage
      }
      ENGINEER_NAME="$2"
      shift 2
      ;;
    --mode)
      [[ $# -ge 2 ]] || {
        fail "--mode requires a value (desktop|vps)"
        usage
      }
      [[ "$2" == "desktop" || "$2" == "vps" ]] || {
        fail "--mode must be 'desktop' or 'vps'"
        usage
      }
      INSTALL_MODE="$2"
      shift 2
      ;;
    --tailscale-key)
      [[ $# -ge 2 ]] || {
        fail "--tailscale-key requires a value"
        usage
      }
      TAILSCALE_KEY="$2"
      shift 2
      ;;
    --claude-user)
      [[ $# -ge 2 ]] || {
        fail "--claude-user requires a value"
        usage
      }
      CLAUDE_USER="$2"
      shift 2
      ;;
    --cc-version)
      [[ $# -ge 2 ]] || {
        fail "--cc-version requires a value"
        usage
      }
      CC_VERSION="$2"
      shift 2
      ;;
    --no-autoupdate)
      CC_NO_AUTOUPDATE="true"
      shift
      ;;
    --cc-asked)
      CC_ASKED=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -v | --verbose)
      VERBOSE=true
      shift
      ;;
    --ccflare-skip)
      CCFLARE_SKIP=true
      shift
      ;;
    --ccflare-port)
      [[ $# -ge 2 ]] || {
        fail "--ccflare-port requires a value"
        usage
      }
      CCFLARE_PORT="$2"
      shift 2
      ;;
    --ccflare-host)
      [[ $# -ge 2 ]] || {
        fail "--ccflare-host requires a value"
        usage
      }
      CCFLARE_HOST="$2"
      shift 2
      ;;
    --letta-skip)
      LETTA_SKIP=true
      shift
      ;;
    --letta-port)
      [[ $# -ge 2 ]] || {
        fail "--letta-port requires a value"
        usage
      }
      LETTA_PORT="$2"
      shift 2
      ;;
    --letta-password)
      [[ $# -ge 2 ]] || {
        fail "--letta-password requires a value"
        usage
      }
      LETTA_PASSWORD="$2"
      shift 2
      ;;
    --no-ollama)
      OLLAMA_SKIP=true
      shift
      ;;
    --letta-ctrl-skip)
      LETTA_CTRL_SKIP=true
      shift
      ;;
    --letta-ctrl-port)
      [[ $# -ge 2 ]] || {
        fail "--letta-ctrl-port requires a value"
        usage
      }
      LETTA_CTRL_PORT="$2"
      shift 2
      ;;
    --no-cozempic)
      COZEMPIC_SKIP=true
      shift
      ;;
    --no-vexp)
      VEXP_SKIP=true
      shift
      ;;
    --claudecodeui-skip)
      CLAUDECODEUI_SKIP=true
      shift
      ;;
    --n8n-skip)
      N8N_SKIP=true
      shift
      ;;
    --claudecodeui-port)
      [[ $# -ge 2 ]] || {
        fail "--claudecodeui-port requires a value"
        usage
      }
      CLAUDECODEUI_PORT="$2"
      shift 2
      ;;
    --force-updates)
      FORCE_UPDATES=true
      shift
      ;;
    --fresh)
      phase_reset
      shift
      ;;
    --minimal)
      MINIMAL=true
      LETTA_SKIP=true
      OLLAMA_SKIP=true
      COZEMPIC_SKIP=true
      LETTA_CTRL_SKIP=true
      VEXP_SKIP=true
      CLAUDECODEUI_SKIP=true
      N8N_SKIP=true
      shift
      ;;
    --secrets-file)
      [[ $# -ge 2 ]] || {
        fail "--secrets-file requires a file path"
        usage
      }
      if [[ -f "$2" ]]; then
        # Read key=value pairs (TAILSCALE_KEY, LETTA_PASSWORD)
        while IFS='=' read -r key value; do
          [[ -z "$key" || "$key" == \#* ]] && continue
          key=$(echo "$key" | xargs)
          value=$(echo "$value" | xargs)
          case "$key" in
            TAILSCALE_KEY) TAILSCALE_KEY="$value" ;;
            LETTA_PASSWORD) LETTA_PASSWORD="$value" ;;
            *) warn "secrets-file: unknown key '$key' (ignored)" ;;
          esac
        done <"$2"
        ok "Secrets loaded from $2"
      else
        fail "Secrets file not found: $2"
        exit 1
      fi
      shift 2
      ;;
    --version)
      echo "titan-setup ${SCRIPT_VERSION}"
      exit 0
      ;;
    -h | --help) usage ;;
    *)
      fail "Unknown option: $1"
      usage
      ;;
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

# ─── Installation profile ───
if [[ -z "$INSTALL_MODE" ]]; then
  echo -e "\n${CYAN}Select installation profile:${NC}"
  echo "  1) Desktop  — full workstation setup"
  echo "  2) VPS      — workstation + server extras"
  read -rp "  Choice [1/2]: " _mode_choice || true
  case "$_mode_choice" in
    1) INSTALL_MODE="desktop" ;;
    2) INSTALL_MODE="vps" ;;
    *)
      fail "Invalid choice. Run with --mode desktop or --mode vps"
      exit 1
      ;;
  esac
fi
echo -e "  Profile: ${GREEN}${INSTALL_MODE}${NC}\n"

# ─── Desktop mode: fix HOME when running as root via sudo ───
# sudo changes HOME to /root, but services/configs must go to the target user's home.
# VPS mode handles this via re-exec (lib/03-vps-reexec.sh). Desktop mode needs this fix.
if [[ "$INSTALL_MODE" == "desktop" && "$(id -u)" == "0" ]]; then
  _TARGET_USER="${CLAUDE_USER:-${SUDO_USER:-}}"
  if [[ -n "$_TARGET_USER" && "$_TARGET_USER" != "root" ]]; then
    _TARGET_HOME=$(getent passwd "$_TARGET_USER" | cut -d: -f6)
    if [[ -n "$_TARGET_HOME" && -d "$_TARGET_HOME" ]]; then
      export HOME="$_TARGET_HOME"
      # Add user's tool paths so mise/cargo/go/bun/uv binaries are found
      export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/go/bin:$PATH"
      echo -e "  ${GREEN}✓${NC} HOME → $_TARGET_HOME (running as root, targeting $_TARGET_USER)"
    fi
  fi
fi

# ─── Claude Code version + autoupdate ───
if [[ -z "$CC_VERSION" ]] && ! $CC_ASKED; then
  read -rp "  Claude Code version to install (blank = latest): " CC_VERSION || true
fi
if [[ -z "$CC_NO_AUTOUPDATE" ]] && ! $CC_ASKED; then
  read -rp "  Disable Claude Code auto-updates? [y/N]: " _au_ans || true
  case "${_au_ans,,}" in
    y | yes) CC_NO_AUTOUPDATE="true" ;;
    *) CC_NO_AUTOUPDATE="" ;;
  esac
fi
[[ -n "$CC_VERSION" ]] && echo -e "  CC version:    ${GREEN}${CC_VERSION}${NC}"
[[ "$CC_NO_AUTOUPDATE" == "true" ]] && echo -e "  Auto-updates:  ${YELLOW}disabled${NC}" || echo -e "  Auto-updates:  ${GREEN}enabled${NC}"

# ─── VPS: create Claude user and re-exec as them ───
