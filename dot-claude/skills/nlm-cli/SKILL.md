---
name: nlm-cli
description: "Expert guide for the NotebookLM CLI (`nlm`) — create/manage notebooks, add sources (URLs, YouTube, text, files), generate content (podcast, video, report, quiz, flashcards, mindmap, slides, infographic, data table), download artifacts, run research, and chat with sources. Trigger on: nlm, notebooklm, notebook lm, podcast generation, audio overview, video overview, study guide, or any NotebookLM automation task."
paths: ["**/.nlm*", "**/nlm*", "**/notebooklm*", "**/.notebooklm*"]
---

# NotebookLM CLI (`nlm`)

Install: `uv tool install notebooklm-mcp-cli` — binary is `nlm`.
Requires a Chromium-based browser for authentication (CDP cookie extraction).
Sessions last ~20 min. Re-run `nlm login` when auth errors appear.
Run `nlm doctor` to diagnose auth/config issues.

## Critical Rules

1. **Authenticate first**: `nlm login` before any operation
2. **`--confirm` required**: All generate and delete commands need `--confirm` or `-y`
3. **`--notebook-id` required for research**: Not positional — must be the flag
4. **Use `--wait` when adding sources**: Ensures source is indexed before generating
5. **Use aliases**: `nlm alias set myproject <uuid>` to avoid retyping UUIDs
6. **One-shot Q&A only**: Never use `nlm chat start` (interactive REPL). Use `nlm notebook query <id> "question"` instead
7. **Ask before delete**: Deletions are irreversible — confirm with user before any delete `--confirm`
8. **Two syntax styles**: Both work — `nlm notebook create` or `nlm create notebook`

## Authentication

```bash
nlm login                          # Opens browser, extracts cookies automatically
nlm login --check                  # Verify current session
nlm login --profile work           # Named profile (Chrome, Arc, Brave, Edge, Chromium)
nlm login switch <profile>         # Switch default profile
nlm login profile list             # List profiles with email addresses
nlm login profile delete <name>    # Delete a profile
nlm auth status                    # Check session validity
nlm doctor                         # Diagnose auth, install, config issues
```

## Notebooks

```bash
nlm notebook list                       # List all notebooks
nlm notebook list --json                # JSON output
nlm notebook list --quiet               # IDs only (for scripting)
nlm notebook create "Title"             # Create → returns ID
nlm notebook get <id>                   # Get details
nlm notebook describe <id>              # AI summary
nlm notebook query <id> "question"      # One-shot Q&A with sources
nlm notebook rename <id> "New Title"
nlm notebook delete <id> --confirm      # PERMANENT
```

## Sources

```bash
# Add sources
nlm source add <id> --url "https://..."              # Web page
nlm source add <id> --url "https://..." --wait       # Add and wait until indexed
nlm source add <id> --youtube "https://..."          # YouTube video
nlm source add <id> --file document.pdf --wait       # Upload file (pdf, txt, docx)
nlm source add <id> --text "content" --title "X"     # Pasted text
nlm source add <id> --drive <doc-id>                 # Google Drive (auto-detects type)

# List & inspect
nlm source list <id>
nlm source get <source-id>             # Get content
nlm source describe <source-id>        # AI summary + keywords

# Drive sync
nlm source stale <id>                  # List outdated Drive sources
nlm source sync <id> --confirm         # Sync all stale

# Delete
nlm source delete <source-id> --confirm
```

## Research (Discover New Sources)

```bash
nlm research start "query" --notebook-id <id>               # Fast web (~30s)
nlm research start "query" --notebook-id <id> --mode deep   # Deep web (~5min)
nlm research start "query" --notebook-id <id> --source drive

nlm research status <id> --max-wait 300    # Poll until done (5 min timeout)
nlm research import <id> <task-id>         # Import all discovered sources
```

## Content Generation

All require `--confirm`. Optional: `--source-ids <id1,id2>`, `--language <bcp47>`

```bash
# Audio (Podcast)
nlm audio create <id> --confirm
nlm audio create <id> --format deep_dive --length long --confirm
# formats: deep_dive|brief|critique|debate   lengths: short|default|long

# Video
nlm video create <id> --confirm
nlm video create <id> --format explainer --style whiteboard --confirm
# formats: explainer|brief
# styles: auto_select|classic|whiteboard|kawaii|anime|watercolor|retro_print|heritage|paper_craft

# Report
nlm report create <id> --format "Study Guide" --confirm
# formats: "Briefing Doc"|"Study Guide"|"Blog Post"|"Create Your Own"

# Quiz
nlm quiz create <id> --count 10 --difficulty medium --focus "Focus on key concepts" --confirm

# Flashcards
nlm flashcards create <id> --difficulty hard --focus "Focus on definitions" --confirm
# difficulty: easy|medium|hard

# Mind Map
nlm mindmap create <id> --confirm

# Slides
nlm slides create <id> --confirm
nlm slides revise <artifact-id> --slide '1 Make title larger' --confirm

# Infographic
nlm infographic create <id> --orientation landscape --style professional --confirm
# orientations: landscape|portrait|square

# Data Table
nlm data-table create <id> --description "Sales by region" --confirm
```

## Downloads

```bash
nlm download audio <id> <artifact-id> --output podcast.mp3
nlm download video <id> <artifact-id> --output video.mp4
nlm download report <id> <artifact-id> --output report.md
nlm download mind-map <id> <artifact-id> --output mindmap.json
nlm download slide-deck <id> <artifact-id> --output slides.pdf
nlm download infographic <id> <artifact-id> --output infographic.png
nlm download data-table <id> <artifact-id> --output data.csv
nlm download quiz <id> <artifact-id> --format html --output quiz.html
nlm download flashcards <id> <artifact-id> --format markdown --output cards.md
```

## Studio Status

```bash
nlm studio status <id>                              # List all artifacts + status
nlm studio status <id> --json                       # JSON for parsing
nlm studio delete <id> <artifact-id> --confirm
```

## Sharing

```bash
nlm share status <id>
nlm share public <id>                               # Enable public link
nlm share private <id>                              # Disable public link
nlm share invite <id> email@example.com
nlm share invite <id> email@example.com --role editor
```

## Aliases

```bash
nlm alias set myproject <notebook-id>
nlm alias list
nlm alias get myproject   # resolve to UUID
nlm alias delete myproject
```

## MCP & Skill Setup (one-time)

```bash
nlm setup add claude-code      # Configure NotebookLM MCP server for Claude Code
nlm skill install claude-code  # Install skill docs into ~/.claude/skills/
nlm skill list                 # Show installation status
nlm doctor                     # Verify everything is working
```

## Configuration

```bash
nlm config show
nlm config set auth.default_profile work
nlm config set output.format json
nlm config set auth.browser chrome   # chrome|arc|brave|edge|chromium
```

## Complete Workflow: Files → Video

```bash
nlm login
nlm notebook create "Titan Setup Guide"
nlm alias set titan <id>
nlm source add titan --file README.md --wait
nlm source add titan --file USER_GUIDE.md --wait
nlm video create titan --format explainer --confirm
nlm studio status titan          # poll until completed
nlm download video titan <artifact-id> --output titan-guide.mp4
```

## Error Reference

| Error | Fix |
|-------|-----|
| "Cookies have expired" | `nlm login` |
| "Notebook not found" | `nlm notebook list` for correct ID |
| "Research already in progress" | Use `--force` or import first |
| Rate limit (~50 queries/day free) | Wait, retry |
| Auth/config issues | `nlm doctor` |
