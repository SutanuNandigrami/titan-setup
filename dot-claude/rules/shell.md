---
paths: ["**/*.sh", "**/*.bash", "**/justfile"]
---
# Shell Rules
- Start scripts with `set -euo pipefail`
- Always quote variables: `"$var"` not `$var`
- Run `shellcheck` before executing any script
- Use `shfmt` for formatting
- Prefer `[[` over `[` for conditionals
- Use `command -v` not `which` for existence checks
- Arrays: `"${arr[@]}"` with quotes
