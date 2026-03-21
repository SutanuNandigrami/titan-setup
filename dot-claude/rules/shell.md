---
paths: "**/*.sh,**/*.bash,**/justfile"
---
# Shell Rules

## Basics
- Start scripts with `set -euo pipefail`
- Always quote variables: `"$var"` not `$var`
- Use `[[` over `[`, `command -v` over `which`
- Arrays: `"${arr[@]}"` with quotes
- Run `shellcheck` and `shfmt` before committing

## set -e Guard Patterns
Scripts using `set -euo pipefail` will silently die on any unguarded failure.
Every command that can fail (network, packages, services) MUST be guarded:

```bash
# Pattern 1: && chain with || fallback
curl -fsSL ... && echo "done" || echo "failed"

# Pattern 2: || true for non-critical
sudo systemctl enable foo --now || true
wget -qO- https://example.com/key.gpg | sudo gpg --dearmor -o /path/key.gpg 2>/dev/null || true

# Pattern 3: if/then for critical installs (verify outcome, not exit code)
curl -fsSL https://example.com/install.sh | bash || true
if command -v tool &>/dev/null; then
  echo "installed"
else
  echo "failed" >&2
fi

# Pattern 4: guard pipeline substitutions (pipefail kills unguarded ones)
VAR=$(curl -s https://api.example.com | jq -r '.tag' || true)
[[ -n "$VAR" && "$VAR" != "null" ]] || echo "fetch failed" >&2
```

## Multiline commands
When a command pipes or continues to the next line, the guard goes on the FINAL line:
```bash
curl -fsSL https://example.com/key.gpg |                    # no guard here
  sudo gpg --dearmor -o /path/key.gpg 2>/dev/null || true   # guard here
```
