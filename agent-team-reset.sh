#!/usr/bin/env bash
# agent-team-reset.sh — manage parallel agent team worktrees
# Usage:
#   ./agent-team-reset.sh list           — show all agent worktrees
#   ./agent-team-reset.sh reset <name>   — remove one worktree + its branch
#   ./agent-team-reset.sh reset-all      — nuke all agent worktrees + branches
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
WORKTREE_DIR="$REPO_ROOT/.worktrees"

cmd="${1:-list}"

list_worktrees() {
    echo "Agent worktrees:"
    if [[ ! -d "$WORKTREE_DIR" ]] || [[ -z "$(ls -A "$WORKTREE_DIR" 2>/dev/null)" ]]; then
        echo "  (none)"
        return
    fi
    for wt in "$WORKTREE_DIR"/*/; do
        [[ -d "$wt" ]] || continue
        branch=$(git -C "$wt" branch --show-current 2>/dev/null || echo "unknown")
        commits=$(git -C "$wt" log --oneline origin/main..HEAD 2>/dev/null | wc -l | tr -d ' ')
        modified=$(git -C "$wt" status --short 2>/dev/null | wc -l | tr -d ' ')
        echo "  $(basename "$wt")  branch=$branch  commits_ahead=$commits  modified_files=$modified"
    done
}

reset_one() {
    local name="$1"
    local path="$WORKTREE_DIR/$name"
    if [[ ! -d "$path" ]]; then
        echo "Error: worktree '$name' not found in $WORKTREE_DIR" >&2
        exit 1
    fi
    branch=$(git -C "$path" branch --show-current 2>/dev/null || echo "")
    echo "Removing worktree: $path"
    git worktree remove --force "$path"
    if [[ -n "$branch" ]]; then
        echo "Deleting branch: $branch"
        git branch -D "$branch" 2>/dev/null && echo "  done" || echo "  (branch already gone)"
    fi
}

reset_all() {
    if [[ ! -d "$WORKTREE_DIR" ]] || [[ -z "$(ls -A "$WORKTREE_DIR" 2>/dev/null)" ]]; then
        echo "No agent worktrees to remove."
        return
    fi
    echo "Removing all agent worktrees..."
    for wt in "$WORKTREE_DIR"/*/; do
        [[ -d "$wt" ]] || continue
        name=$(basename "$wt")
        reset_one "$name"
    done
    rmdir "$WORKTREE_DIR" 2>/dev/null && echo "Removed $WORKTREE_DIR" || true
    echo "All agent worktrees cleared."
}

case "$cmd" in
    list)       list_worktrees ;;
    reset)      [[ -n "${2:-}" ]] || { echo "Usage: $0 reset <name>" >&2; exit 1; }; reset_one "$2" ;;
    reset-all)  reset_all ;;
    *)          echo "Usage: $0 {list|reset <name>|reset-all}" >&2; exit 1 ;;
esac
