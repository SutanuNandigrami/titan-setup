# Edit Locations in titan-setup.sh

Grep anchors for finding insertion points. These patterns survive line number shifts.

## Install Section Anchors

| Method | Grep pattern | How to edit |
|--------|-------------|-------------|
| cargo | `^CARGO_CRATES=(` | Add crate name to the array (space-separated) |
| cargo (git) | After `# spotify_player` block | Add new `if ! command -v` block |
| go | `^declare -A GO_MAP=(` | Add `["binary"]="module/path@latest"` entry |
| go (special) | After `# age —` block | Add new `if command -v` block |
| uv | `^UV_TOOLS=(` | Add package name to the array |
| bun | `^BUN_TOOLS=(` | Add package name to the array |
| apt | `sudo apt install -y` | Add package to the continued line |
| binary | After `# trufflehog —` block | Add new download block |

## cli-tools Heredoc Anchor

The heredoc starts with:
```
cat > "$CLAUDE_DIR/skills/cli-tools/SKILL.md" << 'SKILL'
```

Find the category header and append `- \`tool\` — description` before the
next blank line or next category header.

### Valid categories
Search & Find, File Viewing & Management, Text & Data Wrangling, Git Operations,
Code Quality, Containers & Kubernetes, Infrastructure, Networking & HTTP/Proxy,
Security & Scanning, Databases, System Monitoring, Development Workflow,
Cloud CLIs, AI Tools, Documentation, Terminal Productivity

## Live File Paths

| File | Path |
|------|------|
| cli-tools skill | `~/.claude/skills/cli-tools/SKILL.md` |
| CLAUDE.md | `~/.claude/CLAUDE.md` |
| settings.json | `~/.claude/settings.json` |

## CLAUDE.md Table Anchors

- Tool routing table: grep for last row of `## Tool Routing` table
- MCP replacement table: grep for last row of `## CLI Tools That Replace MCPs` table

## settings.json Allow List Anchor

Inside `"allow": [` block. Add `"Bash(<binary> *)"` after any existing
similar permission line.
