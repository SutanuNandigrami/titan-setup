Review current branch against main using the `reviewer` subagent:
1. `git diff main...HEAD` — review every changed file
2. Check: logic errors, security issues, style violations, missing tests, error handling
3. For each issue: file + line, severity (critical/warning/suggestion), what's wrong, how to fix
4. End with: APPROVE, REQUEST CHANGES, or NEEDS DISCUSSION
$ARGUMENTS
