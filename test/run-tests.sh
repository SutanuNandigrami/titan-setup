#!/usr/bin/env bash
# run-tests.sh — Titan setup test suite (legacy runner)
# Prefer `just test` (bats) when vendor/bats is available.
# This script runs inside or outside Docker with no internet required.
set -euo pipefail

REPO="${TITAN_REPO_FILES:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || echo /repo)}"

# Delegate to bats if available
if [[ -x "$REPO/vendor/bats/bin/bats" ]]; then
  exec "$REPO/vendor/bats/bin/bats" "$REPO"/test/*.bats
fi
PASS=0; FAIL=0

check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf "  ✓ %s\n" "$desc"; (( PASS++ )) || true
  else
    printf "  ✗ %s\n" "$desc"; (( FAIL++ )) || true
  fi
}

check_grep() {
  local desc="$1" pattern="$2" file="$3"
  if grep -q "$pattern" "$file" >/dev/null 2>&1; then
    printf "  ✓ %s\n" "$desc"; (( PASS++ )) || true
  else
    printf "  ✗ %s\n" "$desc"; (( FAIL++ )) || true
  fi
}

section() { printf "\n── %s ──\n" "$1"; }

# ─── 1. Script syntax ────────────────────────────────────────────────────────
section "Script syntax"
check "titan-setup.sh: bash -n"   bash -n "$REPO/titan-setup.sh"
check "bin/agt: bash -n"          bash -n "$REPO/bin/agt"
check "agent-team-reset.sh: bash -n"    bash -n "$REPO/agent-team-reset.sh"
check "agent-team-teardown.sh: bash -n" bash -n "$REPO/agent-team-teardown.sh"

for hook in "$REPO"/dot-claude/hooks/*.sh; do
  [[ -f "$hook" ]] || continue
  check "hooks/$(basename "$hook"): bash -n"  bash -n "$hook"
done

# ─── 2. shellcheck ───────────────────────────────────────────────────────────
section "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  check "bin/agt: shellcheck"               shellcheck "$REPO/bin/agt"
  check "agent-team-reset.sh: shellcheck"   shellcheck "$REPO/agent-team-reset.sh"
  check "agent-team-teardown.sh: shellcheck" shellcheck "$REPO/agent-team-teardown.sh"
  for hook in "$REPO"/dot-claude/hooks/*.sh; do
    [[ -f "$hook" ]] || continue
    check "hooks/$(basename "$hook"): shellcheck"  shellcheck "$hook"
  done
else
  printf "  (shellcheck not installed — skipping)\n"
fi

# ─── 3. dot-claude file presence ────────────────────────────────────────────
section "dot-claude required files"
DOT_CLAUDE_REQUIRED=(
  "CLAUDE.md.tmpl"
  "settings.json"
  "skills/cli-tools/SKILL.md"
  "skills/security-scan/SKILL.md"
  "skills/git-workflow/SKILL.md"
  "hooks/session-start.sh"
  "hooks/session-end.sh"
  "hooks/pre-compact.sh"
  "rules/security.md"
  "rules/memory.md"
)
for f in "${DOT_CLAUDE_REQUIRED[@]}"; do
  check "dot-claude/$f exists"  test -f "$REPO/dot-claude/$f"
done

# ─── 4. bin/agt structure ────────────────────────────────────────────────────
section "bin/agt"
check "bin/agt is executable"    test -x "$REPO/bin/agt"
check_grep "bin/agt has shebang" "#!/usr/bin/env bash" "$REPO/bin/agt"
check_grep "bin/agt has cmd_load"   "cmd_load()" "$REPO/bin/agt"
check_grep "bin/agt has cmd_unload" "cmd_unload()" "$REPO/bin/agt"
check_grep "bin/agt has cmd_status" "cmd_status()" "$REPO/bin/agt"

# ─── 5. titan-setup.sh structure ─────────────────────────────────────────────
section "titan-setup.sh structure"
check_grep "Has --dry-run flag"    "\-\-dry-run"          "$REPO/titan-setup.sh"
check_grep "Has --mode flag"       "\-\-mode"              "$REPO/titan-setup.sh"
check_grep "Has set -euo pipefail" "set -euo pipefail"    "$REPO/titan-setup.sh"
check_grep "Installs Claude Code"  "claude"                "$REPO/titan-setup.sh"
check_grep "Has REPO_FILES block"  "TITAN_REPO_FILES"      "$REPO/titan-setup.sh"
check_grep "VPS mode guard"        "INSTALL_MODE.*==.*vps" "$REPO/titan-setup.sh"

# ─── 6. dry-run smoke test ────────────────────────────────────────────────────
section "dry-run smoke test"
DRY_OUTPUT=$(bash "$REPO/titan-setup.sh" --dry-run --mode desktop --name "test" 2>&1 || true)
if echo "$DRY_OUTPUT" | grep -qi "dry.run\|no changes"; then
  printf "  ✓ dry-run prints warning\n"; (( PASS++ )) || true
else
  printf "  ✗ dry-run prints warning\n"; (( FAIL++ )) || true
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
printf "\n══ Results: %d passed, %d failed ══\n" "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
