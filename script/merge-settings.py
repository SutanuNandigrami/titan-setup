#!/usr/bin/env python3
"""Atomic merge of titan template settings.json with live Claude Code settings.

Strategy: "Replace what we own, merge what we share, preserve what's theirs"

- Titan-managed keys: template always wins (overwrite)
- Runtime-injected keys: set by caller via --inject flags (overwrite)
- User-owned keys: live always wins (preserve)
- enabledPlugins: union (our plugins always present, user plugins preserved)

Usage:
  python3 merge-settings.py TEMPLATE LIVE OUTPUT [--inject KEY=VALUE ...]
  python3 merge-settings.py TEMPLATE LIVE OUTPUT --dry-run

Arguments:
  TEMPLATE  Path to repo template (dot-claude/settings.json)
  LIVE      Path to live settings (~/.claude/settings.json), may not exist
  OUTPUT    Path to write merged result (use temp file + mv for atomicity)

Options:
  --inject KEY=VALUE   Set a runtime-injected env var (repeatable)
  --dry-run            Show what would change without writing
  --engineer NAME      Substitute TITAN_ENGINEER_NAME placeholder
  --path VALUE         Substitute TITAN_PATH_PLACEHOLDER
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from copy import deepcopy
from pathlib import Path

# ── Titan-managed keys ──────────────────────────────────────────────────────
# These are owned by titan. Template value always wins on re-run.
# Organized by category for maintainability.

TITAN_MANAGED_ENV_KEYS: set[str] = {
    # Core CC behavior
    "ENGINEER_NAME",
    "DEFAULT_BRANCH",
    "ENABLE_TOOL_SEARCH",
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE",
    "CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR",
    "CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY",
    "BASH_DEFAULT_TIMEOUT_MS",
    "BASH_MAX_TIMEOUT_MS",
    "CLAUDE_CODE_SUBAGENT_MODEL",
    "CLAUDE_CODE_ENABLE_TASKS",
    "CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS",
    # Computed at install time
    "PATH",
}

# Runtime-injected env keys — set by --inject flags, NOT from template.
# Listed here so they aren't treated as user-owned (they get overwritten).
RUNTIME_INJECTED_ENV_KEYS: set[str] = {
    "ANTHROPIC_BASE_URL",
    "LETTA_BASE_URL",
    "LETTA_API_KEY",
    "LETTA_MODEL",
    "LETTA_MODE",
    "LETTA_SDK_TOOLS",
    "DISABLE_AUTOUPDATER",
    "NTFY_TOPIC",
    "NTFY_URL",
}

# Titan-managed top-level scalar keys (template always wins)
TITAN_MANAGED_TOPLEVEL: set[str] = {
    "respectGitignore",
    "includeCoAuthoredBy",
    "effortLevel",
    "showTurnDuration",
    "skipDangerousModePermissionPrompt",
    "preferences",
}

# model is special: set from template on fresh install only.
# If the user changes it via /model, their choice persists across re-runs.
# To restore opusplan: edit ~/.claude/settings.json manually or delete model key.

# Titan-managed top-level block keys (template always wins, full replace)
TITAN_MANAGED_BLOCKS: set[str] = {
    "permissions",
    "hooks",
    "statusLine",
}

# Template plugins (always present in merged output)
TITAN_MANAGED_PLUGINS: set[str] = {
    "code-review@claude-plugins-official",
    "skill-creator@claude-plugins-official",
    "episodic-memory@superpowers-marketplace",
    "playwright@claude-plugins-official",
}


def load_json(path: Path) -> dict:
    """Load JSON file, return empty dict if missing or malformed."""
    if not path.exists():
        return {}
    try:
        with open(path) as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        # Backup malformed file
        backup = path.with_suffix(f".json.bak.{os.getpid()}")
        shutil.copy2(path, backup)
        print(f"WARNING: Malformed {path} — backed up to {backup}", file=sys.stderr)
        return {}


def merge_settings(
    template: dict,
    live: dict,
    injections: dict[str, str],
    engineer_name: str | None = None,
    path_value: str | None = None,
) -> dict:
    """Merge template + live + injections into final settings."""
    result = deepcopy(template)

    # ── 1. env block: titan-managed from template, runtime from injections, rest from live ──
    tmpl_env = result.get("env", {})
    live_env = live.get("env", {})

    # Start with template env (titan-managed keys)
    merged_env: dict[str, str] = {}

    # Titan-managed: from template
    for k in TITAN_MANAGED_ENV_KEYS:
        if k in tmpl_env:
            merged_env[k] = tmpl_env[k]

    # User-owned: from live (anything not titan-managed and not runtime-injected)
    for k, v in live_env.items():
        if k not in TITAN_MANAGED_ENV_KEYS and k not in RUNTIME_INJECTED_ENV_KEYS:
            merged_env[k] = v

    # Runtime-injected: from --inject flags (overwrites both template and live)
    for k, v in injections.items():
        merged_env[k] = v

    # Placeholder substitution
    if engineer_name and "ENGINEER_NAME" in merged_env:
        merged_env["ENGINEER_NAME"] = engineer_name
    if path_value and "PATH" in merged_env:
        merged_env["PATH"] = path_value

    result["env"] = merged_env

    # ── 2. Top-level scalars: titan-managed from template ──
    for k in TITAN_MANAGED_TOPLEVEL:
        if k in template:
            result[k] = deepcopy(template[k])

    # model: set from template on fresh install, preserve user's choice on re-run
    if "model" in live:
        result["model"] = live["model"]
    elif "model" in template:
        result["model"] = template["model"]

    # User-owned top-level keys: preserve from live
    for k, v in live.items():
        if (
            k not in TITAN_MANAGED_TOPLEVEL
            and k not in TITAN_MANAGED_BLOCKS
            and k not in ("env", "enabledPlugins", "model")
            and k not in result
        ):
            result[k] = deepcopy(v)

    # Special: extraKnownMarketplaces is always user-owned
    if "extraKnownMarketplaces" in live:
        result["extraKnownMarketplaces"] = deepcopy(live["extraKnownMarketplaces"])

    # ── 3. Block keys: full replace from template ──
    for k in TITAN_MANAGED_BLOCKS:
        if k in template:
            result[k] = deepcopy(template[k])

    # ── 4. enabledPlugins: union merge ──
    tmpl_plugins = template.get("enabledPlugins", {})
    live_plugins = live.get("enabledPlugins", {})
    merged_plugins = {}
    # User plugins first
    for k, v in live_plugins.items():
        merged_plugins[k] = v
    # Titan plugins always present (overwrite if conflict)
    for k, v in tmpl_plugins.items():
        merged_plugins[k] = v
    result["enabledPlugins"] = merged_plugins

    return result


def diff_settings(old: dict, new: dict, prefix: str = "") -> list[str]:
    """Generate human-readable diff between two settings dicts."""
    changes: list[str] = []
    all_keys = sorted(set(list(old.keys()) + list(new.keys())))
    for k in all_keys:
        path = f"{prefix}.{k}" if prefix else k
        if k not in old:
            changes.append(f"  + {path}: {json.dumps(new[k])[:80]}")
        elif k not in new:
            changes.append(f"  - {path}: {json.dumps(old[k])[:80]}")
        elif old[k] != new[k]:
            if isinstance(old[k], dict) and isinstance(new[k], dict):
                changes.extend(diff_settings(old[k], new[k], path))
            else:
                changes.append(f"  ~ {path}: {json.dumps(old[k])[:40]} -> {json.dumps(new[k])[:40]}")
    return changes


def main() -> None:
    parser = argparse.ArgumentParser(description="Atomic merge of titan settings.json")
    parser.add_argument("template", type=Path, help="Repo template settings.json")
    parser.add_argument("live", type=Path, help="Live ~/.claude/settings.json")
    parser.add_argument("output", type=Path, help="Output path for merged settings")
    parser.add_argument("--inject", action="append", default=[], metavar="KEY=VALUE",
                        help="Runtime-injected env var (repeatable)")
    parser.add_argument("--dry-run", action="store_true", help="Show diff without writing")
    parser.add_argument("--engineer", default=None, help="Engineer name substitution")
    parser.add_argument("--path", default=None, help="PATH value substitution")
    args = parser.parse_args()

    # Parse injections
    injections: dict[str, str] = {}
    for item in args.inject:
        if "=" not in item:
            print(f"ERROR: --inject must be KEY=VALUE, got: {item}", file=sys.stderr)
            sys.exit(1)
        k, v = item.split("=", 1)
        injections[k] = v

    template = load_json(args.template)
    if not template:
        print(f"ERROR: Template {args.template} is empty or missing", file=sys.stderr)
        sys.exit(1)

    live = load_json(args.live)
    is_fresh = not live

    merged = merge_settings(template, live, injections, args.engineer, args.path)

    if args.dry_run:
        if is_fresh:
            print("Fresh install — no existing settings.json")
            print(f"Would write {len(json.dumps(merged))} bytes")
        else:
            changes = diff_settings(live, merged)
            if changes:
                print(f"Changes ({len(changes)} keys):")
                for c in changes:
                    print(c)
            else:
                print("No changes")
        return

    # Write atomically
    args.output.parent.mkdir(parents=True, exist_ok=True)
    content = json.dumps(merged, indent=2) + "\n"
    tmp = args.output.with_suffix(".json.tmp")
    try:
        tmp.write_text(content)
        # Preserve permissions if output exists
        if args.output.exists():
            st = args.output.stat()
            os.chmod(tmp, st.st_mode)
        tmp.rename(args.output)
    except Exception:
        tmp.unlink(missing_ok=True)
        raise

    if is_fresh:
        print(f"Fresh install: wrote {args.output}")
    else:
        changes = diff_settings(live, merged)
        print(f"Merged: {len(changes)} changes → {args.output}")


if __name__ == "__main__":
    main()
