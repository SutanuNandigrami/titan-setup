#!/usr/bin/env bats
# syntax.bats — bash -n syntax checks for all scripts

setup() {
  load helpers/setup
}

@test "titan-setup.sh passes bash -n" {
  run bash -n "$REPO/titan-setup.sh"
  assert_success
}

@test "bin/agt passes bash -n" {
  run bash -n "$REPO/bin/agt"
  assert_success
}

@test "agent-team-reset.sh passes bash -n" {
  run bash -n "$REPO/agent-team-reset.sh"
  assert_success
}

@test "agent-team-teardown.sh passes bash -n" {
  run bash -n "$REPO/agent-team-teardown.sh"
  assert_success
}

@test "assembled titan-setup.sh passes bash -n (authoritative fragment check)" {
  # Individual fragments cannot be checked with bash -n because if/fi blocks
  # span multiple files. The assembled script is the authoritative syntax check.
  run bash -n "$REPO/titan-setup.sh"
  assert_success
}

@test "all dot-claude/hooks/*.sh pass bash -n" {
  for f in "$REPO"/dot-claude/hooks/*.sh; do
    [[ -f "$f" ]] || continue
    run bash -n "$f"
    assert_success "Syntax error in $f"
  done
}
