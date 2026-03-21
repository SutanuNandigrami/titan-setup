if phase_done "phase1" && ! $FORCE_UPDATES; then
  section "Phase 1/6 — System Prerequisites (cached ✓)"
else
  section "Phase 1/6 — System Prerequisites"

  # Suppress needrestart interactive kernel/service restart prompts on Ubuntu VPS
  # Sets restart mode to automatic so apt upgrades never block waiting for user input
  if [[ -d /etc/needrestart ]]; then
    sudo mkdir -p /etc/needrestart/conf.d
    # restart='a' → auto-restart services; kernelhints=-1 → suppress "Pending kernel upgrade" dialog
    printf '\$nrconf{restart} = '"'"'a'"'"';\n\$nrconf{kernelhints} = -1;\n\$nrconf{ucodehints} = 0;\n' |
      sudo tee /etc/needrestart/conf.d/titan-auto.conf >/dev/null
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
