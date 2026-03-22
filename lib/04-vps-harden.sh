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
  _wait_apt_lock
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
