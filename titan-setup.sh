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
  exec bash "$_SELF" "$@"
fi
# ────────────────────────────────────────────────────────────────────────────

# ╔══════════════════════════════════════════════════════════════════╗
# ║  TITAN SETUP — Single Source of Truth                           ║
# ║  Fresh Ubuntu → fully armed Claude Code workstation             ║
# ║                                                                  ║
# ║  What this does:                                                 ║
# ║   1. System prerequisites + Linux tuning                        ║
# ║   2. Package managers: uv, bun, cargo, go, mise                ║
# ║   3. 155+ CLI tools (zero pip, zero npm -g)                    ║
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

SCRIPT_VERSION="v3.17"

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
INSTALL_MODE=""
TAILSCALE_KEY=""
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
CCFLARE_PROXY_PORT=8081  # billing proxy port (Bun-based; Docker containers reach via host.docker.internal:8081)
SEMGREP_TOKEN=""
SEMGREP_SKIP=false
LETTA_SKIP=false
LETTA_PORT=8283
LETTA_PASSWORD=""
OLLAMA_SKIP=false
LETTA_CTRL_SKIP=false
LETTA_CTRL_PORT=8284

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
    --name)            [[ $# -ge 2 ]] || { fail "--name requires a value"; usage; }; ENGINEER_NAME="$2"; shift 2 ;;
    --mode)            [[ $# -ge 2 ]] || { fail "--mode requires a value (desktop|vps)"; usage; }
                       [[ "$2" == "desktop" || "$2" == "vps" ]] || { fail "--mode must be 'desktop' or 'vps'"; usage; }
                       INSTALL_MODE="$2"; shift 2 ;;
    --tailscale-key)   [[ $# -ge 2 ]] || { fail "--tailscale-key requires a value"; usage; }; TAILSCALE_KEY="$2"; shift 2 ;;
    --claude-user)     [[ $# -ge 2 ]] || { fail "--claude-user requires a value"; usage; }; CLAUDE_USER="$2"; shift 2 ;;
    --cc-version)      [[ $# -ge 2 ]] || { fail "--cc-version requires a value"; usage; }; CC_VERSION="$2"; shift 2 ;;
    --no-autoupdate)   CC_NO_AUTOUPDATE="true"; shift ;;
    --cc-asked)        CC_ASKED=true; shift ;;
    --dry-run)         DRY_RUN=true; shift ;;
    -v|--verbose)      VERBOSE=true; shift ;;
    --ccflare-skip)    CCFLARE_SKIP=true; shift ;;
    --ccflare-port)    [[ $# -ge 2 ]] || { fail "--ccflare-port requires a value"; usage; }; CCFLARE_PORT="$2"; shift 2 ;;
    --ccflare-host)    [[ $# -ge 2 ]] || { fail "--ccflare-host requires a value"; usage; }; CCFLARE_HOST="$2"; shift 2 ;;
    --semgrep-token)   [[ $# -ge 2 ]] || { fail "--semgrep-token requires a value"; usage; }; SEMGREP_TOKEN="$2"; shift 2 ;;
    --no-semgrep)      SEMGREP_SKIP=true; shift ;;
    --letta-skip)      LETTA_SKIP=true; shift ;;
    --letta-port)      [[ $# -ge 2 ]] || { fail "--letta-port requires a value"; usage; }; LETTA_PORT="$2"; shift 2 ;;
    --letta-password)  [[ $# -ge 2 ]] || { fail "--letta-password requires a value"; usage; }; LETTA_PASSWORD="$2"; shift 2 ;;
    --no-ollama)       OLLAMA_SKIP=true; shift ;;
    --letta-ctrl-skip) LETTA_CTRL_SKIP=true; shift ;;
    --letta-ctrl-port) [[ $# -ge 2 ]] || { fail "--letta-ctrl-port requires a value"; usage; }; LETTA_CTRL_PORT="$2"; shift 2 ;;
    --version)         echo "titan-setup ${SCRIPT_VERSION}"; exit 0 ;;
    -h|--help)         usage ;;
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

# ─── Installation profile ───
if [[ -z "$INSTALL_MODE" ]]; then
  echo -e "\n${CYAN}Select installation profile:${NC}"
  echo "  1) Desktop  — full workstation setup"
  echo "  2) VPS      — workstation + server extras"
  read -rp "  Choice [1/2]: " _mode_choice
  case "$_mode_choice" in
    1) INSTALL_MODE="desktop" ;;
    2) INSTALL_MODE="vps" ;;
    *) fail "Invalid choice. Run with --mode desktop or --mode vps"; exit 1 ;;
  esac
fi
echo -e "  Profile: ${GREEN}${INSTALL_MODE}${NC}\n"

# ─── Claude Code version + autoupdate ───
if [[ -z "$CC_VERSION" ]] && ! $CC_ASKED; then
  read -rp "  Claude Code version to install (blank = latest): " CC_VERSION
fi
if [[ -z "$CC_NO_AUTOUPDATE" ]] && ! $CC_ASKED; then
  read -rp "  Disable Claude Code auto-updates? [y/N]: " _au_ans
  case "${_au_ans,,}" in
    y|yes) CC_NO_AUTOUPDATE="true" ;;
    *)     CC_NO_AUTOUPDATE="" ;;
  esac
fi
[[ -n "$CC_VERSION" ]] && echo -e "  CC version:    ${GREEN}${CC_VERSION}${NC}"
[[ "$CC_NO_AUTOUPDATE" == "true" ]] && echo -e "  Auto-updates:  ${YELLOW}disabled${NC}" || echo -e "  Auto-updates:  ${GREEN}enabled${NC}"

# ─── Semgrep token (interactive prompt if not set via flag) ───
if ! $SEMGREP_SKIP && [[ -z "$SEMGREP_TOKEN" ]]; then
  echo -e "\n  ${CYAN}Semgrep (static analysis in Claude Code):${NC}"
  echo "  Get a free token at semgrep.dev → Settings → Tokens"
  read -rp "  Semgrep App Token (Enter to skip): " SEMGREP_TOKEN
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
    read -rp "  Username for Claude Code (created if absent): " CLAUDE_USER
    [[ -z "$CLAUDE_USER" ]] && { fail "Username required for VPS mode"; exit 1; }
  fi

  if [[ "$(whoami)" != "$CLAUDE_USER" ]]; then
    if ! id "$CLAUDE_USER" &>/dev/null; then
      sudo useradd -m -s /bin/bash "$CLAUDE_USER"
      echo -e "  ${GREEN}✓${NC} Created user: $CLAUDE_USER"
    fi
    echo "$CLAUDE_USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/"$CLAUDE_USER" > /dev/null
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
    [[ -n "$CC_VERSION" ]]         && _VPS_REEXEC_ARGS+=(--cc-version "$CC_VERSION")
    [[ "$CC_NO_AUTOUPDATE" == "true" ]] && _VPS_REEXEC_ARGS+=(--no-autoupdate)
    $VERBOSE                       && _VPS_REEXEC_ARGS+=(--verbose)
    $CCFLARE_SKIP                  && _VPS_REEXEC_ARGS+=(--ccflare-skip)
    _VPS_REEXEC_ARGS+=(--ccflare-port "$CCFLARE_PORT" --ccflare-host "$CCFLARE_HOST")
    [[ -n "$SEMGREP_TOKEN" ]]      && _VPS_REEXEC_ARGS+=(--semgrep-token "$SEMGREP_TOKEN")
    $SEMGREP_SKIP                  && _VPS_REEXEC_ARGS+=(--no-semgrep)
    $LETTA_SKIP                    && _VPS_REEXEC_ARGS+=(--letta-skip)
    _VPS_REEXEC_ARGS+=(--letta-port "$LETTA_PORT")
    [[ -n "$LETTA_PASSWORD" ]]     && _VPS_REEXEC_ARGS+=(--letta-password "$LETTA_PASSWORD")
    $OLLAMA_SKIP                   && _VPS_REEXEC_ARGS+=(--no-ollama)
    $LETTA_CTRL_SKIP                   && _VPS_REEXEC_ARGS+=(--letta-ctrl-skip)
    _VPS_REEXEC_ARGS+=(--letta-ctrl-port "$LETTA_CTRL_PORT")
    exec sudo -u "$CLAUDE_USER" bash "$0" "${_VPS_REEXEC_ARGS[@]}"
  fi
fi

# ─── Ensure we are in a readable working directory ───
# exec sudo -u USER inherits root's CWD (/root) which USER may not be able to stat.
# Go, some build tools, and mktemp -d with relative paths all call getcwd() and fail.
cd "$HOME" || cd /tmp

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
      printf ' %q' "${_ORIG_ARGS[@]+"${_ORIG_ARGS[@]}"}"
      # Carry forward interactively-resolved values not present in _ORIG_ARGS
      if [[ -n "$SEMGREP_TOKEN" ]]; then
        printf ' --semgrep-token %q' "$SEMGREP_TOKEN"
      elif $SEMGREP_SKIP; then
        printf ' --no-semgrep'
      fi
      printf ' 2>&1 | tee %q\n' "$_TMUX_LOG"
    } > "$_TMUX_WRAPPER"
    chmod +x "$_TMUX_WRAPPER"
    echo -e "\n  ${CYAN}Re-launching inside tmux (SSH-disconnect safe)${NC}"
    echo -e "  ${GREEN}Reconnect:${NC} tmux attach -t titan-setup"
    echo -e "  ${GREEN}Log:${NC}       tail -f $_TMUX_LOG\n"
    exec tmux new-session -s titan-setup "bash $_TMUX_WRAPPER"
  fi
fi

# ─── Log file for quiet mode ───
LOG_FILE="/tmp/titan-setup-$(date +%Y%m%d-%H%M%S).log"
# run_q: run a command, routing output to log file unless --verbose
run_q() { if $VERBOSE; then "$@"; else "$@" >> "$LOG_FILE" 2>&1; fi; }
echo "# titan-setup log — $(date)" > "$LOG_FILE"

# ─── Temp directory for downloads ───
WORKDIR=$(mktemp -d)
_CLEANUP_DIRS=("$WORKDIR")
_do_cleanup() { rm -rf "${_CLEANUP_DIRS[@]}"; }
trap '_do_cleanup' EXIT

# ─── Architecture detection ───
UNAME_ARCH=$(uname -m)
case "$UNAME_ARCH" in
  x86_64)  ARCH_AMD="amd64"; ARCH_GO="amd64"; ARCH_RUST="x86_64"; ARCH_FULL="x86_64" ;;
  aarch64) ARCH_AMD="arm64"; ARCH_GO="arm64"; ARCH_RUST="aarch64"; ARCH_FULL="aarch64" ;;
  *) fail "Unsupported architecture: $UNAME_ARCH"; exit 1 ;;
esac

# ─── VPS Pre-hardening (before tool installation) ───
if [[ "$INSTALL_MODE" == "vps" ]]; then
  section "VPS — Server Hardening"

  # ── Require Tailscale auth key ─────────────────────────────────────────
  if [[ -z "$TAILSCALE_KEY" ]]; then
    echo -e "  ${CYAN}Tailscale auth key${NC} (required — generate at login.tailscale.com/admin/settings/keys):"
    read -rsp "  Key: " TAILSCALE_KEY
    echo ""
    [[ -z "$TAILSCALE_KEY" ]] && { fail "Tailscale key required for VPS mode"; exit 1; }
  fi

  # ── Require non-root Claude user ───────────────────────────────────────
  if [[ -z "$CLAUDE_USER" ]]; then
    read -rp "  Non-root user for Claude Code (created if absent): " CLAUDE_USER
    [[ -z "$CLAUDE_USER" ]] && { fail "--claude-user required for VPS mode"; exit 1; }
  fi

  # ── Security packages ──────────────────────────────────────────────────
  run_q sudo apt-get update
  run_q sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    -o Dpkg::Options::="--force-confold" \
    fail2ban unattended-upgrades auditd audispd-plugins
  ok "Security packages (fail2ban, unattended-upgrades, auditd)"

  # ── SSH hardening ──────────────────────────────────────────────────────
  # Patch main config AND drop-in dir (e.g. Hetzner's 50-cloud-init.conf overrides main)
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

  # ── UFW — NOT used (Tailscale handles network isolation) ─────────────
  # UFW conflicts with Tailscale routing. Tailscale provides network-level
  # isolation via WireGuard. Do not enable UFW on Tailscale VPS nodes.
  # Reference: https://tailscale.com/kb/1077/secure-server-ubuntu-18-04

  # ── fail2ban — SSH protection ─────────────────────────────────────────
  sudo tee /etc/fail2ban/jail.local > /dev/null << 'FAIL2BAN_EOF'
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
  sudo systemctl enable fail2ban --now
  ok "fail2ban active (SSH: 5 retries → 1h ban)"

  # ── unattended-upgrades — security patches only ───────────────────────
  sudo tee /etc/apt/apt.conf.d/50unattended-upgrades-titan > /dev/null << 'UU_EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
