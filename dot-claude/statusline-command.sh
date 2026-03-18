#!/usr/bin/env bash
# Claude Code native statusline — 4-row display
# Reads JSON from stdin, outputs ANSI-colored status rows.
# Replicates ccstatusline layout using native CC data (API-accurate).
#
# Row 1: Model | Style | Version | ⎇ branch | git-root
# Row 2: Ctx used% | Ctx remaining% | Ctx size | progress bar
# Row 3: Free mem | Cost | Cached tokens | In | Out | Total
# Row 4: Duration | +lines/-lines | Date

set -euo pipefail

input=$(cat)

# ── ANSI background+foreground color blocks ───────────────────
BLK_G='\033[42;30m'    # green bg, black fg
BLK_M='\033[45;97m'    # magenta bg, white fg
BLK_R='\033[41;97m'    # red bg, white fg
BLK_C='\033[46;30m'    # cyan bg, black fg
BLK_B='\033[44;97m'    # blue bg, white fg
BLK_W='\033[47;30m'    # white bg, black fg
BLK_Y='\033[43;30m'    # yellow bg, black fg
BLK_K='\033[100;97m'   # dark gray bg, white fg
BLK_BM='\033[105;30m'  # bright magenta bg, black fg
BLK_BW='\033[107;30m'  # bright white bg, black fg
BLK_BR='\033[101;97m'  # bright red bg, white fg
BLK_BG='\033[102;30m'  # bright green bg, black fg
BLK_BY='\033[103;30m'  # bright yellow bg, black fg
BLK_BC='\033[106;30m'  # bright cyan bg, black fg
X='\033[0m'            # reset

