#!/usr/bin/env bats
# shellcheck.bats — shellcheck validation

setup() {
  load helpers/setup
  if ! command -v shellcheck &>/dev/null; then
    skip "shellcheck not installed"
  fi
}

@test "titan-setup.sh passes shellcheck (errors only)" {
  run shellcheck -x --severity=error "$REPO/titan-setup.sh"
  assert_success
}

@test "bin/agt passes shellcheck" {
  run shellcheck -x --severity=error "$REPO/bin/agt"
  assert_success
}

@test "agent-team-reset.sh passes shellcheck" {
  run shellcheck -x --severity=error "$REPO/agent-team-reset.sh"
  assert_success
}

@test "agent-team-teardown.sh passes shellcheck" {
  run shellcheck -x --severity=error "$REPO/agent-team-teardown.sh"
  assert_success
}

@test "all lib/*.sh fragments pass shellcheck (errors only)" {
  local files
  mapfile -t files < <(find "$REPO/lib" -name '*.sh' | sort)
  if [[ ${#files[@]} -eq 0 ]]; then
    skip "no lib/*.sh fragments found"
  fi
  run shellcheck -x --shell bash --severity=error \
    --exclude=SC2034,SC2154,SC1046,SC1047,SC1072,SC1073,SC1089,SC1009 \
    "${files[@]}"
  assert_success
}

@test "all dot-claude/hooks/*.sh pass shellcheck" {
  for f in "$REPO"/dot-claude/hooks/*.sh; do
    [[ -f "$f" ]] || continue
    run shellcheck -x --severity=error "$f"
    assert_success "shellcheck failed for $f"
  done
}
