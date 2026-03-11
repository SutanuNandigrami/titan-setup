# Titan Setup — Public Release Fixes

## Script Bugs
- [x] 1. Guard `--name` against missing arg (crashes with `set -u`)
- [x] 2. Use temp dir for all downloads (Go, kubectl, duckdb, shellcheck, yazi, mc)
- [x] 3. Add arch detection (x86_64 vs aarch64)
- [x] 4. Validate curl responses for version vars (GO_VERSION, LAZYDOCKER_VERSION, SHELLCHECK_VERSION)
- [x] 5. Add `sd` dependency check before Phase 5 (fallback to sed)
- [x] 6. Fix unconditional success messages (k9s, helm, hadolint, fzf)
- [x] 7. Add existence checks for bun/uv one-off installs

## Security
- [x] 8. Replace deprecated `apt-key add` with signed-by keyring pattern for trivy
- [x] 9. Add checksum note/disclaimer for curl|bash installs (in script header)

## README Gaps
- [x] 10. Document CLI options (--name, --dry-run, --help)
- [x] 11. Add prerequisites section (Ubuntu, x86_64/arm64, sudo, internet, runtime)
- [x] 12. Document Phase 5b (Plugins)
- [x] 13. Add Docker engine to documented installs
- [x] 14. Add ansible-lint to tools list
- [x] 15. Fix skills line count (~340 → ~385)
- [x] 16. Add disclaimer for third-party packages (Claude Desktop/Cowork)
