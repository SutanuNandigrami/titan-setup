#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  Claude Code Status Line — Final
#  Requires: jq
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

input=$(cat)

# ── Parse fields (separate jq calls = safe with any path/value) ────
MODEL=$(echo "$input"    | jq -r '.model.display_name // "?"')
CUR_DIR=$(echo "$input"  | jq -r '.workspace.current_dir // "."')
PCT=$(echo "$input"      | jq -r '.context_window.used_percentage // 0 | floor')
CTX_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
TOT_IN=$(echo "$input"   | jq -r '.context_window.total_input_tokens // 0')
TOT_OUT=$(echo "$input"  | jq -r '.context_window.total_output_tokens // 0')
EXCEEDS=$(echo "$input"  | jq -r '.exceeds_200k_tokens // false')
COST=$(echo "$input"     | jq -r '.cost.total_cost_usd // 0')
DUR=$(echo "$input"      | jq -r '.cost.total_duration_ms // 0')
ADDED=$(echo "$input"    | jq -r '.cost.total_lines_added // 0')
REMOVED=$(echo "$input"  | jq -r '.cost.total_lines_removed // 0')
SID=$(echo "$input"      | jq -r '.session_id // ""')
VIM_MODE=$(echo "$input" | jq -r '.vim.mode // empty')
AGENT=$(echo "$input"    | jq -r '.agent.name // empty')
WT_NAME=$(echo "$input"  | jq -r '.worktree.name // empty')
WT_ORIG=$(echo "$input"  | jq -r '.worktree.original_branch // empty')

# ── Colors ─────────────────────────────────────────────────────────
RS='\033[0m'
B='\033[1m'; D='\033[2m'
RED='\033[31m'; GRN='\033[32m'; YLW='\033[33m'
BLU='\033[34m'; MAG='\033[35m'; CYN='\033[36m'; WHT='\033[97m'

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  LINE 1 — IDENTITY: model · dir · git · badges
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Short session tag (first 4 chars) — helps distinguish parallel sessions
STAG=""
[ -n "$SID" ] && STAG="${D}${SID:0:4}${RS} "

L1="${STAG}${B}${CYN}${MODEL}${RS} 📁 ${WHT}${CUR_DIR##*/}${RS}"

# ── Git (5s cache, keyed on full dir hash) ─────────────────────────
DIR_HASH=$(printf '%s' "$CUR_DIR" | cksum | cut -d' ' -f1)
CACHE="/tmp/cc-sl-${DIR_HASH}"
NOW=$(date +%s)
STALE=1
if [ -f "$CACHE" ]; then
  CMTIME=$(stat -c %Y "$CACHE" 2>/dev/null || stat -f %m "$CACHE" 2>/dev/null || echo 0)
  [ $(( NOW - CMTIME )) -le 5 ] && STALE=0
fi

