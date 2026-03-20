# sd is required for template substitution (installed via cargo in Phase 3)
if ! command -v sd &>/dev/null; then
  warn "sd not found — falling back to sed for template substitution"
  sd() { sed -i "s|$1|$2|g" "$3"; }
fi

CLAUDE_DIR="$HOME/.claude"

# ─── Detect running CC sessions — warn before config changes ───
if pgrep -f 'claude' &>/dev/null; then
  warn "Claude Code is running — config changes may not take effect until restart"
fi

# ─── Cleanup stale artifacts from previous versions ───
rm -rf "$HOME/.claude/plugins/cache/claude-plugins-official/hookify/" 2>/dev/null
rm -rf "$HOME/.claude/skills/tool-discovery/" 2>/dev/null    # replaced by cli-tools
rm -rf "$HOME/.claude/skills/security-ops/" 2>/dev/null      # replaced by security-scan
rm -rf "$HOME/.claude/skills/debug-protocol/" 2>/dev/null    # replaced by systematic-debugging

# Backup existing
if [ -d "$CLAUDE_DIR/skills" ] || [ -d "$CLAUDE_DIR/commands" ] || [ -d "$CLAUDE_DIR/agents" ]; then
  BACKUP="$CLAUDE_DIR.backup.$(date +%s)"
  cp -r "$CLAUDE_DIR" "$BACKUP" 2>/dev/null || true
  ok "Backed up existing config to $BACKUP"
fi

mkdir -p "$CLAUDE_DIR"/{skills/cli-tools,skills/security-scan,skills/git-workflow,skills/infra-deploy,skills/add-cli-tool/references,skills/tmux-control,skills/workspace,skills/pueue-orchestrator,skills/diagrams,skills/deploy,skills/process-supervisor,skills/docker-security,skills/vibesec,skills/trailofbits-modern-python,skills/notebooklm-skills,commands,agents,hooks,memory,rules,logs,templates,agent-stash/_loaded,agent-stash/agents}
mkdir -p "$HOME/.config/agt"

# REPO_FILES already set by lib/06b-repo-files.sh (cloned early for tool patches)

# ─── CLAUDE.md ───
install -Dm644 "$REPO_FILES/dot-claude/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
sd 'TITAN_ENGINEER_NAME' "$ENGINEER_NAME" "$CLAUDE_DIR/CLAUDE.md"
ok "CLAUDE.md"

# ─── settings.json — atomic merge (replace what we own, preserve what's theirs) ───
TITAN_PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.cargo/bin:$HOME/go/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Build --inject flags for runtime-detected state
_MERGE_INJECT=()
_MERGE_INJECT+=(--inject "NTFY_TOPIC=")
_MERGE_INJECT+=(--inject "NTFY_URL=https://ntfy.sh")

if ! $CCFLARE_SKIP && command -v better-ccflare &>/dev/null; then
  _MERGE_INJECT+=(--inject "ANTHROPIC_BASE_URL=http://127.0.0.1:${CCFLARE_PORT}")
fi

if ! $LETTA_SKIP && [[ -f "$HOME/.config/letta/credentials" ]]; then
  _LETTA_PASS=$(grep '^LETTA_SERVER_PASSWORD=' "$HOME/.config/letta/credentials" | cut -d= -f2-)
  _MERGE_INJECT+=(--inject "LETTA_BASE_URL=http://127.0.0.1:${LETTA_PORT}")
  _MERGE_INJECT+=(--inject "LETTA_API_KEY=${_LETTA_PASS}")
  _MERGE_INJECT+=(--inject "LETTA_MODEL=anthropic/claude-sonnet-4-6")
  _MERGE_INJECT+=(--inject "LETTA_MODE=full")
  _MERGE_INJECT+=(--inject "LETTA_SDK_TOOLS=read-only")
fi

if [[ -n "$SEMGREP_TOKEN" ]] && ! $SEMGREP_SKIP; then
  _MERGE_INJECT+=(--inject "SEMGREP_APP_TOKEN=${SEMGREP_TOKEN}")
