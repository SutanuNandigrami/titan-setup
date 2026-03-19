# ─── Phase 5b — Claude Code Plugins ───
section "Phase 5b — Claude Code Plugins"
echo "  Installing official and community plugins..."

# claude auth login is broken over SSH (Enter doesn't register — upstream bug)
# Skip inline auth; plugins are installed below only if already authenticated.
# After setup: run 'claude auth login' from a fresh terminal prompt (not inside
# a script), then re-run plugin installs with: claude plugin install code-review
if command -v claude &>/dev/null && ! claude auth status &>/dev/null 2>&1; then
  warn "Claude not authenticated — plugins will be skipped"
  echo "  After setup, run 'claude auth login' then:"
  echo "    claude plugin marketplace add anthropic/claude-plugins-official"
  echo "    claude plugin install code-review skill-creator"
  echo "    claude plugin marketplace add obra/superpowers-marketplace"
  echo "    claude plugin install episodic-memory"
fi

if ! command -v claude &>/dev/null; then
  warn "Claude CLI not found — skipping plugins"
elif ! claude auth status &>/dev/null 2>&1; then
  warn "Claude not authenticated — skipping plugins (run 'claude auth login' then re-run)"
else
  # Register official marketplace if not already registered
  claude plugin marketplace add anthropic/claude-plugins-official 2>/dev/null \
    && ok "official marketplace" || ok "official marketplace (exists)"

  # Install plugins from official marketplace
  claude plugin install code-review 2>/dev/null && ok "code-review" || warn "code-review"
  claude plugin install skill-creator 2>/dev/null && ok "skill-creator" || warn "skill-creator"

  # playwright MCP — Microsoft's official browser automation MCP server (@playwright/mcp)
  # Provides 22 deferred tools (browser_navigate, browser_click, browser_snapshot, etc.)
  # Uses ref-based accessibility tree for deterministic element targeting — no fragile CSS selectors
  # Requires playwright + chromium (already installed via bun in Phase 4)
  # Token cost: ~300 tokens at startup (deferred tool names), ~2.7K when tools are fetched on first use
  # NOTE: Do NOT remove — this is intentionally an MCP plugin, not a CLI replacement.
  # Playwright CLI (installed in lib/07) handles E2E testing; MCP plugin handles AI-driven browser automation.
  claude plugin install playwright 2>/dev/null && ok "playwright MCP" || warn "playwright MCP"

  # semgrep plugin — only if token was provided
  if [[ -n "$SEMGREP_TOKEN" ]] && ! $SEMGREP_SKIP; then
    if claude plugin install semgrep 2>/dev/null; then
      ok "semgrep plugin"
      # Remove semgrep's UserPromptSubmit hook — injects ~500 tokens of static
      # "Secure-by-Default Libraries" text on EVERY prompt. Wasteful and errors out.
      # Keep PostToolUse (scan on edit) and SessionStart (one-time defaults).
      _sg_hooks=$(find "$HOME/.claude/plugins/cache" -path "*/semgrep/*/hooks/hooks.json" 2>/dev/null | head -1)
      if [[ -n "$_sg_hooks" ]] && jq -e '.hooks.UserPromptSubmit' "$_sg_hooks" &>/dev/null; then
        jq 'del(.hooks.UserPromptSubmit)' "$_sg_hooks" > "${_sg_hooks}.tmp" \
          && mv "${_sg_hooks}.tmp" "$_sg_hooks" \
          && ok "semgrep: removed UserPromptSubmit hook (~500 tokens/prompt saved)"
      fi
