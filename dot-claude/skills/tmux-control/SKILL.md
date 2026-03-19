---
description: Control tmux sessions — create panes, run commands, read output, monitor processes
triggers:
  - tmux
  - terminal pane
  - run in background
  - monitor process
  - split pane
  - send keys
paths: "**/.tmux*,**/tmux.conf,**/*.tmux,**/tmuxinator*"
---

# tmux Control

## Core Commands
```bash
# Sessions
tmux new-session -d -s <name>          # create detached
tmux list-sessions                      # list
tmux kill-session -t <name>             # kill

# Panes
tmux split-window -h|-v -t <session>   # split horizontal/vertical
tmux select-pane -t <session>:<pane>   # switch pane

# Run commands
tmux send-keys -t <session>:<pane> '<command>' Enter

# Read output
tmux capture-pane -t <session>:<pane> -p          # current screen
tmux capture-pane -t <session>:<pane> -p -S -100  # last 100 lines
```

## Pattern: Run and Monitor
```bash
tmux new-session -d -s dev
tmux send-keys -t dev 'npm run dev' Enter
sleep 2
tmux capture-pane -t dev -p  # check output
```

## Rules
1. Always `-d` (detached) when creating from Claude
2. Use `capture-pane -p` to read — never interact with TUIs
3. Name sessions descriptively: `dev`, `build`, `logs`
4. Clean up: `tmux kill-session -t <name>` when done
5. For interactive tools (htop, vim), tell user to open manually