fi

if [[ "$CC_NO_AUTOUPDATE" == "true" ]]; then
  _MERGE_INJECT+=(--inject "DISABLE_AUTOUPDATER=1")
fi

# Single atomic merge: template + live + runtime injections → settings.json
python3 "$REPO_FILES/script/merge-settings.py" \
  "$REPO_FILES/dot-claude/settings.json" \
  "$CLAUDE_DIR/settings.json" \
  "$CLAUDE_DIR/settings.json" \
  --engineer "$ENGINEER_NAME" \
  --path "$TITAN_PATH" \
  "${_MERGE_INJECT[@]}" \
  && ok "settings.json (atomic merge)" \
  || { warn "settings.json merge failed — falling back to template overwrite"
       install -Dm644 "$REPO_FILES/dot-claude/settings.json" "$CLAUDE_DIR/settings.json"
       sd 'TITAN_ENGINEER_NAME' "$ENGINEER_NAME" "$CLAUDE_DIR/settings.json"
       sd 'TITAN_PATH_PLACEHOLDER' "$TITAN_PATH" "$CLAUDE_DIR/settings.json"
       ok "settings.json (fallback — template overwrite)"; }

# Enable semgrep plugin if token provided (merge handles env var, this handles plugin)
if [[ -n "$SEMGREP_TOKEN" ]] && ! $SEMGREP_SKIP; then
  jq '.enabledPlugins["semgrep@claude-plugins-official"] = true' \
    "$CLAUDE_DIR/settings.json" > /tmp/_cc_settings.json \
    && mv /tmp/_cc_settings.json "$CLAUDE_DIR/settings.json" \
    && ok "settings.json (semgrep plugin enabled)" \
    || warn "semgrep plugin enablement failed"
fi

# RTK global hook — runs after settings.json is written so it appends, not overwrites
if command -v rtk &>/dev/null && rtk gain &>/dev/null 2>&1; then
  run_q rtk init -g --auto-patch && ok "rtk global hook (token compression active)" \
    || warn "rtk init -g failed — run manually: rtk init -g"
fi

# ─── cozempic — context bloat cleaner (global hooks) ───
# Injects hooks directly into ~/.claude/settings.json — NOT via `cozempic init`,
# which writes to cwd/.claude/settings.json (project-scoped = wrong for a global installer).
# Each hook is session/cwd-scoped at runtime: guard gets --session $SESSION_ID from hook
# input; checkpoint uses cwd which CC sets to the project dir when firing hooks.
# No project mixing — fully safe as global hooks.
# Must run AFTER settings.json is fully written (install -Dm644 above would erase hooks).
if ! $COZEMPIC_SKIP && command -v cozempic &>/dev/null; then
  python3 - "$CLAUDE_DIR/settings.json" <<'PYEOF'
import json, sys
f = sys.argv[1]
with open(f) as fh:
    cfg = json.load(fh)

GUARD = (
    'INPUT=$(cat); '
    'SESSION_ID=$(echo "$INPUT" | python3 -c '
    '"import sys,json; print(json.load(sys.stdin).get(\'session_id\',\'\'))" 2>/dev/null); '
    'CTX_WIN=$(echo "$INPUT" | python3 -c '
    '"import sys,json; d=json.load(sys.stdin); '
    'print(d.get(\'context_window\',{}).get(\'context_window_size\',\'\'))" 2>/dev/null); '
    'cozempic guard --daemon --system-overhead-tokens 35000 '
    '${SESSION_ID:+--session $SESSION_ID} '
    '${CTX_WIN:+--context-window $CTX_WIN} '
    '2>/dev/null || true'
)
CKPT = 'cozempic checkpoint 2>/dev/null || true'

hooks = cfg.setdefault('hooks', {})

def has_cmd(arr, kw):
    return any(any(kw in c.get('command','') for c in h.get('hooks',[])) for h in arr if isinstance(h,dict))

