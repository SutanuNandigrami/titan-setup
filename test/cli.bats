#!/usr/bin/env bats
# cli.bats — unit tests for CLI argument parsing via assembled script

setup() {
  load helpers/setup
}

@test "--version exits 0" {
  run bash "$REPO/titan-setup.sh" --version
  assert_success
}

@test "--version output matches titan-setup vX.X" {
  run bash "$REPO/titan-setup.sh" --version
  assert_output --regexp "^titan-setup v[0-9]"
}

@test "--help exits 0" {
  run bash "$REPO/titan-setup.sh" --help
  assert_success
}

@test "--help shows --name option" {
  run bash "$REPO/titan-setup.sh" --help
  assert_output --partial "--name"
}

@test "--help shows --mode option" {
  run bash "$REPO/titan-setup.sh" --help
  assert_output --partial "--mode"
}

@test "--dry-run exits 0" {
  run bash "$REPO/titan-setup.sh" --dry-run --mode desktop --name ci-test
  assert_success
}

@test "--dry-run --mode vps exits 0 (no interactive prompts in dry-run)" {
  run bash "$REPO/titan-setup.sh" --dry-run --mode vps --name ci-test
  assert_success
}

@test "--mode with invalid value prints error message" {
  # usage() exits 0 (always shows help); verify error text is present
  run bash "$REPO/titan-setup.sh" --dry-run --mode invalid
  assert_output --partial "must be"
}

@test "unknown flag prints error message" {
  # usage() exits 0 (always shows help); verify error text is present
  run bash "$REPO/titan-setup.sh" --unknown-flag-xyz
  assert_output --partial "Unknown option"
}

@test "--name sets engineer name in dry-run output" {
  run bash "$REPO/titan-setup.sh" --dry-run --mode desktop --name "Bob"
  assert_output --partial "Bob"
}
