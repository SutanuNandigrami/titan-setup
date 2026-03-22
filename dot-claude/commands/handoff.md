---
description: Create structured handoff document for session continuity
argument-hint: Optional focus area (e.g., "auth refactor", "deployment pipeline")
---

Create or update `_handoff.md` in the current project root. This document must let a fresh session (or a different engineer) resume with zero context loss.

## Instructions

1. **Gather context** by running these commands (do NOT skip any):
   - `git branch --show-current` — current branch
   - `git log --oneline -10` — recent commits
   - `git status -s` — uncommitted changes
   - `git diff --stat` — what's modified
   - Check for `_scratchpad.md`, `_handoff.md`, open TODOs in code

2. **Write `_handoff.md`** with ALL of these sections:

```markdown
# Handoff — [brief task description]
> Last updated: YYYY-MM-DD HH:MM by [session/engineer]
> Branch: `branch-name` | Base: `main` @ `abc1234`

## Current Task
One paragraph: what we're doing and why.

## Completed
- [x] Description (file paths changed)
- [x] Description (file paths changed)

## In Progress
- [ ] Description — current state, what's left
- [ ] Description — current state, what's left

## Key Decisions
| Decision | Why | Alternative Rejected |
|----------|-----|---------------------|
| Chose X over Y | Reason | Y was too complex because... |

## Blockers / Risks
- Blocker: description (who can unblock)
- Risk: description (mitigation)

## Test Status
- [ ] Unit tests: pass / fail / not run
- [ ] Integration tests: pass / fail / not run
- [ ] Lint: pass / fail / not run
- Notes: any flaky tests, known failures

## Next Steps (priority order)
1. First thing to do
2. Second thing to do
3. Third thing to do

## Files of Interest
Key files that the next session should read first:
- `path/to/critical/file.py` — why it matters
- `path/to/other/file.sh` — why it matters
```

3. **Stage and commit** `_handoff.md` with message: `docs: update handoff for [task]`

## Quality Rules
- Write for someone with ZERO context — no "as discussed" or "the thing we talked about"
- Include file paths for every change mentioned
- Key Decisions table is mandatory — decisions are the hardest thing to reconstruct
- If `$ARGUMENTS` is provided, focus the handoff on that area: $ARGUMENTS
