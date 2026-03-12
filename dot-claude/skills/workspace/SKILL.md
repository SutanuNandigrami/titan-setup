---
description: Project workspace configuration — auto-detect commands, _workspace.json convention, .envrc templates
triggers:
  - workspace
  - project setup
  - _workspace.json
  - how to build
  - how to test
  - how to deploy
  - envrc
  - project config
paths: ["**/_workspace.json", "**/.envrc", "**/justfile", "**/Makefile", "**/package.json", "**/pyproject.toml"]
---

# Workspace Configuration

## _workspace.json Convention
Projects can include a `_workspace.json` at the root:

```json
{
  "name": "my-app",
  "commands": {
    "dev": "bun dev",
    "build": "bun run build",
    "test": "bun test",
    "lint": "ruff check . && shellcheck **/*.sh",
    "deploy": "terraform apply -auto-approve"
  },
  "main_branch": "main",
  "language": "typescript",
  "framework": "next.js"
}
```

## Auto-Detection (when no _workspace.json exists)
Detect project type from files present:

| File | Type | Dev | Test | Lint |
|------|------|-----|------|------|
| `package.json` | Node/Bun | `bun dev` | `bun test` | `bun lint` |
| `pyproject.toml` | Python | `uv run dev` | `uv run pytest` | `ruff check .` |
| `Cargo.toml` | Rust | `cargo run` | `cargo test` | `cargo clippy` |
| `go.mod` | Go | `go run .` | `go test ./...` | `golangci-lint run` |
| `Makefile` | Make | `make dev` | `make test` | `make lint` |
| `justfile` | Just | `just dev` | `just test` | `just lint` |
| `Taskfile.yml` | Task | `task dev` | `task test` | `task lint` |
| `Dockerfile` | Docker | `docker compose up` | — | `hadolint Dockerfile` |
| `terraform/` | Terraform | — | `terraform plan` | `tflint` |

## .envrc Templates
When setting up a new project with `direnv`:

### Python
```bash
# .envrc
layout python3
export DATABASE_URL="postgres://localhost/myapp_dev"
```

### Node
```bash
# .envrc
use mise
export NODE_ENV=development
```

### General
```bash
# .envrc
dotenv_if_exists .env.local
PATH_add bin
```

## Workflow
1. Check for `_workspace.json` first.
2. If absent, auto-detect from project files.
3. Use detected commands for `/ship`, `/scan`, testing.
4. Suggest creating `_workspace.json` if project is complex.
5. Use `direnv allow` after creating `.envrc`.
