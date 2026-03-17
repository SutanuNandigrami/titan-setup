---
name: shell-consistency
description: Enforce variable and path consistency in shell scripts. Use when editing titan-setup.sh, adding new install/copy/mkdir commands, doing bulk find-and-replace on shell files, or reviewing shell scripts for correctness. Also triggers on "check paths", "lint setup script", "review titan-setup", or any shell script consistency review.
paths: ["**/titan-setup.sh", "**/*.sh", "**/*.bash"]
---

# Shell Script Consistency Guard

This skill prevents path-variable and convention drift in shell scripts — the
class of bugs where `$CLAUDE_DIR` is defined but some lines hardcode
`~/.claude/` or `$HOME/.claude/` instead. These bugs are silent until they
cause permission errors or write to wrong locations.

## When This Skill Activates

- Editing or adding lines to `titan-setup.sh`
- Bulk find-and-replace (`sd`, `sed`, `perl -pi`) on any shell script
- Adding new skills, plugins, commands, or agents to the setup script
- Reviewing shell scripts for correctness

## Rule 1: Use Defined Variables, Never Hardcode Paths

Before writing ANY file path in a shell script, scan for existing variable
definitions. Common patterns:

| Variable | Definition | NEVER use instead |
|----------|-----------|-------------------|
| `$CLAUDE_DIR` | `CLAUDE_DIR="$HOME/.claude"` | `~/.claude/`, `$HOME/.claude/` |
| `$REPO_FILES` | Set earlier in script | `/dot-claude/`, bare relative paths |
| `$AGT_STASH_DIR` | `AGT_STASH_DIR="$CLAUDE_DIR/agent-stash"` | `$HOME/.claude/agent-stash` |

**Exception:** Cron entries, display strings, and comments may use literal paths
since they execute outside the script's variable scope.

## Rule 2: Pattern-Match Neighboring Lines

Before writing a new `install`, `cp`, `mkdir`, `cat >`, or `git clone` line:

1. Read the 5 lines above and below the insertion point
2. Identify which variables the neighbors use
3. Use the SAME variable pattern — never introduce a different style

**Example — WRONG:**
```bash
# Neighbors use $CLAUDE_DIR:
install -Dm644 "$REPO_FILES/dot-claude/skills/deploy/SKILL.md" "$CLAUDE_DIR/skills/deploy/SKILL.md"
# You add:
install -Dm644 "/dot-claude/skills/new-skill/SKILL.md" "/skills/new-skill/SKILL.md"  # ← BUG
```

**Example — CORRECT:**
```bash
install -Dm644 "$REPO_FILES/dot-claude/skills/deploy/SKILL.md" "$CLAUDE_DIR/skills/deploy/SKILL.md"
install -Dm644 "$REPO_FILES/dot-claude/skills/new-skill/SKILL.md" "$CLAUDE_DIR/skills/new-skill/SKILL.md"
```

## Rule 3: Bulk Edit Safety

When using `sd`, `sed`, or any find-and-replace tool on files containing shell
variables:

1. **Use single quotes** for the pattern to prevent shell expansion
2. **Use `--string-mode`** (sd) or `--expression` (sed) to avoid variable
   interpolation
3. **After the edit**, grep for paths missing their variable prefix:
   ```bash
   rg '(install|cp|mkdir|cat >|git clone).*"/' titan-setup.sh | grep -v '\$'
   ```
4. Any line with a bare `"/` path (not starting with `$`) in a file operation
   is almost certainly a bug

## Rule 4: Post-Edit Verification Checklist

After ANY edit to `titan-setup.sh`, run these checks:

```bash
# 1. Syntax check
bash -n titan-setup.sh

# 2. Find hardcoded ~/.claude/ in functional lines (not comments/display)
rg '(install|cp|mkdir|cat >|git clone|rm |find |sed ).*~/\.claude/' titan-setup.sh

# 3. Find hardcoded $HOME/.claude/ where $CLAUDE_DIR should be used
rg '(install|cp|mkdir|cat >|git clone|rm |find |sed ).*\$HOME/\.claude/' titan-setup.sh

# 4. Find bare absolute paths missing variable prefixes
rg '(install|cp|mkdir|cat >).*"/[a-z]' titan-setup.sh | grep -v '\$'
```

If any of checks 2-4 return results, fix them before committing.

## Rule 5: Copy-Paste from External Sources

When pasting installation commands from upstream READMEs or documentation:

1. External docs will use `~/.claude/` — this is expected
2. **Always** replace with `$CLAUDE_DIR/` when pasting into `titan-setup.sh`
3. **Always** replace source paths with `$REPO_FILES/` prefix when applicable

## Common Mistakes This Skill Prevents

| Mistake | How it happens | Prevention |
|---------|---------------|------------|
| Missing `$REPO_FILES` | Bulk `sd` expands vars to empty | Rule 3 |
| Missing `$CLAUDE_DIR` | Copy-paste from upstream README | Rule 5 |
| Inconsistent `$HOME/.claude` | Different dev wrote the section | Rule 1 |
| Partial fix after bulk edit | Grep found 10/11 broken lines | Rule 4 |
| Bare `/skills/` path | Variable expanded to nothing | Rule 4, check 4 |