# ── Parse all JSON fields in one jq call ──────────────────────
eval "$(echo "$input" | jq -r '
  "MODEL="         + (.model.display_name          // "?" | @sh),
  "STYLE="         + (.output_style.name           // "default" | @sh),
  "VERSION="       + (.version                     // "" | @sh),
  "COST="          + ((.cost.total_cost_usd        // 0) | tostring),
  "DURATION_MS="   + ((.cost.total_duration_ms     // 0) | tostring),
  "LINES_ADD="     + ((.cost.total_lines_added     // 0) | tostring),
  "LINES_DEL="     + ((.cost.total_lines_removed   // 0) | tostring),
  "CTX_USED="      + ((.context_window.used_percentage       // 0) | tostring),
  "CTX_REM="       + ((.context_window.remaining_percentage  // 0) | tostring),
  "CTX_SIZE="      + ((.context_window.context_window_size   // 200000) | tostring),
  "TOT_IN="        + ((.context_window.total_input_tokens    // 0) | tostring),
  "TOT_OUT="       + ((.context_window.total_output_tokens   // 0) | tostring),
  "CACHE_READ="    + ((.context_window.current_usage.cache_read_input_tokens    // 0) | tostring),
  "CACHE_CREATE="  + ((.context_window.current_usage.cache_creation_input_tokens // 0) | tostring),
  "CUR_IN="        + ((.context_window.current_usage.input_tokens  // 0) | tostring),
  "CUR_OUT="       + ((.context_window.current_usage.output_tokens // 0) | tostring)
' 2>/dev/null || true)"

# ── Derived values ────────────────────────────────────────────
# Format floats to 1dp safely
CTX_PCT=$(awk "BEGIN{printf \"%.1f\", ${CTX_USED:-0}}")
CTX_REM_PCT=$(awk "BEGIN{printf \"%.1f\", ${CTX_REM:-0}}")
CTX_K=$(awk "BEGIN{printf \"%.1f\", ${CTX_SIZE:-200000}/1000}")
COST_FMT=$(awk "BEGIN{printf \"\$%.2f\", ${COST:-0}}")
CACHED=$(( ${CACHE_READ:-0} + ${CACHE_CREATE:-0} ))
TOTAL=$(( ${TOT_IN:-0} + ${TOT_OUT:-0} ))

# Duration: ms → hr / min
MINS=$(( ${DURATION_MS:-0} / 60000 ))
HOURS=$(( MINS / 60 ))
[[ $HOURS -gt 0 ]] && DUR_FMT="${HOURS}hr" || DUR_FMT="${MINS}m"

# Format large numbers as k / M
fmt_tok() {
    local n=${1:-0}
    if   (( n >= 1000000 )); then awk "BEGIN{printf \"%.1fM\", $n/1000000}"
    elif (( n >= 1000    )); then awk "BEGIN{printf \"%.1fk\", $n/1000}"
    else printf "%d" "$n"; fi
}

# Context progress bar (16 wide, threshold-colored)
BAR_W=16
CTX_INT=$(awk "BEGIN{printf \"%d\", ${CTX_USED:-0}}")
FILLED=$(( CTX_INT * BAR_W / 100 ))
EMPTY=$(( BAR_W - FILLED ))
BAR=""
(( FILLED > 0 )) && { printf -v F "%${FILLED}s"; BAR="${F// /█}"; }
(( EMPTY  > 0 )) && { printf -v E "%${EMPTY}s";  BAR="${BAR}${E// /░}"; }
(( CTX_INT >= 90 )) && BAR_COL=$BLK_BR || { (( CTX_INT >= 70 )) && BAR_COL=$BLK_BY || BAR_COL=$BLK_B; }

# Git info — cached 5s to avoid repeated git calls
GIT_CACHE="/tmp/cc-statusline-git.cache"
CACHE_AGE=$(( $(date +%s) - $(stat -c %Y "$GIT_CACHE" 2>/dev/null || echo 0) ))
if [[ ! -f "$GIT_CACHE" ]] || (( CACHE_AGE > 5 )); then
    if git rev-parse --git-dir > /dev/null 2>&1; then
        GB=$(git branch --show-current 2>/dev/null || echo "HEAD")
        GR=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "")
    else
        GB="no git"; GR=""
    fi
    printf '%s|%s\n' "$GB" "$GR" > "$GIT_CACHE"
fi
IFS='|' read -r GBRANCH GROOT < "$GIT_CACHE" || true

# Free memory (used/total)
FREE_MEM=$(free -h 2>/dev/null | awk '/^Mem:/{print $3"/"$2}' || echo "?")

# Date string matching ccstatusline format
DATE_STR=$(date "+%a %b %d %I:%M:%S %p %Z %Y")

# ── Render rows ───────────────────────────────────────────────
# Row 1: Model | Style | Version | git branch | git root
printf "${BLK_G} %s ${X} ${BLK_M} Style: %s ${X} ${BLK_M} v%s ${X} ${BLK_BC} ⎇ %s ${X}" \
    "$MODEL" "$STYLE" "$VERSION" "$GBRANCH"
[[ -n "$GROOT" ]] && printf " ${BLK_C} %s ${X}" "$GROOT"
printf '\n'

# Row 2: Context usage
printf "${BLK_W} Ctx: %s%% ${X} ${BLK_B} Ctx(r): %s%% ${X} ${BLK_BR} Ctx: %sk ${X} ${BAR_COL} Context: [%s] ${X}\n" \
    "$CTX_PCT" "$CTX_REM_PCT" "$CTX_K" "$BAR"

# Row 3: System stats + token counts
printf "${BLK_BR} %s ${X} ${BLK_R} %s ${X} ${BLK_BM} Cached: %s ${X} ${BLK_BW} In: %s ${X} ${BLK_BR} Out: %s ${X} ${BLK_BG} Total: %s ${X}\n" \
    "$FREE_MEM" "$COST_FMT" "$(fmt_tok "$CACHED")" \
    "$(fmt_tok "$CUR_IN")" "$(fmt_tok "$CUR_OUT")" "$(fmt_tok "$TOTAL")"

# Row 4: Duration | code changes | date
printf "${BLK_BR} %s ${X} ${BLK_R} +%d/-%d lines ${X} ${BLK_BY} %s ${X}\n" \
    "$DUR_FMT" "${LINES_ADD:-0}" "${LINES_DEL:-0}" "$DATE_STR"
