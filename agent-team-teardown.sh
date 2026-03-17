#!/usr/bin/env bash
# agent-team-teardown.sh — disable agent team mode in settings.json
# Run when done with the agent team session. Does NOT touch worktrees or branches.
# Usage: ./agent-team-teardown.sh [--dry-run]
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

if ! command -v jq &>/dev/null; then
    echo "Error: jq required" >&2; exit 1
fi

echo "=== Agent Team Teardown ==="
echo "Settings: $SETTINGS"
echo ""

# Show current state
echo "Before:"
jq '{
  CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: .env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS,
  CLAUDE_CODE_SUBAGENT_MODEL: .env.CLAUDE_CODE_SUBAGENT_MODEL,
  teammateMode: .teammateMode
}' "$SETTINGS"
echo ""

if [[ "$DRY_RUN" == true ]]; then
    echo "[dry-run] Would revert to: AGENT_TEAMS removed, SUBAGENT_MODEL=haiku, teammateMode removed"
    exit 0
fi

# Revert: remove AGENT_TEAMS flag, restore haiku, remove teammateMode
tmp=$(mktemp)
jq '
  del(.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS) |
  .env.CLAUDE_CODE_SUBAGENT_MODEL = "claude-haiku-4-5-20251001" |
  del(.teammateMode)
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

echo "After:"
jq '{
  CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: .env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS,
  CLAUDE_CODE_SUBAGENT_MODEL: .env.CLAUDE_CODE_SUBAGENT_MODEL,
  teammateMode: .teammateMode
}' "$SETTINGS"
echo ""
echo "Done. Restart Claude Code to apply."
echo "Worktrees and feature branches are untouched."
