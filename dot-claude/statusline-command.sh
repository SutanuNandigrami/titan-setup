#!/usr/bin/env bash
# Claude Code statusline — 2-row, plain text, no ANSI
#
# Row 1:  Model  │  ⎇ branch +staged ~unstaged  │  vX.Y.Z  │  style:X
# Row 2:  ctx N% [████░░░░]  │  $cost  │  Xhr Ym  │  cache:X in:X out:X total:X

set -euo pipefail
input=$(cat)

# ── Parse all fields in one jq call ───────────────────────────
eval "$(echo "$input" | jq -r '
  "MODEL="     + (.model.display_name                                         // "?" | @sh),
  "STYLE="     + (.output_style.name                                          // "default" | @sh),
  "VERSION="   + (.version                                                    // "" | @sh),
  "COST="      + ((.cost.total_cost_usd                                       // 0) | tostring),
  "DUR_MS="    + ((.cost.total_duration_ms                                    // 0) | tostring),
  "LINES_A="   + ((.cost.total_lines_added                                    // 0) | tostring),
  "LINES_D="   + ((.cost.total_lines_removed                                  // 0) | tostring),
  "CTX_PCT="   + ((.context_window.used_percentage                            // 0) | tostring),
  "CTX_SIZE="  + ((.context_window.context_window_size                        // 200000) | tostring),
  "TOT_IN="    + ((.context_window.total_input_tokens                         // 0) | tostring),
  "TOT_OUT="   + ((.context_window.total_output_tokens                        // 0) | tostring),
  "CACHE_R="   + ((.context_window.current_usage.cache_read_input_tokens      // 0) | tostring),
  "CACHE_C="   + ((.context_window.current_usage.cache_creation_input_tokens  // 0) | tostring),
  "CUR_IN="    + ((.context_window.current_usage.input_tokens                 // 0) | tostring),
  "CUR_OUT="   + ((.context_window.current_usage.output_tokens                // 0) | tostring),
  "AGENT="     + (.agent.name                                                 // "" | @sh),
  "WORKTREE="  + (.worktree.name                                              // "" | @sh)
' 2>/dev/null || true)"

# No ANSI — plain text only (multi-line + ANSI causes rendering issues in CC)

# ── Helpers ───────────────────────────────────────────────────
fmt_tok() {
    local n=${1:-0}
    if   (( n >= 1000000 )); then awk "BEGIN{printf \"%.1fM\", $n/1000000}"
    elif (( n >= 1000    )); then awk "BEGIN{printf \"%.1fk\", $n/1000}"
    else printf "%d" "$n"; fi
}

# ── Derived ───────────────────────────────────────────────────
CTX_INT=$(awk "BEGIN{printf \"%d\", ${CTX_PCT:-0}}")
COST_FMT=$(awk "BEGIN{printf \"\$%.2f\", ${COST:-0}}")
CACHED=$(( ${CACHE_R:-0} + ${CACHE_C:-0} ))
TOTAL=$(( ${TOT_IN:-0} + ${TOT_OUT:-0} ))

# Duration: Xhr Ym or Ym
MINS=$(( ${DUR_MS:-0} / 60000 ))
HOURS=$(( MINS / 60 ))
(( HOURS > 0 )) && DUR="${HOURS}hr $((MINS % 60))m" || DUR="${MINS}m"

# Context bar (20 wide)
BAR_W=20
FILLED=$(( CTX_INT * BAR_W / 100 ))
EMPTY=$(( BAR_W - FILLED ))
BAR=""
(( FILLED > 0 )) && { printf -v _F "%${FILLED}s"; BAR="${_F// /█}"; }
(( EMPTY  > 0 )) && { printf -v _E "%${EMPTY}s";  BAR="${BAR}${_E// /░}"; }

# Context urgency marker (plain text — no ANSI)
(( CTX_INT >= 90 )) && CTX_WARN="!!! " || { (( CTX_INT >= 70 )) && CTX_WARN="! " || CTX_WARN=""; }

# ── Git (cached 5s to avoid per-turn overhead) ────────────────
GCACHE="/tmp/cc-sl-git.cache"
CAGE=$(( $(date +%s) - $(stat -c %Y "$GCACHE" 2>/dev/null || echo 0) ))
if [[ ! -f "$GCACHE" ]] || (( CAGE > 5 )); then
    if git rev-parse --git-dir >/dev/null 2>&1; then
        GB=$(git branch --show-current 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo "HEAD")
        ST=$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
        UT=$(git diff --numstat 2>/dev/null | wc -l | tr -d ' ')
        printf '%s|%s|%s\n' "$GB" "$ST" "$UT" > "$GCACHE"
    else
        printf 'no git|0|0\n' > "$GCACHE"
    fi
fi
IFS='|' read -r GB ST UT < "$GCACHE" || true

# Git suffix: +staged ~unstaged
GIT_SUFFIX=""
(( ${ST:-0} > 0 )) && GIT_SUFFIX="${GIT_SUFFIX} +${ST}"
(( ${UT:-0} > 0 )) && GIT_SUFFIX="${GIT_SUFFIX} ~${UT}"

# Optional agent / worktree badges
BADGES=""
[[ -n "${AGENT:-}"    ]] && BADGES="${BADGES} │ agent:${AGENT}"
[[ -n "${WORKTREE:-}" ]] && BADGES="${BADGES} │ wt:${WORKTREE}"

# Lines changed (omit if zero)
LINES_SEG=""
(( ${LINES_A:-0} + ${LINES_D:-0} > 0 )) && LINES_SEG=" │ +${LINES_A}/-${LINES_D} lines"

# ── Row 1: identity + git ─────────────────────────────────────
printf '%s │ ⎇ %s%s │ v%s │ style:%s%s\n' \
    "$MODEL" \
    "$GB" "$GIT_SUFFIX" \
    "$VERSION" \
    "$STYLE" \
    "$BADGES"

# ── Row 2: context + cost + tokens ────────────────────────────
printf '%sctx %d%% [%s] │ %s │ %s%s │ cache:%s  in:%s  out:%s  total:%s\n' \
    "$CTX_WARN" \
    "$CTX_INT" \
    "$BAR" \
    "$COST_FMT" \
    "$DUR" \
    "$LINES_SEG" \
    "$(fmt_tok "$CACHED")" \
    "$(fmt_tok "$CUR_IN")" \
    "$(fmt_tok "$CUR_OUT")" \
    "$(fmt_tok "$TOTAL")"
