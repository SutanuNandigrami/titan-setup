Save a piece of knowledge to persistent memory for use across sessions.

1. Find your auto memory directory (shown in system prompt as "persistent auto memory directory at ...")
2. Read `MEMORY.md` in that directory (create if missing)
3. Parse `$ARGUMENTS` — the user wants to remember this fact/preference/pattern
4. Check if a similar memory already exists — update it instead of duplicating
5. Categorize the memory:
   - **Preferences**: workflow, tool, style choices
   - **Patterns**: code patterns, naming conventions, architecture decisions
   - **Solutions**: fixes for recurring problems
   - **Project context**: key files, APIs, deployment targets
6. Append to the appropriate section in MEMORY.md
7. If MEMORY.md exceeds 150 lines, create topic-specific files and link from MEMORY.md
8. Confirm what was saved and where