def add_hook(arr, matcher, cmd):
    arr.append({'matcher': matcher, 'hooks': [{'type': 'command', 'command': cmd}]})

ss = hooks.setdefault('SessionStart', [])
if not has_cmd(ss, 'cozempic guard'):
    add_hook(ss, '', GUARD)

for ev in ('PreCompact', 'Stop'):
    arr = hooks.setdefault(ev, [])
    if not has_cmd(arr, 'cozempic checkpoint'):
        add_hook(arr, '', CKPT)

ptu = hooks.setdefault('PostToolUse', [])
for m in ('Task', 'TaskCreate|TaskUpdate'):
    if not any(isinstance(h,dict) and h.get('matcher')==m and has_cmd([h],'cozempic checkpoint') for h in ptu):
        add_hook(ptu, m, CKPT)

with open(f, 'w') as fh:
    json.dump(cfg, fh, indent=2)
    fh.write('\n')
PYEOF
  [[ $? -eq 0 ]] \
    && ok "cozempic: hooks wired globally in ~/.claude/settings.json" \
    || warn "cozempic: hook injection failed — run manually from a project dir: cozempic init"

  # Install /cozempic slash command from cozempic's own venv (avoids cozempic init's cwd problem)
  _COZEMPIC_PY="$(dirname "$(command -v cozempic)")/python3"
  if [[ -x "$_COZEMPIC_PY" ]]; then
    _SLASH=$("$_COZEMPIC_PY" -c \
      "import importlib.resources as r; print(r.files('cozempic.data').joinpath('cozempic_slash_command.md'))" \
      2>/dev/null)
    [[ -n "$_SLASH" ]] && install -Dm644 "$_SLASH" "$CLAUDE_DIR/commands/cozempic.md" \
      && ok "cozempic: /cozempic slash command installed"
  fi
fi

# ─── ccstatusline config ───
install -Dm644 "$REPO_FILES/config/ccstatusline/settings.json" "$HOME/.config/ccstatusline/settings.json" \
  && ok "ccstatusline: config" || warn "ccstatusline config (missing from repo)"

# ─── Skills ───
# tool-discovery, security-ops, debug-protocol removed — replaced by better versions:
#   tool-discovery → cli-tools (150 lines, full tool reference)
#   security-ops   → security-scan (39 lines, structured workflows)
#   debug-protocol → systematic-debugging (from superpowers)

install -Dm644 "$REPO_FILES/dot-claude/skills/cli-tools/SKILL.md" "$CLAUDE_DIR/skills/cli-tools/SKILL.md"
ok "skill: cli-tools"

install -Dm644 "$REPO_FILES/dot-claude/skills/security-scan/SKILL.md" "$CLAUDE_DIR/skills/security-scan/SKILL.md"
ok "skill: security-scan"

install -Dm644 "$REPO_FILES/dot-claude/skills/git-workflow/SKILL.md" "$CLAUDE_DIR/skills/git-workflow/SKILL.md"
ok "skill: git-workflow"

install -Dm644 "$REPO_FILES/dot-claude/skills/infra-deploy/SKILL.md" "$CLAUDE_DIR/skills/infra-deploy/SKILL.md"
ok "skill: infra-deploy"

install -Dm644 "$REPO_FILES/dot-claude/skills/add-cli-tool/SKILL.md" "$CLAUDE_DIR/skills/add-cli-tool/SKILL.md"
ok "skill: add-cli-tool"

install -Dm644 "$REPO_FILES/dot-claude/skills/add-cli-tool/references/locations.md" "$CLAUDE_DIR/skills/add-cli-tool/references/locations.md"
ok "skill: add-cli-tool (references)"

# ─── Skill: tmux-control ───
install -Dm644 "$REPO_FILES/dot-claude/skills/tmux-control/SKILL.md" "$CLAUDE_DIR/skills/tmux-control/SKILL.md"
ok "skill: tmux-control"

