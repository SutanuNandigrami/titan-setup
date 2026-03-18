#!/usr/bin/env bash
# Install bats-core + helper libraries to vendor/bats/
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
VENDOR_DIR="$REPO_ROOT/vendor/bats"

if [[ -d "$VENDOR_DIR/bin" ]]; then
  echo "bats already installed — skipping"
  exit 0
fi

mkdir -p "$VENDOR_DIR"

clone_or_update() {
  local url="$1" dest="$2"
  if [[ -d "$dest/.git" ]]; then
    git -C "$dest" pull --quiet
  else
    git clone --depth=1 --quiet "$url" "$dest"
  fi
}

clone_or_update "https://github.com/bats-core/bats-core"    "$VENDOR_DIR/bats-core"
clone_or_update "https://github.com/bats-core/bats-support" "$VENDOR_DIR/bats-support"
clone_or_update "https://github.com/bats-core/bats-assert"  "$VENDOR_DIR/bats-assert"

"$VENDOR_DIR/bats-core/install.sh" "$VENDOR_DIR"
echo "bats installed: $("$VENDOR_DIR/bin/bats" --version)"
