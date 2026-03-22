# vexp-cli Integration — Codemap & Design Spec
**Date**: 2026-03-23
**Status**: Implemented (ADR-031)
**PR**: #54
**Version**: v3.21

---

## Overview

vexp-cli is a local-first context engine for AI coding agents. It uses tree-sitter AST parsing, dependency graphs, and skeleton context to provide token-efficient code understanding (~65% reduction). Titan integrates it as a globally-available MCP server that Claude Code spawns on demand via stdio transport.

---

## Decisions

| Concern | Decision | Rationale |
|---|---|---|
| Package manager | `bun install -g` | npm blocked by PreToolUse hook; bun handles optional deps natively |
| Platform binary | Optional deps (`@vexp/core-linux-x64`, `@vexp/core-linux-arm64`) | No postinstall needed; bun resolves platform package automatically |
| MCP transport | stdio (`vexp mcp`) | No daemon, no port, no systemd — CC manages lifecycle |
| MCP config location | `settings.json` via jq post-merge | Runtime path (`$HOME`) can't be a template placeholder |
| mcpServers ownership | NOT in TITAN_MANAGED_BLOCKS | User-added MCP servers preserved across re-runs |
| Skip mechanism | `--no-vexp` flag + `--minimal` | Follows `--no-cozempic` / `COZEMPIC_SKIP` pattern |
| Default | Always installed | Free tier (2000 nodes, 8 calls/day) is useful out-of-box |

---

## Architecture

```
vexp-cli (npm package)
├── bin/vexp.js                 ← Node.js entry point (thin bootstrap)
├── dist/cli.js                 ← CLI commands (index, daemon, mcp, setup, etc.)
├── dist/binary.js              ← Platform binary resolver
└── dist/agent-config.js        ← Agent config auto-generation

@vexp/core-linux-x64 (optional dep, auto-installed by bun)
└── bin/vexp-core               ← Rust native daemon (tree-sitter, SQLite, petgraph)
```

### Runtime flow

```
Claude Code session starts
  └── settings.json has mcpServers.vexp
        └── CC spawns: vexp mcp (stdin/stdout)
              └── vexp-core Rust daemon starts in-process
                    ├── tree-sitter parses codebase → AST
                    ├── builds dependency graph (petgraph)
                    ├── stores in .vexp/index.db (SQLite, per-project)
                    └── serves 11 MCP tools via stdio

Claude Code session ends
  └── CC kills vexp mcp process (automatic)
```

### MCP tool invocation

```
CC agent needs code context
  └── calls run_pipeline(task="fix auth bug", preset="auto")
        └── vexp auto-detects intent → "debug" preset
              ├── FTS5 keyword search + TF-IDF similarity
              ├── graph traversal from pivot nodes (depth=2)
              ├── skeleton reduction (signatures only for non-pivot)
              └── returns context capsule (bounded to max_tokens)
```

---

## Files Modified (titan-setup)

| File | Lines added | What |
|---|---|---|
| `lib/02-cli.sh` | +7 | `VEXP_SKIP=false`, `--no-vexp` flag, `--minimal` integration |
| `lib/07-tools-python-js.sh` | +16 | Install block: bun install + vexp-core binary verification |
| `lib/11-deploy-config.sh` | +10 | MCP server injection: `jq '.mcpServers.vexp = ...'` |
| `docs/decisions.md` | +7 | ADR-031 |
| `test/session-review.bats` | +52 | 12 VEXP regression tests + ADR-031 assertion |
| `test/structure.bats` | +12 | 2 structure assertions |
| `CHANGELOG.md` | +22 | v3.21 entry |
| `lib/00-header.sh` | +1 | Version bump v3.20 → v3.21 |

---

## Install Flow (lib/07-tools-python-js.sh)

```
Phase 3/6 — 150+ CLI Tools
  └── JS tools (bun):
        ├── BUN_TOOLS array (trash-cli, tldr, prettier, repomix)
        ├── gemini-cli, mermaid-cli (scoped packages)
        ├── vexp-cli ← NEW
        │     ├── if VEXP_SKIP || MINIMAL → skip
        │     ├── if already installed (bun pm ls -g) → skip
        │     ├── bun install -g vexp-cli → installs CLI + @vexp/core-linux-x64
        │     └── verify: command -v vexp && vexp version
        │           ├── pass → ok "vexp-core binary (version)"
        │           └── fail → warn with manual install hint
        └── playwright, n8n (docker)...
```

### Idempotency

- `bun pm ls -g | grep vexp-cli` — skip if already installed
- `command -v vexp && vexp version` — verify binary works
- `--force-updates` does NOT reinstall vexp (follows BUN_TOOLS pattern)
- Re-runs: MCP config re-injected via jq (additive, overwrites `.mcpServers.vexp` only)

---

## MCP Config Injection (lib/11-deploy-config.sh)

```
Phase 5/6 — Deploy Config
  └── After settings.json atomic merge
        └── After cozempic hooks injection
              └── After claude-lens statusline
                    └── vexp MCP injection ← NEW
                          ├── if VEXP_SKIP || MINIMAL → skip
                          ├── if vexp not on PATH → skip
                          └── jq '.mcpServers.vexp = {"command":"vexp","args":["mcp"]}'
                                ├── writes to ${WORKDIR}/_cc_settings.json (temp)
                                ├── mv → $CLAUDE_DIR/settings.json (atomic)
                                └── ok/warn guard (set -e safe)
```

### Resulting settings.json entry

```json
{
  "mcpServers": {
    "vexp": {
      "command": "vexp",
      "args": ["mcp"]
    }
  }
}
```