# ─── Skill: workspace ───
install -Dm644 "$REPO_FILES/dot-claude/skills/workspace/SKILL.md" "$CLAUDE_DIR/skills/workspace/SKILL.md"
ok "skill: workspace"

# ─── Skill: pueue-orchestrator ───
install -Dm644 "$REPO_FILES/dot-claude/skills/pueue-orchestrator/SKILL.md" "$CLAUDE_DIR/skills/pueue-orchestrator/SKILL.md"
ok "skill: pueue-orchestrator"

# ─── Skill: diagrams ───
install -Dm644 "$REPO_FILES/dot-claude/skills/diagrams/SKILL.md" "$CLAUDE_DIR/skills/diagrams/SKILL.md"
ok "skill: diagrams"

# ─── Skill: deploy ───
install -Dm644 "$REPO_FILES/dot-claude/skills/deploy/SKILL.md" "$CLAUDE_DIR/skills/deploy/SKILL.md"
ok "skill: deploy"

# ─── Skill: process-supervisor ───
install -Dm644 "$REPO_FILES/dot-claude/skills/process-supervisor/SKILL.md" "$CLAUDE_DIR/skills/process-supervisor/SKILL.md"
ok "skill: process-supervisor"

# ─── Skill: docker-security ───
install -Dm644 "$REPO_FILES/dot-claude/skills/docker-security/SKILL.md" "$CLAUDE_DIR/skills/docker-security/SKILL.md"
ok "skill: docker-security"

# ─── Skill: vibesec ───
install -Dm644 "$REPO_FILES/dot-claude/skills/vibesec/SKILL.md" "$CLAUDE_DIR/skills/vibesec/SKILL.md"
ok "skill: vibesec"

# ─── Skill: trailofbits-modern-python ───
install -Dm644 "$REPO_FILES/dot-claude/skills/trailofbits-modern-python/SKILL.md" "$CLAUDE_DIR/skills/trailofbits-modern-python/SKILL.md"
ok "skill: trailofbits-modern-python"

# ─── Skill: notebooklm-skills ───
install -Dm644 "$REPO_FILES/dot-claude/skills/notebooklm-skills/SKILL.md" "$CLAUDE_DIR/skills/notebooklm-skills/SKILL.md"
ok "skill: notebooklm-skills"

# ─── Hook Scripts (Memory/Context Management) ───

install -Dm755 "$REPO_FILES/dot-claude/hooks/pre-compact.sh" "$CLAUDE_DIR/hooks/pre-compact.sh"
ok "hook: pre-compact.sh"

install -Dm755 "$REPO_FILES/dot-claude/hooks/session-end.sh" "$CLAUDE_DIR/hooks/session-end.sh"
ok "hook: session-end.sh"

install -Dm755 "$REPO_FILES/dot-claude/hooks/session-start.sh" "$CLAUDE_DIR/hooks/session-start.sh"
ok "hook: session-start.sh"

# ─── CC Thinking Patcher (auto-patches after CC updates) ───
install -Dm755 "$REPO_FILES/dot-claude/bin/cc-patch-thinking" "$HOME/.local/bin/cc-patch-thinking"
ok "bin: cc-patch-thinking"

# UserPromptSubmit: inject memory only when recall-intent keywords detected (zero tokens otherwise)
install -Dm755 "$REPO_FILES/dot-claude/hooks/prompt-memory-inject.sh" "$CLAUDE_DIR/hooks/prompt-memory-inject.sh"
ok "hook: prompt-memory-inject.sh"

# ─── Status Line Script ───
install -Dm755 "$REPO_FILES/dot-claude/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
# If ccstatusline is installed, use it directly; else fall back to statusline-command.sh
if command -v ccstatusline &>/dev/null; then
  jq '.statusLine = {"type": "command", "command": "ccstatusline", "padding": 0}' \
    "$CLAUDE_DIR/settings.json" > /tmp/_cc_settings.json \
    && mv /tmp/_cc_settings.json "$CLAUDE_DIR/settings.json"
  ok "statusline: ccstatusline (native)"
