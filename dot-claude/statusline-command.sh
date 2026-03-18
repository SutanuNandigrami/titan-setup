#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  Claude Code Status Line — Final
#  Requires: jq  (brew install jq / apt install jq)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

input=$(cat)

# ── Parse fields (one jq per field, matches doc pattern) ─────
MODEL=$(echo "$input" | jq -r '.model.display_name')
CUR_DIR=$(echo "$input" | jq -r '.workspace.current_dir')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
CTX_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
EXCEEDS=$(echo "$input" | jq -r '.exceeds_200k_tokens // false')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
DUR=$(echo "$input" | jq -r '.cost.total_duration_ms // 0' | cut -d. -f1)
ADDED=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
REMOVED=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')
VIM_MODE=$(echo "$input" | jq -r '.vim.mode // empty')
AGENT=$(echo "$input" | jq -r '.agent.name // empty')
WT_NAME=$(echo "$input" | jq -r '.worktree.name // empty')
WT_ORIG=$(echo "$input" | jq -r '.worktree.original_branch // empty')

# Get actual current input tokens for display (not cumulative)
CUR_INPUT=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
CUR_CACHE_CREATE=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
CUR_CACHE_READ=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')

# ── Colors (same escape style as docs) ───────────────────────
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
BLUE='\033[34m'
MAGENTA='\033[35m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  LINE 1 — WHERE: model · folder · git branch+status · badges
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

FOLDER="${CUR_DIR##*/}"

# ── Git (5s cache, keyed on sanitized dir path) ──────────────
SAFE_DIR=$(echo "$CUR_DIR" | tr '/' '_')
CACHE="/tmp/cc-sl${SAFE_DIR}"
STALE=1
if [ -f "$CACHE" ]; then
  NOW=$(date +%s)
  CMOD=$(stat -c %Y "$CACHE" 2>/dev/null || stat -f %m "$CACHE" 2>/dev/null || echo 0)
  [ $(( NOW - CMOD )) -le 5 ] && STALE=0
fi

if [ "$STALE" -eq 1 ]; then
  if git -C "$CUR_DIR" rev-parse --git-dir > /dev/null 2>&1; then
    _B=$(git -C "$CUR_DIR" branch --show-current 2>/dev/null)
    _S=$(git -C "$CUR_DIR" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    _M=$(git -C "$CUR_DIR" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
    echo "${_B}|${_S}|${_M}" > "$CACHE"
  else
    echo "||" > "$CACHE"
  fi
fi
IFS='|' read -r GIT_BR GIT_ST GIT_MO < "$CACHE"

# Build line 1
L1="${BOLD}${CYAN}${MODEL}${RESET} 📁 ${FOLDER}"

if [ -n "$GIT_BR" ]; then
  L1="${L1} ${DIM}|${RESET} ${CYAN}🌿 ${GIT_BR}${RESET}"
  [ "$GIT_ST" -gt 0 ] 2>/dev/null && L1="${L1} ${GREEN}●${GIT_ST}${RESET}"
  [ "$GIT_MO" -gt 0 ] 2>/dev/null && L1="${L1} ${YELLOW}~${GIT_MO}${RESET}"
fi

# Conditional badges
if [ -n "$WT_NAME" ]; then
  WT_LBL="⎇ ${WT_NAME}"
  [ -n "$WT_ORIG" ] && WT_LBL="${WT_LBL}←${WT_ORIG}"
  L1="${L1} ${BLUE}${WT_LBL}${RESET}"
fi
[ -n "$AGENT" ] && L1="${L1} ${MAGENTA}🤖 ${AGENT}${RESET}"
[ -n "$VIM_MODE" ] && L1="${L1} ${DIM}[${VIM_MODE}]${RESET}"

echo -e "$L1"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  LINE 2 — HEALTH: context bar · tokens · cost · reset timer
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# ── Context bar color ────────────────────────────────────────
if [ "$PCT" -ge 90 ]; then BAR_COLOR="$RED"
elif [ "$PCT" -ge 70 ]; then BAR_COLOR="$YELLOW"
else BAR_COLOR="$GREEN"; fi

# 12-block bar (each block ≈ 8%)
FILLED=$((PCT * 12 / 100))
EMPTY=$((12 - FILLED))
BAR=""
if [ "$FILLED" -gt 0 ]; then
  printf -v FILL_S "%${FILLED}s" ""
  BAR="${FILL_S// /█}"
fi
if [ "$EMPTY" -gt 0 ]; then
  printf -v EMPTY_S "%${EMPTY}s" ""
  BAR="${BAR}${EMPTY_S// /░}"
fi

# ── Token count from current_usage (actual context state) ────
USED_TOKENS=$((CUR_INPUT + CUR_CACHE_CREATE + CUR_CACHE_READ))
if [ "$USED_TOKENS" -ge 1000000 ]; then
  TOK_H=$((USED_TOKENS / 100000))
  TOK_W=$((TOK_H / 10))
  TOK_F=$((TOK_H % 10))
  TOK_LABEL="${TOK_W}.${TOK_F}M"
elif [ "$USED_TOKENS" -ge 1000 ]; then
  TOK_LABEL="$((USED_TOKENS / 1000))K"
else
  TOK_LABEL="${USED_TOKENS}"
fi

# Context window size label for extended models
CTX_TAG=""
[ "$CTX_SIZE" -ge 1000000 ] && CTX_TAG="${DIM}/1M${RESET}"

# Exceeds 200K warning
WARN=""
[ "$EXCEEDS" = "true" ] && WARN=" ${RED}${BOLD}⚠>200K${RESET}"

L2="${BAR_COLOR}${BAR}${RESET} ${BOLD}${PCT}%%${RESET} ${DIM}${TOK_LABEL}${CTX_TAG}${RESET}${WARN}"

# ── Cost (use jq for formatting to avoid locale issues) ──────
COST_FMT=$(echo "$COST" | jq -r 'if . >= 1 then "$\(. | tostring | .[0:5])" elif . >= 0.1 then "$\(. * 100 | floor / 100 | tostring)" else "$\(. * 1000 | floor / 1000 | tostring)" end' 2>/dev/null)
[ -z "$COST_FMT" ] && COST_FMT="\$${COST}"

L2="${L2} ${DIM}|${RESET} 💰 ${YELLOW}${BOLD}${COST_FMT}${RESET}"

# ── 5hr reset countdown ──────────────────────────────────────
REM_MS=$((18000000 - DUR))
[ "$REM_MS" -lt 0 ] && REM_MS=0
REM_H=$((REM_MS / 3600000))
REM_M=$(((REM_MS % 3600000) / 60000))
REM_S=$(((REM_MS % 60000) / 1000))

if [ "$REM_H" -eq 0 ] && [ "$REM_M" -lt 30 ]; then TIME_C="$RED"
elif [ "$REM_H" -eq 0 ]; then TIME_C="$YELLOW"
else TIME_C="$GREEN"; fi

if [ "$REM_H" -gt 0 ]; then
  TIME_FMT="${REM_H}h${REM_M}m"
else
  TIME_FMT="${REM_M}m${REM_S}s"
fi

L2="${L2} ${DIM}|${RESET} 🔄 ${TIME_C}${BOLD}${TIME_FMT}${RESET}"

# ── Code changes (only if any exist) ─────────────────────────
if [ "$ADDED" -gt 0 ] 2>/dev/null || [ "$REMOVED" -gt 0 ] 2>/dev/null; then
  L2="${L2} ${DIM}|${RESET} ${GREEN}+${ADDED}${RESET} ${RED}-${REMOVED}${RESET}"
fi

echo -e "$L2"
