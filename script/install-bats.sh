#!/usr/bin/env bash
# Install bats-core + helper libraries to vendor/bats/
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
VENDOR_DIR="$REPO_ROOT/vendor/bats"

echo "Installing bats-core to $VENDOR_DIR ..."

if [[ -d "$VENDOR_DIR/bin" ]]; then
  echo "bats already installed — skipping (run: rm -rf vendor/bats to reinstall)"
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

# Install bats-core into vendor/bats/
"$VENDOR_DIR/bats-core/install.sh" "$VENDOR_DIR"

echo "bats installed: $("$VENDOR_DIR/bin/bats" --version)"
echo "Support + assert libraries available at:"
echo "  $VENDOR_DIR/bats-support"
echo "  $VENDOR_DIR/bats-assert"
