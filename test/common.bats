#!/usr/bin/env bats
# common.bats — unit tests for lib/01-common.sh and lib/03-vps-reexec.sh

setup() {
  load helpers/setup
  # Source output helpers (safe — only defines variables and functions)
  # shellcheck source=/dev/null
  source "$REPO/lib/01-common.sh"
  # Source arch detection from vps-reexec (contains run_q, WORKDIR, arch vars)
  # Only source the parts that are safe outside TITAN_TESTING guard
  VERBOSE=false
  LOG_FILE=$(mktemp)
}

teardown() {
  rm -f "${LOG_FILE:-}"
}

@test "section() outputs header text" {
  run section "Test Header"
  assert_output --partial "Test Header"
}

@test "ok() outputs check mark" {
  run ok "success message"
  assert_output --partial "✓"
  assert_output --partial "success message"
}

@test "warn() outputs warning symbol" {
  run warn "warning text"
  assert_output --partial "⚠"
  assert_output --partial "warning text"
}

@test "fail() outputs X symbol" {
  run fail "error text"
  assert_output --partial "✗"
  assert_output --partial "error text"
}

@test "CYAN color variable is set" {
  assert [ -n "$CYAN" ]
}

@test "GREEN color variable is set" {
  assert [ -n "$GREEN" ]
}

@test "NC (no color) variable is set" {
  assert [ -n "$NC" ]
}
