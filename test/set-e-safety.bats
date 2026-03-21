#!/usr/bin/env bats
# set-e-safety.bats — catch unguarded commands that silently kill the script under set -e
#
# WHY THIS EXISTS:
# titan-setup.sh runs under `set -euo pipefail`. Any command that returns
# non-zero (network timeout, API rate-limit, package not found) will kill
# the ENTIRE script instantly and silently. This has caused regressions
# 3 times. These tests enforce that every failable command is guarded.
#
# PATTERNS THAT KILL UNDER set -e:
#   curl ...                         # bare curl — network fail = script dies
#   sudo apt-get install -y foo      # package missing = script dies
#   sudo systemctl enable foo --now  # service masked = script dies
#   VAR=$(curl ... | jq ...)         # pipefail + set -e = script dies
#
# SAFE PATTERNS:
#   curl ... && ok "..." || warn "..."        # guarded chain
#   curl ... || true                           # explicit ignore
#   if curl ...; then ok; else warn; fi        # conditional
#   VAR=$(curl ... | jq ... || true)           # guarded subshell

setup() {
  load helpers/setup
}

# Helper: scan lib/ files for unguarded pattern, excluding safe contexts.
# A line is "guarded" if it contains ||, ends with && or &&\, or is inside
# an if/while condition. We also skip comments and continuation lines.
_scan_unguarded() {
  local pattern="$1"
  local extra_exclude="${2:-}"
  local violations=""

  while IFS= read -r file; do
    local result
    result=$(grep -nE "$pattern" "$file" \
      | grep -v '^\s*#' \
      | grep -v '||' \
      | grep -v '&&\s*$' \
      | grep -v '&& \\' \
      | grep -v '^\s*[0-9]*:\s*if ' \
      | grep -v '^\s*[0-9]*:\s*elif ' \
      | grep -v '^\s*[0-9]*:\s*while ' \
      | grep -v '^\s*[0-9]*:\s*until ' \
      ${extra_exclude:+| grep -v "$extra_exclude"} \
      || true)
    if [[ -n "$result" ]]; then
      violations+="$(basename "$file"):
$result
"
    fi
  done < <(find "$REPO/lib" -name '*.sh' | sort)

  echo "$violations"
}

# ── Bare curl that starts a command (not curl as a package name or arg) ────

@test "no unguarded curl commands in lib/" {
  # Match lines where curl is the COMMAND (start of statement, possibly after sudo/echo -n).
  # Exclude: lines inside if/while, lines with || or && guards, comments,
  # curl appearing as a string/package name (e.g. inside apt-get install lists).
  local violations=""

  while IFS= read -r file; do
    local result
    # Only match lines where curl is actually being EXECUTED as a command:
    # starts with optional whitespace then curl, or "sudo curl"
    # Exclude: lines ending with | or \ (continuation — guard is on next line)
    result=$(grep -nP '^\s+(curl|sudo\s+curl)\s+-' "$file" \
      | grep -v '^\s*#' \
      | grep -v '||' \
      | grep -v '&&\s*$' \
      | grep -v '&& \\$' \
      | grep -v '&& break' \
      | grep -v '|\s*$' \
      | grep -v '\\\s*$' \
      | grep -vP '^\s*\d+:\s*if\s' \
      | grep -vP '^\s*\d+:\s*elif\s' \
      || true)
    if [[ -n "$result" ]]; then
      violations+="$(basename "$file"):
$result
"
    fi
  done < <(find "$REPO/lib" -name '*.sh' | sort)

  if [[ -n "$violations" ]]; then
    echo "UNGUARDED curl commands found (will kill script under set -e):"
    echo "$violations"
    echo ""
    echo "Fix: add '&& ok ... || warn ...' or '|| true' to each curl call"
    return 1
  fi
}

# ── Bare wget that starts a command ───────────────────────────────────────

