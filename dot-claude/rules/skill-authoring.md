---
paths: "**/.claude/skills/**,**/SKILL.md"
---
# Skill Authoring Rules

## MANDATORY: paths: frontmatter on every SKILL.md
Every SKILL.md MUST have `paths:` in its YAML frontmatter. Without it, the skill loads on EVERY turn and wastes tokens.

Format: `paths: "glob1,glob2,glob3"` (CSV string, NOT JSON array)

WRONG: `paths: ["*.py", "*.sh"]` — CC silently fails, skill loads always
RIGHT: `paths: "**/*.py,**/*.sh"` — CC correctly lazy-loads

## Gating standards by domain
| Domain | paths: value |
|--------|-------------|
| Python | `"**/*.py,**/pyproject.toml,**/requirements*.txt,**/uv.lock"` |
| Shell/Bash | `"**/*.sh,**/*.bash,**/justfile,**/Makefile"` |
| Docker | `"**/Dockerfile*,**/docker-compose*,**/compose.y*ml,**/.dockerignore"` |
| Terraform/IaC | `"**/*.tf,**/*.tfvars,**/*.hcl,**/terraform/**"` |
| Kubernetes | `"**/k8s/**,**/helm/**,**/Chart.yaml,**/*.yaml"` |
| Web frontend | `"**/*.html,**/*.js,**/*.ts,**/*.jsx,**/*.tsx,**/*.vue,**/*.svelte"` |
| Go | `"**/*.go,**/go.mod,**/go.sum"` |
| Rust | `"**/*.rs,**/Cargo.toml,**/Cargo.lock"` |
| Security (always-on) | `"**/*"` |
| General reference (always-on) | `"**/*"` |

## Rules
- Match file types the skill actually references — don't over-gate
- Use `**/*` only for skills that must be available regardless of context
- After creating or installing a skill, verify `grep '^paths:' SKILL.md` returns a CSV string
- Community/plugin skills often lack `paths:` — add it post-install via `sed -i '2a paths: "globs"'`
