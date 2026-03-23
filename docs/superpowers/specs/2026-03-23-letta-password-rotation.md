# Letta Password Rotation Fix — Feature Codemap
**Date**: 2026-03-23
**Status**: Shipped (fix/letta-password-rotation)
**ADR**: ADR-036

---

## Problem

On titan re-runs, `LETTA_SERVER_PASSWORD` is regenerated (unless `--letta-password` is passed).
Three artefacts are updated atomically: `~/.config/letta/credentials`, `~/.config/letta/docker.env`,
and `~/.claude/settings.json` (via `merge-settings.py`).

But the running `letta-server` Docker container is **not restarted**.

`systemctl start letta` is a no-op when `letta.service` is already `active (exited)`
(Type=oneshot + RemainAfterExit=yes — ADR-026). The container keeps its launch-time
`LETTA_SERVER_PASSWORD`, which no longer matches the key in `settings.json`.

Result: every `claude-subconscious` session hook returns HTTP 401. CC reports
`SessionStart:startup hook error` at every session start.

---

## Architecture

```
titan-setup.sh re-run
  │
  ├── lib/08-tools-letta.sh (password block)
  │     ├── openssl rand → LETTA_PASSWORD (new)
  │     ├── ~/.config/letta/credentials ← new key
  │     └── ~/.config/letta/docker.env  ← new key
  │
  ├── lib/08-tools-letta.sh (service block)  ← FIX IS HERE
  │     ├── docker inspect letta-server → _RUNNING_PASS
  │     ├── if _RUNNING_PASS != LETTA_PASSWORD
  │     │     └── systemctl --user restart letta  (container recreated, picks up new docker.env)
  │     └── else
  │           └── systemctl --user start letta    (no-op if already running, normal start if not)
  │
  └── lib/16-finalize.sh (merge block)
        └── merge-settings.py --inject LETTA_API_KEY=$LETTA_PASSWORD → ~/.claude/settings.json
```

### Container env flow

```
~/.config/letta/docker.env
  SECURE=true
  LETTA_SERVER_PASSWORD=<key>          ← authoritative source for container
  ANTHROPIC_BASE_URL=http://host.docker.internal:8081   ← better-ccflare proxy
  ANTHROPIC_API_KEY=sk-proxy-via-ccflare

docker run --env-file docker.env letta/letta:latest
  └── container env: LETTA_SERVER_PASSWORD=<key>
        └── Letta auth: Bearer <key> required on all /v1/* endpoints

~/.claude/settings.json env block
  LETTA_API_KEY=<key>                  ← must match container
  LETTA_BASE_URL=http://127.0.0.1:8283
  LETTA_MODEL=anthropic/claude-sonnet-4-6
  LETTA_MODE=whisper
```

### claude-subconscious hook chain

```
CC SessionStart
  ├── session_start.ts   (CLAUDE_PLUGIN_ROOT/scripts/)
  │     ├── reads LETTA_API_KEY from env
  │     ├── POST /v1/agents/:id/messages  (notify session start)
  │     └── exit 0 always (non-blocking — patched ADR-035)
  └── sync_letta_memory.ts
        ├── reads LETTA_API_KEY from env
        ├── GET /v1/agents/:id  (sync memory blocks to CLAUDE.md)
        └── exit 0 always (non-blocking — patched ADR-035)
```

---

## Files Changed

| File | Change |
|---|---|
| `lib/08-tools-letta.sh` | Added `docker inspect` password-mismatch check before service start |
| `titan-setup.sh` | Rebuilt from fragments (authoritative assembled script) |
| `test/session-review.bats` | 4 regression tests (ROT prefix) |
| `docs/decisions.md` | ADR-036 appended |
| `~/.claude/plugins/marketplaces/claude-subconscious/scripts/session_start.ts` | exit 0 on Letta API error (non-blocking, also patched in ADR-035) |
| `~/.claude/plugins/marketplaces/claude-subconscious/scripts/sync_letta_memory.ts` | exit 0 on all errors (non-blocking) |

> Note: plugin patches are live on the local machine only — not in the titan repo.
> They are re-applied by titan during install via the `/dev/tty` patch block (lib/11-plugins.sh).

---

## Key Invariant

After any titan re-run:

```
docker inspect letta-server | grep LETTA_SERVER_PASSWORD
~/.config/letta/credentials | grep LETTA_SERVER_PASSWORD
~/.claude/settings.json | jq '.env.LETTA_API_KEY'
```

All three must agree. The fix enforces this.

---

## Manual Repair (if needed)

If the mismatch persists (e.g. titan ran with `--letta-skip`):

```bash
# Get container's actual key
docker inspect letta-server --format '{{range .Config.Env}}{{println .}}{{end}}' \
  | grep LETTA_SERVER_PASSWORD

# Update settings.json
sudo python3 -c "
import json; p='/home/\$USER/.claude/settings.json'
s=json.load(open(p)); s['env']['LETTA_API_KEY']='<key-from-above>'
json.dump(s, open(p,'w'), indent=2)"

# Or restart container to match credentials
systemctl --user restart letta
```

---

## Testing

```bash
cd /opt/projects/proj-01
just build
just check  # includes 4 ROT tests + 239 total
```
