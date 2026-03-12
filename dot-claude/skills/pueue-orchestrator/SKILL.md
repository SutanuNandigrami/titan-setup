---
description: Parallel task orchestration with pueue — queue builds, tests, scans in parallel
triggers:
  - pueue
  - parallel tasks
  - task queue
  - run in parallel
  - background tasks
  - orchestrate
paths: ["**/pueue*", "**/.pueue*", "**/*.task", "**/tasks/**"]
---

# Pueue Task Orchestrator

Use `pueue` to run multiple tasks in parallel with dependency management.

## Setup
```bash
pueued -d                    # start daemon (if not running)
pueue status                 # check status
pueue parallel 4             # allow 4 parallel tasks (default: 1)
```

## Core Operations
```bash
# Add tasks
pueue add -- 'ruff check .'                    # add to default group
pueue add --label "lint-py" -- 'ruff check .'  # with label
pueue add --after 0 -- 'bun test'              # run after task 0

# Groups (for organizing)
pueue group add build
pueue group add test
pueue add --group build -- 'make build'
pueue add --group test -- 'bun test'

# Monitor
pueue status                 # see all tasks
pueue log <id>               # see output of task
pueue follow <id>            # stream output live

# Control
pueue pause <id>             # pause task
pueue start <id>             # resume task
pueue kill <id>              # kill task
pueue clean                  # remove finished tasks
pueue reset                  # kill all, clean everything
```

## Orchestration Patterns

### Pre-push pipeline (parallel lint + test, then scan)
```bash
pueued -d 2>/dev/null || true
pueue parallel 3
LINT=$(pueue add --print-task-id -- 'ruff check . && shellcheck **/*.sh')
TEST=$(pueue add --print-task-id -- 'bun test')
pueue add --after "$LINT,$TEST" -- 'gitleaks detect --verbose'
pueue wait  # blocks until all done
pueue status
```

### Build + deploy with dependencies
```bash
BUILD=$(pueue add --print-task-id --label build -- 'docker build -t app .')
SCAN=$(pueue add --print-task-id --after "$BUILD" --label scan -- 'trivy image app')
pueue add --after "$SCAN" --label deploy -- 'docker push app'
```

### Parallel security scans
```bash
pueue parallel 5
pueue add --label secrets -- 'gitleaks detect --verbose'
pueue add --label deps -- 'osv-scanner -r .'
pueue add --label sast -- 'semgrep --config auto .'
pueue add --label container -- 'trivy image myapp:latest'
pueue add --label iac -- 'tflint --recursive'
pueue wait
```

## Rules
1. Always start `pueued -d` before adding tasks.
2. Set `pueue parallel N` based on task type (CPU-bound: nproc, IO-bound: higher).
3. Use `--print-task-id` to capture IDs for dependencies.
4. Use `pueue wait` to block until pipeline completes.
5. Check `pueue log <id>` for failures, not just exit codes.
6. Run `pueue clean` after reviewing results.
