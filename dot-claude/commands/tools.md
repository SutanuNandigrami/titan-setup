List all installed CLI tools by package manager:
1. `uv tool list` — Python tools
2. `ls ~/.cargo/bin/ | sort` — Rust tools
3. `ls ~/go/bin/ | sort` — Go tools
4. `bun pm ls -g` — JS tools
Group by domain (search, data, git, security, infra, etc). If $ARGUMENTS provided, filter to matching keyword.
