#!/usr/bin/env bash
# Stop hook — capture final session state for next session
set -euo pipefail

MEMORY_DIR="$HOME/.claude/memory"
HANDOFF="$MEMORY_DIR/handoff.md"
mkdir -p "$MEMORY_DIR"

# Read input JSON from stdin
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null | head -c 2000)

# Capture git state
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
MODIFIED=$(git diff --name-only HEAD 2>/dev/null || true)
STATUS=$(git status --porcelain 2>/dev/null | head -20 || true)
DIFF_STAT=$(git diff --stat 2>/dev/null | tail -5 || true)
RECENT_COMMITS=$(git log --oneline -5 2>/dev/null || true)

# Write handoff file
cat > "$HANDOFF" << EOF
---
timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
session_id: ${SESSION_ID}
branch: ${BRANCH}
trigger: session-end
---

# Session Handoff

## Branch
\`${BRANCH}\`

## Recent Commits (this session)
\`\`\`
${RECENT_COMMITS:-No commits}
\`\`\`

## Modified Files (uncommitted)
\`\`\`
${MODIFIED:-No modified files}
\`\`\`

## Git Status
\`\`\`
${STATUS:-Clean working tree}
\`\`\`

## Diff Summary
\`\`\`
${DIFF_STAT:-No changes}
\`\`\`

## Last Assistant Message
${LAST_MSG:-No message captured}
EOF

exit 0
