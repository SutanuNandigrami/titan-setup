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
    check_port "$LETTA_CTRL_PORT" "letta-ctrl" "bun" || true
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
$([[ "$INSTALL_MODE" == "vps" ]] && echo 'Environment="LETTA_CTRL_TOKEN=disable"')
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
