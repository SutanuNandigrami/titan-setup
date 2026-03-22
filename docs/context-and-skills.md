# Context System & Skill Auto-Activation — Codemap

> ADR-033 | Inspired by [claude-code-infrastructure-showcase](https://github.com/diet103/claude-code-infrastructure-showcase) (diet103)

## What This Does

Two features that improve Claude Code session continuity and skill discoverability:

1. **Unified context system** — Enhanced `/handoff` and `/catchup` commands that create structured session state documents, surviving context resets and session switches.
2. **Skill auto-activation** — A pure bash hook that suggests relevant skills based on prompt keywords, with zero token cost when no skill matches.

## File Map

```
dot-claude/
├── commands/
│   ├── handoff.md          ← /handoff — creates structured _handoff.md
│   └── catchup.md          ← /catchup — reads git + handoff + memory, summarizes
├── hooks/
│   ├── prompt-memory-inject.sh  ← existing: memory recall on keyword match
│   └── skill-suggest.sh         ← NEW: skill suggestions on keyword match
└── settings.json           ← UserPromptSubmit hooks (both memory + skills)

lib/
└── 11-deploy-config.sh     ← installs skill-suggest.sh to ~/.claude/hooks/

test/
└── session-review.bats     ← 6 regression tests (ADR31: prefix)
```

## Skill Auto-Activation Flow

```
User types prompt
    │
    ▼
UserPromptSubmit hook fires
    │
    ├─→ prompt-memory-inject.sh (existing)
    │     └─→ matches recall keywords? → inject memory
    │
    └─→ skill-suggest.sh (new)
          └─→ matches skill keywords? → output "[Skills] Relevant: /scan, ..."
                                         (zero tokens if no match)
```

## Built-in Skill Registry

| Skill | Trigger Keywords |
|-------|-----------------|
| `/scan` | scan, vulnerability, pentest, security audit, CVE, OWASP |
| `infra-deploy` | terraform, ansible, playbook, provision, infrastructure |
| `docker-security` | docker, container, image, Dockerfile, compose |
| `git-workflow` | branch strategy, pull request, merge conflict, rebase |
| `pueue` | parallel task, queue, pueue, concurrent, batch job |
| `tmux-control` | tmux, terminal session, split pane |
| `diagrams` | diagram, mermaid, flowchart, architecture diagram |
| `workspace-init` | workspace, project init, new project, scaffold |
| `vibesec` | XSS, SQL inject, CSRF, SSRF, auth bypass |
| `TDD` | test-driven, write tests first, red-green-refactor |

Keywords are case-insensitive extended regex patterns matched via `grep -qE`.

## /handoff Document Structure

When user runs `/handoff`, Claude creates `_handoff.md` with:

```markdown
# Handoff — [task]
> Branch: `feat/foo` | Base: `main` @ `abc1234`

## Current Task         ← one paragraph
## Completed            ← checkbox list with file paths
## In Progress          ← what's left
## Key Decisions        ← table: Decision | Why | Rejected Alternative
## Blockers / Risks     ← who can unblock
## Test Status          ← pass/fail/not run
## Next Steps           ← priority-ordered
## Files of Interest    ← paths + why they matter
```

## /catchup Flow

1. Reads git state (branch, log, status, diff)
2. Reads `_handoff.md`, `_scratchpad.md` (if exist)
3. Reads `~/.claude/memory/handoff.md` (session hook state)
4. Reads auto-memory `MEMORY.md` + memory files
5. Outputs structured summary
6. Asks what to work on

## Design Decisions

- **Pure bash, no TypeScript** — The showcase uses tsx for skill activation. We use bash + jq + grep to stay consistent with titan's zero-dependency hook philosophy (ADR-004/015).
- **Built-in registry, no JSON config** — skill-rules.json adds a file to manage. The bash array is simpler and covers titan's 10 deployed skills.
- **Two hooks, one event** — Both memory and skill hooks fire on UserPromptSubmit. Each exits silently on no match (zero tokens). Combined worst-case: ~8s on double match.
- **Key Decisions table in /handoff** — Decisions are the hardest thing to reconstruct. Making them mandatory ensures session continuity.
