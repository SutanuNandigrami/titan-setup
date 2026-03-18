#!/usr/bin/env bats
# smoke.bats — dry-run and CLI integration tests

setup() {
  load helpers/setup
}

@test "--version prints version string" {
  run bash "$REPO/titan-setup.sh" --version
  assert_success
  assert_output --partial "titan-setup"
}

@test "--help exits 0" {
  run bash "$REPO/titan-setup.sh" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "--dry-run --mode desktop exits 0" {
  run bash "$REPO/titan-setup.sh" --dry-run --mode desktop --name "test"
  assert_success
}

@test "--dry-run prints dry run warning" {
  run bash "$REPO/titan-setup.sh" --dry-run --mode desktop --name "test"
  assert_output --partial "Dry run"
}

@test "--dry-run shows engineer name" {
  run bash "$REPO/titan-setup.sh" --dry-run --mode desktop --name "alice"
  assert_output --partial "alice"
}

@test "unknown option prints error message" {
  # usage() exits 0 (shows help on any error); check error is printed
  run bash "$REPO/titan-setup.sh" --invalid-flag-xyz
  assert_output --partial "Unknown option"
}

@test "--mode with invalid value prints error" {
  run bash "$REPO/titan-setup.sh" --dry-run --mode invalid
  assert_output --partial "must be"
}