UU_EOF
  sudo systemctl enable unattended-upgrades --now
  ok "unattended-upgrades active (security patches only, no auto-reboot)"

  # ── auditd — privilege escalation monitoring ──────────────────────────
  sudo tee /etc/audit/rules.d/titan.rules > /dev/null << 'AUDIT_EOF'
-a always,exit -F arch=b64 -S execve -F euid=0 -F auid!=0 -k privesc
-w /etc/passwd -p wa -k passwd_changes
-w /etc/sudoers -p wa -k sudoers_changes
-w /etc/sudoers.d/ -p wa -k sudoers_changes
AUDIT_EOF
  sudo systemctl enable auditd --now
  ok "auditd active (privesc monitoring, passwd/sudoers watch)"

  # ── Repo supply chain guard ───────────────────────────────────────────
  sudo tee /usr/local/sbin/repo_supply_chain_guard.sh > /dev/null << 'GUARD_EOF'
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
  sudo bash /usr/local/sbin/repo_supply_chain_guard.sh
  ok "Repo supply chain guard installed and run"

  # ── Compliance check script ───────────────────────────────────────────
  sudo tee /usr/local/bin/compliance_check.sh > /dev/null << 'COMPLIANCE_EOF'
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

if tailscale status 2>/dev/null | grep -qE 'logged in|Connected|is running'; then
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

if command -v tailscale >/dev/null 2>&1 && tailscale status 2>/dev/null | grep -q 'logged in\|Connected\|is running'; then
  pass "tailscale connected (network isolation active)"
else
  fail "tailscale connected (network isolation active)"
fi

exit "$FAIL"
COMPLIANCE_EOF
  sudo chmod 755 /usr/local/bin/compliance_check.sh
  ok "Compliance check script installed"

  # ── Compliance systemd timer (every 6h) ───────────────────────────────
  sudo tee /etc/systemd/system/compliance-check.service > /dev/null << 'SVC_EOF'
[Unit]
Description=Run server compliance checks
After=network-online.target

[Service]
Type=oneshot
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/usr/local/bin/compliance_check.sh
SVC_EOF

  sudo tee /etc/systemd/system/compliance-check.timer > /dev/null << 'TIMER_EOF'
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

  sudo systemctl daemon-reload
  sudo systemctl enable --now compliance-check.timer
  ok "Compliance timer enabled (runs at boot +5m, then every 6h)"

fi

section "Phase 1/6 — System Prerequisites"

# Suppress needrestart interactive kernel/service restart prompts on Ubuntu VPS
# Sets restart mode to automatic so apt upgrades never block waiting for user input
if [[ -d /etc/needrestart ]]; then
  sudo mkdir -p /etc/needrestart/conf.d
  # restart='a' → auto-restart services; kernelhints=-1 → suppress "Pending kernel upgrade" dialog
  printf '\$nrconf{restart} = '"'"'a'"'"';\n\$nrconf{kernelhints} = -1;\n\$nrconf{ucodehints} = 0;\n' \
    | sudo tee /etc/needrestart/conf.d/titan-auto.conf > /dev/null
fi

