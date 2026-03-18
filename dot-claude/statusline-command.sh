#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  Claude Code Status Line v2
#  Requires: jq
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

input=$(cat)

# ── Single jq call to parse all fields ─────────────────────
eval "$(echo "$input" | jq -r '
  @sh "MODEL=\(.model.display_name // "?")",
  @sh "CUR_DIR=\(.workspace.current_dir // ".")",
  @sh "PCT=\(.context_window.used_percentage // 0 | floor)",
  @sh "CTX_SIZE=\(.context_window.context_window_size // 200000)",
  @sh "EXCEEDS=\(.exceeds_200k_tokens // false)",
  @sh "COST=\(.cost.total_cost_usd // 0)",
  @sh "DUR_MS=\(.cost.total_duration_ms // 0 | floor)",
  @sh "ADDED=\(.cost.total_lines_added // 0)",
  @sh "REMOVED=\(.cost.total_lines_removed // 0)",
  @sh "VIM_MODE=\(.vim.mode // "")",
  @sh "AGENT=\(.agent.name // "")",
  @sh "WT_NAME=\(.worktree.name // "")",
  @sh "WT_ORIG=\(.worktree.original_branch // "")",
  @sh "CUR_INPUT=\(.context_window.current_usage.input_tokens // 0)",
  @sh "CUR_CACHE_CREATE=\(.context_window.current_usage.cache_creation_input_tokens // 0)",
  @sh "CUR_CACHE_READ=\(.context_window.current_usage.cache_read_input_tokens // 0)"
' 2>/dev/null | tr ',' '\n')"

# Fallbacks if jq failed
: "${MODEL:=?}" "${CUR_DIR:=.}" "${PCT:=0}" "${CTX_SIZE:=200000}"
: "${COST:=0}" "${DUR_MS:=0}" "${ADDED:=0}" "${REMOVED:=0}"
: "${CUR_INPUT:=0}" "${CUR_CACHE_CREATE:=0}" "${CUR_CACHE_READ:=0}"

# ── Colors ─────────────────────────────────────────────────
C='\033[36m' G='\033[32m' Y='\033[33m' R='\033[31m'
B='\033[34m' M='\033[35m' BOLD='\033[1m' DIM='\033[2m' Z='\033[0m'

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  LINE 1 — model · folder · git · badges
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

FOLDER="${CUR_DIR##*/}"

# Git (5s cache, keyed on dir path)
SAFE_DIR=$(echo "$CUR_DIR" | tr '/' '_')
CACHE="/tmp/cc-sl${SAFE_DIR}"
STALE=1
if [ -f "$CACHE" ]; then
  NOW=$(date +%s)
  CMOD=$(stat -c %Y "$CACHE" 2>/dev/null || stat -f %m "$CACHE" 2>/dev/null || echo 0)
  [ $(( NOW - CMOD )) -le 5 ] && STALE=0
fi
if [ "$STALE" -eq 1 ]; then
  if git -C "$CUR_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    _B=$(git -C "$CUR_DIR" branch --show-current 2>/dev/null)
    _S=$(git -C "$CUR_DIR" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    _M=$(git -C "$CUR_DIR" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
    echo "${_B}|${_S}|${_M}" > "$CACHE"
  else
    echo "||" > "$CACHE"
  fi
fi
IFS='|' read -r GIT_BR GIT_ST GIT_MO < "$CACHE" || true

L1="${BOLD}${C}${MODEL}${Z} ${DIM}${FOLDER}${Z}"
if [ -n "$GIT_BR" ]; then
  L1="${L1} ${C}${GIT_BR}${Z}"
  [ "${GIT_ST:-0}" -gt 0 ] 2>/dev/null && L1="${L1} ${G}+${GIT_ST}${Z}"
  [ "${GIT_MO:-0}" -gt 0 ] 2>/dev/null && L1="${L1} ${Y}~${GIT_MO}${Z}"
fi
[ -n "$WT_NAME" ] && L1="${L1} ${B}⎇${WT_NAME}${Z}"
[ -n "$AGENT" ] && L1="${L1} ${M}${AGENT}${Z}"
[ -n "$VIM_MODE" ] && L1="${L1} ${DIM}[${VIM_MODE}]${Z}"

echo -e "$L1"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  LINE 2 — context bar · tokens · cost · session time · changes
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Context bar color
if [ "$PCT" -ge 90 ]; then BAR_C="$R"
elif [ "$PCT" -ge 70 ]; then BAR_C="$Y"
else BAR_C="$G"; fi

# 10-block bar (matches docs)
FILLED=$((PCT * 10 / 100))
EMPTY=$((10 - FILLED))
BAR=""
[ "$FILLED" -gt 0 ] && { printf -v _F "%${FILLED}s" ""; BAR="${_F// /█}"; }
[ "$EMPTY" -gt 0 ] && { printf -v _E "%${EMPTY}s" ""; BAR="${BAR}${_E// /░}"; }

# Actual token count from current_usage
USED_TOKENS=$((CUR_INPUT + CUR_CACHE_CREATE + CUR_CACHE_READ))
if [ "$USED_TOKENS" -ge 1000000 ]; then
  TOK="$((USED_TOKENS / 100000))"
  TOK_LABEL="$((TOK / 10)).$((TOK % 10))M"
elif [ "$USED_TOKENS" -ge 1000 ]; then
  TOK_LABEL="$((USED_TOKENS / 1000))K"
else
  TOK_LABEL="${USED_TOKENS}"
fi

# >200K warning
WARN=""
[ "$EXCEEDS" = "true" ] && WARN=" ${R}${BOLD}>200K${Z}"

L2="${BAR_C}${BAR}${Z} ${BOLD}${PCT}%${Z} ${DIM}${TOK_LABEL}${Z}${WARN}"

# Cost (jq for locale-safe formatting)
COST_FMT=$(echo "$COST" | jq -r '
  if . >= 10 then "$\(. * 100 | floor / 100)"
  elif . >= 1 then "$\(. * 100 | floor / 100)"
  elif . >= 0.01 then "$\(. * 100 | floor / 100)"
  else "$\(. * 1000 | floor / 1000)"
  end' 2>/dev/null)
[ -z "$COST_FMT" ] && COST_FMT="\$${COST}"

L2="${L2} ${Y}${COST_FMT}${Z}"

# Session duration (wall clock — NOT rate limit)
DUR_S=$((DUR_MS / 1000))
DUR_M=$((DUR_S / 60))
DUR_H=$((DUR_M / 60))
if [ "$DUR_H" -gt 0 ]; then
  TIME_FMT="${DUR_H}h$((DUR_M % 60))m"
else
  TIME_FMT="${DUR_M}m$((DUR_S % 60))s"
fi
L2="${L2} ${DIM}${TIME_FMT}${Z}"

# Code changes
if [ "${ADDED:-0}" -gt 0 ] 2>/dev/null || [ "${REMOVED:-0}" -gt 0 ] 2>/dev/null; then
  L2="${L2} ${G}+${ADDED}${Z}${R}-${REMOVED}${Z}"
fi

echo -e "$L2"
