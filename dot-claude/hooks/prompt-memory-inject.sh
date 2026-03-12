#!/usr/bin/env bash
# Keyword-triggered memory injection — stdout injected as context ONLY on keyword match
# Zero token cost on every non-matching prompt
set -euo pipefail

PROMPT=$(jq -r '.prompt // empty' 2>/dev/null || echo "")

# Exit with no stdout if no recall-intent keywords — nothing injected into context
if ! echo "$PROMPT" | grep -qiE 'recall|remember|last session|previously|we decided|what did we|what was|history|forget|memory'; then
  exit 0
fi

# Find the active project memory directory
MEMDIR="$HOME/.claude/projects"
MAINMEM=$(find "$MEMDIR" -path "*/memory/MEMORY.md" 2>/dev/null | sort | tail -1)

if [[ -f "$MAINMEM" ]]; then
  TOPICDIR=$(dirname "$MAINMEM")
  printf '=== Project Memory ===\n'
  cat "$MAINMEM"
  for f in "$TOPICDIR"/*.md; do
    [[ "$f" == "$MAINMEM" ]] && continue
    [[ -f "$f" ]] && printf '\n=== %s ===\n' "$(basename "$f")" && cat "$f"
  done
fi

# Also inject last session handoff
HANDOFF="$HOME/.claude/memory/handoff.md"
if [[ -f "$HANDOFF" ]]; then
  printf '\n=== Last Session Handoff ===\n'
  head -60 "$HANDOFF"
fi
