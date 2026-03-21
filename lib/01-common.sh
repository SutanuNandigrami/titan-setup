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
# Accepts optional 3rd arg: expected owner (docker container name OR process name).
# Idempotent: if the expected owner already has the port, skip silently.
check_port() {
  local port="$1" service="$2" expected_owner="${3:-}"
  if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
    if [[ -n "$expected_owner" ]]; then
      # Check docker container by name (works for docker-proxied ports)
      if command -v docker &>/dev/null &&
        docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${expected_owner}$"; then
        return 0
      fi
      # Check process name across ALL ss lines for this port (not just first)
      # Use sudo to see docker-proxy and root-owned processes
      local all_owners
      all_owners=$(sudo ss -tlnp 2>/dev/null | grep ":${port} " | grep -oP 'users:\(\("\K[^"]+' || true)
      if echo "$all_owners" | grep -q "$expected_owner"; then
        return 0
      fi
    fi
    local owner
    owner=$(sudo ss -tlnp 2>/dev/null | grep ":${port} " | grep -oP 'users:\(\("\K[^"]+' | head -1 || echo "unknown")
    [[ -z "$owner" ]] && owner="unknown"
    warn "${service}: port ${port} already in use by ${owner}"
    return 1
  fi
  return 0
}
