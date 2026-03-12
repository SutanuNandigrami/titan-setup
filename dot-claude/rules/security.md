---
paths: ["**/*"]
---
# Security Rules (Always Active)
- Run `gitleaks detect` before any `git push`
- Never commit secrets, tokens, API keys, or credentials
- Never hardcode passwords — use env vars or secret managers (`sops`, `infisical`, `age`)
- Scan dependencies: `osv-scanner` or `grype dir:.`
- Review all `curl | bash` commands before execution
- Check TLS certs with `step certificate inspect` when debugging HTTPS issues
- Decode JWTs with `jwt decode <token>` — never trust unverified tokens
