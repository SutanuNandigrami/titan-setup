---
name: modern-python
description: Configures Python projects with modern tooling (uv, ruff, ty). Use when creating projects, writing standalone scripts, or migrating from pip/Poetry/mypy/black.
paths: ["**/*.py", "**/pyproject.toml", "**/setup.py", "**/setup.cfg", "**/requirements*.txt", "**/.python-version", "**/uv.lock", "**/Pipfile*"]
---

# Modern Python

Based on [trailofbits/cookiecutter-python](https://github.com/trailofbits/cookiecutter-python).

## Anti-Patterns

| Avoid | Use Instead |
|-------|-------------|
| `pip install` / Poetry | `uv add` + `uv sync` |
| Manual venv activation | `uv run <cmd>` |
| requirements.txt | PEP 723 (scripts) or pyproject.toml (projects) |
| flake8 / black / isort | `ruff` |
| mypy / pyright | `ty` |
| `[project.optional-dependencies]` for dev | `[dependency-groups]` (PEP 735) |
| `hatchling` build backend | `uv_build` |
| pre-commit | `prek` (faster, Rust-native) |
| `[tool.ty]` python-version | `[tool.ty.environment]` python-version |
| Editing pyproject.toml for deps | `uv add`/`uv remove` |

## Decision Tree

- **Single-file script with deps?** → PEP 723 inline metadata
- **Multi-file project (not distributed)?** → `uv init` minimal setup
- **Reusable package/library?** → `uv init --package` full setup
- **Migrating?** → `uv init --bare && uv add <pkgs> && uv sync`, delete old files

## Tool Overview

| Tool | Purpose | Replaces |
|------|---------|----------|
| **uv** | Package/dependency mgmt | pip, virtualenv, pip-tools, pipx, pyenv |
| **ruff** | Lint + format | flake8, black, isort |
| **ty** | Type checking | mypy, pyright |
| **prek** | Pre-commit hooks | pre-commit |

## Quick Start

```bash
uv init myproject && cd myproject
uv add requests rich
uv add --group dev pytest ruff ty
uv run python src/myproject/main.py
uv run pytest && uv run ruff check .
```

## Full Setup (cookiecutter)

```bash
uvx cookiecutter gh:trailofbits/cookiecutter-python
```

Or manually:
```bash
uv init --package myproject && cd myproject
```

### pyproject.toml config

```toml
[project]
name = "myproject"
version = "0.1.0"
requires-python = ">=3.11"

[dependency-groups]
dev = [{include-group = "lint"}, {include-group = "test"}]
lint = ["ruff", "ty"]
test = ["pytest", "pytest-cov"]

[tool.ruff]
line-length = 100
target-version = "py311"

[tool.ruff.lint]
select = ["ALL"]
ignore = ["D", "COM812", "ISC001"]

[tool.pytest]
addopts = ["--cov=myproject", "--cov-fail-under=80"]

[tool.ty.environment]
python-version = "3.11"
```

Then: `uv sync --all-groups`

## uv Commands

| Command | Description |
|---------|-------------|
| `uv init` | Create project |
| `uv add <pkg>` | Add dependency |
| `uv add --group dev <pkg>` | Add dev dependency |
| `uv remove <pkg>` | Remove dependency |
| `uv sync --all-groups` | Install all groups |
| `uv run <cmd>` | Run in venv |
| `uv build` | Build package |
