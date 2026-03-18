#!/usr/bin/env bats
# templates.bats — validate dot-claude/ template files and config assets

setup() {
  load helpers/setup
}

@test "settings.json is valid JSON" {
  if ! command -v jq &>/dev/null; then skip "jq not installed"; fi
  run jq . "$REPO/dot-claude/settings.json"
  assert_success
}

@test "all SKILL.md files have paths: frontmatter (lazy-load)" {
  local missing=()
  for f in "$REPO"/dot-claude/skills/*/SKILL.md; do
    [[ -f "$f" ]] || continue
    if ! grep -q '^paths:' "$f" 2>/dev/null; then
      missing+=("$(basename "$(dirname "$f")")")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    fail "Missing 'paths:' frontmatter in skills: ${missing[*]}"
  fi
}

@test "all dot-claude/hooks/*.sh pass bash -n" {
  local failed=()
  for f in "$REPO"/dot-claude/hooks/*.sh; do
    [[ -f "$f" ]] || continue
    if ! bash -n "$f" 2>/dev/null; then
      failed+=("$(basename "$f")")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    fail "Syntax errors in hooks: ${failed[*]}"
  fi
}

@test "all dot-claude/hooks/*.sh are executable" {
  local not_exec=()
  for f in "$REPO"/dot-claude/hooks/*.sh; do
    [[ -f "$f" ]] || continue
    if [[ ! -x "$f" ]]; then
      not_exec+=("$(basename "$f")")
    fi
  done
  if [[ ${#not_exec[@]} -gt 0 ]]; then
    fail "Not executable: ${not_exec[*]}"
  fi
}

@test "agt config file exists" {
  assert [ -f "$REPO/config/agt/config" ]
}

@test "letta-ctrl-server.js exists after heredoc extraction" {
  assert [ -f "$REPO/config/letta/letta-ctrl-server.js" ]
}

@test "letta-ctrl.html exists after heredoc extraction" {
  assert [ -f "$REPO/config/letta/letta-ctrl.html" ]
}

@test "letta-ctrl-server.js is valid JS (has import statement)" {
  run grep -c "^import " "$REPO/config/letta/letta-ctrl-server.js"
  assert_success
}

@test "letta-ctrl.html is valid HTML (has DOCTYPE)" {
  run grep -c "DOCTYPE html" "$REPO/config/letta/letta-ctrl.html"
  assert_success
}

@test "build-check: titan-setup.sh matches assembled lib/ source" {
  if ! [ -d "$REPO/lib" ] || [ -z "$(find "$REPO/lib" -name '*.sh' 2>/dev/null)" ]; then
    skip "lib/ fragments not present"
  fi
  run bash "$REPO/script/build.sh" --check
  assert_success
}
