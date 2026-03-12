#!/usr/bin/env bash
# SessionStart hook — load previous session state and run maintenance
set -euo pipefail

HANDOFF="$HOME/.claude/memory/handoff.md"

# Show handoff from previous session (if recent — within 24h)
if [[ -f "$HANDOFF" ]]; then
  FILE_AGE=$(( $(date +%s) - $(stat -c %Y "$HANDOFF" 2>/dev/null || echo 0) ))
  if (( FILE_AGE < 86400 )); then
    echo "[Memory] Previous session handoff ($(( FILE_AGE / 60 ))m ago):" >&2
    head -30 "$HANDOFF" >&2
    echo "---" >&2
  fi
fi

# Remind about auto memory files
MEMORY_COUNT=$(find "$HOME/.claude/projects/" -name "MEMORY.md" 2>/dev/null | wc -l)
if (( MEMORY_COUNT > 0 )); then
  echo "[Memory] ${MEMORY_COUNT} project memory file(s) available." >&2
else
  echo "[Memory] No project memories yet. Use /remember or write to auto memory directory." >&2
fi

# ─── Maintenance: JSONL prune (cap at 30, delete >30 days old) ───
# Run on every session start (not just pre-compact) to prevent accumulation
find "$HOME/.claude/projects" -name "*.jsonl" -mtime +30 -delete 2>/dev/null || true
mapfile -t ALL_JSONL < <(find "$HOME/.claude/projects" -maxdepth 2 -name "*.jsonl" -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk '{print $2}')
if [[ ${#ALL_JSONL[@]} -gt 30 ]]; then
  printf '%s\n' "${ALL_JSONL[@]:30}" | xargs -r rm -f 2>/dev/null || true
fi

# ─── Maintenance: Rotate audit log if over 10MB ───
AUDIT_LOG="$HOME/.claude/logs/audit.jsonl"
if [[ -f "$AUDIT_LOG" ]]; then
  AUDIT_SIZE=$(stat -c %s "$AUDIT_LOG" 2>/dev/null || echo 0)
  if (( AUDIT_SIZE > 10485760 )); then
    mv "$AUDIT_LOG" "${AUDIT_LOG}.$(date +%s).bak"
    echo "[Audit] Log rotated (was $(( AUDIT_SIZE / 1048576 ))MB)" >&2
  fi
fi

# ─── Agent slots: show loaded agents (stderr = zero token cost) ───
MANIFEST="$HOME/.claude/agent-stash/_loaded/.manifest"
if [[ -f "$MANIFEST" ]] && [[ -s "$MANIFEST" ]]; then
  echo "[Agents] Loaded slots:" >&2
  while IFS=$'\t' read -r slot agent _ts; do
    echo "  $slot: $agent" >&2
  done < "$MANIFEST"
fi

exit 0
