#!/usr/bin/env bash
# Assemble lib/*.sh fragments into titan-setup.sh
# Usage: build.sh [--check]
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
LIB_DIR="$REPO_ROOT/lib"
OUTPUT="$REPO_ROOT/titan-setup.sh"
CHECK_MODE=false

[[ "${1:-}" == "--check" ]] && CHECK_MODE=true

if [[ ! -d "$LIB_DIR" ]]; then
  echo "ERROR: lib/ directory not found — fragments not yet created" >&2
  echo "titan-setup.sh is still the monolithic source of truth." >&2
  exit 1
fi

# Collect fragments in order
mapfile -t FRAGMENTS < <(find "$LIB_DIR" -maxdepth 1 -name '*.sh' | sort)

if [[ ${#FRAGMENTS[@]} -eq 0 ]]; then
  echo "ERROR: no .sh files found in $LIB_DIR" >&2
  exit 1
fi

# Build to temp file
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

for frag in "${FRAGMENTS[@]}"; do
  cat "$frag" >> "$TMP"
  # Add newline between fragments if file doesn't end with one
  [[ -z "$(tail -c1 "$frag")" ]] || echo >> "$TMP"
done

if "$CHECK_MODE"; then
  if diff -q "$OUTPUT" "$TMP" > /dev/null 2>&1; then
    echo "build-check: titan-setup.sh matches lib/ source ✓"
    exit 0
  else
    echo "ERROR: titan-setup.sh is out of sync with lib/ fragments" >&2
    echo "Run 'just build' to regenerate." >&2
    diff "$OUTPUT" "$TMP" | head -20 >&2
    exit 1
  fi
else
  cp "$TMP" "$OUTPUT"
  chmod +x "$OUTPUT"
  echo "Built titan-setup.sh from ${#FRAGMENTS[@]} fragments ($(wc -l < "$OUTPUT") lines)"
fi