run_q sudo apt-get update -qq
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
    curl -fsSL -o "$TMPFONT/JetBrainsMono.tar.xz" \
      "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz"
    tar -xf "$TMPFONT/JetBrainsMono.tar.xz" -C "$TMPFONT"
    cp "$TMPFONT"/*.ttf "$FONT_DIR/" 2>/dev/null || true
    fc-cache -f "$FONT_DIR" 2>/dev/null
    rm -rf "$TMPFONT"
    ok "JetBrainsMono Nerd Font installed"
  fi
  # Note: Cosmic Terminal font is NOT set here — change it manually via terminal settings.
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
  # shellcheck source=/dev/null
  [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
  ok "cargo installed: $(cargo --version)"
fi
# Ensure cargo binaries are on PATH for the rest of this script (idempotent)
# shellcheck source=/dev/null
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

# ─── uv (replaces pip, pipx, venv, pyenv) ───
if command -v uv &>/dev/null; then
  ok "uv already installed: $(uv --version)"
else
  echo "  Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
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
  export PATH="$HOME/.bun/bin:$PATH"
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
  if (( _TOTAL_RAM_MB < 3072 )); then
    warn "System has ${_TOTAL_RAM_MB}MB RAM — Letta+Ollama need ~2GB."
    echo "  Consider --letta-skip or adding swap:"
    echo "    sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile"
  fi
fi

section "Phase 3/6 — 155+ CLI Tools"

# ─── Python tools via uv (isolated venvs, zero system pollution) ───
echo -e "  ${CYAN}Python tools (uv):${NC}"

UV_TOOLS=(
  "yq"              # yq — YAML/XML/TOML processor
  "semgrep"         # semgrep — static analysis
  "ansible-core"    # ansible, ansible-playbook, ansible-galaxy + more (NOT 'ansible' — that's the meta-pkg)
  "ansible-lint"    # ansible-lint — linter for Ansible playbooks
  "sqlmap"          # sqlmap — SQL injection testing
  "pgcli"           # pgcli — Postgres with autocomplete
  "ruff"            # ruff — Python linter (replaces flake8+black+isort+pyflakes)
  "ast-grep-cli"    # ast-grep, sg — structural code search
  "mitmproxy"       # mitmproxy, mitmdump — HTTP/HTTPS proxy for debugging
  "cookiecutter"    # cookiecutter — project scaffolding from templates
  "notebooklm-mcp-cli"  # nlm — Google NotebookLM CLI + MCP server
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
# claude-agent-sdk is a library (not a CLI tool) — needs --break-system-packages on Ubuntu 24.04 externally-managed Python
_PYSITE="$HOME/.local/lib/python3.12/site-packages"
python3 -c "import claude_agent_sdk" 2>/dev/null && ok "claude-agent-sdk (exists)" || \
  { mkdir -p "$_PYSITE" && uv pip install --target "$_PYSITE" --quiet claude-agent-sdk 2>/dev/null \
    && ok "claude-agent-sdk" || warn "claude-agent-sdk (install manually: uv pip install --target ~/.local/lib/python3.12/site-packages claude-agent-sdk)"; }
unset _PYSITE

# sqlite-vec is installed to ~/.local/lib/python-libs/ as a memory library (used on-demand, not at startup)

# ─── JS tools via bun ───
echo -e "\n  ${CYAN}JS tools (bun):${NC}"

# Trust postinstall scripts for packages that need them (esbuild, puppeteer, canvas, etc.)
# Also skip puppeteer chromium download — we install chromium via playwright separately
cat > "$HOME/.bunfig.toml" << 'BUNFIG'
[install]
trustedDependencies = ["puppeteer", "esbuild", "@swc/core", "canvas", "node-gyp", "sharp", "fsevents"]

[install.scopes]
BUNFIG
export PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=1

BUN_TOOLS=("trash-cli" "tldr" "prettier" "repomix" "ccstatusline")
for tool in "${BUN_TOOLS[@]}"; do
  if bun pm ls -g 2>/dev/null | grep -q "$tool"; then
    ok "$tool (exists)"
  else
    echo -n "  Installing $tool..."
    run_q bun install -g "$tool" && echo -e " ${GREEN}✓${NC}" || echo -e " ${YELLOW}⚠${NC}"
  fi
done

command -v gemini &>/dev/null && ok "gemini-cli (exists)" || { run_q bun install -g @google/gemini-cli && ok "gemini-cli" || warn "gemini-cli"; }
command -v mmdc &>/dev/null && ok "mermaid-cli (exists)" || { run_q bun install -g @mermaid-js/mermaid-cli && ok "mermaid-cli" || warn "mermaid-cli"; }

# playwright — browser automation and E2E testing
if ! bun pm ls -g 2>/dev/null | grep -q playwright; then
  run_q bun install -g playwright && ok "playwright" || warn "playwright"
  # Install chromium: apt deps need root, browser download runs as current user
  if command -v playwright &>/dev/null; then
    # install-deps uses apt-get; titan has NOPASSWD sudo so playwright's internal sudo call works
    sudo -E env "PATH=$PATH" "$(command -v playwright)" install-deps chromium >> "$LOG_FILE" 2>&1 || true
    run_q playwright install chromium && ok "playwright chromium" \
      || warn "playwright chromium (install manually: playwright install chromium)"
  fi
else
  ok "playwright (exists)"
fi

# n8n — workflow automation server (runs as systemd user service via docker)
if command -v docker &>/dev/null; then
  # Add user to docker group and ensure daemon is running
  sudo usermod -aG docker "$USER" 2>/dev/null || true
  sudo systemctl enable --now docker 2>/dev/null || true

  # Enable systemd linger so user services start at boot without login
  loginctl enable-linger "$USER" 2>/dev/null || true

  # Pull image — user is in docker group; fall back to sudo if socket isn't yet accessible
  if docker pull n8nio/n8n:latest >> "$LOG_FILE" 2>&1 \
      || sg docker -c "docker pull n8nio/n8n:latest" >> "$LOG_FILE" 2>&1 \
      || sudo docker pull n8nio/n8n:latest >> "$LOG_FILE" 2>&1; then
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
  cat > "$HOME/.config/systemd/user/n8n.service" << SERVICEEOF
[Unit]
Description=n8n workflow automation
After=default.target

[Service]
Type=simple
ExecStartPre=-${DOCKER_BIN} rm -f n8n
ExecStart=${DOCKER_BIN} run --rm --name n8n -p 127.0.0.1:5678:5678 -v %h/.n8n:/home/node/.n8n n8nio/n8n
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
    if curl -fsSL https://ollama.com/install.sh | sh >> "$LOG_FILE" 2>&1; then
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
    printf '[Service]\nEnvironment="OLLAMA_HOST=0.0.0.0:11434"\n' \
      | sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null
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
      if ollama pull nomic-embed-text >> "$LOG_FILE" 2>&1; then
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
  cat > "$HOME/.config/letta/credentials" << CREDEOF
# Letta server credentials (generated by titan-setup ${SCRIPT_VERSION})
LETTA_SERVER_PASSWORD=${LETTA_PASSWORD}
LETTA_BASE_URL=http://127.0.0.1:${LETTA_PORT}
LETTA_API_KEY=${LETTA_PASSWORD}
CREDEOF
  chmod 600 "$HOME/.config/letta/credentials"

  # Docker env file for Letta container
  cat > "$HOME/.config/letta/docker.env" << ENVEOF
SECURE=true
LETTA_SERVER_PASSWORD=${LETTA_PASSWORD}
ENVEOF
  if ! $OLLAMA_SKIP && command -v ollama &>/dev/null; then
    echo "OLLAMA_BASE_URL=http://host.docker.internal:11434/v1" >> "$HOME/.config/letta/docker.env"
  fi
  if ! $CCFLARE_SKIP && command -v better-ccflare &>/dev/null; then
    echo "ANTHROPIC_BASE_URL=http://host.docker.internal:${CCFLARE_PROXY_PORT}" >> "$HOME/.config/letta/docker.env"
    echo "ANTHROPIC_API_KEY=sk-proxy-via-ccflare" >> "$HOME/.config/letta/docker.env"
  elif [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}" >> "$HOME/.config/letta/docker.env"
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
  if run_q docker pull letta/letta:latest; then
    ok "letta/letta:latest image"
  else
    warn "letta docker pull failed — check: docker pull letta/letta:latest"
    LETTA_SKIP=true
  fi

  if ! $LETTA_SKIP; then
    mkdir -p "$HOME/.letta/.persist/pgdata"

    # Systemd user service using --env-file to avoid secrets in unit file
    mkdir -p "$HOME/.config/systemd/user"
    cat > "$HOME/.config/systemd/user/letta.service" << SERVICEEOF
[Unit]
Description=Letta persistent memory server
After=default.target

[Service]
Type=simple
ExecStartPre=-${_DOCKER_BIN} rm -f letta-server
ExecStart=${_DOCKER_BIN} run --rm --name letta-server -p ${LETTA_PORT}:8283 --add-host=host.docker.internal:host-gateway -v %h/.letta/.persist/pgdata:/var/lib/postgresql/data --env-file %h/.config/letta/docker.env letta/letta:latest
ExecStop=${_DOCKER_BIN} stop letta-server
Restart=on-failure
RestartSec=15

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
  if ! command -v better-ccflare &>/dev/null; then
    _BCF_SRC=$(mktemp -d -t bcf-src-XXXXXX)
    _CLEANUP_DIRS+=("$_BCF_SRC")
    if run_q git clone --depth=1 https://github.com/tombii/better-ccflare.git "$_BCF_SRC"; then
      # Patch: fix NULL constraint for refresh_token in CLI account creation
      python3 - "$_BCF_SRC/packages/cli-commands/src/commands/account.ts" << 'PYEOF'
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
      python3 - "$_BCF_SRC/packages/cli-commands/src/commands/account.ts" << 'PYEOF'
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
      if run_q bun install --cwd "$_BCF_SRC" && run_q bun --cwd "$_BCF_SRC/apps/cli" run build; then
        _BCF_DIST="$_BCF_SRC/apps/cli/dist/better-ccflare"
        if [[ -f "$_BCF_DIST" ]]; then
          mkdir -p "$HOME/.bun/bin" "$HOME/.local/bin"
          install -m 0755 "$_BCF_DIST" "$HOME/.bun/bin/better-ccflare"
          install -m 0755 "$_BCF_DIST" "$HOME/.local/bin/better-ccflare"
          ok "better-ccflare (built from source + NULL constraint patches applied)"
        else
          warn "better-ccflare build succeeded but binary not found at $_BCF_DIST — falling back to npm"
          run_q bun install -g better-ccflare || warn "better-ccflare npm install also failed"
        fi
      else
        warn "better-ccflare build failed — falling back to npm binary (kilo/zai/minimax may have issues)"
        run_q bun install -g better-ccflare || warn "better-ccflare npm install also failed"
      fi
    else
      warn "better-ccflare repo clone failed — falling back to npm binary"
      run_q bun install -g better-ccflare || warn "better-ccflare install failed"
    fi
  else
    ok "better-ccflare (exists)"
  fi

  # Phase B: Systemd user service
  # Resolve binary path at install time — avoids hardcoded ~/.bun/bin/ which may not exist
  _BCF_BIN=$(command -v better-ccflare 2>/dev/null || echo "$HOME/.local/bin/better-ccflare")
  mkdir -p "$HOME/.config/systemd/user"
  cat > "$HOME/.config/systemd/user/better-ccflare.service" << SERVICEEOF
[Unit]
Description=better-ccflare Claude load balancer proxy
After=default.target

[Service]
Type=simple
ExecStart=${_BCF_BIN} --serve --port ${CCFLARE_PORT}
Restart=on-failure
RestartSec=5
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
    cat > "$HOME/.config/letta/ccflare-billing-proxy.js" << 'BPROXY'
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
  port: PORT, hostname: "0.0.0.0",
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

    cat > "$HOME/.config/systemd/user/ccflare-docker-proxy.service" << SVCEOF
[Unit]
Description=betterccflare billing header proxy (issue #89 — Sonnet/Opus via OAuth)
After=better-ccflare.service
BindsTo=better-ccflare.service

[Service]
Type=simple
ExecStart=${_BUN_BIN} run %h/.config/letta/ccflare-billing-proxy.js
Environment="CCFLARE_PORT=${CCFLARE_PORT}"
Environment="CCFLARE_PROXY_PORT=${CCFLARE_PROXY_PORT}"
Environment="PATH=${HOME}/.local/bin:${HOME}/.bun/bin:/usr/local/bin:/usr/bin:/bin"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
SVCEOF
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable ccflare-docker-proxy 2>/dev/null || true
    systemctl --user start ccflare-docker-proxy 2>/dev/null || true
    ok "ccflare-billing-proxy (0.0.0.0:${CCFLARE_PROXY_PORT} → 127.0.0.1:${CCFLARE_PORT}, billing header injection)"
  else
    warn "bun not found — ccflare-billing-proxy skipped (Letta LLM calls will fail)"
  fi
fi  # end $CCFLARE_SKIP

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
    sudo apt install -y libpcre3-dev 2>/dev/null
    echo "y" | bash <(curl -sL get.comby.dev) 2>/dev/null \
      && ok "comby" || warn "comby install failed"
  else ok "comby (exists)"; fi
else warn "comby: skipped (amd64 only, detected ${ARCH_AMD})"; fi



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
  ok "Backed up existing config to $BACKUP"
fi

mkdir -p "$CLAUDE_DIR"/{skills/cli-tools,skills/security-scan,skills/git-workflow,skills/infra-deploy,skills/add-cli-tool/references,skills/tmux-control,skills/workspace,skills/pueue-orchestrator,skills/diagrams,skills/deploy,skills/process-supervisor,skills/nlm-cli,skills/docker-security,skills/ansible-ops,skills/incident-response,skills/terraform-security,commands,agents,hooks,memory,rules,logs,templates,agent-stash/_loaded,agent-stash/agents}
mkdir -p "$HOME/.config/agt"

# ─── Repo files (static content loaded from git repo) ────────────────────────
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

# ─── CLAUDE.md ───
install -Dm644 "$REPO_FILES/dot-claude/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
sd 'TITAN_ENGINEER_NAME' "$ENGINEER_NAME" "$CLAUDE_DIR/CLAUDE.md"
ok "CLAUDE.md"

# ─── settings.json ───
install -Dm644 "$REPO_FILES/dot-claude/settings.json" "$CLAUDE_DIR/settings.json"
sd 'TITAN_ENGINEER_NAME' "$ENGINEER_NAME" "$CLAUDE_DIR/settings.json"
TITAN_PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.cargo/bin:$HOME/go/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
sd 'TITAN_PATH_PLACEHOLDER' "$TITAN_PATH" "$CLAUDE_DIR/settings.json"
if [[ "$CC_NO_AUTOUPDATE" == "true" ]]; then
  jq '.env.DISABLE_AUTOUPDATER = "1"' "$CLAUDE_DIR/settings.json" > /tmp/_cc_settings.json \
    && mv /tmp/_cc_settings.json "$CLAUDE_DIR/settings.json"
  ok "settings.json (DISABLE_AUTOUPDATER=1)"
else
  ok "settings.json"
fi
# ─── Semgrep token injection ───
if [[ -n "$SEMGREP_TOKEN" ]] && ! $SEMGREP_SKIP; then
  jq --arg tok "$SEMGREP_TOKEN" \
    '.env.SEMGREP_APP_TOKEN = $tok | .enabledPlugins["semgrep@claude-plugins-official"] = true' \
    "$CLAUDE_DIR/settings.json" > /tmp/_cc_settings.json \
    && mv /tmp/_cc_settings.json "$CLAUDE_DIR/settings.json" \
    && ok "settings.json (SEMGREP_APP_TOKEN injected, plugin enabled)" \
    || warn "semgrep token injection failed"
fi

# RTK global hook — runs after settings.json is written so it appends, not overwrites
if command -v rtk &>/dev/null && rtk gain &>/dev/null 2>&1; then
  run_q rtk init -g --auto-patch && ok "rtk global hook (token compression active)" \
    || warn "rtk init -g failed — run manually: rtk init -g"
fi

# Inject ANTHROPIC_BASE_URL if better-ccflare is installed (desktop and VPS)
if ! $CCFLARE_SKIP && command -v better-ccflare &>/dev/null; then
  jq --arg url "http://127.0.0.1:${CCFLARE_PORT}" '.env.ANTHROPIC_BASE_URL = $url' \
    "$CLAUDE_DIR/settings.json" > /tmp/_cc_settings.json \
    && mv /tmp/_cc_settings.json "$CLAUDE_DIR/settings.json"
  ok "settings.json (ANTHROPIC_BASE_URL → http://127.0.0.1:${CCFLARE_PORT})"
fi

# Inject Letta env vars if Letta is installed
if ! $LETTA_SKIP && [[ -f "$HOME/.config/letta/credentials" ]]; then
  _LETTA_PASS=$(grep '^LETTA_SERVER_PASSWORD=' "$HOME/.config/letta/credentials" | cut -d= -f2-)
  jq --arg url "http://127.0.0.1:${LETTA_PORT}" \
     --arg key "$_LETTA_PASS" \
     --arg model "anthropic/claude-sonnet-4-6" \
     --arg mode "whisper" \
     --arg tools "read-only" \
     '.env.LETTA_BASE_URL = $url |
      .env.LETTA_API_KEY = $key |
      .env.LETTA_MODEL = $model |
      .env.LETTA_MODE = $mode |
      .env.LETTA_SDK_TOOLS = $tools' \
    "$CLAUDE_DIR/settings.json" > /tmp/_cc_settings.json \
    && mv /tmp/_cc_settings.json "$CLAUDE_DIR/settings.json"
  ok "settings.json (Letta env vars injected — LETTA_BASE_URL, LETTA_API_KEY, LETTA_MODEL, LETTA_MODE)"
fi

# ─── ntfy push notifications — set NTFY_TOPIC to enable ───
# Injects NTFY_TOPIC and NTFY_URL into Claude Code env so session hooks can send push alerts.
# Leave NTFY_TOPIC blank to disable. Set to any ntfy.sh topic name or self-hosted topic.
jq '.env.NTFY_TOPIC = "" | .env.NTFY_URL = "https://ntfy.sh"' \
  "$CLAUDE_DIR/settings.json" > /tmp/_cc_settings.json \
  && mv /tmp/_cc_settings.json "$CLAUDE_DIR/settings.json"
ok "settings.json (ntfy env vars added — set NTFY_TOPIC to enable push alerts)"

# ─── ccstatusline config ───
install -Dm644 "$REPO_FILES/config/ccstatusline/settings.json" "$HOME/.config/ccstatusline/settings.json" \
  && ok "ccstatusline: config" || warn "ccstatusline config (missing from repo)"

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

# ─── Skill: nlm-cli ───
install -Dm644 "/dot-claude/skills/nlm-cli/SKILL.md" "/skills/nlm-cli/SKILL.md"
ok "skill: nlm-cli"

# ─── Skill: docker-security ───
install -Dm644 "$REPO_FILES/dot-claude/skills/docker-security/SKILL.md" "$CLAUDE_DIR/skills/docker-security/SKILL.md"
ok "skill: docker-security"

# ─── Skill: ansible-ops ───
install -Dm644 "$REPO_FILES/dot-claude/skills/ansible-ops/SKILL.md" "$CLAUDE_DIR/skills/ansible-ops/SKILL.md"
ok "skill: ansible-ops"

# ─── Skill: incident-response ───
install -Dm644 "$REPO_FILES/dot-claude/skills/incident-response/SKILL.md" "$CLAUDE_DIR/skills/incident-response/SKILL.md"
ok "skill: incident-response"

# ─── Skill: terraform-security ───
install -Dm644 "$REPO_FILES/dot-claude/skills/terraform-security/SKILL.md" "$CLAUDE_DIR/skills/terraform-security/SKILL.md"
ok "skill: terraform-security"

# ─── Hook Scripts (Memory/Context Management) ───

install -Dm755 "$REPO_FILES/dot-claude/hooks/pre-compact.sh" "$CLAUDE_DIR/hooks/pre-compact.sh"
ok "hook: pre-compact.sh"

install -Dm755 "$REPO_FILES/dot-claude/hooks/session-end.sh" "$CLAUDE_DIR/hooks/session-end.sh"
ok "hook: session-end.sh"

install -Dm755 "$REPO_FILES/dot-claude/hooks/session-start.sh" "$CLAUDE_DIR/hooks/session-start.sh"
ok "hook: session-start.sh"

# UserPromptSubmit: inject memory only when recall-intent keywords detected (zero tokens otherwise)
install -Dm755 "$REPO_FILES/dot-claude/hooks/prompt-memory-inject.sh" "$CLAUDE_DIR/hooks/prompt-memory-inject.sh"
ok "hook: prompt-memory-inject.sh"

# ─── Status Line Script ───
install -Dm755 "$REPO_FILES/dot-claude/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
ok "statusline-command.sh"

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

install -Dm644 "$REPO_FILES/dot-claude/rules/security.md" "$CLAUDE_DIR/rules/security.md"
ok "rule: security.md"

install -Dm644 "$REPO_FILES/dot-claude/rules/memory.md" "$CLAUDE_DIR/rules/memory.md"
ok "rule: memory.md"

# ─── /recall command ───
install -Dm644 "$REPO_FILES/dot-claude/commands/recall.md" "$CLAUDE_DIR/commands/recall.md"
ok "command: /recall"

# ─── /remember command ───
install -Dm644 "$REPO_FILES/dot-claude/commands/remember.md" "$CLAUDE_DIR/commands/remember.md"
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
    # Add paths scoping to large skills so they don't load on every session (bug #14882)
    if [ -f ~/.claude/skills/tdd/SKILL.md ] && ! grep -q '^paths:' ~/.claude/skills/tdd/SKILL.md 2>/dev/null; then
      sed -i '3a paths: ["**/*.py", "**/*.js", "**/*.ts", "**/*.jsx", "**/*.tsx", "**/*.go", "**/*.rs", "**/*.java", "**/*.cpp", "**/*.c", "**/*.rb", "**/test*", "**/spec*", "**/*_test*", "**/*_spec*", "**/pytest.ini", "**/jest.config*", "**/go.mod"]' ~/.claude/skills/tdd/SKILL.md
    fi
    if [ -f ~/.claude/skills/systematic-debugging/SKILL.md ] && ! grep -q '^paths:' ~/.claude/skills/systematic-debugging/SKILL.md 2>/dev/null; then
      sed -i '3a paths: ["**/*.py", "**/*.js", "**/*.ts", "**/*.go", "**/*.rs", "**/*.java", "**/*.sh", "**/*.bash", "**/*.cpp", "**/*.c", "**/*.rb", "**/Makefile", "**/CMakeLists.txt"]' ~/.claude/skills/systematic-debugging/SKILL.md
    fi
    if [ -f ~/.claude/skills/brainstorming/SKILL.md ] && ! grep -q '^paths:' ~/.claude/skills/brainstorming/SKILL.md 2>/dev/null; then
      sed -i '3a paths: ["**/_scratchpad*", "**/_plan*", "**/spec*", "**/*.spec.md", "**/brainstorm*"]' ~/.claude/skills/brainstorming/SKILL.md
    fi
    if [ -f ~/.claude/skills/verification-before-completion/SKILL.md ] && ! grep -q '^paths:' ~/.claude/skills/verification-before-completion/SKILL.md 2>/dev/null; then
      sed -i '3a paths: ["**/*.py", "**/*.js", "**/*.ts", "**/*.go", "**/*.sh", "**/*.rs", "**/test*", "**/spec*", "**/Makefile"]' ~/.claude/skills/verification-before-completion/SKILL.md
    fi
    if [ -f ~/.claude/skills/writing-plans/SKILL.md ] && ! grep -q '^paths:' ~/.claude/skills/writing-plans/SKILL.md 2>/dev/null; then
      sed -i '3a paths: ["**/_scratchpad*", "**/_plan*", "**/spec*", "**/plan*", "**/*.spec.md"]' ~/.claude/skills/writing-plans/SKILL.md
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
if [ ! -d ~/.claude/skills/vibesec ]; then
  git clone --depth 1 https://github.com/BehiSecc/VibeSec-Skill.git ~/.claude/skills/vibesec 2>/dev/null && ok "vibesec" || warn "vibesec"
