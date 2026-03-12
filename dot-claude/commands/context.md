Pack the current repo into an AI-optimized context file using repomix:
1. Run `repomix` in the current directory (respects .gitignore)
2. Report: total files, token count, output path
3. If tokens > 100K, suggest: `repomix --include "src/**"` to narrow scope
4. If $ARGUMENTS provided, pass as `repomix --include "$ARGUMENTS"`
