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
  bash "$_SELF" "$@"; _rc=$?
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

SCRIPT_VERSION="v3.17"

