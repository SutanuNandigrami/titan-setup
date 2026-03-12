---
name: git-workflow
description: Git branching, commit, and PR conventions. Use when creating branches, making commits, or opening PRs.
paths: ["**/*.py", "**/*.js", "**/*.ts", "**/*.go", "**/*.sh", "**/*.rs", "**/*.md", "**/*.tf", "**/Dockerfile*"]
---
# Git Workflow
Branches: `feat/<desc>`, `fix/<desc>`, `chore/<desc>`, `docs/<desc>`
Commits: `<type>(<scope>): <description>` — types: feat, fix, docs, style, refactor, perf, test, chore, ci

## Before Commit
`git diff --stat` → revert unrelated → `shellcheck`/`ruff check` → `gitleaks detect`

## PR: `git push -u origin HEAD` → `gh pr create --fill`

Rules: never force push main, never commit to main, one change per commit, PRs under 400 lines.
