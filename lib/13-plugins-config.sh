      # Patch semgrep hooks.json to guard against non-git-repo dirs
      # semgrep ci requires a git root; without this guard, every Write/Edit outside a repo fails
      _SEMGREP_HOOKS=$(find "$CLAUDE_DIR/plugins/cache" -path '*/semgrep/*/hooks/hooks.json' | head -1)
      if [[ -f "$_SEMGREP_HOOKS" ]]; then
        jq '(.hooks.PostToolUse[].hooks[].command) |= "git rev-parse --git-dir &>/dev/null && " + . + " || true"' \
          "$_SEMGREP_HOOKS" > /tmp/_semgrep_hooks.json \
          && mv /tmp/_semgrep_hooks.json "$_SEMGREP_HOOKS" \
          && ok "semgrep: hooks patched (git-repo guard added)" \
          || warn "semgrep hooks patch failed"
      fi
    else
      warn "semgrep plugin"
    fi
  fi

  # episodic-memory — semantic search over past Claude Code sessions (~200 tokens/session)
  # Free, MIT, no subscription. Local embeddings via @xenova/transformers (no API key needed).
  claude plugin marketplace add obra/superpowers-marketplace 2>/dev/null \
    && ok "superpowers marketplace" || ok "superpowers marketplace (exists)"
  claude plugin install episodic-memory 2>/dev/null && ok "episodic-memory plugin" || warn "episodic-memory plugin"

  # cozempic plugin — context diagnose/treat MCP tools (diagnose_current, treat_session)
  # CLI (uv) provides the primary interface; plugin adds MCP tools for in-session diagnostics
  if ! $COZEMPIC_SKIP; then
    claude plugin marketplace add Ruya-AI/cozempic 2>/dev/null \
      && ok "cozempic marketplace" || ok "cozempic marketplace (exists)"
    claude plugin install cozempic 2>/dev/null && ok "cozempic plugin" || warn "cozempic plugin"
  fi

  # claude-subconscious — Letta-based persistent cross-session memory agent
  if ! $LETTA_SKIP; then
    claude plugin marketplace add letta-ai/claude-subconscious 2>/dev/null \
      && ok "letta marketplace" || ok "letta marketplace (exists)"
    if claude plugin install claude-subconscious 2>/dev/null; then
      ok "claude-subconscious plugin"

      # Install node_modules (tsx + @letta-ai/letta-code-sdk) — CC does not auto-install plugin deps
      _SUBCON_DIR=$(jq -r '.plugins["claude-subconscious@claude-subconscious"][0].installPath // empty' \
        "$CLAUDE_DIR/plugins/installed_plugins.json" 2>/dev/null)
      if [[ -n "$_SUBCON_DIR" ]] && [[ -f "$_SUBCON_DIR/package.json" ]]; then
        (cd "$_SUBCON_DIR" && npm install --silent 2>/dev/null) \
          && ok "subconscious: node_modules installed" \
          || warn "subconscious: npm install failed — hooks may not work"
      fi

      # Patch Subconscious.af: override LLM + embedding to use self-hosted Letta infrastructure
      # Default .af uses openai/text-embedding-3-small and zai/glm-5 (cloud only)
      _SUBCON_AF=""
      if [[ -f "$CLAUDE_DIR/plugins/installed_plugins.json" ]]; then
        _SUBCON_INSTALL=$(jq -r '.plugins["claude-subconscious@claude-subconscious"][0].installPath // empty' \
          "$CLAUDE_DIR/plugins/installed_plugins.json" 2>/dev/null)
        [[ -n "$_SUBCON_INSTALL" ]] && _SUBCON_AF="$_SUBCON_INSTALL/Subconscious.af"
      fi

      if [[ -f "$_SUBCON_AF" ]]; then
        # Patch LLM config: use ccflare billing proxy if available, else direct Anthropic
        # Check bun + proxy file (billing proxy was migrated from socat to Bun)
        if ! $CCFLARE_SKIP && command -v bun &>/dev/null \
            && [[ -f "$HOME/.config/letta/ccflare-billing-proxy.js" ]]; then
          _SUBCON_LLM_ENDPOINT="http://host.docker.internal:${CCFLARE_PROXY_PORT}"
        else
          _SUBCON_LLM_ENDPOINT="https://api.anthropic.com/v1"
        fi
        # Use Sonnet via billing-header proxy (ccflare-billing-proxy injects required header)
        jq --arg ep "$_SUBCON_LLM_ENDPOINT" '
          .agents[0].llm_config.model = "claude-sonnet-4-6" |
          .agents[0].llm_config.model_endpoint_type = "anthropic" |
          .agents[0].llm_config.model_endpoint = $ep |
          .agents[0].llm_config.provider_name = "anthropic" |
          .agents[0].llm_config.handle = "anthropic/claude-sonnet-4-6" |
          .agents[0].llm_config.context_window = 200000
        ' "$_SUBCON_AF" > /tmp/_subcon_af.json \
          && mv /tmp/_subcon_af.json "$_SUBCON_AF" \
          && ok "subconscious: .af patched (LLM → claude-sonnet-4-6 via ${_SUBCON_LLM_ENDPOINT})" \
          || warn "subconscious: .af LLM patch failed"

        # Patch embedding config: use host.docker.internal (Letta runs in Docker, must reach host Ollama)
        if ! $OLLAMA_SKIP && command -v ollama &>/dev/null; then
          jq '
            .agents[0].embedding_config.embedding_endpoint_type = "ollama" |
            .agents[0].embedding_config.embedding_endpoint = "http://host.docker.internal:11434/v1" |
            .agents[0].embedding_config.embedding_model = "nomic-embed-text" |
            .agents[0].embedding_config.embedding_dim = 768 |
            .agents[0].embedding_config.handle = "ollama/nomic-embed-text"
          ' "$_SUBCON_AF" > /tmp/_subcon_af.json \
            && mv /tmp/_subcon_af.json "$_SUBCON_AF" \
            && ok "subconscious: .af patched (embeddings → ollama/nomic-embed-text)" \
            || warn "subconscious: .af embedding patch failed"
        fi
      else
        warn "subconscious: Subconscious.af not found — .af patching skipped"
      fi

      # Enable plugin in settings.json
      jq '.enabledPlugins["claude-subconscious@claude-subconscious"] = true' \
        "$CLAUDE_DIR/settings.json" > /tmp/_cc_settings.json \
        && mv /tmp/_cc_settings.json "$CLAUDE_DIR/settings.json" \
        && ok "subconscious: enabled in settings.json" \
        || warn "subconscious: settings.json update failed"
    else
      warn "claude-subconscious plugin install failed"
    fi
  fi

fi
# ── end claude auth guard (opened in 12-plugins-install.sh) ──