else ok "vibesec (exists)"; fi
# Add paths scoping to vibesec (758 lines — only load for web/security files)
if [ -f ~/.claude/skills/vibesec/SKILL.md ] && ! grep -q '^paths:' ~/.claude/skills/vibesec/SKILL.md 2>/dev/null; then
  sed -i '3a paths: ["**/*.html", "**/*.htm", "**/*.js", "**/*.ts", "**/*.jsx", "**/*.tsx", "**/*.vue", "**/*.svelte", "**/*.py", "**/routes*", "**/auth*", "**/views*", "**/controllers*", "**/api*", "**/nginx*", "**/Dockerfile*", "**/docker-compose*"]' ~/.claude/skills/vibesec/SKILL.md
fi

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
# Fix SKILL.md path: plugin structure nests SKILL.md under skills/modern-python/, Claude expects root
# Also add paths scoping so it only loads for Python files
if [ -f ~/.claude/skills/trailofbits-modern-python/skills/modern-python/SKILL.md ] \
   && [ ! -f ~/.claude/skills/trailofbits-modern-python/SKILL.md ]; then
  sed '3a paths: ["**/*.py", "**/pyproject.toml", "**/setup.py", "**/setup.cfg", "**/requirements*.txt", "**/.python-version", "**/uv.lock", "**/Pipfile*"]' \
    ~/.claude/skills/trailofbits-modern-python/skills/modern-python/SKILL.md \
    > ~/.claude/skills/trailofbits-modern-python/SKILL.md
  ok "trailofbits: SKILL.md fixed at root with paths scoping"
elif [ -f ~/.claude/skills/trailofbits-modern-python/SKILL.md ] && ! grep -q '^paths:' ~/.claude/skills/trailofbits-modern-python/SKILL.md 2>/dev/null; then
  sed -i '3a paths: ["**/*.py", "**/pyproject.toml", "**/setup.py", "**/setup.cfg", "**/requirements*.txt", "**/.python-version", "**/uv.lock", "**/Pipfile*"]' \
    ~/.claude/skills/trailofbits-modern-python/SKILL.md
fi
# Remove duplicate nested SKILL.md — root copy has correct paths: scoping; nested is always-on (bug)
rm -f ~/.claude/skills/trailofbits-modern-python/skills/modern-python/SKILL.md 2>/dev/null || true

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

install -Dm644 "$REPO_FILES/dot-claude/commands/context.md" "$CLAUDE_DIR/commands/context.md"
ok "command: /context"

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
  case $_slot_i in 1|2|3) _slot_model="haiku" ;; 4) _slot_model="sonnet" ;; 5) _slot_model="opus" ;; esac
  _slot_i="$_slot_i" _slot_model="$_slot_model" \
    envsubst '$_slot_i $_slot_model' \
    < "$REPO_FILES/dot-claude/agents/slot-template.md" \
    > "$CLAUDE_DIR/agents/slot-${_slot_i}.md"
  ok "agent: slot-${_slot_i} [${_slot_model}]"
done
unset _slot_i _slot_model

# ─── agt config ───
install -Dm644 "$REPO_FILES/config/agt/config" "$HOME/.config/agt/config"
ok "agt: config"

# ─── agt CLI ───
install -Dm755 "$REPO_FILES/bin/agt" "$HOME/.local/bin/agt"
ok "agt: CLI installed"

