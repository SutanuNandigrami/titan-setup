# Power Tools Implementation Plan

## Tool Installs (add to titan-setup.sh Phase 3)
- [ ] 1. `inotify-tools` (inotifywait) — apt install
- [ ] 2. `expect` — apt install
- [ ] 3. `mermaid-cli` (mmdc) — bun install -g @mermaid-js/mermaid-cli
- [ ] 4. `asciinema` — apt install
- [ ] 5. `jnv` — cargo install
- [ ] 6. `gum` — go install (charm)
- [ ] 7. `mitmproxy` — uv tool install
- [ ] 8. `at` — apt install (atd)

## Skills (add to titan-setup.sh Phase 5)
- [ ] 9. `tmux-control` skill — send-keys, split panes, read output
- [ ] 10. `workspace` skill — _workspace.json convention + auto-detect
- [ ] 11. `pueue-orchestrator` skill — parallel task orchestration
- [ ] 12. `diagrams` skill — mermaid rendering + architecture diagrams

## Config Updates
- [ ] 13. `direnv` .envrc template in workspace skill
- [ ] 14. sqlite-vec setup for local codebase indexing
- [ ] 15. Update README with all additions
- [ ] 16. Update cli-tools SKILL.md with new tools
