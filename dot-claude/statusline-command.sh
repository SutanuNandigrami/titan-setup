#!/usr/bin/env bash
# Claude Code statusLine command
# Mirrors PS1: user@host:dir (green/blue), plus model and context usage

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "?"')
model=$(echo "$input" | jq -r '.model.display_name // "?"')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

# Shorten home directory to ~
home="$HOME"
short_cwd="${cwd/#$home/~}"

# Build context indicator
if [ -n "$remaining" ]; then
  ctx_part=" [ctx:${remaining}%]"
else
  ctx_part=""
fi

# green=\033[01;32m  reset=\033[00m  blue=\033[01;34m  dim=\033[02m
printf '\033[01;32m%s@%s\033[00m:\033[01;34m%s\033[00m\033[02m  %s%s\033[00m' \
  "$(whoami)" "$(hostname -s)" "$short_cwd" "$model" "$ctx_part"