else
  ok "statusline: statusline-command.sh (fallback)"
fi

# ─── .claudeignore Template ───

install -Dm644 "$REPO_FILES/dot-claude/claudeignore-template" "$CLAUDE_DIR/claudeignore-template"
ok "template: claudeignore-template"

# ─── Conditional Rules ───

install -Dm644 "$REPO_FILES/dot-claude/rules/python.md" "$CLAUDE_DIR/rules/python.md"
ok "rule: python.md"

install -Dm644 "$REPO_FILES/dot-claude/rules/shell.md" "$CLAUDE_DIR/rules/shell.md"
ok "rule: shell.md"

install -Dm644 "$REPO_FILES/dot-claude/rules/terraform.md" "$CLAUDE_DIR/rules/terraform.md"
ok "rule: terraform.md"

install -Dm644 "$REPO_FILES/dot-claude/rules/docker.md" "$CLAUDE_DIR/rules/docker.md"
ok "rule: docker.md"

install -Dm644 "$REPO_FILES/dot-claude/rules/security.md" "$CLAUDE_DIR/rules/security.md"
ok "rule: security.md"

install -Dm644 "$REPO_FILES/dot-claude/rules/memory.md" "$CLAUDE_DIR/rules/memory.md"
ok "rule: memory.md"

install -Dm644 "$REPO_FILES/dot-claude/rules/skill-authoring.md" "$CLAUDE_DIR/rules/skill-authoring.md"
ok "rule: skill-authoring.md"

# ─── /recall command ───
install -Dm644 "$REPO_FILES/dot-claude/commands/recall.md" "$CLAUDE_DIR/commands/recall.md"
ok "command: /recall"

# ─── /remember command ───
install -Dm644 "$REPO_FILES/dot-claude/commands/remember.md" "$CLAUDE_DIR/commands/remember.md"
ok "command: /remember"

# obra/superpowers (multiple useful skills)
if [ ! -d "$CLAUDE_DIR/skills/tdd" ]; then
  git clone --depth 1 https://github.com/obra/superpowers.git /tmp/superpowers 2>/dev/null || true
  if [ -d /tmp/superpowers/skills ]; then
    cp -r /tmp/superpowers/skills/test-driven-development "$CLAUDE_DIR/skills/tdd" 2>/dev/null || true
    cp -r /tmp/superpowers/skills/systematic-debugging "$CLAUDE_DIR/skills/systematic-debugging" 2>/dev/null || true
    cp -r /tmp/superpowers/skills/brainstorming "$CLAUDE_DIR/skills/brainstorming" 2>/dev/null || true
    cp -r /tmp/superpowers/skills/verification-before-completion "$CLAUDE_DIR/skills/verification-before-completion" 2>/dev/null || true
    cp -r /tmp/superpowers/skills/writing-plans "$CLAUDE_DIR/skills/writing-plans" 2>/dev/null || true
    # Add paths scoping to large skills so they don't load on every session (bug #14882)
    if [ -f "$CLAUDE_DIR/skills/tdd/SKILL.md" ] && ! grep -q '^paths:' "$CLAUDE_DIR/skills/tdd/SKILL.md" 2>/dev/null; then
      sed -i '3a paths: "**/*.py,**/*.js,**/*.ts,**/*.jsx,**/*.tsx,**/*.go,**/*.rs,**/*.java,**/*.cpp,**/*.c,**/*.rb,**/test*,**/spec*,**/*_test*,**/*_spec*,**/pytest.ini,**/jest.config*,**/go.mod"' "$CLAUDE_DIR/skills/tdd/SKILL.md"
    fi
    if [ -f "$CLAUDE_DIR/skills/systematic-debugging/SKILL.md" ] && ! grep -q '^paths:' "$CLAUDE_DIR/skills/systematic-debugging/SKILL.md" 2>/dev/null; then
      sed -i '3a paths: "**/*.py,**/*.js,**/*.ts,**/*.go,**/*.rs,**/*.java,**/*.sh,**/*.bash,**/*.cpp,**/*.c,**/*.rb,**/Makefile,**/CMakeLists.txt"' "$CLAUDE_DIR/skills/systematic-debugging/SKILL.md"
    fi
    if [ -f "$CLAUDE_DIR/skills/brainstorming/SKILL.md" ] && ! grep -q '^paths:' "$CLAUDE_DIR/skills/brainstorming/SKILL.md" 2>/dev/null; then
      sed -i '3a paths: "**/_scratchpad*,**/_plan*,**/spec*,**/*.spec.md,**/brainstorm*"' "$CLAUDE_DIR/skills/brainstorming/SKILL.md"
    fi
    if [ -f "$CLAUDE_DIR/skills/verification-before-completion/SKILL.md" ] && ! grep -q '^paths:' "$CLAUDE_DIR/skills/verification-before-completion/SKILL.md" 2>/dev/null; then
      sed -i '3a paths: "**/*.py,**/*.js,**/*.ts,**/*.go,**/*.sh,**/*.rs,**/test*,**/spec*,**/Makefile"' "$CLAUDE_DIR/skills/verification-before-completion/SKILL.md"
    fi
    if [ -f "$CLAUDE_DIR/skills/writing-plans/SKILL.md" ] && ! grep -q '^paths:' "$CLAUDE_DIR/skills/writing-plans/SKILL.md" 2>/dev/null; then
      sed -i '3a paths: "**/_scratchpad*,**/_plan*,**/spec*,**/plan*,**/*.spec.md"' "$CLAUDE_DIR/skills/writing-plans/SKILL.md"
    fi
    ok "superpowers skills"
  else
    warn "superpowers clone failed"
  fi
  rm -rf /tmp/superpowers
