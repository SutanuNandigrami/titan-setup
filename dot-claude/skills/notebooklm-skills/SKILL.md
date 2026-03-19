---
name: notebooklm-skills
description: "Transform files and folders into learning materials using NotebookLM. Actions: transform, convert, generate, create from files. Outputs: audio podcast, video explainer, slide deck, study guide, quiz, flashcards, infographic, mind map, briefing doc, report. Sources: PDF, text files, URLs, folders, subfolders. Features: batch processing, watermark removal, progress tracking, configurable granularity."
paths: ["**/.notebook-decks*", "**/notebooks/**", "**/*.ipynb", "**/notebooklm*"]
---

# Notebook Decks

Transform user files and folders into rich learning materials (podcasts, videos, slide decks, quizzes, etc.) using the NotebookLM MCP, with automatic watermark removal for slide decks.

## Rules (apply to ALL phases)

1. **MCP Only**: Use `notebooklm-mcp` MCP tool calls for ALL NotebookLM operations. NEVER use `nlm` CLI via Bash (except `nlm login` for auth). NEVER create automation script files (.js, .py, .sh, .bat).
2. **No Skipping**: Every question in every phase must be asked and answered before proceeding. Do not assume defaults.
3. **State First**: State files (`.notebook-decks-meta.json`, `tasks.md`, `generation-config.jsonl`) must be written to disk before any `notebook_create` call.

## Start Here

Check if `.notebook-decks-meta.json` exists in the project root, then follow the appropriate path:

### Path A: Fresh Start (no state file)

1. Read `phases/01-configure.md` — collect all user configuration (8 steps)
2. When Phase 1 complete, read `phases/02-confirm.md` — save state files and get user confirmation
3. When Phase 2 complete, read `phases/03-process.md` — process batches

### Path B: Resume (state exists with incomplete batches)

Read `phases/03-process.md` directly. Resume from the first batch with status != "downloaded" or "cleaned".

### Path C: Complete (all batches done)

Tell user: "All N batches were completed. Start a new session (clear state) or modify configuration?"

---

**IMPORTANT**: Read ONE phase file at a time. Complete ALL steps before reading the next. This skill controls routing — phase files do NOT chain to each other.
