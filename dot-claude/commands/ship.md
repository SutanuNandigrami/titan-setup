Run full pre-push pipeline:
1. Lint modified files (shellcheck for .sh, ruff for .py, hadolint for Dockerfile)
2. Run relevant tests
3. `gitleaks detect --verbose`
4. `git diff --stat` — verify all changes are intentional
5. Commit with conventional message if needed
6. `git push -u origin HEAD`
7. Ask if I want a PR, if yes: `gh pr create --fill`
Stop on any failure. $ARGUMENTS
