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

# Port pre-flight check — warn if a port is already in use by another service.
# Accepts optional 3rd arg: docker container name to check before warning.
# Idempotent: if the expected container/service already owns the port, skip.
check_port() {
  local port="$1" service="$2" container="${3:-}"
  if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
    # If a docker container name is given, check if it's already running on this port
    if [[ -n "$container" ]] && command -v docker &>/dev/null &&
      docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"; then
      return 0  # our container already owns this port — idempotent
    fi
    local owner
    owner=$(ss -tlnp 2>/dev/null | grep ":${port} " | head -1 | grep -oP 'users:\(\("\K[^"]+' || echo "unknown")
    warn "${service}: port ${port} already in use by ${owner}"
    return 1
  fi
  return 0
}