else
  ok "superpowers skills (exist)"
fi

# Security skills
if [ ! -d "$CLAUDE_DIR/skills/vibesec" ]; then
  git clone --depth 1 https://github.com/BehiSecc/VibeSec-Skill.git "$CLAUDE_DIR/skills/vibesec" 2>/dev/null && ok "vibesec" || warn "vibesec"
else ok "vibesec (exists)"; fi
# Add paths scoping to vibesec (758 lines — only load for web/security files)
if [ -f "$CLAUDE_DIR/skills/vibesec/SKILL.md" ] && ! grep -q '^paths:' "$CLAUDE_DIR/skills/vibesec/SKILL.md" 2>/dev/null; then
  sed -i '3a paths: "**/*.html,**/*.htm,**/*.js,**/*.ts,**/*.jsx,**/*.tsx,**/*.vue,**/*.svelte,**/*.py,**/routes*,**/auth*,**/views*,**/controllers*,**/api*,**/nginx*,**/Dockerfile*,**/docker-compose*"' "$CLAUDE_DIR/skills/vibesec/SKILL.md"
fi

# Trail of Bits — selective install (modern-python only, not the full 60-skill repo)
# Full clone was 71K lines / 60 SKILL.md files — most never triggered (blockchain, fuzzing, etc.)
# Individual plugins can be installed on-demand via: claude plugin marketplace add trailofbits/skills
if [ ! -d "$CLAUDE_DIR/skills/trailofbits-modern-python" ]; then
  git clone --depth 1 https://github.com/trailofbits/skills.git /tmp/trailofbits-skills 2>/dev/null
  if [ -d /tmp/trailofbits-skills/plugins/modern-python ]; then
    cp -r /tmp/trailofbits-skills/plugins/modern-python "$CLAUDE_DIR/skills/trailofbits-modern-python" 2>/dev/null && ok "trailofbits: modern-python" || warn "trailofbits: modern-python"
  else
    warn "trailofbits: modern-python not found in repo"
  fi
  rm -rf /tmp/trailofbits-skills
