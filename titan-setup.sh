#!/usr/bin/env bash
set -euo pipefail

# ─── Self-materialize when invoked via process substitution ─────────────────
# bash <(curl ...) gives $0=/dev/fd/63 (a pipe). exec sudo -u USER bash "$0"
# fails because the new process has no access to that fd. Re-download to a
# real temp file and re-exec with all original args preserved.
if [[ ! -f "$0" ]]; then
  _SELF=$(mktemp /tmp/titan-setup-XXXXXX.sh)
  curl -fsSL https://raw.githubusercontent.com/SutanuNandigrami/claude-titan-setup/main/titan-setup.sh \
    -o "$_SELF"
  chmod a+rx "$_SELF"
  # Use bash+exit instead of exec to keep the process-substitution pipe open.
  # exec would close the pipe fd immediately, causing the original curl to fail
  # with "curl: (23) Failure writing output to destination".
  bash "$_SELF" "$@"
  _rc=$?
  rm -f "$_SELF"
  exit "$_rc"
fi
# ────────────────────────────────────────────────────────────────────────────

# ╔══════════════════════════════════════════════════════════════════╗
# ║  TITAN SETUP — Single Source of Truth                           ║
# ║  Fresh Ubuntu → fully armed Claude Code workstation             ║
# ║                                                                  ║
# ║  What this does:                                                 ║
# ║   1. System prerequisites + Linux tuning                        ║
# ║   2. Package managers: uv, bun, cargo, go, mise                ║
# ║   3. 150+ CLI tools (zero pip, zero npm -g)                    ║
# ║   4. Claude Code CLI (native binary)                            ║
# ║   5. ~/.claude/ global config (skills, hooks, commands, agents) ║
# ║   6. Shell integration + verification                           ║
# ║                                                                  ║
# ║  Safe to re-run: skips already-installed components             ║
# ║                                                                  ║
# ║  Security note: This script uses curl|bash for several official  ║
# ║  installers (rustup, uv, bun, mise, docker, helm, etc). Review  ║
# ║  URLs before running. Claude Desktop (desktop mode only) installs ║
# ║  from patrickjaja.github.io via sudo.                            ║
# ╚══════════════════════════════════════════════════════════════════╝

SCRIPT_VERSION="v3.19"
# ─── Phase checkpoint system for resume capability ───
_PROGRESS_DIR="$HOME/.titan-progress"
mkdir -p "$_PROGRESS_DIR" 2>/dev/null || true

phase_done() {
  [[ -f "$_PROGRESS_DIR/$1" ]] && return 0 || return 1
}
phase_mark() {
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$_PROGRESS_DIR/$1"
}
phase_reset() {
  rm -rf "$_PROGRESS_DIR"
  mkdir -p "$_PROGRESS_DIR"
}

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

section() { echo -e "\n${CYAN}═══ $1 ═══${NC}\n"; }
ok() { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }

# Cached apt-get update — runs once per session, skips on subsequent calls
# Pass --force to re-run after adding new apt repos (resets the cache)
_APT_UPDATED=false
apt_update() {
  if [[ "${1:-}" == "--force" ]]; then
    _APT_UPDATED=false
  fi
  if ! $_APT_UPDATED; then
    run_q sudo apt-get update -qq && _APT_UPDATED=true
  fi
}

