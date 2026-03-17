#!/usr/bin/env bash
# docker-test.sh — Run titan test suite in a fresh Ubuntu 24.04 container
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
IMAGE="titan-test:$(date +%s)"

echo "Building test image..."
docker build -t "$IMAGE" -f "$REPO_ROOT/test/Dockerfile" "$REPO_ROOT/test"

echo "Running tests..."
docker run --rm \
  -v "$REPO_ROOT:/repo:ro" \
  -e TITAN_REPO_FILES=/repo \
  "$IMAGE" \
  bash /repo/test/run-tests.sh

EXIT=$?
docker rmi "$IMAGE" >/dev/null 2>&1 || true

[[ $EXIT -eq 0 ]] && echo "All tests passed." || echo "Tests FAILED (exit $EXIT)."
exit $EXIT