else ok "trailofbits: modern-python (exists)"; fi
# Fix SKILL.md path: plugin structure nests SKILL.md under skills/modern-python/, Claude expects root
# Also add paths scoping so it only loads for Python files
if [ -f "$CLAUDE_DIR/skills/trailofbits-modern-python/skills/modern-python/SKILL.md" ] \
   && [ ! -f "$CLAUDE_DIR/skills/trailofbits-modern-python/SKILL.md" ]; then
  sed '3a paths: "**/*.py,**/pyproject.toml,**/setup.py,**/setup.cfg,**/requirements*.txt,**/.python-version,**/uv.lock,**/Pipfile*"' \
    "$CLAUDE_DIR/skills/trailofbits-modern-python/skills/modern-python/SKILL.md" \
    > "$CLAUDE_DIR/skills/trailofbits-modern-python/SKILL.md"
  ok "trailofbits: SKILL.md fixed at root with paths scoping"
elif [ -f "$CLAUDE_DIR/skills/trailofbits-modern-python/SKILL.md" ] && ! grep -q '^paths:' "$CLAUDE_DIR/skills/trailofbits-modern-python/SKILL.md" 2>/dev/null; then
  sed -i '3a paths: "**/*.py,**/pyproject.toml,**/setup.py,**/setup.cfg,**/requirements*.txt,**/.python-version,**/uv.lock,**/Pipfile*"' \
    "$CLAUDE_DIR/skills/trailofbits-modern-python/SKILL.md"
fi
# Remove duplicate nested SKILL.md — root copy has correct paths: scoping; nested is always-on (bug)
rm -f "$CLAUDE_DIR/skills/trailofbits-modern-python/skills/modern-python/SKILL.md" 2>/dev/null || true

# Cleanup: remove full trailofbits/hashicorp clones from previous installs (token bloat)
# These dumped 60+14 SKILL.md files into context at startup (~81K lines)
if [ -d "$CLAUDE_DIR/skills/trailofbits" ]; then
  rm -rf "$CLAUDE_DIR/skills/trailofbits"
  ok "removed old trailofbits full clone (60 skills → 1 selective)"
fi
if [ -d "$CLAUDE_DIR/skills/hashicorp" ]; then
  rm -rf "$CLAUDE_DIR/skills/hashicorp"
  ok "removed old hashicorp full clone (14 skills → covered by infra-deploy)"
fi


# ─── Commands ───
install -Dm644 "$REPO_FILES/dot-claude/commands/catchup.md" "$CLAUDE_DIR/commands/catchup.md"
ok "command: /catchup"

install -Dm644 "$REPO_FILES/dot-claude/commands/handoff.md" "$CLAUDE_DIR/commands/handoff.md"
ok "command: /handoff"

install -Dm644 "$REPO_FILES/dot-claude/commands/ship.md" "$CLAUDE_DIR/commands/ship.md"
ok "command: /ship"

install -Dm644 "$REPO_FILES/dot-claude/commands/standup.md" "$CLAUDE_DIR/commands/standup.md"
ok "command: /standup"

install -Dm644 "$REPO_FILES/dot-claude/commands/scan.md" "$CLAUDE_DIR/commands/scan.md"
ok "command: /scan"

install -Dm644 "$REPO_FILES/dot-claude/commands/review.md" "$CLAUDE_DIR/commands/review.md"
ok "command: /review"

install -Dm644 "$REPO_FILES/dot-claude/commands/tools.md" "$CLAUDE_DIR/commands/tools.md"
ok "command: /tools"

install -Dm644 "$REPO_FILES/dot-claude/commands/workspace-init.md" "$CLAUDE_DIR/commands/workspace-init.md"
ok "command: /workspace-init"

install -Dm644 "$REPO_FILES/dot-claude/commands/pack.md" "$CLAUDE_DIR/commands/pack.md"
ok "command: /pack"

