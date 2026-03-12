---
name: add-cli-tool
description: Add a new CLI tool to the titan setup and make it usable immediately. Use when installing a new CLI tool, registering a tool in the setup script, updating the tool inventory, or when the user says "add tool", "new CLI tool", "register tool", "install X to titan". Also triggers on "I installed X", "add X to the setup", or any request to add a CLI tool to the workstation.
paths: ["**/titan-setup.sh", "**/.claude/**", "**/CLAUDE.md"]
---

# Add CLI Tool

This skill registers a new CLI tool across all required locations and makes it
usable in the current session — doing manually what `titan-setup.sh` would do
on a fresh machine.

## Step 1: Gather Information

Ask (or infer from context) these details:

| Field | Required | Example |
|-------|----------|---------|
| Tool name | Yes | `bore-cli` |
| Binary name | If different from tool name | `bore` |
| Install method | Yes | `cargo`, `go`, `uv`, `bun`, `apt`, `binary` |
| Install command | Yes | `cargo install bore-cli` |
| One-line description | Yes | `expose local ports publicly (tunneling)` |
| Category | Yes | One of the categories in cli-tools skill |
| Replaces legacy tool? | No | `replaces dig` → add to CLAUDE.md routing table |
| Replaces an MCP? | No | `replaces Fetch MCP` → add to CLAUDE.md MCP table |

## Step 2: Find titan-setup.sh

```bash
fd titan-setup.sh ~/ --max-depth 3 --type f
```

If not found, ask the user for the path. Store it for the rest of this operation.

## Step 3: Install the Tool NOW

Run the actual install command so the tool is available this session.

## Step 4: Verify Installation

```bash
command -v <binary> && echo "OK" || echo "FAILED"
<binary> --help | head -5
```

If install failed, stop and report the error. Do not proceed to file edits.

## Step 5: Update titan-setup.sh

Read `references/locations.md` for the exact grep anchors for each edit location.

**5a. Install section** — Add to the correct array or block:
- `cargo` → append to `CARGO_CRATES=( ... )` array
- `go` → add entry to `declare -A GO_MAP=( ... )` associative array
- `uv` → append to `UV_TOOLS=( ... )` array
- `bun` → append to `BUN_TOOLS=( ... )` array
- `apt` → append to the `sudo apt install -y \` line
- `binary` / `git` → add a new standalone block after the last binary download section

**5b. cli-tools heredoc** — Find the category header (e.g., `**Security & Scanning:**`)
inside the `cat > "$CLAUDE_DIR/skills/cli-tools/SKILL.md"` heredoc.
Append the tool entry as a new `- \`tool\` — description` line under that category.

IMPORTANT: Only edit within these specific sections. Do NOT modify any other
part of the script.

## Step 6: Update Live Files

Apply the SAME cli-tools edit to the live file — this makes the tool
discoverable by Claude in the current session without re-running the script:

```
~/.claude/skills/cli-tools/SKILL.md
```

Find the same category header and append the same line.

## Step 7: Conditional Updates

Only if applicable:

- **Replaces legacy tool** → Add row to `## Tool Routing` table in `~/.claude/CLAUDE.md`
  AND in the CLAUDE.md heredoc in titan-setup.sh
- **Replaces an MCP** → Add row to `## CLI Tools That Replace MCPs` table in
  `~/.claude/CLAUDE.md` AND in the CLAUDE.md heredoc in titan-setup.sh
- **Needs auto-permission** → Add `Bash(<binary> *)` to the `"allow"` array in BOTH:
  - The settings.json heredoc in titan-setup.sh
  - The live `~/.claude/settings.json`

## Step 8: Validate

```bash
bash -n <path-to-titan-setup.sh>
```

If syntax errors, fix them before proceeding.

## Step 9: Test Tool Call

Run a simple command with the tool to confirm Claude can invoke it:

```bash
<binary> --version
```

## Step 10: Summary

Report to the user:
- Tool installed: Yes/No
- Files updated: list each file touched
- Syntax check: pass/fail
- Tool callable: Yes/No

## Rules

1. NEVER modify parts of titan-setup.sh outside the specific install/heredoc sections.
2. ALWAYS update both the script AND the live file for every edit.
3. ALWAYS run `bash -n` after editing the script.
4. If the tool is already installed (`command -v` succeeds), skip Step 3 but still
   register it in all files if missing.
5. If the tool is already in the cli-tools skill, tell the user — no duplicate entries.
