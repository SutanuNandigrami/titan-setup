---
description: Control tmux sessions — create panes, run commands, read output, monitor processes
triggers:
  - tmux
  - terminal pane
  - run in background
  - monitor process
  - split pane
  - send keys
paths: ["**/.tmux*", "**/tmux.conf", "**/*.tmux", "**/tmuxinator*"]
---

# tmux Control

Use tmux to run, monitor, and control background processes.

## Core Commands
```bash
# Session management
tmux new-session -d -s <name>          # create detached session
tmux list-sessions                      # list sessions
tmux kill-session -t <name>             # kill session

# Pane operations
tmux split-window -h -t <session>       # horizontal split
tmux split-window -v -t <session>       # vertical split
tmux select-pane -t <session>:<pane>    # switch pane

# Send commands to panes
tmux send-keys -t <session>:<pane> '<command>' Enter

# Capture pane output (read what's on screen)
tmux capture-pane -t <session>:<pane> -p          # current screen
tmux capture-pane -t <session>:<pane> -p -S -50   # last 50 lines

# Wait for command to finish (check if prompt returned)
tmux send-keys -t <session> 'echo DONE_MARKER' Enter
# Then capture-pane and grep for DONE_MARKER
```

## Patterns

### Run and monitor a dev server
```bash
tmux new-session -d -s dev
tmux send-keys -t dev 'npm run dev' Enter
sleep 2
tmux capture-pane -t dev -p  # check if started
```

### Run parallel tasks
```bash
tmux new-session -d -s work
tmux send-keys -t work 'make build' Enter
tmux split-window -h -t work
tmux send-keys -t work:0.1 'make test' Enter
```

### Read output from a running process
```bash
tmux capture-pane -t <session> -p -S -100  # last 100 lines
```

## Rules
1. Always use `-d` (detached) when creating sessions from Claude.
2. Use `capture-pane -p` to read output — never try to interact with TUI apps.
3. Name sessions descriptively: `dev`, `build`, `logs`, `deploy`.
4. Clean up: `tmux kill-session -t <name>` when done.
5. For interactive tools (htop, vim), tell the user to open them manually.
