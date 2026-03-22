#!/usr/bin/env bash
# Skill auto-activation — suggests relevant skills based on prompt keywords
# Inspired by claude-code-infrastructure-showcase (diet103)
# Zero token cost when no skill matches — exits silently
# NOTE: no set -euo pipefail — hook must not die on non-zero exits (ADR-004/015)

PROMPT=$(jq -r '.prompt // empty' 2>/dev/null || echo "")
[[ -z "$PROMPT" ]] && exit 0

# Lowercase for case-insensitive matching
PROMPT_LC=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

# Built-in skill registry: skill-name|display-name|keywords (pipe-separated)
# Keywords are grep -E patterns (extended regex, already lowercase)
SKILLS=(
  "security-scan|/scan|scan|vulnerabilit|pentest|security audit|cve|owasp|gitleaks|trivy|nuclei"
  "infra-deploy|infra-deploy|terraform|ansible|playbook|provision|infrastructure|hcl|tfvars"
  "docker-security|docker-security|docker|container|image|dockerfile|compose|hadolint|dive"
  "git-workflow|git-workflow|branch strategy|pull request|merge conflict|rebase|cherry.pick|git flow"
  "pueue-orchestrator|pueue|parallel task|queue|pueue|concurrent|batch job|orchestrat"
  "tmux-control|tmux-control|tmux|terminal session|split pane|detach"
  "diagrams|diagrams|diagram|mermaid|flowchart|sequence diagram|architecture diagram|ascii art"
  "workspace|workspace-init|workspace|project init|new project|scaffold|boilerplate"
  "vibesec|vibesec|xss|sql inject|csrf|ssrf|auth bypass|input validat|sanitiz"
  "tdd|TDD|test.driven|write tests first|red.green.refactor|failing test"
)

MATCHED=""
for entry in "${SKILLS[@]}"; do
  IFS='|' read -r _skill_name display keywords <<< "$entry"
  # Split keywords by | and build grep pattern
  pattern=$(echo "$keywords" | tr '|' '\n' | paste -sd'|')
  if echo "$PROMPT_LC" | grep -qE "$pattern"; then
    MATCHED="${MATCHED:+$MATCHED, }$display"
  fi
done

# Only output if we matched something — zero tokens on no match
if [[ -n "$MATCHED" ]]; then
  echo "[Skills] Relevant skills detected: $MATCHED — use /skill-name to activate"
fi
