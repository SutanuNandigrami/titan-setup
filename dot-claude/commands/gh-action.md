Set up Claude Code GitHub Action for the current project:
1. Copy `~/.claude/templates/claude-code-action.yml` to `.github/workflows/claude.yml`
2. Tell the user to add `ANTHROPIC_API_KEY` as a GitHub secret: `gh secret set ANTHROPIC_API_KEY`
3. Explain: `@claude` in PR/issue comments triggers the agent, PRs get auto-reviewed
