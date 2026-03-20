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
_APT_UPDATED=false
apt_update() {
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
