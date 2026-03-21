---
paths: "**/*.sh,**/*.bash,**/justfile,**/lib/**"
---
# Shell Rules

## Basics
- Start scripts with `set -euo pipefail`
- Always quote variables: `"$var"` not `$var`
- Use `[[` over `[`, `command -v` over `which`
- Arrays: `"${arr[@]}"` with quotes
- Run `shellcheck` and `shfmt` before committing

## set -e Guard Patterns (titan-specific)
Every failable command in `lib/*.sh` MUST use one of these patterns:

```bash
# Pattern 1: && chain with || fallback (most common)
curl -fsSL ... && ok "tool" || warn "tool install failed"

# Pattern 2: || true for non-critical
sudo systemctl enable foo --now || true
wget -qO- https://example.com/key.gpg | sudo gpg --dearmor -o /path/key.gpg 2>/dev/null || true

# Pattern 3: if/then for critical installs (verify outcome, not exit code)
curl -fsSL https://example.com/install.sh | bash || true
if command -v tool &>/dev/null; then
  ok "tool installed: $(tool --version)"
else
  fail "tool install failed"; exit 1
fi

# Pattern 4: guard pipeline substitutions (pipefail kills unguarded ones)
VAR=$(curl -s https://api.example.com | jq -r '.tag' || true)
[[ -n "$VAR" && "$VAR" != "null" ]] || { warn "fetch failed"; }
```

## Multiline commands
When a curl/wget pipes to the next line with `|` or continues with `\`, the guard
goes on the FINAL line of the chain, not the first:
```bash
curl -fsSL https://example.com/key.gpg |                    # no guard here
  sudo gpg --dearmor -o /path/key.gpg 2>/dev/null || true   # guard here
```

## GitHub API
Never call `api.github.com` directly — 60 req/hr unauthenticated rate limit.
Use `_gh_latest_tag()` from `lib/09-tools-rust-go.sh` which uses redirect-based detection.

## Titan helpers (lib/01-common.sh)
- `ok "msg"` / `warn "msg"` / `fail "msg"` — colored status output
- `section "Phase N — Name"` — phase banner
- `phase_done "phaseN"` / `phase_mark "phaseN"` — idempotent checkpoint system
- `apt_update` — cached apt-get update (runs once per session)
- `check_port 8080 "service"` — warn if port already in use
- `run_q cmd...` — run quietly (stdout/stderr suppressed)

## Testing
After modifying any `lib/*.sh`, always: `just build && just test`
The `set-e-safety.bats` tests automatically catch unguarded commands.
