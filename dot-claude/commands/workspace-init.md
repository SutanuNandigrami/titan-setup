Initialize workspace for the current project:
1. Detect project type from files (package.json, pyproject.toml, Cargo.toml, go.mod, etc.)
2. Create `_workspace.json` with detected commands (dev, build, test, lint, deploy)
3. If no `.envrc` exists, create one with `direnv` template for the project type
4. Run `direnv allow` if `.envrc` was created
5. Show the user the generated config and ask for adjustments