@test "no unguarded wget commands in lib/" {
  local violations=""

  while IFS= read -r file; do
    local result
    result=$(grep -nP '^\s+(wget|sudo\s+wget)\s+-' "$file" \
      | grep -v '^\s*#' \
      | grep -v '||' \
      | grep -v '&&\s*$' \
      | grep -v '&& \\$' \
      | grep -vP '^\s*\d+:\s*if\s' \
      || true)
    if [[ -n "$result" ]]; then
      violations+="$(basename "$file"):
$result
"
    fi
  done < <(find "$REPO/lib" -name '*.sh' | sort)

  if [[ -n "$violations" ]]; then
    echo "UNGUARDED wget commands found (will kill script under set -e):"
    echo "$violations"
    echo ""
    echo "Fix: add '&& ok ... || warn ...' or '|| true' to each wget call"
    return 1
  fi
}

# ── Bare systemctl enable/start without guard ─────────────────────────────

@test "no unguarded systemctl enable/start in lib/" {
  local violations=""

  while IFS= read -r file; do
    local result
    result=$(grep -nE '^\s+(sudo\s+)?systemctl\s+(enable|start|restart)' "$file" \
      | grep -v '^\s*#' \
      | grep -v '||' \
      | grep -v '&&\s*$' \
      | grep -vP '^\s*\d+:\s*if\s' \
      || true)
    if [[ -n "$result" ]]; then
      violations+="$(basename "$file"):
$result
"
    fi
  done < <(find "$REPO/lib" -name '*.sh' | sort)

  if [[ -n "$violations" ]]; then
    echo "UNGUARDED systemctl commands found (will kill script under set -e):"
    echo "$violations"
    echo ""
    echo "Fix: add '|| true' or '&& ok ... || warn ...'"
    return 1
  fi
}

# ── GitHub API calls (rate-limited to 60/hr unauthenticated) ──────────────

@test "no direct api.github.com calls in lib/ or titan-setup.sh" {
  local violations=""

  while IFS= read -r file; do
    local result
    result=$(grep -nE 'api\.github\.com' "$file" \
      | grep -v '^\s*#' \
      || true)
    if [[ -n "$result" ]]; then
      violations+="$(basename "$file"):
$result
"
    fi
  done < <(find "$REPO/lib" -name '*.sh' | sort)

  local result
  result=$(grep -nE 'api\.github\.com' "$REPO/titan-setup.sh" \
    | grep -v '^\s*#' \
    || true)
  if [[ -n "$result" ]]; then
    violations+="titan-setup.sh:
$result
"
  fi

  if [[ -n "$violations" ]]; then
    echo "Direct GitHub API calls found (60 req/hr rate limit will crash script):"
    echo "$violations"
    echo ""
    echo "Fix: use _gh_latest_tag() which uses redirect-based version detection"
    return 1
  fi
}

# ── Unguarded $(curl...|...) command substitutions ────────────────────────

@test "no unguarded \$(curl...|...) pipeline substitutions in lib/" {
  local violations=""

  while IFS= read -r file; do
    local result
    # Match VAR=$(curl ... | ...) without || true/echo inside the $()
    result=$(grep -nE '\$\(curl\s.*\|' "$file" \
      | grep -v '^\s*#' \
      | grep -v '|| true' \
      | grep -v '|| echo' \
      | grep -v '||echo' \
      | grep -v '_gh_latest_tag' \
      || true)
    if [[ -n "$result" ]]; then
      violations+="$(basename "$file"):
$result
"
    fi
  done < <(find "$REPO/lib" -name '*.sh' | sort)

  if [[ -n "$violations" ]]; then
    echo "UNGUARDED \$(curl|...) found (pipefail + set -e = instant death):"
    echo "$violations"
    echo ""
    echo "Fix: add '|| true' inside the \$(): VAR=\$(curl ... | jq ... || true)"
    return 1
  fi
}

# ── Bare sysctl -p without guard ──────────────────────────────────────────

@test "no unguarded sysctl -p in lib/" {
  local violations=""

  while IFS= read -r file; do
    local result
    result=$(grep -nE '^\s+(sudo\s+)?sysctl\s+-p' "$file" \
      | grep -v '^\s*#' \
      | grep -v '||' \
      || true)
    if [[ -n "$result" ]]; then
      violations+="$(basename "$file"):
$result
"
    fi
  done < <(find "$REPO/lib" -name '*.sh' | sort)

  if [[ -n "$violations" ]]; then
    echo "UNGUARDED sysctl -p found (invalid entries from other software = script dies):"
    echo "$violations"
    echo ""
    echo "Fix: add '|| true'"
    return 1
  fi
}
