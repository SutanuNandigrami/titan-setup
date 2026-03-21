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
    exec tmux new-session -s titan-setup "bash $_TMUX_WRAPPER"
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
