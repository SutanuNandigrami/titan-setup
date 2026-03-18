#!/usr/bin/env bats
# structure.bats — file presence, agt structure, titan-setup patterns

setup() {
  load helpers/setup
}

# ── dot-claude required files ──────────────────────────────────────────────

@test "dot-claude/CLAUDE.md exists" {
  assert [ -f "$REPO/dot-claude/CLAUDE.md" ]
}

@test "dot-claude/settings.json exists" {
  assert [ -f "$REPO/dot-claude/settings.json" ]
}

@test "dot-claude/skills/cli-tools/SKILL.md exists" {
  assert [ -f "$REPO/dot-claude/skills/cli-tools/SKILL.md" ]
}

@test "dot-claude/skills/security-scan/SKILL.md exists" {
  assert [ -f "$REPO/dot-claude/skills/security-scan/SKILL.md" ]
}

@test "dot-claude/skills/git-workflow/SKILL.md exists" {
  assert [ -f "$REPO/dot-claude/skills/git-workflow/SKILL.md" ]
}

@test "dot-claude/hooks/session-start.sh exists" {
  assert [ -f "$REPO/dot-claude/hooks/session-start.sh" ]
}

@test "dot-claude/hooks/session-end.sh exists" {
  assert [ -f "$REPO/dot-claude/hooks/session-end.sh" ]
}

@test "dot-claude/hooks/pre-compact.sh exists" {
  assert [ -f "$REPO/dot-claude/hooks/pre-compact.sh" ]
}

@test "dot-claude/rules/security.md exists" {
  assert [ -f "$REPO/dot-claude/rules/security.md" ]
}

@test "dot-claude/rules/memory.md exists" {
  assert [ -f "$REPO/dot-claude/rules/memory.md" ]
}

# ── bin/agt structure ──────────────────────────────────────────────────────

@test "bin/agt is executable" {
  assert [ -x "$REPO/bin/agt" ]
}

@test "bin/agt has shebang" {
  run grep -c "#!/usr/bin/env bash" "$REPO/bin/agt"
  assert_success
}

@test "bin/agt has cmd_load function" {
  run grep -c "cmd_load()" "$REPO/bin/agt"
  assert_success
}

@test "bin/agt has cmd_unload function" {
  run grep -c "cmd_unload()" "$REPO/bin/agt"
  assert_success
}

@test "bin/agt has cmd_status function" {
  run grep -c "cmd_status()" "$REPO/bin/agt"
  assert_success
}

# ── titan-setup.sh structure ───────────────────────────────────────────────

@test "titan-setup.sh has --dry-run flag" {
  run grep -c "\-\-dry-run" "$REPO/titan-setup.sh"
  assert_success
}

@test "titan-setup.sh has --mode flag" {
  run grep -c "\-\-mode" "$REPO/titan-setup.sh"
  assert_success
}

@test "titan-setup.sh has set -euo pipefail" {
  run grep -c "set -euo pipefail" "$REPO/titan-setup.sh"
  assert_success
}

@test "titan-setup.sh has REPO_FILES block" {
  run grep -c "TITAN_REPO_FILES" "$REPO/titan-setup.sh"
  assert_success
}

@test "titan-setup.sh has VPS mode guard" {
  run grep -c 'INSTALL_MODE.*==.*vps' "$REPO/titan-setup.sh"
  assert_success
}

# ── lib/ fragment structure ────────────────────────────────────────────────

@test "lib/ directory has expected number of fragments" {
  local count
  count=$(find "$REPO/lib" -name '*.sh' 2>/dev/null | wc -l)
  assert [ "$count" -ge 18 ]
}

@test "lib/00-header.sh has shebang" {
  run grep -c "#!/usr/bin/env bash" "$REPO/lib/00-header.sh"
  assert_success
}

@test "lib/01-common.sh has output functions" {
  run grep -c "^ok()\|^warn()\|^fail()\|^section()" "$REPO/lib/01-common.sh"
  assert_success
}

@test "config/letta/letta-ctrl-server.js exists" {
  assert [ -f "$REPO/config/letta/letta-ctrl-server.js" ]
}

@test "config/letta/letta-ctrl.html exists" {
  assert [ -f "$REPO/config/letta/letta-ctrl.html" ]
}
