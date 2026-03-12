#!/usr/bin/env bash
# PreCompact hook — save session state before compaction + maintenance cleanup
set -euo pipefail

MEMORY_DIR="$HOME/.claude/memory"
HANDOFF="$MEMORY_DIR/handoff.md"
mkdir -p "$MEMORY_DIR"

# Read input JSON from stdin
INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)

# Capture git state
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
MODIFIED=$(git diff --name-only HEAD 2>/dev/null || true)
STATUS=$(git status --porcelain 2>/dev/null | head -20 || true)
DIFF_STAT=$(git diff --stat 2>/dev/null | tail -5 || true)
RECENT_COMMITS=$(git log --oneline -10 2>/dev/null || true)

# Extract last 5 user+assistant exchanges (not just assistant) for richer context preservation
RECENT_EXCHANGES=""
if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
  RECENT_EXCHANGES=$(tail -300 "$TRANSCRIPT" 2>/dev/null \
    | jq -r 'select(.type == "user" or .type == "assistant")
      | .type + ": " + (
          (.message.content // [])[]?
          | select(.type == "text")
          | .text // empty
          | .[0:600]
        )' 2>/dev/null \
    | tail -c 5000 || true)
fi

# Write handoff file
cat > "$HANDOFF" << EOF
---
timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
session_id: ${SESSION_ID}
branch: ${BRANCH}
trigger: pre-compact
---

# Session Handoff

## Branch
\`${BRANCH}\`

## Recent Commits
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

## Recent Conversation (last ~5 exchanges before compact)
${RECENT_EXCHANGES:-No transcript context available}
EOF

# ─── Maintenance: JSONL prune (runs on every compact) ───
# Cap main sessions at 15; delete old sessions AND their subagent dirs together
_prune_jsonl() {
  local projects="$HOME/.claude/projects"
  # Delete sessions older than 30 days (including subagent dirs)
  while IFS= read -r f; do
    local sid sdir
    sid=$(basename "$f" .jsonl)
    sdir="$(dirname "$f")/$sid"
    rm -f "$f" 2>/dev/null || true
    rm -rf "$sdir" 2>/dev/null || true
  done < <(find "$projects" -maxdepth 2 -name "*.jsonl" -mtime +30 2>/dev/null)
  # Cap at 15 newest main sessions
  mapfile -t ALL_MAIN < <(find "$projects" -maxdepth 2 -name "*.jsonl" -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk '{print $2}')
  if [[ ${#ALL_MAIN[@]} -gt 15 ]]; then
    local f sid sdir
    for f in "${ALL_MAIN[@]:15}"; do
      sid=$(basename "$f" .jsonl)
      sdir="$(dirname "$f")/$sid"
      rm -f "$f" 2>/dev/null || true
      rm -rf "$sdir" 2>/dev/null || true
    done
  fi
}
_prune_jsonl

# ─── Maintenance: clean stale plugin cache versions ───
_prune_plugin_cache() {
  local installed_json="$HOME/.claude/plugins/installed_plugins.json"
  [[ -f "$installed_json" ]] || return 0
  local cache_root="$HOME/.claude/plugins/cache"
  [[ -d "$cache_root" ]] || return 0

  mapfile -t ACTIVE_PATHS < <(jq -r '.plugins | to_entries[] | .value[] | .installPath' "$installed_json" 2>/dev/null)

  local marketplace plugin version vpath is_active ap
  for marketplace in "$cache_root"/*/; do
    for plugin in "$marketplace"*/; do
      [[ -d "$plugin" ]] || continue
      for version in "$plugin"*/; do
        [[ -d "$version" ]] || continue
        vpath="${version%/}"
        is_active=false
        for ap in "${ACTIVE_PATHS[@]}"; do
          [[ "$ap" == "$vpath" ]] && { is_active=true; break; }
        done
        if ! $is_active; then
          rm -rf "$vpath" 2>/dev/null || true
        fi
      done
    done
  done
}
_prune_plugin_cache

exit 0
