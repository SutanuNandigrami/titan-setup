# Handoff — proj-01 (titan-setup)

## Branch: `main`

## What's done
- Copied `titan-setup.sh` and `README.md` from `~/titan/` into `/opt/projects/proj-01/`
- Fixed atuin bug: added `bash-preexec` download + source before `atuin init bash` in the setup script
- Moved `CLAUDE.md` from `proj-01/` up to `/opt/projects/` (project-wide config)
- Initial commit: `d891c07`

## What's pending
- Git global identity was set repo-local only — consider `git config --global` for all repos
- No remote configured yet — `git remote add origin <url>` when ready to push
- The `~/titan/titan-setup.sh` source file also has the fix (in sync)

## Key files
- `titan-setup.sh` — main setup script (~1700 lines)
- `README.md` — project documentation
- `/opt/projects/CLAUDE.md` — shared Claude instructions (moved here from proj-01)