---

## MCP Tools Available (11 total)

| Tool | Tier | Purpose |
|---|---|---|
| `run_pipeline` | Free | Single-call: context search + impact + memory (auto-detects intent) |
| `get_context_capsule` | Free | Pivot files + skeleton supporting files |
| `get_impact_graph` | Free | Callers, importers, dependents of a symbol |
| `search_logic_flow` | Free | Execution paths between two symbols |
| `get_skeleton` | Pro | Token-reduced file signatures |
| `index_status` | Free | Index statistics |
| `workspace_setup` | Free | Onboarding tool |
| `submit_lsp_edges` | Pro | Type-resolved call edges |
| `get_session_context` | Free | Observations from current/previous sessions |
| `search_memory` | Pro | Cross-session hybrid search |
| `save_observation` | Free | Persist insights (type: insight/decision/error/manual) |

### Presets for run_pipeline

| Preset | Trigger keywords | Behavior |
|---|---|---|
| `auto` | (default) | Auto-detect from task description |
| `explore` | "understand", "how does" | Broad context, high skeleton detail |
| `debug` | "fix", "bug", "error" | Follow error paths, include tests |
| `modify` | "add", "implement", "change" | Focus on modification targets |
| `refactor` | "refactor", "clean up" | Blast radius analysis |

---

## Per-Project State

vexp creates a `.vexp/` directory in each project root on first use:

```
project-root/
└── .vexp/
    ├── index.db          ← SQLite: AST nodes, edges, FTS5 index (gitignored)
    ├── manifest.json     ← blake3 hashes per file (git-tracked, incremental rebuild)
    ├── workspace.json    ← multi-repo config (optional)
    ├── daemon.sock       ← IPC socket (runtime only)
    ├── daemon.pid        ← process ID (runtime only)
    ├── mcp.port          ← active port file (HTTP mode only)
    └── .gitignore        ← auto-generated, excludes index.db + runtime files
```

### Exclusion

- `.vexp_ignore` file (gitignore syntax) excludes paths from indexing
- Auto-excludes: `.env*`, `*secret*`, `*credential*`, API key patterns

---

## Supported Languages (30)

TypeScript, JavaScript, TSX/JSX, Python, Go, Rust, Java, C#, C, C++, Ruby,
Bash, Kotlin, Scala, Swift, Dart, PHP, Elixir, Haskell, OCaml, Lua, R, Zig,
HCL/Terraform, Objective-C, Dockerfile, Clojure, F#

---

## Configuration Reference

| Setting | Default | Purpose |
|---|---|---|
| `vexp.enabled` | `true` | Enable/disable entirely |
| `vexp.maxContextTokens` | `8000` | Max tokens per context capsule |
| `vexp.skeletonDetail` | `"standard"` | `minimal` (~5%), `standard` (~15%), `detailed` (~30%) |
| `vexp.autoCommitIndex` | `true` | Auto-include manifest.json in git commits |
| `vexp.gitHooksInstall` | `true` | Install git merge driver for manifest conflicts |
| `vexp.mcpPort` | `7821` | HTTP port (unused in stdio mode) |
| `vexp.logLevel` | `"warn"` | `error`, `warn`, `info`, `debug` |
| `vexp.telemetry.enabled` | `false` | Usage metrics only, no code content |
| `vexp.multiRepo.enabled` | `true` | Multi-repo workspace support |

---

## Plans & Limits

| Plan | Nodes | Repos | Tools | Rate | Cost |
|---|---|---|---|---|---|
| Starter (Free) | 2,000 | 1 | 7 (4 core + 3 memory) | 8 calls/day | $0 |
| Pro | 50,000 | 3 | All 11 | Unlimited | $19/mo |
| Team | Unlimited | Unlimited | All 11 | Unlimited | $29/user/mo |
| Enterprise | Unlimited | Unlimited | All 11 | Unlimited | Custom |

License auto-refreshes every 7 days. Offline grace: 7 days before fallback to Starter.

---

## Regression Tests (test/session-review.bats)

| Test | What it guards |
|---|---|
| `VEXP: VEXP_SKIP variable defined` | Flag exists in lib/02-cli.sh |
| `VEXP: --no-vexp flag in CLI parser` | CLI parsing works |
| `VEXP: --minimal sets VEXP_SKIP=true` | Minimal mode skips vexp |
| `VEXP: vexp-cli install block in lib/07` | Install command present |
| `VEXP: install block guarded` | VEXP_SKIP + MINIMAL guards |
| `VEXP: install uses ok/warn guard` | set -e safety |
| `VEXP: vexp-core binary verification` | Binary check exists |
| `VEXP: MCP config uses jq` | No direct file write |
| `VEXP: MCP uses vexp mcp command` | stdio transport, not HTTP |
| `VEXP: MCP uses WORKDIR temp file` | No /tmp collision |
| `VEXP: MCP injection guarded` | set -e safety |
| `ADR: decisions.md has ADR-031` | ADR documented |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `vexp: command not found` | bun global bin not on PATH | `export PATH="$HOME/.bun/bin:$PATH"` |
| `vexp-core binary missing` | Platform package not installed | `bun install -g @vexp/core-linux-x64` |
| MCP server not starting | vexp not in settings.json | Run titan-setup or add manually |
| `Unsupported platform` | No binary for architecture | Check `@vexp/core-linux-arm64` availability |
| Free tier limit (8/day) | Too many MCP calls | Upgrade to Pro or use sparingly |
| `.vexp/index.db` too large | Big codebase | Add paths to `.vexp_ignore` |
