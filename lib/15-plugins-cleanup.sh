# Patch plugin SKILL.md files with paths: scoping — plugin updates may clear these, so re-patch after install
# This prevents skill-creator/hookify/episodic-memory from loading on every turn (93% token reduction)
if command -v claude &>/dev/null && claude auth status &>/dev/null 2>&1; then
  _patch_plugin_skill() {
    local plugin_key="$1" subpath="$2" paths_value="$3"
    local install_path
    install_path=$(jq -r --arg k "$plugin_key" '.plugins[$k][0].installPath // empty' \
      "$CLAUDE_DIR/plugins/installed_plugins.json" 2>/dev/null)
    [[ -z "$install_path" ]] && return 0
    local skill_md="$install_path/$subpath"
    [[ -f "$skill_md" ]] || return 0
    if ! grep -q '^paths:' "$skill_md" 2>/dev/null; then
      sed -i "2a paths: ${paths_value}" "$skill_md" 2>/dev/null && ok "patched: $plugin_key SKILL.md" || true
    fi
  }
  _patch_plugin_skill "skill-creator@claude-plugins-official" \
    "skills/skill-creator/SKILL.md" \
    '["**/.claude/**", "**/skills/**", "**/SKILL.md", "**/CLAUDE.md"]'
  _patch_plugin_skill "hookify@claude-plugins-official" \
    "skills/writing-rules/SKILL.md" \
    '["**/.claude/**", "**/hooks/**", "**/rules/**", "**/hookify*"]'
  _patch_plugin_skill "episodic-memory@superpowers-marketplace" \
    "skills/remembering-conversations/SKILL.md" \
    '["**/memory/**", "**/.claude/memory/**", "**/handoff*", "**/_scratchpad*"]'

  # Cleanup: remove non-installed plugin dirs from marketplace cache to prevent SKILL.md bloat
  # Each marketplace add can bring many plugin dirs; only keep what's actually installed
  INSTALLED_JSON="$CLAUDE_DIR/plugins/installed_plugins.json"
  if [[ -f "$INSTALLED_JSON" ]]; then
    CACHE_ROOT="$CLAUDE_DIR/plugins/cache"
    mapfile -t ACTIVE_PATHS < <(jq -r '.plugins | to_entries[] | .value[] | .installPath' "$INSTALLED_JSON" 2>/dev/null)
    if [[ -d "$CACHE_ROOT" ]]; then
      while IFS= read -r -d '' vpath; do
        vpath="${vpath%/}"
        is_active=false
        for ap in "${ACTIVE_PATHS[@]}"; do
          [[ "$ap" == "$vpath" ]] && { is_active=true; break; }
        done
        if ! $is_active; then
          rm -rf "$vpath" 2>/dev/null || true
        fi
      done < <(find "$CACHE_ROOT" -mindepth 3 -maxdepth 3 -type d -print0 2>/dev/null)
      ok "plugin cache: removed stale versions"
    fi
  fi
fi