# ─── GitHub Actions Template ───
install -Dm644 "$REPO_FILES/dot-claude/templates/claude-code-action.yml" "$CLAUDE_DIR/templates/claude-code-action.yml"
ok "template: claude-code-action.yml"

install -Dm644 "$REPO_FILES/dot-claude/commands/gh-action.md" "$CLAUDE_DIR/commands/gh-action.md"
ok "command: /gh-action"

# ─── Agents ───
install -Dm644 "$REPO_FILES/dot-claude/agents/researcher.md" "$CLAUDE_DIR/agents/researcher.md"
ok "agent: researcher"

install -Dm644 "$REPO_FILES/dot-claude/agents/planner.md" "$CLAUDE_DIR/agents/planner.md"
ok "agent: planner"

install -Dm644 "$REPO_FILES/dot-claude/agents/reviewer.md" "$CLAUDE_DIR/agents/reviewer.md"
ok "agent: reviewer"

# ─── On-Demand Agent Slots (slot-1..10) ───
for _slot_i in 1 2 3 4 5 6 7 8 9 10; do
  case $_slot_i in 1|2|3|6|7|8) _slot_model="haiku" ;; 4|9) _slot_model="sonnet" ;; 5|10) _slot_model="opus" ;; esac
  _slot_i="$_slot_i" _slot_model="$_slot_model" \
    envsubst '$_slot_i $_slot_model' \
    < "$REPO_FILES/dot-claude/agents/slot-template.md" \
    > "$CLAUDE_DIR/agents/slot-${_slot_i}.md"
  ok "agent: slot-${_slot_i} [${_slot_model}]"
done
unset _slot_i _slot_model

# ─── agt config ───
install -Dm644 "$REPO_FILES/config/agt/config" "$HOME/.config/agt/config"
ok "agt: config"

# ─── agt CLI ───
install -Dm755 "$REPO_FILES/bin/agt" "$HOME/.local/bin/agt"
ok "agt: CLI installed"

# ─── Agent stash: clone or update from GitHub ───
AGT_STASH_REPO="https://github.com/SutanuNandigrami/agent-stash.git"
AGT_STASH_DIR="$CLAUDE_DIR/agent-stash"
if [[ -d "$AGT_STASH_DIR/.git" ]]; then
  git -C "$AGT_STASH_DIR" pull --ff-only 2>/dev/null && ok "agent-stash: updated from GitHub" || warn "agent-stash: pull failed (using existing)"
else
  rm -rf "$AGT_STASH_DIR"
  git clone --depth 1 "$AGT_STASH_REPO" "$AGT_STASH_DIR" 2>/dev/null && ok "agent-stash: cloned from GitHub" || warn "agent-stash: clone failed"
fi
mkdir -p "$AGT_STASH_DIR/_loaded"
touch "$AGT_STASH_DIR/_loaded/.lock" "$AGT_STASH_DIR/_loaded/.manifest"
"$HOME/.local/bin/agt" build-index 2>/dev/null && ok "agent-stash: index built" || warn "agent-stash: index build failed"

# ─── Cron: weekly agent stash refresh ───
(crontab -l 2>/dev/null | grep -v 'agt build-index\|agt-refresh' || true; \
  echo "0 3 * * 0 cd \$HOME/.claude/agent-stash && git pull --ff-only 2>/dev/null && \$HOME/.local/bin/agt build-index >> \$HOME/.claude/logs/agt-refresh.log 2>&1") | crontab -
ok "cron: weekly agent-stash refresh (Sun 03:00)"

# CLIProxyAPI — proxy server for AI coding tools (clone, not a CLI install)
if [ ! -d ~/tools/CLIProxyAPI ]; then
  mkdir -p ~/tools
  git clone --depth 1 https://github.com/router-for-me/CLIProxyAPI.git ~/tools/CLIProxyAPI 2>/dev/null && ok "CLIProxyAPI (cloned to ~/tools/)" || warn "CLIProxyAPI"
else ok "CLIProxyAPI (exists)"; fi

