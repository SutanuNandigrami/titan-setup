---
name: VibeSec-Skill
description: This skill helps Claude write secure web applications. Use this when working on any web application or when a user requests a scan or audit to ensure security best practices are followed.
---

# Secure Web App Checklist

**Principles:** Defense in depth, fail closed, least privilege, validate server-side, encode output contextually.

## Access Control
- Verify user owns resource on EVERY request (server-side, not client)
- Use UUIDv4, not sequential IDs
- Check org membership for multi-tenant apps
- On account removal: revoke all tokens/sessions immediately
- Watch for: IDOR, privilege escalation, horizontal/vertical access, mass assignment

## XSS Prevention

**Sanitize ALL user-controllable inputs:**
- Direct: forms, search, file names, rich text
- Indirect: URL params/fragments, headers, third-party API data, WebSocket/postMessage, localStorage
- Overlooked: error messages reflecting input, PDF generators, email templates, admin log viewers, JSON rendered as HTML, SVG uploads, markdown with HTML

**Defenses:**
- Output encode per context (HTML entities, JS escape, URL encode, CSS escape)
- Use framework auto-escaping (React JSX, Vue `{{ }}`)
- CSP: `default-src 'self'; script-src 'self'; frame-ancestors 'none'` — avoid `unsafe-inline`/`unsafe-eval`
- Sanitize with DOMPurify; whitelist tags for rich text
- Headers: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`

## CSRF Protection
- Protect ALL state-changing endpoints (POST/PUT/PATCH/DELETE) AND login/signup/password reset/OAuth callbacks
- Use crypto-random tokens tied to session + validate server-side + regenerate on auth change
- Set `SameSite=Strict; Secure; HttpOnly` on session cookies
- Missing token = rejected request (don't check presence optionally)
- JSON APIs are NOT immune — validate Origin/Referer AND use tokens

## Secrets Exposure
**Never in client-side code:** API keys, DB strings, JWT secrets, encryption keys, OAuth secrets, internal URLs
**Check for leaks in:** JS bundles, source maps, HTML comments, hidden fields, data attributes, localStorage, SSR hydration data, `NEXT_PUBLIC_*`/`REACT_APP_*` env vars

## Open Redirect
- Allowlist valid redirect domains, or accept relative paths only (starts with `/`, no `//`)
- Block bypasses: `@` symbol, subdomain abuse, `javascript:` protocol, double URL encoding, backslash, null byte, data URLs, protocol-relative `//`, unicode homographs

## Password Security
- Min 8 chars (12+ recommended), no max (or 128), allow all chars, don't require specific types
- Hash with Argon2id, bcrypt, or scrypt — NEVER MD5/SHA1/plain SHA256

## SSRF Prevention
- Allowlist approach preferred (pre-approved domains only)
- Resolve DNS before request, validate IP is not private/internal, pin resolved IP
- Block cloud metadata: `169.254.169.254`, `metadata.google.internal`
- Block bypasses: decimal/octal/hex IP, IPv6 localhost `[::1]`, DNS rebinding, CNAME to internal, redirect chains
- Limit/disable redirect following; validate each hop; set timeouts and response size limits

## File Upload Security
- Validate: extension (allowlist), magic bytes, file size (server-side)
- Block: double extension `.php.jpg`, null byte `%00`, MIME spoofing, polyglot files, SVG with JS, XXE via DOCX/XLSX, ZIP slip `../`, ImageMagick exploits
- Handle: rename to UUID, store outside webroot, serve with `Content-Disposition: attachment` + `nosniff`, use CDN/separate domain

## SQL Injection
- PRIMARY: parameterized queries / prepared statements — never concatenate user input
- ORDER BY / table names can't be parameterized — whitelist only
- Escape LIKE wildcards (`%`, `_`)
- DB user must have minimum required permissions

## XXE Prevention
- Disable DTD processing, external entities, XInclude
- Applies to: SOAP, XML-RPC, XML uploads, RSS/feeds, DOCX/XLSX/PPTX (ZIP+XML), SVG, SAML
- Python: `defusedxml` library or `etree.XMLParser(resolve_entities=False, no_network=True)`

## Path Traversal
- Never use user input directly in file paths
- Use indirect references (mapping): `files.get(user_input)`
- If path needed: canonicalize with `os.path.abspath(os.path.realpath(...))`, verify commonpath with base dir
- Reject `..`, absolute paths, whitelist allowed chars

## Security Headers
```
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
Content-Security-Policy: default-src 'self'; script-src 'self'; frame-ancestors 'none'
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Referrer-Policy: strict-origin-when-cross-origin
Cache-Control: no-store  # sensitive pages
```

## JWT Security
- Explicitly specify algorithm on verify — reject `alg: none`, never derive from token
- Use 256+ bit random secrets, always set `exp`, use short-lived tokens (15min) + refresh rotation
- Store in httpOnly/Secure/SameSite=Strict cookies — NEVER localStorage

## API Security
- **Mass assignment**: whitelist allowed fields — never `Model.update(req.body)` directly
- **GraphQL**: disable introspection in prod, limit query depth (10), enforce cost limits, limit batch size
- **Rate limiting**: apply to auth endpoints, API calls, file uploads

## General Rules
1. Validate all input server-side
2. Use parameterized queries
3. Encode output per context
4. Auth + authz checks on every endpoint
5. Handle errors securely (no stack traces to users)
6. Keep dependencies updated
7. When unsure, choose the more restrictive option
