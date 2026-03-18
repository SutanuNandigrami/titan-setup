#!/usr/bin/env bash
# Common bats test setup — source this in each test file's setup() function
# Usage: load helpers/setup (from test/ directory)

export TITAN_TESTING=1
REPO="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
export REPO

load "$REPO/vendor/bats/bats-support/load"
load "$REPO/vendor/bats/bats-assert/load"
