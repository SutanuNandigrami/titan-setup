#!/usr/bin/env bash
# Common bats test setup — sourced by all test files

export TITAN_TESTING=1
REPO="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
export REPO

# Load bats helper libraries
load "$REPO/vendor/bats/bats-support/load"
load "$REPO/vendor/bats/bats-assert/load"
