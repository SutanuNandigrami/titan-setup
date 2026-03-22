---
description: Resume work by loading all available context
argument-hint: Optional - specific area to focus on
---

You are resuming work in this project. Gather ALL available context before asking what to do.

## Step 1: Git State (run all in parallel)
- `git branch --show-current`
- `git log --oneline -10`
- `git status -s`
- `git diff --stat HEAD~3..HEAD` (recent changes)
- `git stash list` (any stashed work)

## Step 2: Project Context (read if they exist)
- `_handoff.md` — structured handoff from previous session (HIGHEST PRIORITY)
- `_scratchpad.md` — working notes, plans, decisions
- `_plan.md` or any `*-plan.md` — active implementation plans
- `TODO.md` or `TODO` — task lists

## Step 3: Memory (read if available)
- `~/.claude/memory/handoff.md` — auto-generated session hook state
- Auto-memory directory `MEMORY.md` — persistent cross-session knowledge
- Any memory files referenced by MEMORY.md index

## Step 4: Summarize (output to user)

Present a structured summary:

```
Branch: `branch-name` (N commits ahead of main)
Last commit: abc1234 — commit message (time ago)
Uncommitted: N files modified, M untracked

Recent work:
- commit 1 summary
- commit 2 summary
- commit 3 summary

From handoff:
- Task: [what was being done]
- Status: [completed / in-progress items]
- Blockers: [any blockers noted]
- Next steps: [priority-ordered list]

From memory:
- [any relevant recalled context]
```

## Step 5: Ask
If `$ARGUMENTS` is provided, focus on: $ARGUMENTS
Otherwise ask: "What would you like to work on?"