# ─── Agent stash: clone or update from GitHub ───
AGT_STASH_REPO="https://github.com/SutanuNandigrami/agent-stash.git"
AGT_STASH_DIR="$HOME/.claude/agent-stash"
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
(crontab -l 2>/dev/null | grep -v 'agt build-index\|agt-refresh' || true; \
  echo "0 3 * * 0 cd \$HOME/.claude/agent-stash && git pull --ff-only 2>/dev/null && \$HOME/.local/bin/agt build-index >> \$HOME/.claude/logs/agt-refresh.log 2>&1") | crontab -
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
# a script), then re-run plugin installs with: claude plugin install hookify
if command -v claude &>/dev/null && ! claude auth status &>/dev/null 2>&1; then
  warn "Claude not authenticated — plugins will be skipped"
  echo "  After setup, run 'claude auth login' then:"
  echo "    claude plugin marketplace add anthropic/claude-plugins-official"
  echo "    claude plugin install hookify code-review skill-creator"
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
  claude plugin install hookify 2>/dev/null && ok "hookify" || warn "hookify"
  claude plugin install code-review 2>/dev/null && ok "code-review" || warn "code-review"
  claude plugin install skill-creator 2>/dev/null && ok "skill-creator" || warn "skill-creator"

  # semgrep plugin — only if token was provided
  if [[ -n "$SEMGREP_TOKEN" ]] && ! $SEMGREP_SKIP; then
    if claude plugin install semgrep 2>/dev/null; then
      ok "semgrep plugin"
      # Patch semgrep hooks.json to guard against non-git-repo dirs
      # semgrep ci requires a git root; without this guard, every Write/Edit outside a repo fails
      _SEMGREP_HOOKS=$(find "$HOME/.claude/plugins/cache" -path '*/semgrep/*/hooks/hooks.json' | head -1)
      if [[ -f "$_SEMGREP_HOOKS" ]]; then
        jq '(.hooks.PostToolUse[].hooks[].command) |= "git rev-parse --git-dir &>/dev/null && " + . + " || true"' \
          "$_SEMGREP_HOOKS" > /tmp/_semgrep_hooks.json \
          && mv /tmp/_semgrep_hooks.json "$_SEMGREP_HOOKS" \
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

  # claude-subconscious — Letta-based persistent cross-session memory agent
  if ! $LETTA_SKIP; then
    claude plugin marketplace add letta-ai/claude-subconscious 2>/dev/null \
      && ok "letta marketplace" || ok "letta marketplace (exists)"
    if claude plugin install claude-subconscious 2>/dev/null; then
      ok "claude-subconscious plugin"

      # Install node_modules (tsx + @letta-ai/letta-code-sdk) — CC does not auto-install plugin deps
      _SUBCON_DIR=$(jq -r '.plugins["claude-subconscious@claude-subconscious"][0].installPath // empty' \
        "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null)
      if [[ -n "$_SUBCON_DIR" ]] && [[ -f "$_SUBCON_DIR/package.json" ]]; then
        (cd "$_SUBCON_DIR" && npm install --silent 2>/dev/null) \
          && ok "subconscious: node_modules installed" \
          || warn "subconscious: npm install failed — hooks may not work"
      fi

      # Patch Subconscious.af: override LLM + embedding to use self-hosted Letta infrastructure
      # Default .af uses openai/text-embedding-3-small and zai/glm-5 (cloud only)
      _SUBCON_AF=""
      if [[ -f "$HOME/.claude/plugins/installed_plugins.json" ]]; then
        _SUBCON_INSTALL=$(jq -r '.plugins["claude-subconscious@claude-subconscious"][0].installPath // empty' \
          "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null)
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
        ' "$_SUBCON_AF" > /tmp/_subcon_af.json \
          && mv /tmp/_subcon_af.json "$_SUBCON_AF" \
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
          ' "$_SUBCON_AF" > /tmp/_subcon_af.json \
            && mv /tmp/_subcon_af.json "$_SUBCON_AF" \
            && ok "subconscious: .af patched (embeddings → ollama/nomic-embed-text)" \
            || warn "subconscious: .af embedding patch failed"
        fi
      else
        warn "subconscious: Subconscious.af not found — .af patching skipped"
      fi

      # Enable plugin in settings.json
      jq '.enabledPlugins["claude-subconscious@claude-subconscious"] = true' \
        "$CLAUDE_DIR/settings.json" > /tmp/_cc_settings.json \
        && mv /tmp/_cc_settings.json "$CLAUDE_DIR/settings.json" \
        && ok "subconscious: enabled in settings.json" \
        || warn "subconscious: settings.json update failed"
    else
      warn "claude-subconscious plugin install failed"
    fi
  fi

  # ─── LettaCtrl GUI — web dashboard for Letta management ───
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
      cat > "$HOME/.config/letta/letta-ctrl-server.js" << 'LETTA_CTRL_SERVER'
import { spawnSync, spawn } from "node:child_process";
import { readFileSync, writeFileSync, existsSync, mkdirSync, chmodSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { randomBytes, timingSafeEqual } from "node:crypto";

// ── Config ──────────────────────────────────────────────────────────────────
const PORT = Number(process.env.LETTA_CTRL_PORT || 8284);
const LETTA_URL = process.env.LETTA_BASE_URL || "http://127.0.0.1:8283";
const HTML_FILE = join(homedir(), ".config/letta/letta-ctrl.html");

// ── Auth token ──────────────────────────────────────────────────────────────
const TOKEN_FILE = join(homedir(), ".config/letta/ctrl-token");
let AUTH_TOKEN = process.env.LETTA_CTRL_TOKEN || "";
if (!AUTH_TOKEN) {
  if (existsSync(TOKEN_FILE)) {
    AUTH_TOKEN = readFileSync(TOKEN_FILE, "utf8").trim();
  }
  if (!AUTH_TOKEN) {
    AUTH_TOKEN = randomBytes(32).toString("hex");
    const tokenDir = join(homedir(), ".config/letta");
    if (!existsSync(tokenDir)) mkdirSync(tokenDir, { recursive: true });
    writeFileSync(TOKEN_FILE, AUTH_TOKEN + "\n", { mode: 0o600 });
    try { chmodSync(TOKEN_FILE, 0o600); } catch {}
    console.log(`Generated LettaCtrl token: ${AUTH_TOKEN}`);
    console.log(`Token saved to: ${TOKEN_FILE}`);
  }
}

function checkAuth(req) {
  const hdr = req.headers.get("authorization") || "";
  const prefix = "Bearer ";
  if (!hdr.startsWith(prefix)) return false;
  const provided = hdr.slice(prefix.length);
  const a = Buffer.from(AUTH_TOKEN);
  const b = Buffer.from(provided);
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

// Read Letta credentials from file (set at install time by titan-setup.sh)
const CREDS_FILE = join(homedir(), ".config/letta/credentials");
let LETTA_PASSWORD = process.env.LETTA_API_KEY || "";
if (!LETTA_PASSWORD && existsSync(CREDS_FILE)) {
  const creds = readFileSync(CREDS_FILE, "utf8");
  const match = creds.match(/LETTA_SERVER_PASSWORD=([^\n]+)/);
  if (match) LETTA_PASSWORD = match[1].trim();
}

// Services: letta/better-ccflare/ccflare-docker-proxy are --user; ollama is system-level
const SERVICES = [
  { name: "letta",                user: true  },
  { name: "ollama",               user: false },
  { name: "better-ccflare",       user: true  },
  { name: "ccflare-docker-proxy", user: true  },
];

// ── Helpers ──────────────────────────────────────────────────────────────────
function lettaHeaders() {
  return {
    "Authorization": `Bearer ${LETTA_PASSWORD}`,
    "Content-Type": "application/json",
  };
}

function parseUptime(timestamp) {
  if (!timestamp || timestamp === "n/a") return "—";
  const start = new Date(timestamp.replace(/\s(UTC|[A-Z]{3})$/, "Z"));
  if (isNaN(start)) return "—";
  const secs = Math.floor((Date.now() - start) / 1000);
  if (secs < 60) return `${secs}s`;
  if (secs < 3600) return `${Math.floor(secs / 60)}m`;
  const h = Math.floor(secs / 3600), m = Math.floor((secs % 3600) / 60);
  return `${h}h ${m}m`;
}

function getServiceStatus(svc) {
  const args = ["show", svc.name,
    "--property=ActiveState,MemoryCurrent,CPUUsageNSec,ActiveEnterTimestamp"];
  if (svc.user) args.unshift("--user");
  const r = spawnSync("systemctl", args, { encoding: "utf8" });
  const props = Object.fromEntries(
    (r.stdout || "").trim().split("\n")
      .map(l => l.split("=", 2))
      .filter(p => p.length === 2)
  );
  const active = props.ActiveState === "active";
  const memBytes = parseInt(props.MemoryCurrent || "0", 10);
  const memMb = isNaN(memBytes) || memBytes <= 0 ? 0 : Math.round(memBytes / 1024 / 1024);
  return {
    active,
    memory_mb: memMb,
    cpu_pct: 0,
    uptime: active ? parseUptime(props.ActiveEnterTimestamp) : "—",
  };
}

// ── Route handlers ────────────────────────────────────────────────────────────
async function handleStatus() {
  const result = {};
  for (const svc of SERVICES) result[svc.name] = getServiceStatus(svc);
  return Response.json(result);
}

async function proxyLetta(path, req) {
  const url = `${LETTA_URL}${path}`;
  const init = {
    method: req.method,
    headers: lettaHeaders(),
  };
  if (req.method !== "GET" && req.method !== "DELETE") {
    init.body = await req.text();
  }
  try {
    const res = await fetch(url, init);
    const body = await res.text();
    return new Response(body, {
      status: res.status,
      headers: { "Content-Type": res.headers.get("Content-Type") || "application/json" },
    });
  } catch (e) {
    console.error(`Letta proxy error on ${path}:`, e.message);
    return Response.json({ error: "Letta server unavailable" }, { status: 502 });
  }
}

function handleLogs(svcName) {
  const svc = SERVICES.find(s => s.name === svcName);
  if (!svc) return new Response("Unknown service", { status: 404 });

  const args = svc.user
    ? ["--user", "-u", svcName, "-f", "-n", "20", "--no-pager", "--output=short-iso"]
    : ["-u", svcName, "-f", "-n", "20", "--no-pager", "--output=short-iso"];

  let child;
  const stream = new ReadableStream({
    start(ctrl) {
      child = spawn("journalctl", args);
      const enc = new TextEncoder();
      child.stdout.on("data", chunk => {
        for (const line of chunk.toString().split("\n")) {
          if (line.trim()) ctrl.enqueue(enc.encode(`data: ${JSON.stringify(line)}\n\n`));
        }
      });
      child.stderr.on("data", () => {});
      child.on("close", () => ctrl.close());
    },
    cancel() { child?.kill(); },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      "Connection": "keep-alive",
      "Access-Control-Allow-Origin": "*",
    },
  });
}

// ── Router ────────────────────────────────────────────────────────────────────
Bun.serve({
  port: PORT,
  hostname: "0.0.0.0",
  async fetch(req) {
    const url = new URL(req.url);
    const path = url.pathname;

    // Static
    if (path === "/" || path === "/index.html") {
      try {
        const html = readFileSync(HTML_FILE, "utf8");
        return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
      } catch {
        return new Response("letta-ctrl.html not found", { status: 500 });
      }
    }

    // CORS preflight
    if (req.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET,POST,PATCH,DELETE,OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Authorization",
        },
      });
    }

    // Auth check for all /api/* routes
    if (path.startsWith("/api/")) {
      if (!checkAuth(req)) {
        return Response.json({ error: "Unauthorized" }, { status: 401 });
      }
    }

    // API
    if (path === "/api/ping") return Response.json({ ok: true });
    if (path === "/api/status") return handleStatus();
    if (path.startsWith("/api/logs/")) return handleLogs(path.slice("/api/logs/".length));

    // Letta proxy
    if (path === "/api/agents" && req.method === "GET")    return proxyLetta("/v1/agents", req);
    if (path === "/api/agents" && req.method === "POST")   return proxyLetta("/v1/agents", req);
    const agentMatch = path.match(/^\/api\/agents\/([^/]+)$/);
    if (agentMatch) {
      if (req.method === "DELETE") return proxyLetta(`/v1/agents/${agentMatch[1]}`, req);
      if (req.method === "GET")    return proxyLetta(`/v1/agents/${agentMatch[1]}`, req);
    }
    const blocksMatch = path.match(/^\/api\/agents\/([^/]+)\/blocks$/);
    if (blocksMatch && req.method === "GET")
      return proxyLetta(`/v1/agents/${blocksMatch[1]}/core-memory/blocks`, req);

    const blockMatch = path.match(/^\/api\/agents\/([^/]+)\/blocks\/([^/]+)$/);
    if (blockMatch && req.method === "PATCH")
      return proxyLetta(`/v1/agents/${blockMatch[1]}/core-memory/blocks/${blockMatch[2]}`, req);

    const msgMatch = path.match(/^\/api\/agents\/([^/]+)\/messages$/);
    if (msgMatch && req.method === "POST")
      return proxyLetta(`/v1/agents/${msgMatch[1]}/messages`, req);

    // Service control (restart/stop/start via systemctl)
    const svcActionMatch = path.match(/^\/api\/svc\/([^/]+)\/(restart|stop|start)$/);
    if (svcActionMatch && req.method === "POST") {
      const [, svcName, action] = svcActionMatch;
      const svc = SERVICES.find(s => s.name === svcName);
      if (!svc) return new Response("Unknown service", { status: 404 });
      const args = svc.user ? ["--user", action, svcName] : [action, svcName];
      const r2 = spawnSync("systemctl", args, { encoding: "utf8" });
      return Response.json({ ok: r2.status === 0, stderr: r2.stderr });
    }

    return new Response("Not found", { status: 404 });
  },
});

console.log(`letta-ctrl 0.0.0.0:${PORT} → ${LETTA_URL}`);

LETTA_CTRL_SERVER

      # Write frontend
      cat > "$HOME/.config/letta/letta-ctrl.html" << 'LETTA_CTRL_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>LettaCtrl</title>