if [ "$STALE" -eq 1 ]; then
  if git -C "$CUR_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    _BR=$(git -C "$CUR_DIR" branch --show-current 2>/dev/null)
    _ST=$(git -C "$CUR_DIR" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    _MO=$(git -C "$CUR_DIR" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
    _RM=$(git -C "$CUR_DIR" remote get-url origin 2>/dev/null \
          | sed 's|git@github.com:|https://github.com/|;s|\.git$||')
    printf '%s\n' "${_BR}|${_ST}|${_MO}|${_RM}" > "$CACHE"
  else
    printf '%s\n' "|||" > "$CACHE"
  fi
fi
IFS='|' read -r GBR GST GMO GRM < "$CACHE"

if [ -n "$GBR" ]; then
  # Clickable branch name via OSC 8 (if remote exists)
  if [ -n "$GRM" ]; then
    printf -v BDISP '%b' "\e]8;;${GRM}\a${GBR}\e]8;;\a"
  else
    BDISP="$GBR"
  fi
  L1="${L1} ${CYN}🌿 ${BDISP}${RS}"
  [ "$GST" -gt 0 ] && L1="${L1} ${GRN}●${GST}${RS}"
  [ "$GMO" -gt 0 ] && L1="${L1}${YLW}~${GMO}${RS}"
fi

# ── Conditional badges (only when active) ──────────────────────────
if [ -n "$WT_NAME" ]; then
  WT_LBL="⎇${WT_NAME}"
  [ -n "$WT_ORIG" ] && WT_LBL="${WT_LBL}←${WT_ORIG}"
  L1="${L1}  ${BLU}${WT_LBL}${RS}"
fi
[ -n "$AGENT" ]    && L1="${L1}  ${MAG}🤖${AGENT}${RS}"
[ -n "$VIM_MODE" ] && L1="${L1}  ${D}[${VIM_MODE}]${RS}"

printf '%b\n' "$L1"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  LINE 2 — HEALTH: context bar+tokens · cost · reset timer · changes
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# ── Context bar (color by threshold) ───────────────────────────────
if   [ "$PCT" -ge 90 ]; then BC="$RED"
elif [ "$PCT" -ge 70 ]; then BC="$YLW"
else                          BC="$GRN"; fi

BW=12
FL=$(( PCT * BW / 100 )); EM=$(( BW - FL ))
BAR=""
[ "$FL" -gt 0 ] && printf -v _f "%${FL}s" && BAR="${_f// /█}"
[ "$EM" -gt 0 ] && printf -v _e "%${EM}s" && BAR="${BAR}${_e// /░}"

# Token count in K (from current_usage via used_percentage * context_size)
USED_TOKENS=$(( CTX_SIZE * PCT / 100 ))
if [ "$USED_TOKENS" -ge 1000000 ]; then
  TOK_LABEL=$(printf '%.1fM' "$(echo "scale=1; $USED_TOKENS / 1000000" | bc 2>/dev/null || echo 0)")
elif [ "$USED_TOKENS" -ge 1000 ]; then
  TOK_LABEL="$(( USED_TOKENS / 1000 ))K"
else
  TOK_LABEL="${USED_TOKENS}"
fi

# Context size label for extended models
CTX_TAG=""
[ "$CTX_SIZE" -ge 1000000 ] && CTX_TAG="${D}/1M${RS}"

# Exceeds 200K warning
WARN=""
[ "$EXCEEDS" = "true" ] && WARN=" ${RED}${B}⚠>200K${RS}"

L2="${BC}▕${BAR}▏${RS} ${B}${PCT}%${RS} ${D}${TOK_LABEL}${CTX_TAG}${RS}${WARN}"

# ── Cost ───────────────────────────────────────────────────────────
CINT=$(printf '%.0f' "$COST" 2>/dev/null || echo 0)
if [ "${CINT:-0}" -ge 1 ]; then
  CFMT=$(printf '$%.2f' "$COST")
else
  CFMT=$(printf '$%.3f' "$COST")
fi
L2="${L2}  ${D}·${RS}  💰${YLW}${B}${CFMT}${RS}"

# ── 5h reset countdown ────────────────────────────────────────────
REM=$(( 18000000 - DUR ))
[ "$REM" -lt 0 ] && REM=0
RH=$(( REM / 3600000 ))
RM=$(( (REM % 3600000) / 60000 ))
RSC=$(( (REM % 60000) / 1000 ))

if   [ "$RH" -eq 0 ] && [ "$RM" -lt 30 ]; then TC="$RED"
elif [ "$RH" -eq 0 ];                      then TC="$YLW"
else                                             TC="$GRN"; fi

# Hours+min when >60m, min+sec when ≤60m
if [ "$RH" -gt 0 ]; then TF="${RH}h${RM}m"
else                      TF="${RM}m${RSC}s"; fi

L2="${L2}  ${D}·${RS}  🔄${TC}${TF}${RS}"

# ── Code changes (only if non-zero) ───────────────────────────────
if [ "$ADDED" -gt 0 ] || [ "$REMOVED" -gt 0 ]; then
  L2="${L2}  ${D}·${RS}  ${GRN}+${ADDED}${RS}${RED}−${REMOVED}${RS}"
fi

printf '%b\n' "$L2"
