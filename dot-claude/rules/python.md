---
paths: ["**/*.py", "**/pyproject.toml", "**/setup.py", "**/requirements*.txt"]
---
# Python Rules
- Use type hints on all function signatures
- Use `ruff check` and `ruff format` — never `black`, `flake8`, `isort`
- Use `uv` for package management — never `pip install`
- Prefer `pathlib.Path` over `os.path`
- Use `logging` module, never bare `print()` for diagnostics
- Docstrings on public functions (Google style)
- Target Python 3.10+ (use `match`, `X | Y` union types)