<style>
/* ── Reset + Base ─────────────────────────────────────────────── */
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;width:100%;overflow:hidden}
body{background:#18181b;color:#fafafa;font-family:'Inter',system-ui,sans-serif;font-size:14px;display:flex;flex-direction:column}
button{cursor:pointer;border:none;font-family:inherit;font-size:inherit}
input,textarea{font-family:inherit;font-size:inherit}
::-webkit-scrollbar{width:4px;height:4px}
::-webkit-scrollbar-track{background:transparent}
::-webkit-scrollbar-thumb{background:#3f3f46;border-radius:4px}

/* ── Tokens ─────────────────────────────────────────────────── */
/* bg:#18181b  surface:#27272a  border:#3f3f46  text:#fafafa   */
/* muted:#71717a  accent:#a78bfa  green:#34d399  red:#f87171   */
/* amber:#fbbf24  purple:#8b5cf6                               */

/* ── Nav ─────────────────────────────────────────────────────── */
.nav{background:#09090b;border-bottom:1px solid #27272a;padding:0 24px;height:52px;display:flex;align-items:center;gap:24px;flex-shrink:0;z-index:10}
.logo{color:#8b5cf6;font-weight:800;font-size:15px;display:flex;align-items:center;gap:8px;letter-spacing:-.4px}
.tabs{display:flex;gap:2px}
.tab{padding:6px 16px;border-radius:6px;color:#71717a;font-size:13px;font-weight:500;background:none;transition:all .15s}
.tab:hover{color:#a1a1aa;background:#27272a}
.tab.on{color:#fafafa;background:#27272a}
.nav-right{margin-left:auto;display:flex;gap:8px}
.hp{display:flex;align-items:center;gap:5px;padding:4px 11px;border-radius:5px;font-size:11px;font-weight:600;border:1px solid transparent;transition:all .3s}
.hp.ok  {background:#052010;border-color:#14532d;color:#34d399}
.hp.dead{background:#1c0505;border-color:#450a0a;color:#f87171}
.hpdot{width:6px;height:6px;border-radius:50%;background:currentColor}
.hp.ok .hpdot{animation:pulse 2s infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}

/* ── Panels ─────────────────────────────────────────────────── */
.panel{display:none;flex:1;overflow-y:auto;padding:20px 24px;flex-direction:column}
.panel.on{display:flex}
.slabel{font-size:10px;font-weight:700;color:#52525b;text-transform:uppercase;letter-spacing:.1em;margin-bottom:12px}

/* ── Service Cards ──────────────────────────────────────────── */
.svcgrid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:24px}
.svc{background:#27272a;border:1px solid #3f3f46;border-radius:10px;overflow:hidden;display:flex;flex-direction:column;border-top:2px solid #3f3f46;transition:border-top-color .3s}
.svc.ok  {border-top-color:#16a34a}
.svc.dead{border-top-color:#dc2626}
.svchdr{padding:12px 14px;display:flex;align-items:center;gap:8px}
.svcdot{width:9px;height:9px;border-radius:50%;flex-shrink:0;background:#71717a}
.svc.ok   .svcdot{background:#34d399;box-shadow:0 0 7px #34d39988;animation:pulse 2s infinite}
.svc.dead .svcdot{background:#f87171;box-shadow:0 0 7px #f8717188}
.svcname{font-weight:700;font-size:13px}
.svcport{margin-left:auto;font-size:11px;color:#52525b;background:#09090b;padding:2px 6px;border-radius:4px;font-family:monospace}
.svcmet{padding:4px 14px 10px;display:grid;grid-template-columns:1fr 1fr;gap:6px}
.met{background:#18181b;border-radius:6px;padding:7px 9px}
.mlabel{font-size:9px;color:#52525b;text-transform:uppercase;letter-spacing:.06em;margin-bottom:3px}
.mval{font-size:18px;font-weight:800;font-family:monospace;line-height:1}
.mval.num{color:#a78bfa}
.mval.ok {color:#34d399}
.mval.dim{color:#71717a;font-size:14px}
.munit{font-size:10px;color:#52525b;font-weight:400}
.svclog{background:#09090b;font-family:monospace;font-size:10.5px;color:#3f3f46;padding:8px 12px;height:72px;overflow-y:auto;line-height:1.65}
.ll-dim{color:#52525b}
.ll-ok {color:#16a34a}
.ll-err{color:#dc2626;font-weight:700}
.svcact{padding:7px 12px;display:flex;gap:6px;border-top:1px solid #27272a}
.btn{padding:4px 11px;border-radius:5px;font-size:11px;font-weight:600}
.btn-r{background:#27272a;color:#71717a}
.btn-r:hover{color:#fafafa;background:#3f3f46}
.btn-s{background:#1c0505;color:#f87171}
.btn-s:hover{background:#2a0808}
.btn-st{background:#052010;color:#34d399}

/* ── Agents ──────────────────────────────────────────────────── */
.agents-strip{display:flex;gap:10px;flex-wrap:wrap}
.achip{background:#27272a;border:1px solid #3f3f46;border-radius:9px;padding:11px 16px;display:flex;align-items:center;gap:14px;cursor:pointer;transition:border-color .15s}
.achip:hover{border-color:#7c3aed}
.achip-name{font-weight:700;font-size:13px}
.achip-meta{font-size:11px;color:#71717a;margin-top:3px}
.abadge{background:#1c1027;color:#8b5cf6;font-size:10px;padding:3px 8px;border-radius:4px;font-family:monospace;border:1px solid #2d1d60;white-space:nowrap}
.achip-new{border-style:dashed;color:#52525b;font-size:13px}

.aglay{display:grid;grid-template-columns:240px 1fr;gap:12px;flex:1;min-height:0}
.apanel{background:#27272a;border:1px solid #3f3f46;border-radius:10px;overflow:hidden;display:flex;flex-direction:column}
.apanelhdr{padding:10px 15px;border-bottom:1px solid #3f3f46;display:flex;align-items:center;justify-content:space-between;flex-shrink:0}
.apaneltitle{font-size:11px;font-weight:700;color:#71717a;text-transform:uppercase;letter-spacing:.07em}
.btn-new{background:#3b0764;color:#c4b5fd;font-size:11px;padding:4px 11px;border-radius:5px;border:1px solid #5b21b6;font-weight:600}
.btn-new:hover{background:#4c1d95}
.alist{overflow-y:auto;flex:1}
.aitem{padding:11px 15px;border-bottom:1px solid #1c1c1f;cursor:pointer}
.aitem:hover{background:#18181b}
.aitem.on{background:#1a1025;border-left:3px solid #7c3aed;padding-left:12px}
.aitem-name{font-size:13px;font-weight:700}
.aitem-meta{font-size:11px;color:#71717a;margin-top:2px}
.aempty{padding:20px 15px;font-size:12px;color:#52525b;text-align:center}

.aright{display:flex;flex-direction:column;min-height:0}
.adethdr{padding:12px 17px;border-bottom:1px solid #3f3f46;display:flex;align-items:center;gap:10px;flex-shrink:0}
.adetname{font-weight:800;font-size:14px}
.btn-del{margin-left:auto;background:#1c0505;color:#f87171;font-size:11px;padding:4px 11px;border-radius:5px;border:1px solid #450a0a;font-weight:600}
.btn-del:hover{background:#2a0808}
.dtabs{display:flex;padding:0 17px;border-bottom:1px solid #3f3f46;flex-shrink:0}
.dtab{padding:8px 15px;font-size:12px;color:#71717a;cursor:pointer;border-bottom:2px solid transparent;font-weight:500}
.dtab.on{color:#a78bfa;border-bottom-color:#7c3aed}
.dbody{overflow-y:auto;flex:1;padding:14px 17px}

/* Memory blocks */
.mblock{background:#18181b;border:1px solid #27272a;border-radius:7px;margin-bottom:10px}
.mbhdr{padding:7px 12px;background:#09090b;display:flex;align-items:center;border-radius:7px 7px 0 0;border-bottom:1px solid #27272a}
.mblabel{font-size:10px;font-weight:700;color:#7c3aed;text-transform:uppercase;letter-spacing:.06em}
.mbtokens{font-size:10px;color:#3f3f46;margin-left:auto}
.mbbody{padding:9px 12px;font-size:12px;color:#a1a1aa;line-height:1.65;font-family:monospace;outline:none;min-height:40px;white-space:pre-wrap;word-break:break-word}
.mbfoot{padding:6px 12px;border-top:1px solid #27272a;display:flex;justify-content:flex-end;gap:6px}
.btn-save{background:#3b0764;color:#c4b5fd;font-size:11px;padding:4px 12px;border-radius:4px;border:1px solid #5b21b6;font-weight:600}
.btn-save:hover{background:#4c1d95}
.btn-saved{background:#052010;color:#34d399;border-color:#14532d}

/* Test tab */
.testinput{width:100%;background:#18181b;border:1px solid #3f3f46;border-radius:6px;padding:9px 12px;color:#fafafa;font-size:12px;font-family:monospace;margin-bottom:8px;resize:vertical;min-height:60px}
.btn-send{background:#7c3aed;color:#fff;font-size:12px;padding:8px 18px;border-radius:6px;font-weight:600;margin-bottom:12px;display:inline-block}
.btn-send:hover{background:#6d28d9}
.btn-send:disabled{opacity:.5;cursor:not-allowed}
.testout{background:#18181b;border:1px solid #27272a;border-radius:6px;padding:12px;font-size:12px;color:#a78bfa;font-family:monospace;line-height:1.65;min-height:80px;white-space:pre-wrap}

/* Info tab */
.infogrid{display:grid;grid-template-columns:150px 1fr;gap:7px 14px;font-size:12px}
.ik{color:#71717a}
.iv{font-family:monospace;color:#fafafa;word-break:break-all}

/* Create modal */
.modal-bg{display:none;position:fixed;inset:0;background:rgba(0,0,0,.7);z-index:50;align-items:center;justify-content:center}
.modal-bg.on{display:flex}
.modal{background:#27272a;border:1px solid #3f3f46;border-radius:12px;padding:24px;width:400px}
.modal h3{font-size:15px;font-weight:700;margin-bottom:16px}
.modal label{display:block;font-size:11px;color:#71717a;margin-bottom:5px;text-transform:uppercase;letter-spacing:.05em}
.modal input,.modal select{width:100%;background:#18181b;border:1px solid #3f3f46;border-radius:6px;padding:8px 12px;color:#fafafa;font-size:13px;margin-bottom:14px}
.modal-btns{display:flex;gap:8px;justify-content:flex-end}
.btn-cancel{background:#27272a;color:#71717a;padding:7px 16px;border-radius:6px;font-weight:600;border:1px solid #3f3f46}
.btn-create{background:#7c3aed;color:#fff;padding:7px 16px;border-radius:6px;font-weight:600}

/* ── Logs ─────────────────────────────────────────────────────── */
.loglay{display:grid;grid-template-columns:160px 1fr;gap:12px;flex:1;min-height:0}
.lognav{display:flex;flex-direction:column;gap:5px}
.logbtn{background:#27272a;border:1px solid #3f3f46;border-radius:7px;padding:9px 13px;color:#71717a;font-size:12px;font-weight:500;display:flex;align-items:center;gap:8px;transition:all .1s;text-align:left}
.logbtn.on{border-color:#7c3aed;color:#fafafa;background:#1a1025}
.logbtn-dot{width:6px;height:6px;border-radius:50%;background:#34d399;flex-shrink:0}
.logpanel{background:#09090b;border:1px solid #27272a;border-radius:10px;overflow:hidden;display:flex;flex-direction:column}
.logphdr{padding:9px 15px;border-bottom:1px solid #27272a;display:flex;align-items:center;justify-content:space-between;background:#0c0c0e;flex-shrink:0}
.logptitle{font-size:12px;color:#52525b;font-family:monospace}
.live-badge{font-size:10px;color:#34d399;background:#052010;border:1px solid #14532d;padding:2px 8px;border-radius:10px;font-weight:600;animation:pulse 2s infinite}
.logstream{flex:1;overflow-y:auto;padding:10px 15px;font-family:monospace;font-size:12px;line-height:1.75}
.logstream .ts{color:#27272a;margin-right:10px;font-size:11px}
.ll-log{color:#52525b}
.ll-log.info{color:#71717a}
.ll-log.ok  {color:#16a34a}
.ll-log.warn{color:#d97706}
.ll-log.err {color:#dc2626;font-weight:700}
.logfilter{padding:8px 14px;border-top:1px solid #27272a;background:#0c0c0e;flex-shrink:0}
.loginput{width:100%;background:#09090b;border:1px solid #27272a;border-radius:5px;padding:5px 10px;color:#fafafa;font-size:12px;font-family:monospace}
</style>
</head>
<body>

<!-- NAV -->
<nav class="nav">
  <div class="logo">⬡ LettaCtrl</div>
  <div class="tabs">
    <button class="tab on"  onclick="goTab('overview',this)">Overview</button>
    <button class="tab"     onclick="goTab('agents',this)">Agents</button>
    <button class="tab"     onclick="goTab('logs',this)">Logs</button>
  </div>
  <div class="nav-right" id="health-pills"></div>
  <button onclick="logout()" title="Logout" style="background:none;border:1px solid #374151;color:#6b7280;padding:4px 10px;border-radius:6px;cursor:pointer;font-size:12px;margin-left:12px">Logout</button>
</nav>

<!-- AUTH OVERLAY -->
<div id="auth-overlay" style="display:none;position:fixed;inset:0;background:rgba(0,0,0,.7);z-index:999;align-items:center;justify-content:center">
  <div style="background:#1f2937;border:1px solid #374151;border-radius:12px;padding:32px;min-width:320px;max-width:400px">
    <div style="color:#8b5cf6;font-weight:700;font-size:16px;margin-bottom:16px">⬡ LettaCtrl — Enter Token</div>
    <p style="color:#9ca3af;font-size:13px;margin-bottom:16px">Enter your LettaCtrl token to continue.<br>Find it with: <code style="color:#c4b5fd">cat ~/.config/letta/ctrl-token</code></p>
    <input id="token-input" type="password" placeholder="Paste token here"
      style="width:100%;padding:10px 12px;background:#111827;border:1px solid #374151;border-radius:8px;color:#f9fafb;font-size:14px;margin-bottom:8px;outline:none"
      onkeydown="if(event.key==='Enter')saveToken()">
    <div id="token-error" style="color:#ef4444;font-size:12px;min-height:18px;margin-bottom:12px"></div>
    <button onclick="saveToken()" style="width:100%;padding:10px;background:#7c3aed;border:none;border-radius:8px;color:#fff;font-size:14px;font-weight:600;cursor:pointer">Connect</button>
  </div>
</div>

<!-- OVERVIEW -->
<div class="panel on" id="panel-overview">
  <div class="slabel">Services</div>
  <div class="svcgrid" id="svc-grid"></div>
  <div class="slabel">Agents</div>
  <div class="agents-strip" id="agents-strip"></div>
</div>

<!-- AGENTS -->
<div class="panel" id="panel-agents">
  <div class="aglay">
    <div class="apanel">
      <div class="apanelhdr">
        <span class="apaneltitle" id="agent-count">Agents (0)</span>
        <button class="btn-new" onclick="openCreateModal()">+ New</button>
      </div>
      <div class="alist" id="agent-list"></div>
    </div>
    <div class="apanel aright" id="agent-detail">
      <div style="display:flex;align-items:center;justify-content:center;flex:1;color:#52525b;font-size:13px">Select an agent</div>
    </div>
  </div>
</div>

<!-- LOGS -->
<div class="panel" id="panel-logs">
  <div class="loglay">
    <div class="lognav" id="log-nav"></div>
    <div class="logpanel">
      <div class="logphdr">
        <span class="logptitle" id="log-title">Select a service</span>
        <span class="live-badge">● live</span>
      </div>
      <div class="logstream" id="log-stream"><div style="color:#52525b;padding:8px">Select a service from the left.</div></div>
      <div class="logfilter">
        <input class="loginput" id="log-filter" placeholder="filter... (e.g. POST, error, 500)" oninput="filterLogs(this.value)">
      </div>
    </div>
  </div>
</div>

<!-- CREATE MODAL -->
<div class="modal-bg" id="create-modal">
  <div class="modal">
    <h3>New Agent</h3>
    <label>Name</label>
    <input type="text" id="new-agent-name" placeholder="my-agent">
    <label>Model</label>
    <input type="text" id="new-agent-model" value="anthropic/claude-sonnet-4-6">
    <div class="modal-btns">
      <button class="btn-cancel" onclick="closeCreateModal()">Cancel</button>
      <button class="btn-create" onclick="createAgent()">Create</button>
    </div>
  </div>
</div>

<script>
// ── Auth ──────────────────────────────────────────────────────────────────
let _token = localStorage.getItem("lettaCtrlToken") || "";

function authFetch(url, opts = {}) {
  const headers = Object.assign({ "Authorization": "Bearer " + _token }, opts.headers || {});
  return fetch(url, Object.assign({}, opts, { headers }));
}

function showTokenPrompt() {
  document.getElementById("auth-overlay").style.display = "flex";
}

function hideTokenPrompt() {
  document.getElementById("auth-overlay").style.display = "none";
}

async function saveToken() {
  const val = document.getElementById("token-input").value.trim();
  if (!val) return;
  _token = val;
  localStorage.setItem("lettaCtrlToken", val);
  // Verify token
  try {
    const r = await authFetch("/api/ping");
    if (r.status === 401) {
      document.getElementById("token-error").textContent = "Invalid token — try again";
      return;
    }
    hideTokenPrompt();
    await pollStatus();
    await fetchAgents();
    buildLogNav();
  } catch {
    document.getElementById("token-error").textContent = "Server unreachable";
  }
}

function logout() {
  _token = "";
  localStorage.removeItem("lettaCtrlToken");
  showTokenPrompt();
}

// ── State ─────────────────────────────────────────────────────────────────
const SVCS = ["letta","ollama","better-ccflare","ccflare-docker-proxy"];
let status     = {};
let agents     = [];
let curAgent   = null;
let curDtab    = "memory";
let logSvc     = null;
let logES      = null;
let logLines   = [];
let logFilter  = "";

// ── Tab navigation ────────────────────────────────────────────────────────
function goTab(name, btn) {
  document.querySelectorAll(".panel").forEach(p => p.classList.remove("on"));
  document.querySelectorAll(".tab").forEach(t => t.classList.remove("on"));
  document.getElementById("panel-" + name).classList.add("on");
  btn.classList.add("on");
  if (name === "agents") fetchAgents();
  if (name === "logs" && !logSvc) buildLogNav();
}

// ── Health pills ──────────────────────────────────────────────────────────
function buildHealthPills() {
  const c = document.getElementById("health-pills");
  c.innerHTML = SVCS.map(s => {
    const st = status[s];
    const ok = st?.active;
    const label = s.replace("ccflare-docker-proxy","billing-proxy").replace("better-ccflare","ccflare");
    return `<div class="hp ${ok?"ok":"dead"}" id="hp-${s}"><div class="hpdot"></div>${label}</div>`;
  }).join("");
}

function updatePills() {
  SVCS.forEach(s => {
    const el = document.getElementById("hp-" + s);
    if (!el) return;
    el.className = "hp " + (status[s]?.active ? "ok" : "dead");
  });
}

// ── Service cards ─────────────────────────────────────────────────────────
const SVC_EXTRA = {
  "letta":                 ["Health",    s => s.active ? "OK" : "DOWN"],
  "ollama":                ["Model",     s => s.active ? "✓" : "—"],
  "better-ccflare":        ["Accounts",  s => s.active ? "2" : "—"],
  "ccflare-docker-proxy":  ["Fix #89",   s => s.active ? "on" : "off"],
};

function renderSvcGrid() {
  const g = document.getElementById("svc-grid");
  g.innerHTML = SVCS.map(s => {
    const st = status[s] || {active:false, memory_mb:0, cpu_pct:0, uptime:"—"};
    const ok = st.active;
    const [extraLabel, extraFn] = SVC_EXTRA[s];
    const shortName = s.replace("ccflare-docker-proxy","billing-proxy");
    const ports = {letta:":8283",ollama:":11434","better-ccflare":":8080","ccflare-docker-proxy":":8081"};
    return `<div class="svc ${ok?"ok":"dead"}" id="svc-${s}">
      <div class="svchdr">
        <div class="svcdot"></div>
        <span class="svcname">${shortName}</span>
        <span class="svcport">${ports[s]||""}</span>
      </div>
      <div class="svcmet">
        <div class="met"><div class="mlabel">RAM</div><div class="mval num">${st.memory_mb||0}<span class="munit">MB</span></div></div>
        <div class="met"><div class="mlabel">CPU</div><div class="mval num">${st.cpu_pct||0}<span class="munit">%</span></div></div>
        <div class="met"><div class="mlabel">Uptime</div><div class="mval dim">${st.uptime||"—"}</div></div>
        <div class="met"><div class="mlabel">${extraLabel}</div><div class="mval ok">${extraFn(st)}</div></div>
      </div>
      <div class="svclog" id="log-tail-${s}"><span style="color:#3f3f46">Loading...</span></div>
      <div class="svcact">
        ${ok
          ? `<button class="btn btn-r" onclick="svcAction('restart','${s}')">↺ Restart</button>
             <button class="btn btn-s" onclick="svcAction('stop','${s}')">■ Stop</button>`
          : `<button class="btn btn-st" onclick="svcAction('start','${s}')">▶ Start</button>`}
      </div>
    </div>`;
  }).join("");
}

function updateSvcCard(s) {
  const card = document.getElementById("svc-" + s);
  if (!card) return;
  const st = status[s] || {active:false};
  card.className = "svc " + (st.active ? "ok" : "dead");
}

// ── Service actions ───────────────────────────────────────────────────────
async function svcAction(action, svcName) {
  await authFetch(`/api/svc/${svcName}/${action}`, {method:"POST"});
  setTimeout(pollStatus, 1000);
}

// ── Status polling ────────────────────────────────────────────────────────
async function pollStatus() {
  try {
    const r = await authFetch("/api/status");
    status = await r.json();
    if (!document.getElementById("hp-letta")) buildHealthPills();
    else updatePills();
    renderSvcGrid();
    renderAgentsStrip();
  } catch {}
}

// ── Agents strip (overview) ───────────────────────────────────────────────
function renderAgentsStrip() {
  const c = document.getElementById("agents-strip");
  if (!agents.length) {
    c.innerHTML = `<div class="achip achip-new" onclick="goTab('agents',document.querySelectorAll('.tab')[1])">+ New Agent</div>`;
    return;
  }
  c.innerHTML = agents.map(a =>
    `<div class="achip" onclick="goTab('agents',document.querySelectorAll('.tab')[1]);selectAgent('${escHtml(a.id)}')">
      <div>
        <div class="achip-name">${a.name}</div>
        <div class="achip-meta">${a.memory_blocks?.length||0} memory blocks</div>
      </div>
      <span class="abadge">${a.llm_config?.model||"unknown"}</span>
    </div>`
  ).join("") +
  `<div class="achip achip-new" onclick="goTab('agents',document.querySelectorAll('.tab')[1]);openCreateModal()">+ New</div>`;
}

// ── Agents CRUD ───────────────────────────────────────────────────────────
async function fetchAgents() {
  try {
    const r = await authFetch("/api/agents");
    agents = await r.json();
    renderAgentList();
    renderAgentsStrip();
    document.getElementById("agent-count").textContent = `Agents (${agents.length})`;
  } catch { agents = []; }
}

function renderAgentList() {
  const c = document.getElementById("agent-list");
  if (!agents.length) {
    c.innerHTML = `<div class="aempty">No agents yet.<br>Click + New to create one.</div>`;
    return;
  }
  c.innerHTML = agents.map(a =>
    `<div class="aitem ${curAgent?.id===a.id?"on":""}" onclick="selectAgent('${escHtml(a.id)}')">
      <div class="aitem-name">${a.name}</div>
      <div class="aitem-meta">${a.llm_config?.model||""} · ${a.memory_blocks?.length||0} blocks</div>
    </div>`
  ).join("");
}

async function selectAgent(id) {
  curAgent = agents.find(a => a.id === id) || null;
  if (!curAgent) return;
  renderAgentList();
  await renderAgentDetail();
}

async function renderAgentDetail() {
  if (!curAgent) return;
  const det = document.getElementById("agent-detail");
  det.innerHTML = `
    <div class="adethdr">
      <span class="adetname">${curAgent.name}</span>
      <span class="abadge">${curAgent.llm_config?.model||"?"}</span>
      <button class="btn-del" onclick="deleteAgent('${escHtml(curAgent.id)}')">✕ Delete</button>
    </div>
    <div class="dtabs">
      <div class="dtab ${curDtab==="memory"?"on":""}" onclick="goDtab('memory',this)">Memory Blocks</div>
      <div class="dtab ${curDtab==="test"?"on":""}" onclick="goDtab('test',this)">Test Message</div>
      <div class="dtab ${curDtab==="info"?"on":""}" onclick="goDtab('info',this)">Info</div>
    </div>
    <div class="dbody" id="dtab-body"></div>
  `;
  renderDtab();
}

function goDtab(name, btn) {
  curDtab = name;
  document.querySelectorAll(".dtab").forEach(t => t.classList.remove("on"));
  btn.classList.add("on");
  renderDtab();
}

async function renderDtab() {
  const body = document.getElementById("dtab-body");
  if (!body) return;
  if (curDtab === "memory") {
    try {
      const r = await authFetch(`/api/agents/${curAgent.id}/blocks`);
      const blocks = await r.json();
      body.innerHTML = blocks.map(b => {
        const rawLbl = b.label||b.id;
        const jsLbl = rawLbl.replace(/'/g, "\\'");
        return `<div class="mblock" id="mb-${rawLbl}">
          <div class="mbhdr">
            <span class="mblabel">${escHtml(rawLbl)}</span>
            <span class="mbtokens">${(b.value||"").length} / ${b.limit||2048} chars</span>
          </div>
          <div class="mbbody" contenteditable="true" id="mb-val-${rawLbl}"
            onblur="mbChanged('${jsLbl}')">${escHtml(b.value||"")}</div>
          <div class="mbfoot">
            <button class="btn-save" id="mb-save-${rawLbl}"
              onclick="saveBlock('${escHtml(curAgent.id)}','${jsLbl}')">Save</button>
          </div>
        </div>`;
      }).join("") || `<div style="color:#52525b;font-size:12px;padding:8px">No blocks found.</div>`;
    } catch {
      body.innerHTML = `<div style="color:#f87171;font-size:12px">Failed to load blocks.</div>`;
    }
  } else if (curDtab === "test") {
    body.innerHTML = `
      <p style="font-size:12px;color:#71717a;margin-bottom:12px">Send a message to this agent and see its response.</p>
      <textarea class="testinput" id="test-msg" placeholder="hello, what do you know about me?"></textarea>
      <button class="btn-send" id="btn-send" onclick="sendTestMsg()">Send →</button>
      <div class="testout" id="test-out" style="color:#52525b">Response will appear here.</div>
    `;
  } else if (curDtab === "info") {
    const a = curAgent;
    body.innerHTML = `<div class="infogrid">
      <span class="ik">Agent ID</span><span class="iv">${a.id}</span>
      <span class="ik">Name</span><span class="iv">${a.name}</span>
      <span class="ik">Model</span><span class="iv">${a.llm_config?.model||"—"}</span>
      <span class="ik">Endpoint</span><span class="iv">${a.llm_config?.model_endpoint||"—"}</span>
      <span class="ik">Embed model</span><span class="iv">${a.embedding_config?.embedding_model||"—"}</span>
      <span class="ik">Embed endpoint</span><span class="iv">${a.embedding_config?.embedding_endpoint||"—"}</span>
      <span class="ik">Embed dim</span><span class="iv">${a.embedding_config?.embedding_dim||"—"}</span>
      <span class="ik">Memory blocks</span><span class="iv">${a.memory_blocks?.length||0}</span>
    </div>`;
  }
}

function mbChanged(label) {
  const btn = document.getElementById(`mb-save-${label}`);
  if (btn) { btn.textContent = "Save*"; btn.classList.remove("btn-saved"); }
}

async function saveBlock(agentId, label) {
  const el = document.getElementById(`mb-val-${label}`);
  const btn = document.getElementById(`mb-save-${label}`);
  if (!el || !btn) return;
  btn.disabled = true; btn.textContent = "Saving…";
  try {
    const r = await authFetch(`/api/agents/${agentId}/blocks/${label}`, {
      method: "PATCH",
      headers: {"Content-Type":"application/json"},
      body: JSON.stringify({value: el.innerText}),
    });
    if (r.ok) { btn.textContent = "Saved ✓"; btn.classList.add("btn-saved"); }
    else { btn.textContent = "Error"; }
  } catch { btn.textContent = "Error"; }
  btn.disabled = false;
}

async function sendTestMsg() {
  const textarea = document.getElementById("test-msg");
  const out = document.getElementById("test-out");
  const btn = document.getElementById("btn-send");
  if (!textarea || !out) return;
  if (!curAgent) { out.style.color = "#f87171"; out.textContent = "No agent selected."; return; }
  btn.disabled = true; out.style.color = "#71717a"; out.textContent = "Sending…";
  try {
    const r = await authFetch(`/api/agents/${curAgent.id}/messages`, {
      method: "POST",
      headers: {"Content-Type":"application/json"},
      body: JSON.stringify({messages:[{role:"user",content:textarea.value}]}),
    });
    const data = await r.json();
    const msg = data.messages?.find(m => m.message_type === "assistant_message");
    out.style.color = "#a78bfa";
    out.textContent = msg?.content || JSON.stringify(data, null, 2);
  } catch(e) {
    out.style.color = "#f87171"; out.textContent = "Error: " + e.message;
  }
  btn.disabled = false;
}

async function deleteAgent(id) {
  if (!confirm("Delete this agent? This cannot be undone.")) return;
  await authFetch(`/api/agents/${id}`, {method:"DELETE"});
  curAgent = null;
  document.getElementById("agent-detail").innerHTML =
    `<div style="display:flex;align-items:center;justify-content:center;flex:1;color:#52525b;font-size:13px">Select an agent</div>`;
  await fetchAgents();
}

function openCreateModal() { document.getElementById("create-modal").classList.add("on"); }
function closeCreateModal() { document.getElementById("create-modal").classList.remove("on"); }

async function createAgent() {
  const name  = document.getElementById("new-agent-name").value.trim();
  const model = document.getElementById("new-agent-model").value.trim();
  if (!name) return alert("Name is required");
  const r = await authFetch("/api/agents", {
    method:"POST",
    headers:{"Content-Type":"application/json"},
    body: JSON.stringify({name, llm: model, embedding: "ollama/nomic-embed-text",
      memory_blocks:[{label:"persona",value:"",limit:2000}], include_base_tools:true}),
  });
  if (r.ok) {
    document.getElementById("new-agent-name").value = "";
    closeCreateModal();
    await fetchAgents();
  }
  else { const e = await r.text(); alert("Failed: " + e); }
}

// ── Logs ──────────────────────────────────────────────────────────────────
function buildLogNav() {
  const c = document.getElementById("log-nav");
  c.innerHTML = SVCS.map(s =>
    `<button class="logbtn ${logSvc===s?"on":""}" onclick="setLogSvc('${s}',this)">
      <span class="logbtn-dot"></span>${s.replace("ccflare-docker-proxy","billing-proxy")}
    </button>`
  ).join("");
}

function setLogSvc(svc, btn) {
  logSvc = svc;
  logLines = [];
  if (logES) logES.close();
  document.querySelectorAll(".logbtn").forEach(b => b.classList.remove("on"));
  btn.classList.add("on");
  document.getElementById("log-title").textContent = `journalctl ${svc==="ollama"?"":"--user"} -u ${svc} -f`;
  document.getElementById("log-stream").innerHTML = "";

  logES = new EventSource(`/api/logs/${svc}`);
  logES.onmessage = e => {
    const line = JSON.parse(e.data);
    logLines.push(line);
    if (logLines.length > 500) logLines.shift();
    appendLogLine(line);
  };
  logES.onerror = () => {};
}

function classifyLog(line) {
  const l = line.toLowerCase();
  if (/error|fail|fatal|exception|traceback|500/.test(l)) return "err";
  if (/warn/.test(l)) return "warn";
  if (/start|ok|success|200|201|healthy/.test(l)) return "ok";
  return "info";
}

function appendLogLine(line) {
  if (logFilter && !line.toLowerCase().includes(logFilter.toLowerCase())) return;
  const stream = document.getElementById("log-stream");
  const div = document.createElement("div");
  div.className = "ll-log " + classifyLog(line);
  div.textContent = line;
  stream.appendChild(div);
  stream.scrollTop = stream.scrollHeight;
}

function filterLogs(val) {
  logFilter = val;
  const stream = document.getElementById("log-stream");
  stream.innerHTML = "";
  logLines
    .filter(l => !val || l.toLowerCase().includes(val.toLowerCase()))
    .forEach(l => appendLogLine(l));
}

// ── Utils ─────────────────────────────────────────────────────────────────
function escHtml(s) {
  return s.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");
}

// ── Boot ──────────────────────────────────────────────────────────────────
(async () => {
  if (!_token) {
    showTokenPrompt();
    return;
  }
  // Verify existing token
  try {
    const r = await authFetch("/api/ping");
    if (r.status === 401) {
      _token = "";
      localStorage.removeItem("lettaCtrlToken");
      showTokenPrompt();
      return;
    }
  } catch {
    showTokenPrompt();
    return;
  }
  await pollStatus();
  await fetchAgents();
  buildLogNav();
  setInterval(pollStatus, 5000);
})();
</script>
</body>
</html>

LETTA_CTRL_HTML

      # Systemd user service
      mkdir -p "$HOME/.config/systemd/user"
      cat > "$HOME/.config/systemd/user/letta-ctrl.service" << LETTA_CTRL_SVC
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
  # This prevents skill-creator/hookify/episodic-memory from loading on every turn (93% token reduction)
  _patch_plugin_skill() {
    local plugin_key="$1" subpath="$2" paths_value="$3"
    local install_path
    install_path=$(jq -r --arg k "$plugin_key" '.plugins[$k][0].installPath // empty' \
      "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null)
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
  _patch_plugin_skill "hookify@claude-plugins-official" \
    "skills/writing-rules/SKILL.md" \
    '["**/.claude/**", "**/hooks/**", "**/rules/**", "**/hookify*"]'
  _patch_plugin_skill "episodic-memory@superpowers-marketplace" \
    "skills/remembering-conversations/SKILL.md" \
    '["**/memory/**", "**/.claude/memory/**", "**/handoff*", "**/_scratchpad*"]'

  # Cleanup: remove non-installed plugin dirs from marketplace cache to prevent SKILL.md bloat
  # Each marketplace add can bring many plugin dirs; only keep what's actually installed
  INSTALLED_JSON="$HOME/.claude/plugins/installed_plugins.json"
  if [[ -f "$INSTALLED_JSON" ]]; then
    CACHE_ROOT="$HOME/.claude/plugins/cache"
    mapfile -t ACTIVE_PATHS < <(jq -r '.plugins | to_entries[] | .value[] | .installPath' "$INSTALLED_JSON" 2>/dev/null)
    if [[ -d "$CACHE_ROOT" ]]; then
      while IFS= read -r -d '' vpath; do
        vpath="${vpath%/}"
        is_active=false
        for ap in "${ACTIVE_PATHS[@]}"; do
          [[ "$ap" == "$vpath" ]] && { is_active=true; break; }
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
SHELL_BLOCK='
# ══════ Titan CLI Arsenal ══════
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.cargo/bin:$HOME/go/bin:/usr/local/go/bin:$PATH"
eval "$(direnv hook bash)"
eval "$(mise activate bash)"
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


# ─── VPS — Tailscale + finalize ───
if [[ "$INSTALL_MODE" == "vps" ]]; then
  # ── Tailscale — install, connect, lock SSH ─────────────────────────────
  if ! command -v tailscale &>/dev/null; then
    run_q curl -fsSL https://tailscale.com/install.sh | sh
  fi
  # --reset ensures idempotent re-runs; --operator grants non-root user access
  sudo tailscale up --authkey="$TAILSCALE_KEY" --ssh --accept-routes --accept-dns \
    --operator="$USER" --reset
  ok "Tailscale connected"

  # Wait for Tailscale IP (up to 60s)
  TS_IP=""
  for _i in $(seq 1 30); do
    TS_IP=$(tailscale ip -4 2>/dev/null || true)
    [[ -n "$TS_IP" ]] && break
    sleep 2
  done
  [[ -z "$TS_IP" ]] && { fail "Tailscale connected but no IPv4 assigned — aborting"; exit 1; }

  # Get MagicDNS hostname for service URLs
  TS_HOSTNAME=$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty' | sed 's/\.$//')

  # ── tailscale serve — expose local services on Tailscale network ───────
  if command -v docker &>/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q n8n; then
    tailscale serve --bg --https=5678 http://localhost:5678 2>/dev/null \
      && ok "tailscale serve: n8n → https://${TS_HOSTNAME}:5678" \
      || warn "tailscale serve for n8n failed — run: tailscale serve --https=5678 http://localhost:5678"
  elif command -v docker &>/dev/null; then
    ok "tailscale serve: n8n skipped (container not running — run tailscale serve manually once n8n starts)"
  fi
  if ! $CCFLARE_SKIP; then
    tailscale serve --bg --https="${CCFLARE_PORT}" "http://localhost:${CCFLARE_PORT}" 2>/dev/null \
      && ok "tailscale serve: ccflare → https://${TS_HOSTNAME}:${CCFLARE_PORT}" \
      || warn "tailscale serve for ccflare failed — run: tailscale serve --https=${CCFLARE_PORT} http://localhost:${CCFLARE_PORT}"
  fi
  if ! $LETTA_SKIP; then
    tailscale serve --bg --https="${LETTA_PORT}" "http://localhost:${LETTA_PORT}" 2>/dev/null \
      && ok "tailscale serve: letta → https://${TS_HOSTNAME}:${LETTA_PORT}" \
      || warn "tailscale serve for letta failed — run: tailscale serve --https=${LETTA_PORT} http://localhost:${LETTA_PORT}"
  fi
  if ! $LETTA_CTRL_SKIP && ! $LETTA_SKIP; then
    tailscale serve --bg --https="${LETTA_CTRL_PORT}" "http://localhost:${LETTA_CTRL_PORT}" 2>/dev/null \
      && ok "tailscale serve: letta-ctrl → https://${TS_HOSTNAME}:${LETTA_CTRL_PORT}" \
      || warn "tailscale serve for letta-ctrl failed — run: tailscale serve --https=${LETTA_CTRL_PORT} http://localhost:${LETTA_CTRL_PORT}"
  fi

  # ── Add Claude user to docker group ────────────────────────────────────
  command -v docker &>/dev/null && sudo usermod -aG docker "$CLAUDE_USER" || true
  ok "$CLAUDE_USER: docker group membership ensured"

  # ── Lock root account ──────────────────────────────────────────────────
  sudo passwd -l root
  ok "Root account locked"

fi

# ── VPS: lock SSH to Tailscale (silently — summary follows) ────────────────
if [[ "$INSTALL_MODE" == "vps" ]]; then
  sudo ufw allow in on tailscale0 to any port 22 proto tcp
  sudo ufw delete allow 22/tcp || true
  sudo ufw delete allow OpenSSH 2>/dev/null || true
  sudo sed -i '/^#\?ListenAddress /d' /etc/ssh/sshd_config
  echo "ListenAddress $TS_IP" | sudo tee -a /etc/ssh/sshd_config > /dev/null
  # Capture compliance output BEFORE sshd restart (restart runs last, after all output)
  COMPLIANCE_OUT=$(sudo /usr/local/bin/compliance_check.sh 2>/dev/null || true)
fi

# ── Desktop: open dashboards silently ──────────────────────────────────────
if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
  if command -v xdg-open &>/dev/null; then
    xdg-open "http://localhost:5678" 2>/dev/null & disown
    ! $CCFLARE_SKIP && { xdg-open "http://localhost:${CCFLARE_PORT}" 2>/dev/null & disown; } || true
  fi
fi

section "Setup Complete"

echo -e "
  ${GREEN}Everything is installed and configured.${NC}  (titan-setup ${SCRIPT_VERSION})

  ${CYAN}Installed:${NC}
    Package managers: uv, bun, cargo, go, mise
    CLI tools:        ~155+ across all managers
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
  $LETTA_SKIP   || echo "    letta:          https://${TS_HOSTNAME}:${LETTA_PORT}"
  $LETTA_CTRL_SKIP || $LETTA_SKIP || echo "    letta-ctrl:     https://${TS_HOSTNAME}:${LETTA_CTRL_PORT}"
  echo "    SSH:            ssh ${CLAUDE_USER}@${TS_HOSTNAME}"
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
  $LETTA_SKIP   || echo "    letta:            http://localhost:${LETTA_PORT}"
  $LETTA_CTRL_SKIP || $LETTA_SKIP || echo "    letta-ctrl:       http://localhost:${LETTA_CTRL_PORT}"
  echo ""
  echo -e "  ${CYAN}Next steps:${NC}
    source ~/.bashrc
    claude auth login
    better-ccflare --add-account NAME --mode claude-oauth  # authenticate proxy
    claude doctor
    cd <your-project>
    /tools                    # see all installed tools
    /catchup                  # orient to the project"
  if ! $LETTA_SKIP; then
    echo -e "
  ${CYAN}Letta subconscious memory:${NC}
    Auto-starts on first Claude Code session (agent created automatically)
    Credentials:  cat ~/.config/letta/credentials
    Logs:         journalctl --user -u letta -f
    Verify:       source ~/.config/letta/credentials && curl -s -H \"Authorization: Bearer \$LETTA_API_KEY\" http://127.0.0.1:${LETTA_PORT}/v1/agents | jq"
  fi
fi

echo -e "
  ${CYAN}Package managers:${NC}
    Python CLIs → uv tool install <pkg>
    JS CLIs     → bun install -g <pkg>
    Rust CLIs   → cargo install <crate>
    Go CLIs     → go install <path>@latest
    ${RED}NEVER USE   → pip install, npm install -g, sudo pip${NC}
"

# ── VPS: restart sshd last — rebinds socket to Tailscale IP only ───────────
# Must be after all output is printed; will drop this session if connected
# via public IP (expected — reconnect via Tailscale)
if [[ "$INSTALL_MODE" == "vps" ]]; then
  sudo systemctl restart ssh 2>/dev/null || sudo systemctl restart sshd 2>/dev/null || true
fi