# Port pre-flight check — warn if a port is already in use
check_port() {
  local port="$1" service="$2"
  if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
    local owner
    owner=$(ss -tlnp 2>/dev/null | grep ":${port} " | head -1 | grep -oP 'users:\(\("\K[^"]+' || echo "unknown")
    warn "${service}: port ${port} already in use by ${owner}"
    return 1
  fi
  return 0
}
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
SEMGREP_TOKEN=""
SEMGREP_SKIP=false
LETTA_SKIP=false
LETTA_PORT=8283
LETTA_PASSWORD=""
OLLAMA_SKIP=false
LETTA_CTRL_SKIP=false
LETTA_CTRL_PORT=8284
COZEMPIC_SKIP=false
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

  semgrep options:
  --semgrep-token TOKEN    Semgrep App Token (enables semgrep plugin in Claude Code)
  --no-semgrep             Skip semgrep plugin entirely (no token needed)

  letta / subconscious options:
  --letta-skip             Skip Letta server + claude-subconscious plugin
  --letta-port PORT        Letta server port (default: 8283)
  --letta-password PASS    Letta server password (auto-generated if omitted)
  --no-ollama              Skip Ollama install (use OPENAI_API_KEY for embeddings instead)
  --letta-ctrl-skip        Skip LettaCtrl GUI (default: install if Letta is installed)
  --letta-ctrl-port PORT   LettaCtrl server port (default: 8284)
  --no-cozempic            Skip cozempic install (context bloat cleaner)

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
    --semgrep-token)
      [[ $# -ge 2 ]] || {
        fail "--semgrep-token requires a value"
        usage
      }
      SEMGREP_TOKEN="$2"
      shift 2
      ;;
    --no-semgrep)
      SEMGREP_SKIP=true
      shift
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
      shift
      ;;
    --secrets-file)
      [[ $# -ge 2 ]] || {
        fail "--secrets-file requires a file path"
        usage
      }
      if [[ -f "$2" ]]; then
        # Read key=value pairs (TAILSCALE_KEY, SEMGREP_TOKEN, LETTA_PASSWORD)
        while IFS='=' read -r key value; do
          [[ -z "$key" || "$key" == \#* ]] && continue
          key=$(echo "$key" | xargs)
          value=$(echo "$value" | xargs)
          case "$key" in
            TAILSCALE_KEY) TAILSCALE_KEY="$value" ;;
            SEMGREP_TOKEN) SEMGREP_TOKEN="$value" ;;
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

# ─── Semgrep token (interactive prompt if not set via flag) ───
if ! $SEMGREP_SKIP && [[ -z "$SEMGREP_TOKEN" ]]; then
  echo -e "\n  ${CYAN}Semgrep (static analysis in Claude Code):${NC}"
  echo "  Get a free token at semgrep.dev → Settings → Tokens"
  read -rp "  Semgrep App Token (Enter to skip): " SEMGREP_TOKEN || true
  [[ -z "$SEMGREP_TOKEN" ]] && SEMGREP_SKIP=true
fi
if $SEMGREP_SKIP; then
  echo -e "  Semgrep:       ${YELLOW}skipped${NC}"
elif [[ -n "$SEMGREP_TOKEN" ]]; then
  echo -e "  Semgrep:       ${GREEN}enabled${NC}"
fi
echo ""

# ─── VPS: create Claude user and re-exec as them ───
if [[ "$INSTALL_MODE" == "vps" ]]; then
  if [[ -z "$CLAUDE_USER" ]]; then
    read -rp "  Username for Claude Code (created if absent): " CLAUDE_USER || true
    [[ -z "$CLAUDE_USER" ]] && {
      fail "Username required for VPS mode"
      exit 1
    }
  fi

  if [[ "$(whoami)" != "$CLAUDE_USER" ]]; then
    if ! id "$CLAUDE_USER" &>/dev/null; then
      sudo useradd -m -s /bin/bash "$CLAUDE_USER"
      echo -e "  ${GREEN}✓${NC} Created user: $CLAUDE_USER"
    fi
    echo "$CLAUDE_USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/"$CLAUDE_USER" >/dev/null
    sudo chmod 440 /etc/sudoers.d/"$CLAUDE_USER"
    echo -e "  ${GREEN}✓${NC} Passwordless sudo granted to $CLAUDE_USER"
    echo -e "  Switching to $CLAUDE_USER and re-running...\n"
    _VPS_REEXEC_ARGS=(
      --mode vps
      --claude-user "$CLAUDE_USER"
      --tailscale-key "$TAILSCALE_KEY"
      --name "$ENGINEER_NAME"
      --cc-asked
    )
    [[ -n "$CC_VERSION" ]] && _VPS_REEXEC_ARGS+=(--cc-version "$CC_VERSION")
    [[ "$CC_NO_AUTOUPDATE" == "true" ]] && _VPS_REEXEC_ARGS+=(--no-autoupdate)
    $VERBOSE && _VPS_REEXEC_ARGS+=(--verbose)
    $CCFLARE_SKIP && _VPS_REEXEC_ARGS+=(--ccflare-skip)
    _VPS_REEXEC_ARGS+=(--ccflare-port "$CCFLARE_PORT" --ccflare-host "$CCFLARE_HOST")
    [[ -n "$SEMGREP_TOKEN" ]] && _VPS_REEXEC_ARGS+=(--semgrep-token "$SEMGREP_TOKEN")
    $SEMGREP_SKIP && _VPS_REEXEC_ARGS+=(--no-semgrep)
    $LETTA_SKIP && _VPS_REEXEC_ARGS+=(--letta-skip)
    _VPS_REEXEC_ARGS+=(--letta-port "$LETTA_PORT")
    [[ -n "$LETTA_PASSWORD" ]] && _VPS_REEXEC_ARGS+=(--letta-password "$LETTA_PASSWORD")
    $OLLAMA_SKIP && _VPS_REEXEC_ARGS+=(--no-ollama)
    $LETTA_CTRL_SKIP && _VPS_REEXEC_ARGS+=(--letta-ctrl-skip)
    _VPS_REEXEC_ARGS+=(--letta-ctrl-port "$LETTA_CTRL_PORT")
    $COZEMPIC_SKIP && _VPS_REEXEC_ARGS+=(--no-cozempic)
    $FORCE_UPDATES && _VPS_REEXEC_ARGS+=(--force-updates)
    # Propagate tmux context through the user-switch: exec sudo strips $TMUX,
    # so the re-executed script would see itself as "not in tmux" and try to
    # launch another session, causing the nested-tmux / duplicate-session error.
    _VPS_TMUX_ENV=()
    [[ -n "${TMUX:-}" || "${TITAN_TMUX:-}" == "1" ]] && _VPS_TMUX_ENV+=(TITAN_TMUX=1)
    # Propagate local repo override so the re-executed script uses the same REPO_FILES
    [[ -n "${TITAN_REPO_FILES:-}" ]] && _VPS_TMUX_ENV+=("TITAN_REPO_FILES=${TITAN_REPO_FILES}")
    # Copy script to /tmp so the non-root user can read it ($0 may be in /root)
    _REEXEC_SCRIPT="/tmp/titan-setup-reexec.sh"
    cp "$0" "$_REEXEC_SCRIPT"
    chmod 644 "$_REEXEC_SCRIPT"
    exec sudo -u "$CLAUDE_USER" "${_VPS_TMUX_ENV[@]+"${_VPS_TMUX_ENV[@]}"}" bash "$_REEXEC_SCRIPT" "${_VPS_REEXEC_ARGS[@]}"
  fi
fi

# ─── Ensure we are in a readable working directory ───
# exec sudo -u USER inherits root's CWD (/root) which USER may not be able to stat.
# Go, some build tools, and mktemp -d with relative paths all call getcwd() and fail.
cd "$HOME" || cd /tmp

# ─── Ensure systemd user session works ───
# exec sudo -u strips XDG_RUNTIME_DIR; without it all systemctl --user calls fail silently.
# Also enable linger so user services survive logout and start at boot.
if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi
if [[ "$INSTALL_MODE" == "vps" ]] && command -v loginctl &>/dev/null; then
  loginctl enable-linger "$USER" 2>/dev/null || sudo loginctl enable-linger "$USER" 2>/dev/null || true
fi

# ─── Disconnect resilience: re-exec inside tmux if not already there ───
# Install takes 30-60 min; SSH drops must not kill it.
if [[ -z "${TMUX:-}" ]] && [[ "${TITAN_TMUX:-}" != "1" ]]; then
  if ! command -v tmux &>/dev/null; then
    sudo apt-get install -y -qq tmux 2>/dev/null || true
  fi
  if command -v tmux &>/dev/null; then
    _TMUX_LOG="/tmp/titan-setup-$(date +%Y%m%d-%H%M%S).log"
    _TMUX_WRAPPER=$(mktemp /tmp/titan-tmux-XXXXXX.sh)
    {
      printf 'TITAN_TMUX=1 bash %q' "$0"
      if [[ ${#_ORIG_ARGS[@]} -gt 0 ]]; then
        printf ' %q' "${_ORIG_ARGS[@]}"
      fi
      # Carry forward interactively-resolved values not present in _ORIG_ARGS
      printf ' --name %q' "$ENGINEER_NAME"
      printf ' --mode %q' "$INSTALL_MODE"
      printf ' --cc-asked'
      if [[ -n "$CC_VERSION" ]]; then
        printf ' --cc-version %q' "$CC_VERSION"
      fi
      if [[ "$CC_NO_AUTOUPDATE" == "true" ]]; then
        printf ' --no-autoupdate'
      fi
      if [[ -n "${TAILSCALE_KEY:-}" ]]; then
        printf ' --tailscale-key %q' "$TAILSCALE_KEY"
      fi
      if [[ -n "$SEMGREP_TOKEN" ]]; then
        printf ' --semgrep-token %q' "$SEMGREP_TOKEN"
      elif $SEMGREP_SKIP; then
        printf ' --no-semgrep'
      fi
      printf ' 2>&1 | tee %q\n' "$_TMUX_LOG"
    } >"$_TMUX_WRAPPER"
    chmod +x "$_TMUX_WRAPPER"
    echo -e "\n  ${CYAN}Re-launching inside tmux (SSH-disconnect safe)${NC}"
    echo -e "  ${GREEN}Reconnect:${NC} tmux attach -t titan-setup"
    echo -e "  ${GREEN}Log:${NC}       tail -f $_TMUX_LOG\n"
    # Kill any stale session from a previous run before creating a new one.
    # Without this, re-running the script fails with "duplicate session: titan-setup".
    tmux kill-session -t titan-setup 2>/dev/null || true
    # Use detached mode (-d) when no terminal is available (non-interactive SSH, cloud-init)
    # then wait for the session to complete; otherwise attach interactively
    if [[ -t 0 ]]; then
      exec tmux new-session -s titan-setup "bash $_TMUX_WRAPPER"
    else
      tmux new-session -d -s titan-setup "bash $_TMUX_WRAPPER"
      echo -e "  ${CYAN}Running detached (no terminal). Monitor:${NC}"
      echo -e "    ssh $USER@\$(hostname) 'tmux attach -t titan-setup'"
      echo -e "    tail -f $_TMUX_LOG"
      # Wait for the tmux session to finish
      while tmux has-session -t titan-setup 2>/dev/null; do sleep 5; done
      exit 0
    fi
  fi
fi

# ─── Log file ───
# Inside tmux: the wrapper already tees ALL output. Find the most recent tmux log.
# Outside tmux (TITAN_TMUX=1 or direct): create new log + exec tee to capture everything.
if [[ -n "${TMUX:-}" ]]; then
  # Wrapper tees to /tmp/titan-setup-YYYYMMDD-HHMMSS.log — find latest one
  LOG_FILE=$(ls -1t /tmp/titan-setup-*.log 2>/dev/null | head -1)
  if [[ -z "$LOG_FILE" ]]; then
    LOG_FILE="/tmp/titan-setup-$(date +%Y%m%d-%H%M%S).log"
  fi
else
  LOG_FILE="/tmp/titan-setup-$(date +%Y%m%d-%H%M%S).log"
  echo "# titan-setup log — $(date)" >"$LOG_FILE"
  exec > >(tee -a "$LOG_FILE") 2>&1
fi
# run_q: run a command, routing output to log file unless --verbose
run_q() { if $VERBOSE; then "$@"; else "$@" >>"$LOG_FILE" 2>&1; fi; }

# ─── Temp directory for downloads ───
WORKDIR=$(mktemp -d)
_CLEANUP_DIRS=("$WORKDIR")
_do_cleanup() { rm -rf "${_CLEANUP_DIRS[@]}"; }
trap '_do_cleanup' EXIT

# ─── Architecture detection ───
UNAME_ARCH=$(uname -m)
case "$UNAME_ARCH" in
  x86_64)
    ARCH_AMD="amd64"
    ARCH_GO="amd64"
    ARCH_RUST="x86_64"
    ARCH_FULL="x86_64"
    ;;
  aarch64)
    ARCH_AMD="arm64"
    ARCH_GO="arm64"
    ARCH_RUST="aarch64"
    ARCH_FULL="aarch64"
    ;;
  *)
    fail "Unsupported architecture: $UNAME_ARCH"
    exit 1
    ;;
esac
# ─── VPS Pre-hardening (before tool installation) ───
if [[ "$INSTALL_MODE" == "vps" ]]; then
  section "VPS — Server Hardening"

  # ── Require Tailscale auth key ─────────────────────────────────────────
  if [[ -z "$TAILSCALE_KEY" ]]; then
    echo -e "  ${CYAN}Tailscale auth key${NC} (required — generate at login.tailscale.com/admin/settings/keys):"
    read -rsp "  Key: " TAILSCALE_KEY || true
    echo ""
    [[ -z "$TAILSCALE_KEY" ]] && {
      fail "Tailscale key required for VPS mode"
      exit 1
    }
  fi

  # ── Require non-root Claude user ───────────────────────────────────────
  if [[ -z "$CLAUDE_USER" ]]; then
    read -rp "  Non-root user for Claude Code (created if absent): " CLAUDE_USER || true
    [[ -z "$CLAUDE_USER" ]] && {
      fail "--claude-user required for VPS mode"
      exit 1
    }
  fi

  # ── Security packages ──────────────────────────────────────────────────
  apt_update
  run_q sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    -o Dpkg::Options::="--force-confold" \
    fail2ban unattended-upgrades auditd audispd-plugins
  ok "Security packages (fail2ban, unattended-upgrades, auditd)"

  # ── SSH hardening — DEFERRED to lib/16-finalize.sh ───────────────────
  # Config changes AND reload are both deferred until after Tailscale SSH
  # provides alternative access. Writing config here is unsafe because apt
  # package installs (openssh-server upgrades, fail2ban) trigger dpkg
  # postinst hooks that restart sshd, which picks up the hardened config
  # and locks out password-based SSH before Tailscale is ready.
  ok "SSH hardening deferred until Tailscale is verified (lib/16-finalize.sh)"

  # ── UFW — NOT used (Tailscale handles network isolation) ─────────────
  # UFW conflicts with Tailscale routing. Tailscale provides network-level
  # isolation via WireGuard. Do not enable UFW on Tailscale VPS nodes.
  # Reference: https://tailscale.com/kb/1077/secure-server-ubuntu-18-04

  # ── fail2ban — SSH protection ─────────────────────────────────────────
  sudo tee /etc/fail2ban/jail.local >/dev/null <<'FAIL2BAN_EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
backend  = %(sshd_backend)s
FAIL2BAN_EOF
  sudo systemctl enable fail2ban --now || true
  ok "fail2ban active (SSH: 5 retries → 1h ban)"

  # ── unattended-upgrades — security patches only ───────────────────────
  sudo tee /etc/apt/apt.conf.d/50unattended-upgrades-titan >/dev/null <<'UU_EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
UU_EOF
  sudo systemctl enable unattended-upgrades --now || true
  ok "unattended-upgrades active (security patches only, no auto-reboot)"

  # ── auditd — privilege escalation monitoring ──────────────────────────
  sudo tee /etc/audit/rules.d/titan.rules >/dev/null <<'AUDIT_EOF'
-a always,exit -F arch=b64 -S execve -F euid=0 -F auid!=0 -k privesc
-w /etc/passwd -p wa -k passwd_changes
-w /etc/sudoers -p wa -k sudoers_changes
-w /etc/sudoers.d/ -p wa -k sudoers_changes
AUDIT_EOF
  sudo systemctl enable auditd --now || true
  ok "auditd active (privesc monitoring, passwd/sudoers watch)"

  # ── Repo supply chain guard ───────────────────────────────────────────
  sudo tee /usr/local/sbin/repo_supply_chain_guard.sh >/dev/null <<'GUARD_EOF'
#!/bin/bash
set -euo pipefail
# Allowlist includes Ubuntu/Debian base repos plus all repos titan-setup.sh adds
ALLOWLIST='^(deb\.debian\.org|security\.debian\.org|archive\.ubuntu\.com|security\.ubuntu\.com|packages\.cloud\.google\.com|dl\.google\.com|download\.docker\.com|apt\.kubernetes\.io|pkgs\.tailscale\.com|aquasecurity\.github\.io|apt\.releases\.hashicorp\.com|cli\.github\.com|packages\.github\.com|artifacts-cli\.infisical\.com|ppa\.launchpadcontent\.net)$'
VIOLATIONS="/var/log/repo_allowlist_violations.log"
: > "$VIOLATIONS"

check_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    if [[ "$line" =~ ^[[:space:]]*deb[[:space:]]+http:// ]]; then
      sed -i "s|^\([[:space:]]*deb[[:space:]]\+http://.*\)$|# disabled-insecure-http \1|g" "$file"
    fi
    if [[ "$line" =~ ^[[:space:]]*deb[[:space:]]+https?://([^/[:space:]]+) ]]; then
      host="${BASH_REMATCH[1]}"
      if ! [[ "$host" =~ $ALLOWLIST ]]; then
        echo "non-allowlisted repo host in $file: $host" >> "$VIOLATIONS"
      fi
    fi
  done < "$file"
}

check_file /etc/apt/sources.list
shopt -s nullglob
for f in /etc/apt/sources.list.d/*.list; do
  check_file "$f"
done
shopt -u nullglob

apt-get update
GUARD_EOF
  sudo chmod 755 /usr/local/sbin/repo_supply_chain_guard.sh
  sudo bash /usr/local/sbin/repo_supply_chain_guard.sh || warn "repo supply chain guard had errors (non-fatal)"
  ok "Repo supply chain guard installed and run"

  # ── Compliance check script ───────────────────────────────────────────
  sudo tee /usr/local/bin/compliance_check.sh >/dev/null <<'COMPLIANCE_EOF'
#!/bin/bash
set -euo pipefail

FAIL=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=1; }

if grep -Eiq '^\s*PasswordAuthentication\s+no\b' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null; then
  pass "ssh password auth disabled"
else
  fail "ssh password auth disabled"
fi

if grep -Eiq '^\s*PermitRootLogin\s+no\b' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null; then
  pass "ssh root login disabled"
else
  fail "ssh root login disabled"
fi

if systemctl is-active --quiet fail2ban; then
  pass "fail2ban active"
else
  fail "fail2ban active"
fi

if systemctl is-active --quiet auditd; then
  pass "auditd active"
else
  fail "auditd active"
fi

if systemctl is-enabled --quiet unattended-upgrades; then
  pass "unattended upgrades enabled"
else
  fail "unattended upgrades enabled"
fi

if ! grep -R --line-number -E '^[[:space:]]*deb[[:space:]]+http://' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
  pass "no insecure apt repos"
else
  fail "no insecure apt repos"
fi

if [[ -f /var/log/repo_allowlist_violations.log ]] && [[ -s /var/log/repo_allowlist_violations.log ]]; then
  fail "allowlist violations detected in /var/log/repo_allowlist_violations.log"
else
  pass "repo allowlist violations not detected"
fi

if passwd -S root 2>/dev/null | grep -qE ' L '; then
  pass "root account locked"
else
  fail "root account locked"
fi

# Tailscale checks (mandatory on VPS)
if ! command -v tailscale >/dev/null 2>&1; then
  fail "tailscale installed"
  fail "tailscale running"
  fail "tailscale has IPv4 address"
  fail "sshd restricted to tailscale IP"
  fail "ufw ssh restricted to tailscale0"
  exit "$FAIL"
fi

if tailscale status &>/dev/null; then
  pass "tailscale running"
elif [ -n "$(tailscale ip -4 2>/dev/null || true)" ]; then
  pass "tailscale running"
else
  fail "tailscale running"
fi

TS_IP=$(tailscale ip -4 2>/dev/null || true)
if [ -n "$TS_IP" ]; then
  pass "tailscale has IPv4 address ($TS_IP)"
else
  fail "tailscale has IPv4 address"
fi

if grep -Eq "^ListenAddress[[:space:]]+$TS_IP" /etc/ssh/sshd_config 2>/dev/null; then
  pass "sshd restricted to tailscale IP"
else
  fail "sshd restricted to tailscale IP"
fi

if command -v tailscale >/dev/null 2>&1 && tailscale status &>/dev/null; then
  pass "tailscale connected (network isolation active)"
else
  fail "tailscale connected (network isolation active)"
fi

exit "$FAIL"
COMPLIANCE_EOF
  sudo chmod 755 /usr/local/bin/compliance_check.sh
  ok "Compliance check script installed"

  # ── Compliance systemd timer (every 6h) ───────────────────────────────
  sudo tee /etc/systemd/system/compliance-check.service >/dev/null <<'SVC_EOF'
[Unit]
Description=Run server compliance checks
After=network-online.target

[Service]
Type=oneshot
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/usr/local/bin/compliance_check.sh
SVC_EOF

  sudo tee /etc/systemd/system/compliance-check.timer >/dev/null <<'TIMER_EOF'
[Unit]
Description=Periodic compliance checks

[Timer]
OnBootSec=5m
OnUnitActiveSec=6h
RandomizedDelaySec=5m
Persistent=true

[Install]
WantedBy=timers.target
TIMER_EOF

  sudo systemctl daemon-reload || true
  sudo systemctl enable --now compliance-check.timer || true
  ok "Compliance timer enabled (runs at boot +5m, then every 6h)"

fi
if phase_done "phase1" && ! $FORCE_UPDATES; then
  section "Phase 1/6 — System Prerequisites (cached ✓)"
else
  section "Phase 1/6 — System Prerequisites"

  # Suppress needrestart interactive kernel/service restart prompts on Ubuntu VPS
  # Sets restart mode to automatic so apt upgrades never block waiting for user input
  if [[ -d /etc/needrestart ]]; then
    sudo mkdir -p /etc/needrestart/conf.d
    # restart='a' → auto-restart services; kernelhints=-1 → suppress "Pending kernel upgrade" dialog
    sudo tee /etc/needrestart/conf.d/titan-auto.conf >/dev/null <<'NEEDRESTART'
$nrconf{restart} = 'a';
$nrconf{kernelhints} = -1;
$nrconf{ucodehints} = 0;
NEEDRESTART
  fi

  # Cap journald disk usage — prevents n8n/Ollama/Letta logs from filling disk
  if ! grep -q 'SystemMaxUse=500M' /etc/systemd/journald.conf 2>/dev/null; then
    sudo mkdir -p /etc/systemd/journald.conf.d
    printf '[Journal]\nSystemMaxUse=500M\nSystemMaxFileSize=50M\nMaxRetentionSec=7day\n' |
      sudo tee /etc/systemd/journald.conf.d/titan-limits.conf >/dev/null
    sudo systemctl restart systemd-journald 2>/dev/null || true
    ok "journald log limits set (500MB max, 7-day retention)"
  fi

  apt_update
  run_q sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq \
    -o Dpkg::Options::="--force-confold"

  run_q sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    -o Dpkg::Options::="--force-confold" \
    curl wget git build-essential unzip software-properties-common \
    lsb-release apt-transport-https gnupg ca-certificates \
    jq mtr nmap tmux pandoc direnv entr nikto lynis \
    redis-tools aria2 btop miller \
    inotify-tools expect asciinema at \
    lnav imagemagick \
    universal-ctags chafa \
    libclang-dev cmake libxml2-dev libcurl4-openssl-dev

  run_q sudo apt-get autoremove -y -qq

  # Desktop-only packages (screenshot/X11 tools not needed on VPS)
  if [[ "$INSTALL_MODE" == "desktop" ]]; then
    run_q sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq maim xdotool
  fi

  # ─── JetBrains Mono Nerd Font (desktop only — Powerline statusline) ───
  if [[ "$INSTALL_MODE" == "desktop" ]]; then
    if fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font"; then
      ok "JetBrainsMono Nerd Font already installed"
    else
      echo -n "  Installing JetBrainsMono Nerd Font..."
      FONT_DIR="$HOME/.local/share/fonts"
      mkdir -p "$FONT_DIR"
      TMPFONT=$(mktemp -d)
      if curl -fsSL -o "$TMPFONT/JetBrainsMono.tar.xz" \
        "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz"; then
        tar -xf "$TMPFONT/JetBrainsMono.tar.xz" -C "$TMPFONT"
        cp "$TMPFONT"/*.ttf "$FONT_DIR/" 2>/dev/null || true
        fc-cache -f "$FONT_DIR" 2>/dev/null
        ok "JetBrainsMono Nerd Font installed"
      else
        warn "JetBrainsMono Nerd Font download failed"
      fi
      rm -rf "$TMPFONT"
    fi
    # Note: Cosmic Terminal font is NOT set here — change it manually via terminal settings.
  fi

  # ─── Linux tuning ───
  section "Linux Tuning"

  # Increase file watchers (needed for large projects)
  if ! grep -q "fs.inotify.max_user_watches" /etc/sysctl.conf 2>/dev/null; then
    echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf
    echo "fs.inotify.max_user_instances=1024" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -p || true
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

  phase_mark "phase1"
fi # end phase1 checkpoint
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
# ─── Repo files (static content loaded from git repo) ────────────────────────
# Cloned early so tools like RTK can use patches from the repo during Phase 3.
REPO_FILES="${TITAN_REPO_FILES:-}"
if [[ -z "$REPO_FILES" ]]; then
  _REPO_TMPDIR=$(mktemp -d -t titan-files-XXXXXX)
  ok "Fetching repo files..."
  git clone --depth=1 --quiet \
    https://github.com/SutanuNandigrami/claude-titan-setup.git \
    "$_REPO_TMPDIR" 2>&1 | tee -a "$LOG_FILE"
  REPO_FILES="$_REPO_TMPDIR"
  _CLEANUP_DIRS+=("$_REPO_TMPDIR")
fi
section "Phase 3/6 — 150+ CLI Tools"

# ── Parallel strategy: uv + bun install in background while cargo compiles in foreground ──
# uv, bun, and cargo use separate package managers with no shared state.
# Cargo is the bottleneck (~25-40 min); running uv/bun concurrently saves ~10-15 min.
_PHASE3_UV_LOG="$WORKDIR/phase3-uv.log"
_PHASE3_BUN_LOG="$WORKDIR/phase3-bun.log"

# ─── Python tools via uv (isolated venvs, zero system pollution) ───
echo -e "  ${CYAN}Python tools (uv):${NC}"

# Core Python tools (always installed)
UV_TOOLS=(
  "yq"           # yq — YAML/XML/TOML processor
  "semgrep"      # semgrep — static analysis
  "ansible-core" # ansible, ansible-playbook, ansible-galaxy + more
  "ansible-lint" # ansible-lint — linter for Ansible playbooks
  "pgcli"        # pgcli — Postgres with autocomplete
  "ruff"         # ruff — Python linter (replaces flake8+black+isort+pyflakes)
  "ast-grep-cli" # ast-grep, sg — structural code search
  "cozempic"     # cozempic — context bloat cleaner for Claude Code sessions
)
# Extended Python tools (skipped with --minimal)
if ! $MINIMAL; then
  UV_TOOLS+=(
    "sqlmap"             # sqlmap — SQL injection testing
    "mitmproxy"          # mitmproxy, mitmdump — HTTP/HTTPS proxy for debugging
    "cookiecutter"       # cookiecutter — project scaffolding from templates
    "notebooklm-mcp-cli" # nlm — Google NotebookLM CLI + MCP server
  )
fi

# Run uv tools in background (output to log, results shown after cargo phase)
(
  if $FORCE_UPDATES; then
    uv tool upgrade --all 2>/dev/null && echo "UV_UPGRADE=ok" || echo "UV_UPGRADE=warn"
  fi
  _uv_list=$(uv tool list 2>/dev/null)
  for tool in "${UV_TOOLS[@]}"; do
    if echo "$_uv_list" | grep -q "^${tool} "; then
      echo "UV_OK=$tool"
    elif uv tool install --force "$tool" &>/dev/null; then
      echo "UV_INSTALLED=$tool"
    else
      echo "UV_FAIL=$tool"
    fi
  done
) >"$_PHASE3_UV_LOG" 2>&1 &
_UV_PID=$!
echo "  uv tools installing in background (${#UV_TOOLS[@]} tools)..."

echo -e "\n  ${CYAN}Claude Code ecosystem tools (uv):${NC}"
command -v ccusage &>/dev/null && ok "ccusage (exists)" || { uv tool install ccusage 2>/dev/null && ok "ccusage" || warn "ccusage"; }
command -v sherlock &>/dev/null && ok "sherlock (exists)" || { uv tool install sherlock-project 2>/dev/null && ok "sherlock" || warn "sherlock"; }
# claude-agent-sdk is a library (not a CLI tool) — needs --break-system-packages on Ubuntu 24.04 externally-managed Python
_PYSITE="$HOME/.local/lib/python3.12/site-packages"
python3 -c "import claude_agent_sdk" 2>/dev/null && ok "claude-agent-sdk (exists)" ||
  { mkdir -p "$_PYSITE" && uv pip install --target "$_PYSITE" --quiet claude-agent-sdk 2>/dev/null &&
    ok "claude-agent-sdk" || warn "claude-agent-sdk (install manually: uv pip install --target ~/.local/lib/python3.12/site-packages claude-agent-sdk)"; }
unset _PYSITE

# sqlite-vec is installed to ~/.local/lib/python-libs/ as a memory library (used on-demand, not at startup)

# ─── JS tools via bun ───
echo -e "\n  ${CYAN}JS tools (bun):${NC}"

# Trust postinstall scripts for packages that need them (esbuild, puppeteer, canvas, etc.)
# Also skip puppeteer chromium download — we install chromium via playwright separately
cat >"$HOME/.bunfig.toml" <<'BUNFIG'
[install]
trustedDependencies = ["puppeteer", "esbuild", "@swc/core", "canvas", "node-gyp", "sharp", "fsevents"]

[install.scopes]
BUNFIG
export PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=1

BUN_TOOLS=("trash-cli" "tldr" "prettier" "repomix" "ccstatusline")
if $FORCE_UPDATES; then
  echo -e "  ${YELLOW}Force-updating all Bun tools...${NC}"
  for tool in "${BUN_TOOLS[@]}"; do
    run_q bun install -g "$tool" && ok "$tool (updated)" || warn "$tool update failed"
  done
else
  for tool in "${BUN_TOOLS[@]}"; do
    if bun pm ls -g 2>/dev/null | grep -q "$tool"; then
      ok "$tool (exists)"
    else
      echo -n "  Installing $tool..."
      run_q bun install -g "$tool" && echo -e " ${GREEN}✓${NC}" || echo -e " ${YELLOW}⚠${NC}"
    fi
  done
fi

command -v gemini &>/dev/null && ok "gemini-cli (exists)" || { run_q bun install -g @google/gemini-cli && ok "gemini-cli" || warn "gemini-cli"; }
command -v mmdc &>/dev/null && ok "mermaid-cli (exists)" || { run_q bun install -g @mermaid-js/mermaid-cli && ok "mermaid-cli" || warn "mermaid-cli"; }

# playwright — browser automation and E2E testing
# Ensure node is on PATH (mise shims may not be sourced in non-interactive context)
command -v node &>/dev/null || export PATH="$HOME/.local/share/mise/shims:$PATH"
if ! bun pm ls -g 2>/dev/null | grep -q playwright; then
  run_q bun install -g playwright && ok "playwright" || warn "playwright"
  # Install chromium: apt deps need root, browser download runs as current user
  if command -v playwright &>/dev/null; then
    # install-deps uses apt-get; titan has NOPASSWD sudo so playwright's internal sudo call works
    sudo -E env "PATH=$PATH" "$(command -v playwright)" install-deps chromium >>"$LOG_FILE" 2>&1 || true
    run_q playwright install chromium && ok "playwright chromium" ||
      warn "playwright chromium (install manually: playwright install chromium)"
  fi
else
  ok "playwright (exists)"
fi

# n8n — workflow automation server (runs as systemd user service via docker)
if $MINIMAL; then
  ok "n8n (skipped — minimal mode)"
elif command -v docker &>/dev/null; then
  check_port 5678 "n8n" || true
  # Add user to docker group and ensure daemon is running
  sudo usermod -aG docker "$USER" 2>/dev/null || true
  sudo systemctl enable --now docker 2>/dev/null || true

  # Enable systemd linger so user services start at boot without login
  loginctl enable-linger "$USER" 2>/dev/null || true

  # Restart user systemd manager so it picks up the new docker group membership.
  # Without this, user services (n8n, letta) crash-loop on "permission denied" to
  # the docker socket because group changes only take effect on new sessions.
  sudo systemctl restart "user@$(id -u).service" 2>/dev/null || true

  # Pull image — user is in docker group; fall back to sudo if socket isn't yet accessible
  # Use /usr/bin/sg explicitly — ast-grep-cli installs an 'sg' binary that shadows it
  if docker pull n8nio/n8n:latest >>"$LOG_FILE" 2>&1 ||
    /usr/bin/sg docker -c "docker pull n8nio/n8n:latest" >>"$LOG_FILE" 2>&1 ||
    sudo docker pull n8nio/n8n:latest >>"$LOG_FILE" 2>&1; then
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
  cat >"$HOME/.config/systemd/user/n8n.service" <<SERVICEEOF
[Unit]
Description=n8n workflow automation
After=docker.service default.target
Wants=docker.service

[Service]
Type=simple
ExecStartPre=-${DOCKER_BIN} rm -f n8n
ExecStart=${DOCKER_BIN} run --rm --name n8n -p 127.0.0.1:5678:5678 -v %h/.n8n:/home/node/.n8n n8nio/n8n
ExecStop=${DOCKER_BIN} stop n8n
Restart=on-failure
RestartSec=10
StartLimitIntervalSec=300
StartLimitBurst=5
MemoryMax=512M

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
# ─── Ollama — local embedding model server (required by Letta for agent creation) ───
if $LETTA_SKIP || $OLLAMA_SKIP; then
  ok "Ollama (skipped)"
else
  if command -v ollama &>/dev/null; then
    ok "ollama already installed: $(ollama --version 2>/dev/null | head -1 || echo installed)"
  else
    echo "  Installing Ollama..."
    if curl -fsSL https://ollama.com/install.sh | sh >>"$LOG_FILE" 2>&1; then
      ok "ollama installed"
    else
      warn "ollama install failed — Letta will need OpenAI embeddings (set OPENAI_API_KEY)"
      OLLAMA_SKIP=true
    fi
  fi

  if ! $OLLAMA_SKIP && command -v ollama &>/dev/null; then
    # Ollama installer creates /etc/systemd/system/ollama.service (system-level)
    # Bind to 0.0.0.0 so Docker bridge containers can reach it via host.docker.internal
    sudo mkdir -p /etc/systemd/system/ollama.service.d
    printf '[Service]\nEnvironment="OLLAMA_HOST=0.0.0.0:11434"\n' |
      sudo tee /etc/systemd/system/ollama.service.d/override.conf >/dev/null
    sudo systemctl daemon-reload 2>/dev/null || true
    sudo systemctl enable ollama 2>/dev/null || true
    sudo systemctl start ollama 2>/dev/null || true
    # Wait for Ollama to be ready (up to 30s)
    for _oi in $(seq 1 15); do
      ollama list &>/dev/null 2>&1 && break
      sleep 2
    done
    if ! ollama list &>/dev/null 2>&1; then
      warn "ollama service not responding — check: sudo systemctl status ollama"
      OLLAMA_SKIP=true
    fi
  fi

  if ! $OLLAMA_SKIP && command -v ollama &>/dev/null; then
    if ollama list 2>/dev/null | grep -q "nomic-embed-text"; then
      ok "nomic-embed-text (exists)"
    else
      echo -n "  Pulling nomic-embed-text (~274MB)..."
      if ollama pull nomic-embed-text >>"$LOG_FILE" 2>&1; then
        echo -e " ${GREEN}✓${NC}"
      else
        echo -e " ${YELLOW}⚠ pull failed — retry: ollama pull nomic-embed-text${NC}"
        OLLAMA_SKIP=true
      fi
    fi
  fi
fi

# ─── Letta password + credentials (generated before Docker container setup) ───
if ! $LETTA_SKIP; then
  if [[ -z "$LETTA_PASSWORD" ]]; then
    LETTA_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)
  fi
  mkdir -p "$HOME/.config/letta"
  cat >"$HOME/.config/letta/credentials" <<CREDEOF
# Letta server credentials (generated by titan-setup ${SCRIPT_VERSION})
LETTA_SERVER_PASSWORD=${LETTA_PASSWORD}
LETTA_BASE_URL=http://127.0.0.1:${LETTA_PORT}
LETTA_API_KEY=${LETTA_PASSWORD}
CREDEOF
  chmod 600 "$HOME/.config/letta/credentials"

  # Docker env file for Letta container
  cat >"$HOME/.config/letta/docker.env" <<ENVEOF
SECURE=true
LETTA_SERVER_PASSWORD=${LETTA_PASSWORD}
ENVEOF
  if ! $OLLAMA_SKIP && command -v ollama &>/dev/null; then
    echo "OLLAMA_BASE_URL=http://host.docker.internal:11434/v1" >>"$HOME/.config/letta/docker.env"
  fi
  if ! $CCFLARE_SKIP && command -v better-ccflare &>/dev/null; then
    echo "ANTHROPIC_BASE_URL=http://host.docker.internal:${CCFLARE_PROXY_PORT}" >>"$HOME/.config/letta/docker.env"
    echo "ANTHROPIC_API_KEY=sk-proxy-via-ccflare" >>"$HOME/.config/letta/docker.env"
  elif [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}" >>"$HOME/.config/letta/docker.env"
  fi
  chmod 600 "$HOME/.config/letta/docker.env"
  ok "Letta credentials (~/.config/letta/)"
fi

# ─── Letta Server — persistent memory backend for claude-subconscious ───
if $LETTA_SKIP; then
  ok "Letta server (skipped)"
elif ! command -v docker &>/dev/null; then
  warn "Letta server skipped — Docker not available (install Docker and re-run)"
  LETTA_SKIP=true
else
  # Pull Letta Docker image (bundles Postgres+pgvector)
  _DOCKER_BIN=$(command -v docker)
  # Use sudo — docker group membership from lib/06 hasn't taken effect in this shell
  if run_q sudo docker pull letta/letta:latest; then
    ok "letta/letta:latest image"
  else
    warn "letta docker pull failed — check: docker pull letta/letta:latest"
    LETTA_SKIP=true
  fi

  if ! $LETTA_SKIP; then
    mkdir -p "$HOME/.letta/.persist/pgdata"

    # Systemd user service using --env-file to avoid secrets in unit file
    mkdir -p "$HOME/.config/systemd/user"
    cat >"$HOME/.config/systemd/user/letta.service" <<SERVICEEOF
[Unit]
Description=Letta persistent memory server
After=docker.service default.target
Wants=docker.service

[Service]
Type=simple
ExecStartPre=-${_DOCKER_BIN} rm -f letta-server
ExecStart=${_DOCKER_BIN} run --rm --name letta-server -p 127.0.0.1:${LETTA_PORT}:8283 --add-host=host.docker.internal:host-gateway -v %h/.letta/.persist/pgdata:/var/lib/postgresql/data --env-file %h/.config/letta/docker.env letta/letta:latest
ExecStop=${_DOCKER_BIN} stop letta-server
Restart=on-failure
RestartSec=15
StartLimitIntervalSec=300
StartLimitBurst=5
MemoryMax=1G

[Install]
WantedBy=default.target
SERVICEEOF

    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable letta 2>/dev/null || true
    systemctl --user start letta 2>/dev/null || true
    ok "letta service (http://127.0.0.1:${LETTA_PORT})"

    # Wait for Letta health (up to 60s — Postgres init slow on first run)
    _LETTA_READY=false
    for _li in $(seq 1 30); do
      if curl -sf "http://127.0.0.1:${LETTA_PORT}/v1/health" &>/dev/null; then
        _LETTA_READY=true
        break
      fi
      sleep 2
    done
    if $_LETTA_READY; then
      ok "letta server healthy (http://127.0.0.1:${LETTA_PORT})"
    else
      warn "letta server not responding yet — check: journalctl --user -u letta -f"
      echo "  (Postgres init can take 30-60s on first run; service will recover automatically)"
    fi
  fi
fi

# ─── better-ccflare — Claude Code load balancer proxy ───
# Distributes requests across Claude OAuth, Vertex AI, Z.ai, OpenRouter, local models
# Dashboard: http://${CCFLARE_HOST}:${CCFLARE_PORT} | Docs: https://github.com/tombii/better-ccflare

if $CCFLARE_SKIP; then
  ok "better-ccflare (skipped — use --ccflare-* flags to configure)"
else
  # Phase A: Install from source with patches
  # Upstream bugs: NULL constraint on refresh_token for kilo/zai/minimax/console CLI modes
  # See: https://github.com/tombii/better-ccflare/issues/83
  if $FORCE_UPDATES || ! command -v better-ccflare &>/dev/null; then
    _BCF_SRC=$(mktemp -d -t bcf-src-XXXXXX)
    _CLEANUP_DIRS+=("$_BCF_SRC")
    if run_q git clone --depth=1 https://github.com/tombii/better-ccflare.git "$_BCF_SRC"; then
      # Patch: fix NULL constraint for refresh_token in CLI account creation
      python3 - "$_BCF_SRC/packages/cli-commands/src/commands/account.ts" <<'PYEOF'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
c = f.read_text()
for provider, values_placeholder, array_signature in [
    ("claude-console-api", "NULL, NULL, NULL, ?, 0, 0", "validatedApiKey,\n\t\t\tnow,\n\t\t\tvalidatedPriority,\n\t\t\tcustomEndpoint"),
    ("minimax",            "NULL, NULL, NULL, ?, 0, 0", "validatedApiKey,\n\t\t\tnow,\n\t\t\tvalidatedPriority,\n\t\t\tnull"),
    ("zai",                "NULL, NULL, NULL, ?, ?, ?", "validatedApiKey,\n\t\t\tnow,\n\t\t\t0,"),
    ("kilo",               "?, ?, ?, ?, ?, ?, ?",       None),  # separate pattern
]:
    if provider == "kilo":
        old = '"kilo",\n\t\t\tvalidatedApiKey,\n\t\t\tnull,'
        new = '"kilo",\n\t\t\tvalidatedApiKey,\n\t\t\tvalidatedApiKey,'
    else:
        old = f'"{provider}",\n\t\t\tvalidatedApiKey,\n\t\t\tnow,'
        new = f'"{provider}",\n\t\t\tvalidatedApiKey,\n\t\t\tvalidatedApiKey,\n\t\t\tnow,'
    c = c.replace(old, new)
f.write_text(c)
PYEOF
      # Also fix SQL placeholders: NULL, NULL, NULL → ?, NULL, NULL for console/minimax/zai
      python3 - "$_BCF_SRC/packages/cli-commands/src/commands/account.ts" <<'PYEOF'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
c = f.read_text()
# Replace the SQL NULL,NULL,NULL with ?,NULL,NULL for API-key providers that store key as refresh_token
# Only target the INSERT patterns that still have the old SQL (not already patched)
c = c.replace(
    ") VALUES (?, ?, ?, ?, NULL, NULL, NULL,",
    ") VALUES (?, ?, ?, ?, ?, NULL, NULL,"
)
f.write_text(c)
PYEOF
      mkdir -p "$HOME/.bun/bin"
      # NOTE: cd is required — `bun --cwd` does not propagate CWD to shell subprocesses
      # in the build script, which uses relative paths like ../../packages/
      if run_q bun install --cwd "$_BCF_SRC" && (cd "$_BCF_SRC/apps/cli" && run_q bun run build); then
        _BCF_DIST="$_BCF_SRC/apps/cli/dist/better-ccflare"
        if [[ -f "$_BCF_DIST" ]]; then
          mkdir -p "$HOME/.bun/bin" "$HOME/.local/bin"
          install -m 0755 "$_BCF_DIST" "$HOME/.bun/bin/better-ccflare"
          install -m 0755 "$_BCF_DIST" "$HOME/.local/bin/better-ccflare"
          ok "better-ccflare (built from source + NULL constraint patches applied)"
        else
          warn "better-ccflare build succeeded but binary not found at $_BCF_DIST"
          if [[ "$ARCH_GO" == "arm64" ]]; then
            warn "  arm64: no pre-built npm binary available — skipping"
          else
            run_q bun install -g better-ccflare || warn "better-ccflare npm install also failed"
          fi
        fi
      else
        warn "better-ccflare build failed"
        if [[ "$ARCH_GO" == "arm64" ]]; then
          warn "  arm64: npm fallback binary is x86-64 only — skipping"
          warn "  Fix: bun install --cwd <bcf-src> && bun --cwd <bcf-src>/apps/cli run build"
        else
          run_q bun install -g better-ccflare || warn "better-ccflare npm install also failed"
        fi
      fi
    else
      warn "better-ccflare repo clone failed"
      if [[ "$ARCH_GO" == "arm64" ]]; then
        warn "  arm64: npm fallback binary is x86-64 only — must build from source"
      else
        run_q bun install -g better-ccflare || warn "better-ccflare install failed"
      fi
    fi
  else
    ok "better-ccflare (exists)"
  fi

  # Phase B: Systemd user service
  # Resolve binary path at install time — avoids hardcoded ~/.bun/bin/ which may not exist
  _BCF_BIN=$(command -v better-ccflare 2>/dev/null || echo "$HOME/.local/bin/better-ccflare")
  mkdir -p "$HOME/.config/systemd/user"
  cat >"$HOME/.config/systemd/user/better-ccflare.service" <<SERVICEEOF
[Unit]
Description=better-ccflare Claude load balancer proxy
After=default.target

[Service]
Type=simple
ExecStart=${_BCF_BIN} --serve --port ${CCFLARE_PORT}
Restart=on-failure
RestartSec=5
StartLimitIntervalSec=300
StartLimitBurst=5
MemoryMax=256M
Environment="PORT=${CCFLARE_PORT}"
Environment="BETTER_CCFLARE_HOST=${CCFLARE_HOST}"
Environment="LB_STRATEGY=session"
Environment="LOG_LEVEL=INFO"
Environment="PATH=${HOME}/.local/bin:${HOME}/.bun/bin:/usr/local/bin:/usr/bin:/bin"
Environment="GOOGLE_APPLICATION_CREDENTIALS=${HOME}/.config/gcloud/application_default_credentials.json"

[Install]
WantedBy=default.target
SERVICEEOF

  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable better-ccflare 2>/dev/null || true
  systemctl --user start better-ccflare 2>/dev/null || true
  ok "better-ccflare service (http://${CCFLARE_HOST}:${CCFLARE_PORT})"
  echo "  Add accounts after install:"
  echo "    better-ccflare --add-account NAME --mode claude-oauth"
  echo "    better-ccflare --add-account NAME --mode kilo        (API key)"
  echo "    better-ccflare --add-account NAME --mode vertex-ai   (gcloud credentials)"
  echo "  ANTHROPIC_BASE_URL is auto-set in settings.json after accounts are added."

  # Billing header proxy (fixes better-ccflare issue #89):
  # - betterccflare binds to 127.0.0.1 only → Docker can't reach it directly
  # - OAuth accounts require x-anthropic-billing-header in system[0] for Sonnet/Opus
  # - This Bun proxy: 0.0.0.0:PROXY_PORT → injects header → 127.0.0.1:CCFLARE_PORT
  # - betterccflare upstream fix pending; when merged, this proxy still works (idempotent)
  _BUN_BIN=$(command -v bun 2>/dev/null || echo "$HOME/.local/bin/bun")
  if [[ -x "$_BUN_BIN" ]]; then
    mkdir -p "$HOME/.config/letta"
    cat >"$HOME/.config/letta/ccflare-billing-proxy.js" <<'BPROXY'
// ccflare-billing-proxy: fix for better-ccflare issue #89 (Sonnet/Opus 400 via OAuth)
// Injects x-anthropic-billing-header as system[0] block — required by Anthropic API
import { createHash } from "node:crypto";
const UPSTREAM = `http://127.0.0.1:${process.env.CCFLARE_PORT || 8080}`;
const PORT = Number(process.env.CCFLARE_PROXY_PORT || 8081);
const CC_VERSION = "2.1.77";
const SALT = "59cf53e54c78";
function computeBillingHeader(firstUserText) {
  const chars = [4, 7, 20].map(i => firstUserText[i] || "0").join("");
  const hash = createHash("sha256").update(SALT + chars + CC_VERSION).digest("hex").slice(0, 3);
  return `x-anthropic-billing-header: cc_version=${CC_VERSION}.${hash}; cc_entrypoint=cli; cch=00000;`;
}
function injectBillingHeader(body) {
  try {
    const json = JSON.parse(body);
    const sys = json.system;
    if (Array.isArray(sys) && sys.some(b => b.type === "text" && b.text?.startsWith("x-anthropic-billing-header:"))) return body;
    let firstUserText = "";
    if (Array.isArray(json.messages)) {
      for (const msg of json.messages) {
        if (msg.role === "user") {
          if (typeof msg.content === "string") firstUserText = msg.content;
          else if (Array.isArray(msg.content)) { const tb = msg.content.find(b => b.type === "text"); if (tb) firstUserText = tb.text || ""; }
          break;
        }
      }
    }
    const bb = { type: "text", text: computeBillingHeader(firstUserText) };
    if (Array.isArray(json.system)) json.system.unshift(bb);
    else if (typeof json.system === "string") json.system = [bb, { type: "text", text: json.system }];
    else json.system = [bb];
    return JSON.stringify(json);
  } catch { return body; }
}
Bun.serve({
  port: PORT, hostname: process.env.CCFLARE_PROXY_HOST || "127.0.0.1",
  async fetch(req) {
    const url = new URL(req.url);
    let body = await req.arrayBuffer();
    const headers = new Headers(req.headers);
    if (req.method === "POST" && url.pathname.includes("/v1/messages")) {
      const patched = injectBillingHeader(new TextDecoder().decode(body));
      body = new TextEncoder().encode(patched);
      headers.set("content-length", body.byteLength.toString());
    }
    const resp = await fetch(UPSTREAM + url.pathname + url.search, { method: req.method, headers, body: req.method !== "GET" && req.method !== "HEAD" ? body : undefined });
    return new Response(resp.body, { status: resp.status, headers: resp.headers });
  },
});
BPROXY

    cat >"$HOME/.config/systemd/user/ccflare-docker-proxy.service" <<SVCEOF
[Unit]
Description=betterccflare billing header proxy (issue #89 — Sonnet/Opus via OAuth)
After=better-ccflare.service
BindsTo=better-ccflare.service

[Service]
Type=simple
ExecStart=${_BUN_BIN} run %h/.config/letta/ccflare-billing-proxy.js
Environment="CCFLARE_PORT=${CCFLARE_PORT}"
Environment="CCFLARE_PROXY_PORT=${CCFLARE_PROXY_PORT}"
Environment="CCFLARE_PROXY_HOST=172.17.0.1"
Environment="PATH=${HOME}/.local/bin:${HOME}/.bun/bin:/usr/local/bin:/usr/bin:/bin"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=better-ccflare.service
SVCEOF
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable ccflare-docker-proxy 2>/dev/null || true
    systemctl --user start ccflare-docker-proxy 2>/dev/null || true
    ok "ccflare-billing-proxy (172.17.0.1:${CCFLARE_PROXY_PORT} → 127.0.0.1:${CCFLARE_PORT}, billing header injection)"
  else
    warn "bun not found — ccflare-billing-proxy skipped (Letta LLM calls will fail)"
  fi
fi # end $CCFLARE_SKIP

command -v kilocode &>/dev/null && ok "kilocode (exists)" || { run_q bun install -g @kilocode/cli && ok "kilocode" || warn "kilocode"; }
command -v vercel &>/dev/null && ok "vercel (exists)" || { run_q bun install -g vercel && ok "vercel" || warn "vercel"; }
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
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg |
    sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg 2>/dev/null || true
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" |
    sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null
  apt_update --force && sudo apt-get install -y -qq google-cloud-cli &&
    ok "gcloud" || warn "gcloud install failed"
else ok "gcloud (exists)"; fi

# terraform + packer
if ! command -v terraform &>/dev/null; then
  wget -qO- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg 2>/dev/null || true
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
  wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo gpg --dearmor -o /usr/share/keyrings/trivy.gpg 2>/dev/null || true
  echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/trivy.list >/dev/null
  apt_update --force && sudo apt-get install -y -qq trivy &&
    ok "trivy" || warn "trivy install failed"
else
  # migrate legacy key if sources.list lacks signed-by (suppresses apt deprecation warning)
  if ! grep -q 'signed-by' /etc/apt/sources.list.d/trivy.list 2>/dev/null; then
    wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo gpg --dearmor -o /usr/share/keyrings/trivy.gpg 2>/dev/null || true
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
# sd is required for template substitution (installed via cargo in Phase 3)
if ! command -v sd &>/dev/null; then
  warn "sd not found — falling back to sed for template substitution"
  sd() { sed -i "s|$1|$2|g" "$3"; }
fi

CLAUDE_DIR="$HOME/.claude"

# ─── Detect running CC sessions — warn before config changes ───
if pgrep -f 'claude' &>/dev/null; then
  warn "Claude Code is running — config changes may not take effect until restart"
fi

# ─── Cleanup stale artifacts from previous versions ───
rm -rf "$HOME/.claude/plugins/cache/claude-plugins-official/hookify/" 2>/dev/null
rm -rf "$HOME/.claude/skills/tool-discovery/" 2>/dev/null # replaced by cli-tools
rm -rf "$HOME/.claude/skills/security-ops/" 2>/dev/null   # replaced by security-scan
rm -rf "$HOME/.claude/skills/debug-protocol/" 2>/dev/null # replaced by systematic-debugging

# Backup existing
if [ -d "$CLAUDE_DIR/skills" ] || [ -d "$CLAUDE_DIR/commands" ] || [ -d "$CLAUDE_DIR/agents" ]; then
  BACKUP="$CLAUDE_DIR.backup.$(date +%s)"
  cp -r "$CLAUDE_DIR" "$BACKUP" 2>/dev/null || true
  ok "Backed up existing config to $BACKUP"
fi

mkdir -p "$CLAUDE_DIR"/{skills/cli-tools,skills/security-scan,skills/git-workflow,skills/infra-deploy,skills/add-cli-tool/references,skills/tmux-control,skills/workspace,skills/pueue-orchestrator,skills/diagrams,skills/deploy,skills/process-supervisor,skills/docker-security,skills/vibesec,skills/trailofbits-modern-python,skills/notebooklm-skills,commands,agents,hooks,memory,rules,logs,templates,agent-stash/_loaded,agent-stash/agents}
mkdir -p "$HOME/.config/agt"

# REPO_FILES already set by lib/06b-repo-files.sh (cloned early for tool patches)

# ─── CLAUDE.md ───
install -Dm644 "$REPO_FILES/dot-claude/CLAUDE.md.tmpl" "$CLAUDE_DIR/CLAUDE.md"
sd 'TITAN_ENGINEER_NAME' "$ENGINEER_NAME" "$CLAUDE_DIR/CLAUDE.md"
ok "CLAUDE.md"

# ─── settings.json — atomic merge (replace what we own, preserve what's theirs) ───
TITAN_PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.cargo/bin:$HOME/go/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Build --inject flags for runtime-detected state
_MERGE_INJECT=()
_MERGE_INJECT+=(--inject "NTFY_TOPIC=")
_MERGE_INJECT+=(--inject "NTFY_URL=https://ntfy.sh")

if ! $CCFLARE_SKIP && command -v better-ccflare &>/dev/null; then
  _MERGE_INJECT+=(--inject "ANTHROPIC_BASE_URL=http://127.0.0.1:${CCFLARE_PORT}")
fi

if ! $LETTA_SKIP && [[ -f "$HOME/.config/letta/credentials" ]]; then
  _LETTA_PASS=$(grep '^LETTA_SERVER_PASSWORD=' "$HOME/.config/letta/credentials" | cut -d= -f2-)
  _MERGE_INJECT+=(--inject "LETTA_BASE_URL=http://127.0.0.1:${LETTA_PORT}")
  _MERGE_INJECT+=(--inject "LETTA_API_KEY=${_LETTA_PASS}")
  _MERGE_INJECT+=(--inject "LETTA_MODEL=anthropic/claude-sonnet-4-6")
  _MERGE_INJECT+=(--inject "LETTA_MODE=whisper")
  _MERGE_INJECT+=(--inject "LETTA_SDK_TOOLS=read-only")
fi

if [[ -n "$SEMGREP_TOKEN" ]] && ! $SEMGREP_SKIP; then
  _MERGE_INJECT+=(--inject "SEMGREP_APP_TOKEN=${SEMGREP_TOKEN}")
fi

if [[ "$CC_NO_AUTOUPDATE" == "true" ]]; then
  _MERGE_INJECT+=(--inject "DISABLE_AUTOUPDATER=1")
fi

# Single atomic merge: template + live + runtime injections → settings.json
python3 "$REPO_FILES/script/merge-settings.py" \
  "$REPO_FILES/dot-claude/settings.json" \
  "$CLAUDE_DIR/settings.json" \
  "$CLAUDE_DIR/settings.json" \
  --engineer "$ENGINEER_NAME" \
  --path "$TITAN_PATH" \
  "${_MERGE_INJECT[@]}" &&
  ok "settings.json (atomic merge)" ||
  {
    if [[ -f "$CLAUDE_DIR/settings.json" ]]; then
      warn "settings.json merge failed — preserving existing user config (fix manually)"
    else
      warn "settings.json merge failed — installing template (no existing config found)"
      install -Dm644 "$REPO_FILES/dot-claude/settings.json" "$CLAUDE_DIR/settings.json"
      sd 'TITAN_ENGINEER_NAME' "$ENGINEER_NAME" "$CLAUDE_DIR/settings.json"
      sd 'TITAN_PATH_PLACEHOLDER' "$TITAN_PATH" "$CLAUDE_DIR/settings.json"
      ok "settings.json (template — first install)"
    fi
  }

# Enable semgrep plugin if token provided (merge handles env var, this handles plugin)
if [[ -n "$SEMGREP_TOKEN" ]] && ! $SEMGREP_SKIP; then
  jq '.enabledPlugins["semgrep@claude-plugins-official"] = true' \
    "$CLAUDE_DIR/settings.json" >/tmp/_cc_settings.json &&
    mv /tmp/_cc_settings.json "$CLAUDE_DIR/settings.json" &&
    ok "settings.json (semgrep plugin enabled)" ||
    warn "semgrep plugin enablement failed"
fi

# RTK global hook — runs after settings.json is written so it appends, not overwrites
if command -v rtk &>/dev/null && rtk gain &>/dev/null 2>&1; then
  run_q rtk init -g --auto-patch && ok "rtk global hook (token compression active)" ||
    warn "rtk init -g failed — run manually: rtk init -g"
fi

# ─── cozempic — context bloat cleaner (global hooks) ───
# Injects hooks directly into ~/.claude/settings.json — NOT via `cozempic init`,
# which writes to cwd/.claude/settings.json (project-scoped = wrong for a global installer).
# Each hook is session/cwd-scoped at runtime: guard gets --session $SESSION_ID from hook
# input; checkpoint uses cwd which CC sets to the project dir when firing hooks.
# No project mixing — fully safe as global hooks.
# Must run AFTER settings.json is fully written (install -Dm644 above would erase hooks).
if ! $COZEMPIC_SKIP && command -v cozempic &>/dev/null; then
  python3 - "$CLAUDE_DIR/settings.json" <<'PYEOF'
import json, sys
f = sys.argv[1]
with open(f) as fh:
    cfg = json.load(fh)

GUARD = (
    'INPUT=$(cat); '
    'SESSION_ID=$(echo "$INPUT" | python3 -c '
    '"import sys,json; print(json.load(sys.stdin).get(\'session_id\',\'\'))" 2>/dev/null); '
    'CTX_WIN=$(echo "$INPUT" | python3 -c '
    '"import sys,json; d=json.load(sys.stdin); '
    'print(d.get(\'context_window\',{}).get(\'context_window_size\',\'\'))" 2>/dev/null); '
    'cozempic guard --daemon --system-overhead-tokens 35000 '
    '${SESSION_ID:+--session $SESSION_ID} '
    '${CTX_WIN:+--context-window $CTX_WIN} '
    '2>/dev/null || true'
)
CKPT = 'cozempic checkpoint 2>/dev/null || true'

hooks = cfg.setdefault('hooks', {})

def has_cmd(arr, kw):
    return any(any(kw in c.get('command','') for c in h.get('hooks',[])) for h in arr if isinstance(h,dict))

def add_hook(arr, matcher, cmd):
    arr.append({'matcher': matcher, 'hooks': [{'type': 'command', 'command': cmd}]})

ss = hooks.setdefault('SessionStart', [])
if not has_cmd(ss, 'cozempic guard'):
    add_hook(ss, '', GUARD)

for ev in ('PreCompact', 'Stop'):
    arr = hooks.setdefault(ev, [])
    if not has_cmd(arr, 'cozempic checkpoint'):
        add_hook(arr, '', CKPT)

ptu = hooks.setdefault('PostToolUse', [])
for m in ('Task', 'TaskCreate|TaskUpdate'):
    if not any(isinstance(h,dict) and h.get('matcher')==m and has_cmd([h],'cozempic checkpoint') for h in ptu):
        add_hook(ptu, m, CKPT)

with open(f, 'w') as fh:
    json.dump(cfg, fh, indent=2)
    fh.write('\n')
PYEOF
  [[ $? -eq 0 ]] &&
    ok "cozempic: hooks wired globally in ~/.claude/settings.json" ||
    warn "cozempic: hook injection failed — run manually from a project dir: cozempic init"

  # Install /cozempic slash command from cozempic's own venv (avoids cozempic init's cwd problem)
  _COZEMPIC_PY="$(dirname "$(command -v cozempic)")/python3"
  if [[ -x "$_COZEMPIC_PY" ]]; then
    _SLASH=$("$_COZEMPIC_PY" -c \
      "import importlib.resources as r; print(r.files('cozempic.data').joinpath('cozempic_slash_command.md'))" \
      2>/dev/null)
    [[ -n "$_SLASH" ]] && install -Dm644 "$_SLASH" "$CLAUDE_DIR/commands/cozempic.md" &&
      ok "cozempic: /cozempic slash command installed"
  fi
fi

# ─── ccstatusline config ───
install -Dm644 "$REPO_FILES/config/ccstatusline/settings.json" "$HOME/.config/ccstatusline/settings.json" &&
  ok "ccstatusline: config" || warn "ccstatusline config (missing from repo)"

# ─── Skills ───
# tool-discovery, security-ops, debug-protocol removed — replaced by better versions:
#   tool-discovery → cli-tools (150 lines, full tool reference)
#   security-ops   → security-scan (39 lines, structured workflows)
#   debug-protocol → systematic-debugging (from superpowers)

install -Dm644 "$REPO_FILES/dot-claude/skills/cli-tools/SKILL.md" "$CLAUDE_DIR/skills/cli-tools/SKILL.md"
ok "skill: cli-tools"

install -Dm644 "$REPO_FILES/dot-claude/skills/security-scan/SKILL.md" "$CLAUDE_DIR/skills/security-scan/SKILL.md"
ok "skill: security-scan"

install -Dm644 "$REPO_FILES/dot-claude/skills/git-workflow/SKILL.md" "$CLAUDE_DIR/skills/git-workflow/SKILL.md"
ok "skill: git-workflow"

install -Dm644 "$REPO_FILES/dot-claude/skills/infra-deploy/SKILL.md" "$CLAUDE_DIR/skills/infra-deploy/SKILL.md"
ok "skill: infra-deploy"

install -Dm644 "$REPO_FILES/dot-claude/skills/add-cli-tool/SKILL.md" "$CLAUDE_DIR/skills/add-cli-tool/SKILL.md"
ok "skill: add-cli-tool"

install -Dm644 "$REPO_FILES/dot-claude/skills/add-cli-tool/references/locations.md" "$CLAUDE_DIR/skills/add-cli-tool/references/locations.md"
ok "skill: add-cli-tool (references)"

# ─── Skill: tmux-control ───
install -Dm644 "$REPO_FILES/dot-claude/skills/tmux-control/SKILL.md" "$CLAUDE_DIR/skills/tmux-control/SKILL.md"
ok "skill: tmux-control"

# ─── Skill: workspace ───
install -Dm644 "$REPO_FILES/dot-claude/skills/workspace/SKILL.md" "$CLAUDE_DIR/skills/workspace/SKILL.md"
ok "skill: workspace"

# ─── Skill: pueue-orchestrator ───
install -Dm644 "$REPO_FILES/dot-claude/skills/pueue-orchestrator/SKILL.md" "$CLAUDE_DIR/skills/pueue-orchestrator/SKILL.md"
ok "skill: pueue-orchestrator"

# ─── Skill: diagrams ───
install -Dm644 "$REPO_FILES/dot-claude/skills/diagrams/SKILL.md" "$CLAUDE_DIR/skills/diagrams/SKILL.md"
ok "skill: diagrams"

# ─── Skill: deploy ───
install -Dm644 "$REPO_FILES/dot-claude/skills/deploy/SKILL.md" "$CLAUDE_DIR/skills/deploy/SKILL.md"
ok "skill: deploy"

# ─── Skill: process-supervisor ───
install -Dm644 "$REPO_FILES/dot-claude/skills/process-supervisor/SKILL.md" "$CLAUDE_DIR/skills/process-supervisor/SKILL.md"
ok "skill: process-supervisor"

# ─── Skill: docker-security ───
install -Dm644 "$REPO_FILES/dot-claude/skills/docker-security/SKILL.md" "$CLAUDE_DIR/skills/docker-security/SKILL.md"
ok "skill: docker-security"

# ─── Skill: vibesec ───
install -Dm644 "$REPO_FILES/dot-claude/skills/vibesec/SKILL.md" "$CLAUDE_DIR/skills/vibesec/SKILL.md"
ok "skill: vibesec"

# ─── Skill: trailofbits-modern-python ───
install -Dm644 "$REPO_FILES/dot-claude/skills/trailofbits-modern-python/SKILL.md" "$CLAUDE_DIR/skills/trailofbits-modern-python/SKILL.md"
ok "skill: trailofbits-modern-python"

# ─── Skill: notebooklm-skills ───
install -Dm644 "$REPO_FILES/dot-claude/skills/notebooklm-skills/SKILL.md" "$CLAUDE_DIR/skills/notebooklm-skills/SKILL.md"
ok "skill: notebooklm-skills"

# ─── Hook Scripts (Memory/Context Management) ───

install -Dm755 "$REPO_FILES/dot-claude/hooks/pre-compact.sh" "$CLAUDE_DIR/hooks/pre-compact.sh"
ok "hook: pre-compact.sh"

install -Dm755 "$REPO_FILES/dot-claude/hooks/session-end.sh" "$CLAUDE_DIR/hooks/session-end.sh"
ok "hook: session-end.sh"

install -Dm755 "$REPO_FILES/dot-claude/hooks/session-start.sh" "$CLAUDE_DIR/hooks/session-start.sh"
ok "hook: session-start.sh"

# ─── CC Thinking Patcher (auto-patches after CC updates) ───
install -Dm755 "$REPO_FILES/dot-claude/bin/cc-patch-thinking" "$HOME/.local/bin/cc-patch-thinking"
ok "bin: cc-patch-thinking"

# UserPromptSubmit: inject memory only when recall-intent keywords detected (zero tokens otherwise)
install -Dm755 "$REPO_FILES/dot-claude/hooks/prompt-memory-inject.sh" "$CLAUDE_DIR/hooks/prompt-memory-inject.sh"
ok "hook: prompt-memory-inject.sh"

# ─── Status Line Script ───
install -Dm755 "$REPO_FILES/dot-claude/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
# If ccstatusline is installed, use it directly; else fall back to statusline-command.sh
if command -v ccstatusline &>/dev/null; then
  jq '.statusLine = {"type": "command", "command": "ccstatusline", "padding": 0}' \
    "$CLAUDE_DIR/settings.json" >/tmp/_cc_settings.json &&
    mv /tmp/_cc_settings.json "$CLAUDE_DIR/settings.json"
  ok "statusline: ccstatusline (native)"
else
  ok "statusline: statusline-command.sh (fallback)"
fi

# ─── .claudeignore Template ───

install -Dm644 "$REPO_FILES/dot-claude/claudeignore-template" "$CLAUDE_DIR/claudeignore-template"
ok "template: claudeignore-template"

# ─── Conditional Rules ───

install -Dm644 "$REPO_FILES/dot-claude/rules/python.md" "$CLAUDE_DIR/rules/python.md"
ok "rule: python.md"

install -Dm644 "$REPO_FILES/dot-claude/rules/shell.md" "$CLAUDE_DIR/rules/shell.md"
ok "rule: shell.md"

install -Dm644 "$REPO_FILES/dot-claude/rules/terraform.md" "$CLAUDE_DIR/rules/terraform.md"
ok "rule: terraform.md"

install -Dm644 "$REPO_FILES/dot-claude/rules/docker.md" "$CLAUDE_DIR/rules/docker.md"
ok "rule: docker.md"

# security.md and memory.md removed — content already in global CLAUDE.md
rm -f "$CLAUDE_DIR/rules/security.md" "$CLAUDE_DIR/rules/memory.md"

install -Dm644 "$REPO_FILES/dot-claude/rules/skill-authoring.md" "$CLAUDE_DIR/rules/skill-authoring.md"
ok "rule: skill-authoring.md"

# ─── /recall command ───
install -Dm644 "$REPO_FILES/dot-claude/commands/recall.md" "$CLAUDE_DIR/commands/recall.md"
ok "command: /recall"

# ─── /remember command ───
install -Dm644 "$REPO_FILES/dot-claude/commands/remember.md" "$CLAUDE_DIR/commands/remember.md"
ok "command: /remember"

# ── Parallel git clones for external skills (saves ~15s vs sequential) ──────
_NEED_SUPERPOWERS=false
_NEED_VIBESEC=false
_NEED_TRAILOFBITS=false
[ ! -d "$CLAUDE_DIR/skills/tdd" ] && _NEED_SUPERPOWERS=true
[ ! -d "$CLAUDE_DIR/skills/vibesec" ] && _NEED_VIBESEC=true
[ ! -d "$CLAUDE_DIR/skills/trailofbits-modern-python" ] && _NEED_TRAILOFBITS=true

if $_NEED_SUPERPOWERS || $_NEED_VIBESEC || $_NEED_TRAILOFBITS; then
  $_NEED_SUPERPOWERS && git clone --depth 1 https://github.com/obra/superpowers.git /tmp/superpowers 2>/dev/null &
  _SP1=$!
  $_NEED_VIBESEC && git clone --depth 1 https://github.com/BehiSecc/VibeSec-Skill.git "$CLAUDE_DIR/skills/vibesec" 2>/dev/null &
  _SP2=$!
  $_NEED_TRAILOFBITS && git clone --depth 1 https://github.com/trailofbits/skills.git /tmp/trailofbits-skills 2>/dev/null &
  _SP3=$!
  wait "$_SP1" "$_SP2" "$_SP3" 2>/dev/null || true
fi

# obra/superpowers (multiple useful skills)
if $_NEED_SUPERPOWERS; then
  if [ -d "/tmp/superpowers/skills" ]; then
    cp -r /tmp/superpowers/skills/test-driven-development "$CLAUDE_DIR/skills/tdd" 2>/dev/null || true
    cp -r /tmp/superpowers/skills/systematic-debugging "$CLAUDE_DIR/skills/systematic-debugging" 2>/dev/null || true
    cp -r /tmp/superpowers/skills/brainstorming "$CLAUDE_DIR/skills/brainstorming" 2>/dev/null || true
    cp -r /tmp/superpowers/skills/verification-before-completion "$CLAUDE_DIR/skills/verification-before-completion" 2>/dev/null || true
    cp -r /tmp/superpowers/skills/writing-plans "$CLAUDE_DIR/skills/writing-plans" 2>/dev/null || true
    # Add paths scoping to large skills so they don't load on every session (bug #14882)
    if [ -f "$CLAUDE_DIR/skills/tdd/SKILL.md" ] && ! grep -q '^paths:' "$CLAUDE_DIR/skills/tdd/SKILL.md" 2>/dev/null; then
      sed -i '3a paths: "**/*.py,**/*.js,**/*.ts,**/*.jsx,**/*.tsx,**/*.go,**/*.rs,**/*.java,**/*.cpp,**/*.c,**/*.rb,**/test*,**/spec*,**/*_test*,**/*_spec*,**/pytest.ini,**/jest.config*,**/go.mod"' "$CLAUDE_DIR/skills/tdd/SKILL.md"
    fi
    if [ -f "$CLAUDE_DIR/skills/systematic-debugging/SKILL.md" ] && ! grep -q '^paths:' "$CLAUDE_DIR/skills/systematic-debugging/SKILL.md" 2>/dev/null; then
      sed -i '3a paths: "**/*.py,**/*.js,**/*.ts,**/*.go,**/*.rs,**/*.java,**/*.sh,**/*.bash,**/*.cpp,**/*.c,**/*.rb,**/Makefile,**/CMakeLists.txt"' "$CLAUDE_DIR/skills/systematic-debugging/SKILL.md"
    fi
    if [ -f "$CLAUDE_DIR/skills/brainstorming/SKILL.md" ] && ! grep -q '^paths:' "$CLAUDE_DIR/skills/brainstorming/SKILL.md" 2>/dev/null; then
      sed -i '3a paths: "**/_scratchpad*,**/_plan*,**/spec*,**/*.spec.md,**/brainstorm*"' "$CLAUDE_DIR/skills/brainstorming/SKILL.md"
    fi
    if [ -f "$CLAUDE_DIR/skills/verification-before-completion/SKILL.md" ] && ! grep -q '^paths:' "$CLAUDE_DIR/skills/verification-before-completion/SKILL.md" 2>/dev/null; then
      sed -i '3a paths: "**/*.py,**/*.js,**/*.ts,**/*.go,**/*.sh,**/*.rs,**/test*,**/spec*,**/Makefile"' "$CLAUDE_DIR/skills/verification-before-completion/SKILL.md"
    fi
    if [ -f "$CLAUDE_DIR/skills/writing-plans/SKILL.md" ] && ! grep -q '^paths:' "$CLAUDE_DIR/skills/writing-plans/SKILL.md" 2>/dev/null; then
      sed -i '3a paths: "**/_scratchpad*,**/_plan*,**/spec*,**/plan*,**/*.spec.md"' "$CLAUDE_DIR/skills/writing-plans/SKILL.md"
    fi
    ok "superpowers skills"
  else
    warn "superpowers clone failed"
  fi
  rm -rf /tmp/superpowers
else
  ok "superpowers skills (exist)"
fi

# Security skills
if $_NEED_VIBESEC; then
  [ -d "$CLAUDE_DIR/skills/vibesec" ] && ok "vibesec" || warn "vibesec"
else ok "vibesec (exists)"; fi
# Add paths scoping to vibesec (758 lines — only load for web/security files)
if [ -f "$CLAUDE_DIR/skills/vibesec/SKILL.md" ] && ! grep -q '^paths:' "$CLAUDE_DIR/skills/vibesec/SKILL.md" 2>/dev/null; then
  sed -i '3a paths: "**/*.html,**/*.htm,**/*.js,**/*.ts,**/*.jsx,**/*.tsx,**/*.vue,**/*.svelte,**/*.py,**/routes*,**/auth*,**/views*,**/controllers*,**/api*,**/nginx*,**/Dockerfile*,**/docker-compose*"' "$CLAUDE_DIR/skills/vibesec/SKILL.md"
fi

# Trail of Bits — selective install (modern-python only, not the full 60-skill repo)
# Full clone was 71K lines / 60 SKILL.md files — most never triggered (blockchain, fuzzing, etc.)
# Individual plugins can be installed on-demand via: claude plugin marketplace add trailofbits/skills
if $_NEED_TRAILOFBITS; then
  if [ -d /tmp/trailofbits-skills/plugins/modern-python ]; then
    cp -r /tmp/trailofbits-skills/plugins/modern-python "$CLAUDE_DIR/skills/trailofbits-modern-python" 2>/dev/null && ok "trailofbits: modern-python" || warn "trailofbits: modern-python"
  else
    warn "trailofbits: modern-python not found in repo"
  fi
  rm -rf /tmp/trailofbits-skills
else ok "trailofbits: modern-python (exists)"; fi
# Fix SKILL.md path: plugin structure nests SKILL.md under skills/modern-python/, Claude expects root
# Also add paths scoping so it only loads for Python files
if [ -f "$CLAUDE_DIR/skills/trailofbits-modern-python/skills/modern-python/SKILL.md" ] &&
  [ ! -f "$CLAUDE_DIR/skills/trailofbits-modern-python/SKILL.md" ]; then
  sed '3a paths: "**/*.py,**/pyproject.toml,**/setup.py,**/setup.cfg,**/requirements*.txt,**/.python-version,**/uv.lock,**/Pipfile*"' \
    "$CLAUDE_DIR/skills/trailofbits-modern-python/skills/modern-python/SKILL.md" \
    >"$CLAUDE_DIR/skills/trailofbits-modern-python/SKILL.md"
  ok "trailofbits: SKILL.md fixed at root with paths scoping"
elif [ -f "$CLAUDE_DIR/skills/trailofbits-modern-python/SKILL.md" ] && ! grep -q '^paths:' "$CLAUDE_DIR/skills/trailofbits-modern-python/SKILL.md" 2>/dev/null; then
  sed -i '3a paths: "**/*.py,**/pyproject.toml,**/setup.py,**/setup.cfg,**/requirements*.txt,**/.python-version,**/uv.lock,**/Pipfile*"' \
    "$CLAUDE_DIR/skills/trailofbits-modern-python/SKILL.md"
fi
# Remove duplicate nested SKILL.md — root copy has correct paths: scoping; nested is always-on (bug)
rm -f "$CLAUDE_DIR/skills/trailofbits-modern-python/skills/modern-python/SKILL.md" 2>/dev/null || true

# Cleanup: remove full trailofbits/hashicorp clones from previous installs (token bloat)
# These dumped 60+14 SKILL.md files into context at startup (~81K lines)
if [ -d "$CLAUDE_DIR/skills/trailofbits" ]; then
  rm -rf "$CLAUDE_DIR/skills/trailofbits"
  ok "removed old trailofbits full clone (60 skills → 1 selective)"
fi
if [ -d "$CLAUDE_DIR/skills/hashicorp" ]; then
  rm -rf "$CLAUDE_DIR/skills/hashicorp"
  ok "removed old hashicorp full clone (14 skills → covered by infra-deploy)"
fi

# ─── Commands ───
install -Dm644 "$REPO_FILES/dot-claude/commands/catchup.md" "$CLAUDE_DIR/commands/catchup.md"
ok "command: /catchup"

install -Dm644 "$REPO_FILES/dot-claude/commands/handoff.md" "$CLAUDE_DIR/commands/handoff.md"
ok "command: /handoff"

install -Dm644 "$REPO_FILES/dot-claude/commands/ship.md" "$CLAUDE_DIR/commands/ship.md"
ok "command: /ship"

install -Dm644 "$REPO_FILES/dot-claude/commands/standup.md" "$CLAUDE_DIR/commands/standup.md"
ok "command: /standup"

install -Dm644 "$REPO_FILES/dot-claude/commands/scan.md" "$CLAUDE_DIR/commands/scan.md"
ok "command: /scan"

install -Dm644 "$REPO_FILES/dot-claude/commands/review.md" "$CLAUDE_DIR/commands/review.md"
ok "command: /review"

install -Dm644 "$REPO_FILES/dot-claude/commands/tools.md" "$CLAUDE_DIR/commands/tools.md"
ok "command: /tools"

install -Dm644 "$REPO_FILES/dot-claude/commands/workspace-init.md" "$CLAUDE_DIR/commands/workspace-init.md"
ok "command: /workspace-init"

install -Dm644 "$REPO_FILES/dot-claude/commands/pack.md" "$CLAUDE_DIR/commands/pack.md"
ok "command: /pack"

# ─── GitHub Actions Template ───
install -Dm644 "$REPO_FILES/dot-claude/templates/claude-code-action.yml" "$CLAUDE_DIR/templates/claude-code-action.yml"
ok "template: claude-code-action.yml"

install -Dm644 "$REPO_FILES/dot-claude/commands/gh-action.md" "$CLAUDE_DIR/commands/gh-action.md"
ok "command: /gh-action"

# ─── Agents ───
install -Dm644 "$REPO_FILES/dot-claude/agents/researcher.md" "$CLAUDE_DIR/agents/researcher.md"
ok "agent: researcher"

install -Dm644 "$REPO_FILES/dot-claude/agents/planner.md" "$CLAUDE_DIR/agents/planner.md"
ok "agent: planner"

install -Dm644 "$REPO_FILES/dot-claude/agents/reviewer.md" "$CLAUDE_DIR/agents/reviewer.md"
ok "agent: reviewer"

# ─── On-Demand Agent Slots (slot-1..5) ───
for _slot_i in 1 2 3 4 5; do
  case $_slot_i in 1 | 2 | 3) _slot_model="haiku" ;; 4) _slot_model="sonnet" ;; 5) _slot_model="opus" ;; esac
  _slot_i="$_slot_i" _slot_model="$_slot_model" \
    envsubst '$_slot_i $_slot_model' \
    <"$REPO_FILES/dot-claude/agents/slot-template.md" \
    >"$CLAUDE_DIR/agents/slot-${_slot_i}.md"
  ok "agent: slot-${_slot_i} [${_slot_model}]"
done
# Clean up stale slots from previous installs (was 10, now 5)
rm -f "$CLAUDE_DIR/agents"/slot-{6,7,8,9,10}.md
unset _slot_i _slot_model

# ─── agt config ───
install -Dm644 "$REPO_FILES/config/agt/config" "$HOME/.config/agt/config"
ok "agt: config"

# ─── agt CLI ───
install -Dm755 "$REPO_FILES/bin/agt" "$HOME/.local/bin/agt"
ok "agt: CLI installed"

# ─── Agent stash: clone or update from GitHub ───
AGT_STASH_REPO="https://github.com/SutanuNandigrami/agent-stash.git"
AGT_STASH_DIR="$CLAUDE_DIR/agent-stash"
if [[ -d "$AGT_STASH_DIR/.git" ]]; then
  git -C "$AGT_STASH_DIR" pull --ff-only 2>/dev/null && ok "agent-stash: updated from GitHub" || warn "agent-stash: pull failed (using existing)"
else
  rm -rf "$AGT_STASH_DIR"
  git clone --depth 1 "$AGT_STASH_REPO" "$AGT_STASH_DIR" 2>/dev/null && ok "agent-stash: cloned from GitHub" || warn "agent-stash: clone failed"
fi
mkdir -p "$AGT_STASH_DIR/_loaded"
touch "$AGT_STASH_DIR/_loaded/.lock" "$AGT_STASH_DIR/_loaded/.manifest"
"$HOME/.local/bin/agt" build-index 2>/dev/null && ok "agent-stash: index built" || warn "agent-stash: index build failed"

# ─── Cron: weekly agent stash refresh ───
(
  crontab -l 2>/dev/null | grep -v 'agt build-index\|agt-refresh' || true
  echo "0 3 * * 0 cd \$HOME/.claude/agent-stash && git pull --ff-only 2>/dev/null && \$HOME/.local/bin/agt build-index >> \$HOME/.claude/logs/agt-refresh.log 2>&1"
) | crontab -
ok "cron: weekly agent-stash refresh (Sun 03:00)"

# CLIProxyAPI — proxy server for AI coding tools (clone, not a CLI install)
if [ ! -d ~/tools/CLIProxyAPI ]; then
  mkdir -p ~/tools
  git clone --depth 1 https://github.com/router-for-me/CLIProxyAPI.git ~/tools/CLIProxyAPI 2>/dev/null && ok "CLIProxyAPI (cloned to ~/tools/)" || warn "CLIProxyAPI"
else ok "CLIProxyAPI (exists)"; fi
# ─── Phase 5b — Claude Code Plugins ───
section "Phase 5b — Claude Code Plugins"
echo "  Installing official and community plugins..."

# claude auth login is broken over SSH (Enter doesn't register — upstream bug)
# Skip inline auth; plugins are installed below only if already authenticated.
# After setup: run 'claude auth login' from a fresh terminal prompt (not inside
# a script), then re-run plugin installs with: claude plugin install code-review
if command -v claude &>/dev/null && ! claude auth status &>/dev/null 2>&1; then
  warn "Claude not authenticated — plugins will be skipped"
  echo "  After setup, run 'claude auth login' then:"
  echo "    claude plugin marketplace add anthropic/claude-plugins-official"
  echo "    claude plugin install code-review skill-creator"
  echo "    claude plugin marketplace add obra/superpowers-marketplace"
  echo "    claude plugin install episodic-memory"
fi

if ! command -v claude &>/dev/null; then
  warn "Claude CLI not found — skipping plugins"
elif ! claude auth status &>/dev/null 2>&1; then
  warn "Claude not authenticated — skipping plugins (run 'claude auth login' then re-run)"
else
  # Register official marketplace if not already registered
  claude plugin marketplace add anthropic/claude-plugins-official 2>/dev/null \
    && ok "official marketplace" || ok "official marketplace (exists)"

  # Install plugins from official marketplace
  claude plugin install code-review 2>/dev/null && ok "code-review" || warn "code-review"
  claude plugin install skill-creator 2>/dev/null && ok "skill-creator" || warn "skill-creator"

  # playwright MCP — Microsoft's official browser automation MCP server (@playwright/mcp)
  # Provides 22 deferred tools (browser_navigate, browser_click, browser_snapshot, etc.)
  # Uses ref-based accessibility tree for deterministic element targeting — no fragile CSS selectors
  # Requires playwright + chromium (already installed via bun in Phase 4)
  # Token cost: ~300 tokens at startup (deferred tool names), ~2.7K when tools are fetched on first use
  # NOTE: Do NOT remove — this is intentionally an MCP plugin, not a CLI replacement.
  # Playwright CLI (installed in lib/07) handles E2E testing; MCP plugin handles AI-driven browser automation.
  claude plugin install playwright 2>/dev/null && ok "playwright MCP" || warn "playwright MCP"

  # semgrep plugin — only if token was provided
  if [[ -n "$SEMGREP_TOKEN" ]] && ! $SEMGREP_SKIP; then
    if claude plugin install semgrep 2>/dev/null; then
      ok "semgrep plugin"
      # Remove semgrep's UserPromptSubmit hook — injects ~500 tokens of static
      # "Secure-by-Default Libraries" text on EVERY prompt. Wasteful and errors out.
      # Keep PostToolUse (scan on edit) and SessionStart (one-time defaults).
      _sg_hooks=$(find "$HOME/.claude/plugins/cache" -path "*/semgrep/*/hooks/hooks.json" 2>/dev/null | head -1)
      if [[ -n "$_sg_hooks" ]] && jq -e '.hooks.UserPromptSubmit' "$_sg_hooks" &>/dev/null; then
        jq 'del(.hooks.UserPromptSubmit)' "$_sg_hooks" > "${_sg_hooks}.tmp" \
          && mv "${_sg_hooks}.tmp" "$_sg_hooks" \
          && ok "semgrep: removed UserPromptSubmit hook (~500 tokens/prompt saved)"
      fi
      # Patch semgrep hooks.json to guard against non-git-repo dirs
      # semgrep ci requires a git root; without this guard, every Write/Edit outside a repo fails
      _SEMGREP_HOOKS=$(find "$CLAUDE_DIR/plugins/cache" -path '*/semgrep/*/hooks/hooks.json' | head -1)
      if [[ -f "$_SEMGREP_HOOKS" ]]; then
        jq '(.hooks.PostToolUse[].hooks[].command) |= "git rev-parse --git-dir &>/dev/null && " + . + " || true"' \
          "$_SEMGREP_HOOKS" > ${WORKDIR}/_semgrep_hooks.json \
          && mv ${WORKDIR}/_semgrep_hooks.json "$_SEMGREP_HOOKS" \
          && ok "semgrep: hooks patched (git-repo guard added)" \
          || warn "semgrep hooks patch failed"
      fi
    else
      warn "semgrep plugin"
    fi
  fi

  # episodic-memory — semantic search over past Claude Code sessions (~200 tokens/session)
  # Free, MIT, no subscription. Local embeddings via @xenova/transformers (no API key needed).
  claude plugin marketplace add obra/superpowers-marketplace 2>/dev/null \
    && ok "superpowers marketplace" || ok "superpowers marketplace (exists)"
  claude plugin install episodic-memory 2>/dev/null && ok "episodic-memory plugin" || warn "episodic-memory plugin"

  # cozempic plugin — context diagnose/treat MCP tools (diagnose_current, treat_session)
  # CLI (uv) provides the primary interface; plugin adds MCP tools for in-session diagnostics
  if ! $COZEMPIC_SKIP; then
    claude plugin marketplace add Ruya-AI/cozempic 2>/dev/null \
      && ok "cozempic marketplace" || ok "cozempic marketplace (exists)"
    claude plugin install cozempic 2>/dev/null && ok "cozempic plugin" || warn "cozempic plugin"
  fi

  # claude-subconscious — Letta-based persistent cross-session memory agent
  if ! $LETTA_SKIP; then
    claude plugin marketplace add letta-ai/claude-subconscious 2>/dev/null \
      && ok "letta marketplace" || ok "letta marketplace (exists)"
    if claude plugin install claude-subconscious 2>/dev/null; then
      ok "claude-subconscious plugin"

      # Install node_modules (tsx + @letta-ai/letta-code-sdk) — CC does not auto-install plugin deps
      _SUBCON_DIR=$(jq -r '.plugins["claude-subconscious@claude-subconscious"][0].installPath // empty' \
        "$CLAUDE_DIR/plugins/installed_plugins.json" 2>/dev/null)
      if [[ -n "$_SUBCON_DIR" ]] && [[ -f "$_SUBCON_DIR/package.json" ]]; then
        (cd "$_SUBCON_DIR" && npm install --silent 2>/dev/null) \
          && ok "subconscious: node_modules installed" \
          || warn "subconscious: npm install failed — hooks may not work"
      fi

      # Patch Subconscious.af: override LLM + embedding to use self-hosted Letta infrastructure
      # Default .af uses openai/text-embedding-3-small and zai/glm-5 (cloud only)
      _SUBCON_AF=""
      if [[ -f "$CLAUDE_DIR/plugins/installed_plugins.json" ]]; then
        _SUBCON_INSTALL=$(jq -r '.plugins["claude-subconscious@claude-subconscious"][0].installPath // empty' \
          "$CLAUDE_DIR/plugins/installed_plugins.json" 2>/dev/null)
        [[ -n "$_SUBCON_INSTALL" ]] && _SUBCON_AF="$_SUBCON_INSTALL/Subconscious.af"
      fi

      if [[ -f "$_SUBCON_AF" ]]; then
        # Patch LLM config: use ccflare billing proxy if available, else direct Anthropic
        # Check bun + proxy file (billing proxy was migrated from socat to Bun)
        if ! $CCFLARE_SKIP && command -v bun &>/dev/null \
            && [[ -f "$HOME/.config/letta/ccflare-billing-proxy.js" ]]; then
          _SUBCON_LLM_ENDPOINT="http://host.docker.internal:${CCFLARE_PROXY_PORT}"
        else
          _SUBCON_LLM_ENDPOINT="https://api.anthropic.com/v1"
        fi
        # Use Sonnet via billing-header proxy (ccflare-billing-proxy injects required header)
        jq --arg ep "$_SUBCON_LLM_ENDPOINT" '
          .agents[0].llm_config.model = "claude-sonnet-4-6" |
          .agents[0].llm_config.model_endpoint_type = "anthropic" |
          .agents[0].llm_config.model_endpoint = $ep |
          .agents[0].llm_config.provider_name = "anthropic" |
          .agents[0].llm_config.handle = "anthropic/claude-sonnet-4-6" |
          .agents[0].llm_config.context_window = 200000
        ' "$_SUBCON_AF" > ${WORKDIR}/_subcon_af.json \
          && mv ${WORKDIR}/_subcon_af.json "$_SUBCON_AF" \
          && ok "subconscious: .af patched (LLM → claude-sonnet-4-6 via ${_SUBCON_LLM_ENDPOINT})" \
          || warn "subconscious: .af LLM patch failed"

        # Patch embedding config: use host.docker.internal (Letta runs in Docker, must reach host Ollama)
        if ! $OLLAMA_SKIP && command -v ollama &>/dev/null; then
          jq '
            .agents[0].embedding_config.embedding_endpoint_type = "ollama" |
            .agents[0].embedding_config.embedding_endpoint = "http://host.docker.internal:11434/v1" |
            .agents[0].embedding_config.embedding_model = "nomic-embed-text" |
            .agents[0].embedding_config.embedding_dim = 768 |
            .agents[0].embedding_config.handle = "ollama/nomic-embed-text"
          ' "$_SUBCON_AF" > ${WORKDIR}/_subcon_af.json \
            && mv ${WORKDIR}/_subcon_af.json "$_SUBCON_AF" \
            && ok "subconscious: .af patched (embeddings → ollama/nomic-embed-text)" \
            || warn "subconscious: .af embedding patch failed"
        fi
      else
        warn "subconscious: Subconscious.af not found — .af patching skipped"
      fi

      # Enable plugin in settings.json
      jq '.enabledPlugins["claude-subconscious@claude-subconscious"] = true' \
        "$CLAUDE_DIR/settings.json" > ${WORKDIR}/_cc_settings.json \
        && mv ${WORKDIR}/_cc_settings.json "$CLAUDE_DIR/settings.json" \
        && ok "subconscious: enabled in settings.json" \
        || warn "subconscious: settings.json update failed"
    else
      warn "claude-subconscious plugin install failed"
    fi
  fi

fi
# ── end claude auth guard ──

# ─── LettaCtrl GUI — web dashboard for Letta management ───
# NOTE: runs outside claude auth guard — letta-ctrl is standalone (no Claude auth needed)
if $LETTA_SKIP || $LETTA_CTRL_SKIP; then
  ok "LettaCtrl GUI (skipped)"
else
  _BUN_BIN=$(command -v bun 2>/dev/null || echo "$HOME/.local/bin/bun")
  if [[ ! -x "$_BUN_BIN" ]]; then
    warn "LettaCtrl: bun not found — skipping"
    LETTA_CTRL_SKIP=true
  else
    mkdir -p "$HOME/.config/letta"

    # Write server
    install -Dm644 "$REPO_FILES/config/letta/letta-ctrl-server.js" "$HOME/.config/letta/letta-ctrl-server.js"

    # Write frontend
    install -Dm644 "$REPO_FILES/config/letta/letta-ctrl.html" "$HOME/.config/letta/letta-ctrl.html"

    # Systemd user service
    mkdir -p "$HOME/.config/systemd/user"
    cat >"$HOME/.config/systemd/user/letta-ctrl.service" <<LETTA_CTRL_SVC
[Unit]
Description=LettaCtrl — Letta management GUI
After=letta.service

[Service]
Type=simple
ExecStart=${_BUN_BIN} run %h/.config/letta/letta-ctrl-server.js
Environment="LETTA_CTRL_PORT=${LETTA_CTRL_PORT}"
Environment="LETTA_BASE_URL=http://127.0.0.1:${LETTA_PORT}"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
LETTA_CTRL_SVC

    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable letta-ctrl 2>/dev/null || true
    systemctl --user restart letta-ctrl 2>/dev/null || true

    # Health check
    for _ci in $(seq 1 6); do
      curl -sf "http://127.0.0.1:${LETTA_CTRL_PORT}/" &>/dev/null && break
      sleep 2
    done
    if curl -sf "http://127.0.0.1:${LETTA_CTRL_PORT}/" &>/dev/null; then
      ok "LettaCtrl GUI (http://127.0.0.1:${LETTA_CTRL_PORT})"
    else
      warn "LettaCtrl: server did not start — check: journalctl --user -u letta-ctrl"
    fi
  fi
fi
# Patch plugin SKILL.md files with paths: scoping — plugin updates may clear these, so re-patch after install
# This prevents skill-creator/episodic-memory from loading on every turn (93% token reduction)
if command -v claude &>/dev/null && claude auth status &>/dev/null 2>&1; then
  _patch_plugin_skill() {
    local plugin_key="$1" subpath="$2" paths_value="$3"
    local install_path
    install_path=$(jq -r --arg k "$plugin_key" '.plugins[$k][0].installPath // empty' \
      "$CLAUDE_DIR/plugins/installed_plugins.json" 2>/dev/null)
    [[ -z "$install_path" ]] && return 0
    local skill_md="$install_path/$subpath"
    [[ -f "$skill_md" ]] || return 0
    if ! grep -q '^paths:' "$skill_md" 2>/dev/null; then
      sed -i "2a paths: ${paths_value}" "$skill_md" 2>/dev/null && ok "patched: $plugin_key SKILL.md" || true
    fi
  }
  _patch_plugin_skill "skill-creator@claude-plugins-official" \
    "skills/skill-creator/SKILL.md" \
    '["**/.claude/**", "**/skills/**", "**/SKILL.md", "**/CLAUDE.md"]'
  _patch_plugin_skill "episodic-memory@superpowers-marketplace" \
    "skills/remembering-conversations/SKILL.md" \
    '["**/memory/**", "**/.claude/memory/**", "**/handoff*", "**/_scratchpad*"]'
  # cozempic SKILL.md — detect key dynamically (format: cozempic@<marketplace-owner>)
  if ! $COZEMPIC_SKIP; then
    _COZEMPIC_KEY=$(jq -r '.plugins | keys[] | select(startswith("cozempic"))' \
      "$CLAUDE_DIR/plugins/installed_plugins.json" 2>/dev/null | head -1)
    [[ -n "$_COZEMPIC_KEY" ]] &&
      _patch_plugin_skill "$_COZEMPIC_KEY" \
        "skills/cozempic/SKILL.md" \
        '["**/.claude/**", "**/*.jsonl", "**/cozempic*"]'
  fi

  # Cleanup: remove non-installed plugin dirs from marketplace cache to prevent SKILL.md bloat
  # Each marketplace add can bring many plugin dirs; only keep what's actually installed
  INSTALLED_JSON="$CLAUDE_DIR/plugins/installed_plugins.json"
  if [[ -f "$INSTALLED_JSON" ]]; then
    CACHE_ROOT="$CLAUDE_DIR/plugins/cache"
    mapfile -t ACTIVE_PATHS < <(jq -r '.plugins | to_entries[] | .value[] | .installPath // empty' "$INSTALLED_JSON" 2>/dev/null)
    if [[ ${#ACTIVE_PATHS[@]} -eq 0 ]]; then
      warn "plugin cache cleanup skipped — no active plugins found (jq may have failed)"
    elif [[ -d "$CACHE_ROOT" ]]; then
      while IFS= read -r -d '' vpath; do
        vpath="${vpath%/}"
        is_active=false
        for ap in "${ACTIVE_PATHS[@]}"; do
          [[ "$ap" == "$vpath" ]] && {
            is_active=true
            break
          }
        done
        if ! $is_active; then
          rm -rf "$vpath" 2>/dev/null || true
        fi
      done < <(find "$CACHE_ROOT" -mindepth 3 -maxdepth 3 -type d -print0 2>/dev/null)
      ok "plugin cache: removed stale versions"
    fi
  fi
fi
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
# ─── VPS — Tailscale + finalize ───
if [[ "$INSTALL_MODE" == "vps" ]]; then
  # ── Tailscale — install, connect, lock SSH ─────────────────────────────
  if ! command -v tailscale &>/dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sudo bash >>"$LOG_FILE" 2>&1 &&
      ok "Tailscale installed" || warn "Tailscale install failed"
  fi
  # --reset ensures idempotent re-runs; --operator grants non-root user access
  if sudo tailscale up --authkey="$TAILSCALE_KEY" --ssh --accept-routes --accept-dns \
    --operator="$USER" --reset 2>&1; then
    ok "Tailscale connected"
  else
    warn "Tailscale auth failed — key may be expired/invalid. Run manually after setup:"
    warn "  sudo tailscale up --authkey=YOUR_KEY --ssh --accept-routes --accept-dns --operator=$USER --reset"
    # Skip SSH lockdown to Tailscale since Tailscale isn't connected
    _TAILSCALE_FAILED=true
  fi

  if [[ "${_TAILSCALE_FAILED:-}" != "true" ]]; then
    # Wait for Tailscale IP (up to 60s)
    TS_IP=""
    for _i in $(seq 1 30); do
      TS_IP=$(tailscale ip -4 2>/dev/null || true)
      [[ -n "$TS_IP" ]] && break
      sleep 2
    done
    if [[ -z "$TS_IP" ]]; then
      warn "Tailscale connected but no IPv4 assigned — skipping SSH lockdown"
      _TAILSCALE_FAILED=true
    fi
  fi

  # ── Apply deferred SSH hardening ────────────────────────────────────
  # Both config changes AND reload are deferred from lib/04-vps-harden.sh
  # to here. Writing sshd_config earlier is unsafe because apt package
  # installs trigger dpkg postinst hooks that restart sshd, which would
  # pick up the hardened config and lock out password-based SSH before
  # Tailscale provides alternative access (--ssh flag above).
  if [[ "${_TAILSCALE_FAILED:-}" != "true" ]]; then
    sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sudo sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
    for _dropin in /etc/ssh/sshd_config.d/*.conf; do
      [[ -f "$_dropin" ]] || continue
      sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$_dropin"
      sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$_dropin"
    done
    sudo systemctl reload ssh 2>/dev/null || sudo systemctl reload sshd 2>/dev/null || true
    ok "SSH hardened (password auth off, root login disabled, MaxAuthTries 3)"
  else
    warn "SSH hardening SKIPPED — Tailscale not connected (would lock out all access)"
    warn "  Run tailscale up first, then: sudo titan-setup.sh --mode vps (re-run is safe)"
  fi

  if [[ "${_TAILSCALE_FAILED:-}" != "true" ]]; then
    # Get MagicDNS hostname for service URLs
    TS_HOSTNAME=$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty' | sed 's/\.$//')

    # ── tailscale serve — expose local services on Tailscale network ───────
    if command -v docker &>/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q n8n; then
      tailscale serve --bg --https=5678 http://localhost:5678 2>/dev/null &&
        ok "tailscale serve: n8n → https://${TS_HOSTNAME}:5678" ||
        warn "tailscale serve for n8n failed — run: tailscale serve --https=5678 http://localhost:5678"
    elif command -v docker &>/dev/null; then
      ok "tailscale serve: n8n skipped (container not running — run tailscale serve manually once n8n starts)"
    fi
    if ! $CCFLARE_SKIP; then
      tailscale serve --bg --https="${CCFLARE_PORT}" "http://localhost:${CCFLARE_PORT}" 2>/dev/null &&
        ok "tailscale serve: ccflare → https://${TS_HOSTNAME}:${CCFLARE_PORT}" ||
        warn "tailscale serve for ccflare failed — run: tailscale serve --https=${CCFLARE_PORT} http://localhost:${CCFLARE_PORT}"
    fi
    if ! $LETTA_SKIP; then
      tailscale serve --bg --https="${LETTA_PORT}" "http://localhost:${LETTA_PORT}" 2>/dev/null &&
        ok "tailscale serve: letta → https://${TS_HOSTNAME}:${LETTA_PORT}" ||
        warn "tailscale serve for letta failed — run: tailscale serve --https=${LETTA_PORT} http://localhost:${LETTA_PORT}"
    fi
    if ! $LETTA_CTRL_SKIP && ! $LETTA_SKIP; then
      tailscale serve --bg --https="${LETTA_CTRL_PORT}" "http://localhost:${LETTA_CTRL_PORT}" 2>/dev/null &&
        ok "tailscale serve: letta-ctrl → https://${TS_HOSTNAME}:${LETTA_CTRL_PORT}" ||
        warn "tailscale serve for letta-ctrl failed — run: tailscale serve --https=${LETTA_CTRL_PORT} http://localhost:${LETTA_CTRL_PORT}"
    fi
  fi

  # ── Add Claude user to docker group ────────────────────────────────────
  command -v docker &>/dev/null && sudo usermod -aG docker "$CLAUDE_USER" || true
  ok "$CLAUDE_USER: docker group membership ensured"

  # ── Lock root account ──────────────────────────────────────────────────
  sudo passwd -l root
  ok "Root account locked"

fi

# ── VPS: allow SSH on Tailscale + capture compliance (non-destructive) ─────
# Public port 22 deletion and sshd restart happen LAST (after all output)
# so the current SSH session stays alive through the entire install.
if [[ "$INSTALL_MODE" == "vps" && "${_TAILSCALE_FAILED:-}" != "true" ]]; then
  sudo ufw allow in on tailscale0
  COMPLIANCE_OUT=$(sudo /usr/local/bin/compliance_check.sh 2>/dev/null || true)
elif [[ "$INSTALL_MODE" == "vps" ]]; then
  warn "SSH lockdown skipped — Tailscale not connected. Run tailscale up manually, then:"
  warn "  sudo ufw allow in on tailscale0"
  warn "  sudo ufw delete allow 22/tcp"
  COMPLIANCE_OUT=$(sudo /usr/local/bin/compliance_check.sh 2>/dev/null || true)
fi

# ── Desktop: print service URLs (do NOT auto-open — security risk) ────────

section "Setup Complete"

echo -e "
  ${GREEN}Everything is installed and configured.${NC}  (titan-setup ${SCRIPT_VERSION})

  ${CYAN}Installed:${NC}
    Package managers: uv, bun, cargo, go, mise
    CLI tools:        ~150+ across all managers
    Claude Code:      native binary
    Config:           ~/.claude/ (skills, hooks, commands, agents)
    Log:              $LOG_FILE
"

if [[ "$INSTALL_MODE" == "vps" ]]; then
  echo -e "  ${CYAN}Hardening:${NC}"
  echo "$COMPLIANCE_OUT" | sed 's/^/    /'
  echo ""
  echo -e "  ${CYAN}Services (Tailscale):${NC}"
  command -v docker &>/dev/null && echo "    n8n:            https://${TS_HOSTNAME}:5678"
  $CCFLARE_SKIP || echo "    better-ccflare: https://${TS_HOSTNAME}:${CCFLARE_PORT}"
  $LETTA_SKIP || echo "    letta:          https://${TS_HOSTNAME}:${LETTA_PORT}"
  $LETTA_CTRL_SKIP || $LETTA_SKIP || echo "    letta-ctrl:     https://${TS_HOSTNAME}:${LETTA_CTRL_PORT}"
  echo "    SSH:            ssh ${CLAUDE_USER}@${TS_HOSTNAME}"
  echo ""
  if ! $LETTA_SKIP && [[ -f "$HOME/.config/letta/credentials" ]]; then
    _LETTA_DISP_KEY=$(grep '^LETTA_SERVER_PASSWORD=' "$HOME/.config/letta/credentials" | cut -d= -f2-)
    echo -e "  ${CYAN}Letta credentials:${NC}
    API key:      ${_LETTA_DISP_KEY}"
  fi
  if ! $LETTA_CTRL_SKIP && ! $LETTA_SKIP && [[ -f "$HOME/.config/letta/ctrl-token" ]]; then
    echo -e "  ${CYAN}LettaCtrl token:${NC}
    Token:        $(tr -d '[:space:]' <"$HOME/.config/letta/ctrl-token")"
  fi
  echo ""
  echo -e "  ${YELLOW}⚠  Public port 22 closed — next login: ssh ${CLAUDE_USER}@${TS_HOSTNAME}${NC}"
  echo ""
  echo -e "  ${CYAN}Next steps:${NC}
    source ~/.bashrc
    su - ${CLAUDE_USER}
    claude auth login
    claude doctor
    cd <your-project>
    /tools                    # see all installed tools
    /catchup                  # orient to the project"
else
  echo -e "  ${CYAN}Services:${NC}
    n8n:              http://localhost:5678"
  $CCFLARE_SKIP || echo "    better-ccflare:   http://localhost:${CCFLARE_PORT}"
  $LETTA_SKIP || echo "    letta:            http://localhost:${LETTA_PORT}"
  $LETTA_CTRL_SKIP || $LETTA_SKIP || echo "    letta-ctrl:       http://localhost:${LETTA_CTRL_PORT}"
  echo ""

  # ── B8: n8n default credentials ──
  echo -e "  ${CYAN}n8n credentials (first-run setup):${NC}
    Open http://localhost:5678 and create your owner account.
    n8n has no default password — first visitor becomes owner."

  # ── B9: Letta API key ──
  if ! $LETTA_SKIP && [[ -f "$HOME/.config/letta/credentials" ]]; then
    _LETTA_DISP_KEY=$(grep '^LETTA_SERVER_PASSWORD=' "$HOME/.config/letta/credentials" | cut -d= -f2-)
    echo -e "
  ${CYAN}Letta subconscious memory:${NC}
    API key:      ${_LETTA_DISP_KEY}
    Base URL:     http://127.0.0.1:${LETTA_PORT}
    Credentials:  cat ~/.config/letta/credentials
    Logs:         journalctl --user -u letta -f
    Verify:       curl -sf -H \"Authorization: Bearer ${_LETTA_DISP_KEY}\" http://127.0.0.1:${LETTA_PORT}/v1/agents | jq '.[] | .name'"
  fi

  # ── B10: letta-ctrl token ──
  if ! $LETTA_CTRL_SKIP && ! $LETTA_SKIP; then
    _CTRL_TOKEN_FILE="$HOME/.config/letta/ctrl-token"
    if [[ -f "$_CTRL_TOKEN_FILE" ]]; then
      _CTRL_TOKEN=$(cat "$_CTRL_TOKEN_FILE" | tr -d '[:space:]')
      echo -e "
  ${CYAN}LettaCtrl GUI:${NC}
    URL:          http://localhost:${LETTA_CTRL_PORT}
    Auth token:   ${_CTRL_TOKEN}
    The frontend prompts for this token on first load."
    fi
  fi

  echo ""
  echo -e "  ${CYAN}Next steps:${NC}
    source ~/.bashrc
    claude auth login
    better-ccflare --add-account NAME --mode claude-oauth  # authenticate proxy
    claude doctor
    cd <your-project>
    /tools                    # see all installed tools
    /catchup                  # orient to the project"
fi

echo -e "
  ${CYAN}Package managers:${NC}
    Python CLIs → uv tool install <pkg>
    JS CLIs     → bun install -g <pkg>
    Rust CLIs   → cargo install <crate>
    Go CLIs     → go install <path>@latest
    ${RED}NEVER USE   → pip install, npm install -g, sudo pip${NC}
"

# ── VPS: lock SSH to Tailscale — ABSOLUTE LAST action ──────────────────────
# Deletes public port 22 rule and restarts sshd here — AFTER all output —
# so the install session stays alive throughout. This will drop the public
# SSH connection; reconnect via Tailscale: ssh CLAUDE_USER@TS_HOSTNAME
if [[ "$INSTALL_MODE" == "vps" && "${_TAILSCALE_FAILED:-}" != "true" ]]; then
  if [[ -z "${TS_IP:-}" ]]; then
    warn "Tailscale IP empty — skipping SSH lockdown (run manually after tailscale up)"
  else
    sudo ufw delete allow 22/tcp || true
    sudo ufw delete allow OpenSSH 2>/dev/null || true
    sudo sed -i '/^#\?ListenAddress /d' /etc/ssh/sshd_config
    echo "ListenAddress $TS_IP" | sudo tee -a /etc/ssh/sshd_config >/dev/null
    # Validate config before restart to avoid SSH lockout
    if sudo sshd -t 2>/dev/null; then
      sudo systemctl restart ssh 2>/dev/null || sudo systemctl restart sshd 2>/dev/null || true
    else
      warn "sshd_config validation failed — reverting ListenAddress change"
      sudo sed -i '/^ListenAddress /d' /etc/ssh/sshd_config
    fi
  fi
fi
