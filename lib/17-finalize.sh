# ─── VPS — Tailscale + finalize ───
if [[ "$INSTALL_MODE" == "vps" ]]; then
  # ── Tailscale — install, connect, lock SSH ─────────────────────────────
  if ! command -v tailscale &>/dev/null; then
    run_q curl -fsSL https://tailscale.com/install.sh | sh
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

  if [[ "${_TAILSCALE_FAILED:-}" != "true" ]]; then
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

# ── VPS: lock SSH to Tailscale — ABSOLUTE LAST action ──────────────────────
# Deletes public port 22 rule and restarts sshd here — AFTER all output —
# so the install session stays alive throughout. This will drop the public
# SSH connection; reconnect via Tailscale: ssh CLAUDE_USER@TS_HOSTNAME
if [[ "$INSTALL_MODE" == "vps" && "${_TAILSCALE_FAILED:-}" != "true" ]]; then
  sudo ufw delete allow 22/tcp || true
  sudo ufw delete allow OpenSSH 2>/dev/null || true
  sudo sed -i '/^#\?ListenAddress /d' /etc/ssh/sshd_config
  echo "ListenAddress $TS_IP" | sudo tee -a /etc/ssh/sshd_config > /dev/null
  sudo systemctl restart ssh 2>/dev/null || sudo systemctl restart sshd 2>/dev/null || true
fi
