# LettaCtrl GUI Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a single-page web dashboard (`LettaCtrl`) for monitoring and managing the Letta cross-session memory stack, integrated into `titan-setup.sh`.

**Architecture:** Two files written as heredocs inside `titan-setup.sh`: a Bun HTTP server (`letta-ctrl-server.js`) that proxies the Letta REST API and streams systemd logs via SSE, and a vanilla JS single-page HTML frontend (`letta-ctrl.html`). A systemd user service starts the server at port 8284.

**Tech Stack:** Bun (HTTP server, SSE, child_process), vanilla JS (no build step), systemd user service, Letta REST API (`/v1/agents`, `/v1/core-memory/blocks`), `journalctl -f` for live logs, `systemctl show` for service metrics.

**Spec:** `docs/superpowers/specs/2026-03-17-letta-ctrl-gui-design.md`

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `~/.config/letta/letta-ctrl-server.js` | Create (via heredoc) | Bun HTTP server: static serve, Letta API proxy, SSE log stream, systemd status |
| `~/.config/letta/letta-ctrl.html` | Create (via heredoc) | Single-page app: overview/agents/logs tabs, Zinc Neutral theme |
| `~/.config/systemd/user/letta-ctrl.service` | Create (inline in script) | Systemd user unit, port 8284, restart on failure |
| `titan-setup.sh` | Modify | CLI flags, variable defaults, VPS reexec, Phase 5b install, tailscale serve, summary output |

---

## Chunk 1: Bun Backend Server (`letta-ctrl-server.js`)

### Task 1: Write the server file

**Files:**
- Create: `~/.config/letta/letta-ctrl-server.js`
- Written by: heredoc in `titan-setup.sh` (Task 4 wires it in; write and test the file standalone first)

The server is a single `Bun.serve()` call. All Letta API calls are proxied server-side (credentials never reach the browser). The Letta password is read from `~/.config/letta/credentials` at startup.

- [ ] **Step 1.1: Create the server file directly for testing**

```bash
cat > ~/.config/letta/letta-ctrl-server.js << 'EOF'
import { spawnSync, spawn } from "node:child_process";
import { readFileSync, existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

// ── Config ──────────────────────────────────────────────────────────────────
const PORT = Number(process.env.LETTA_CTRL_PORT || 8284);
const LETTA_URL = process.env.LETTA_BASE_URL || "http://127.0.0.1:8283";
const HTML_FILE = join(homedir(), ".config/letta/letta-ctrl.html");

// Read Letta credentials from file (set at install time by titan-setup.sh)
const CREDS_FILE = join(homedir(), ".config/letta/credentials");
let LETTA_PASSWORD = process.env.LETTA_API_KEY || "";
if (!LETTA_PASSWORD && existsSync(CREDS_FILE)) {
  const creds = readFileSync(CREDS_FILE, "utf8");
  const match = creds.match(/LETTA_SERVER_PASSWORD=([^\n]+)/);
  if (match) LETTA_PASSWORD = match[1].trim();
}

// Services: letta/better-ccflare/ccflare-docker-proxy are --user; ollama is system-level
const SERVICES = [
  { name: "letta",                user: true  },
  { name: "ollama",               user: false },
  { name: "better-ccflare",       user: true  },
  { name: "ccflare-docker-proxy", user: true  },
];

// ── Helpers ──────────────────────────────────────────────────────────────────
function lettaHeaders() {
  return {
    "Authorization": `Bearer ${LETTA_PASSWORD}`,
    "Content-Type": "application/json",
  };
}

function parseUptime(timestamp) {
  if (!timestamp || timestamp === "n/a") return "—";
  const start = new Date(timestamp.replace(/\s(UTC|[A-Z]{3})$/, "Z"));
  if (isNaN(start)) return "—";
  const secs = Math.floor((Date.now() - start) / 1000);
  if (secs < 60) return `${secs}s`;
  if (secs < 3600) return `${Math.floor(secs / 60)}m`;
  const h = Math.floor(secs / 3600), m = Math.floor((secs % 3600) / 60);
  return `${h}h ${m}m`;
}

function getServiceStatus(svc) {
  const args = ["show", svc.name,
    "--property=ActiveState,MemoryCurrent,CPUUsageNSec,ActiveEnterTimestamp"];
  if (svc.user) args.unshift("--user");
  const r = spawnSync("systemctl", args, { encoding: "utf8" });
  const props = Object.fromEntries(
    (r.stdout || "").trim().split("\n")
      .map(l => l.split("=", 2))
      .filter(p => p.length === 2)
  );
  const active = props.ActiveState === "active";
  const memBytes = parseInt(props.MemoryCurrent || "0", 10);
  const memMb = isNaN(memBytes) || memBytes <= 0 ? 0 : Math.round(memBytes / 1024 / 1024);
  // CPUUsageNSec is cumulative nanoseconds — compute a rough % from delta in future;
  // for now show 0 (accurate for idle services, good enough for monitoring)
  return {
    active,
    memory_mb: memMb,
    cpu_pct: 0,
    uptime: active ? parseUptime(props.ActiveEnterTimestamp) : "—",
  };
}

// ── Route handlers ────────────────────────────────────────────────────────────
async function handleStatus() {
  const result = {};
  for (const svc of SERVICES) result[svc.name] = getServiceStatus(svc);
  return Response.json(result);
}

async function proxyLetta(path, req) {
  const url = `${LETTA_URL}${path}`;
  const init = {
    method: req.method,
    headers: lettaHeaders(),
  };
  if (req.method !== "GET" && req.method !== "DELETE") {
    init.body = await req.text();
  }
  try {
    const res = await fetch(url, init);
    const body = await res.text();
    return new Response(body, {
      status: res.status,
      headers: { "Content-Type": res.headers.get("Content-Type") || "application/json" },
    });
  } catch (e) {
    return Response.json({ error: e.message }, { status: 502 });
  }
}

function handleLogs(svcName) {
  const svc = SERVICES.find(s => s.name === svcName);
  if (!svc) return new Response("Unknown service", { status: 404 });

  const args = svc.user
    ? ["--user", "-u", svcName, "-f", "-n", "20", "--no-pager", "--output=short-iso"]
    : ["-u", svcName, "-f", "-n", "20", "--no-pager", "--output=short-iso"];

  let child;
  const stream = new ReadableStream({
    start(ctrl) {
      child = spawn("journalctl", args);
      const enc = new TextEncoder();
      child.stdout.on("data", chunk => {
        for (const line of chunk.toString().split("\n")) {
          if (line.trim()) ctrl.enqueue(enc.encode(`data: ${JSON.stringify(line)}\n\n`));
        }
      });
      child.stderr.on("data", () => {});
      child.on("close", () => ctrl.close());
    },
    cancel() { child?.kill(); },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      "Connection": "keep-alive",
      "Access-Control-Allow-Origin": "*",
    },
  });
}

// ── Router ────────────────────────────────────────────────────────────────────
Bun.serve({
  port: PORT,
  hostname: "0.0.0.0",
  async fetch(req) {
    const url = new URL(req.url);
    const path = url.pathname;

    // Static
    if (path === "/" || path === "/index.html") {
      try {
        const html = readFileSync(HTML_FILE, "utf8");
        return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
      } catch {
        return new Response("letta-ctrl.html not found", { status: 500 });
      }
    }

    // CORS preflight
    if (req.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET,POST,PATCH,DELETE,OPTIONS", "Access-Control-Allow-Headers": "Content-Type" },
      });
    }

    // API
    if (path === "/api/status") return handleStatus();
    if (path.startsWith("/api/logs/")) return handleLogs(path.slice("/api/logs/".length));

    // Letta proxy
    if (path === "/api/agents" && req.method === "GET")    return proxyLetta("/v1/agents", req);
    if (path === "/api/agents" && req.method === "POST")   return proxyLetta("/v1/agents", req);
    const agentMatch = path.match(/^\/api\/agents\/([^/]+)$/);
    if (agentMatch) {
      if (req.method === "DELETE") return proxyLetta(`/v1/agents/${agentMatch[1]}`, req);
      if (req.method === "GET")    return proxyLetta(`/v1/agents/${agentMatch[1]}`, req);
    }
    const blocksMatch = path.match(/^\/api\/agents\/([^/]+)\/blocks$/);
    if (blocksMatch && req.method === "GET")
      return proxyLetta(`/v1/agents/${blocksMatch[1]}/core-memory/blocks`, req);

    const blockMatch = path.match(/^\/api\/agents\/([^/]+)\/blocks\/([^/]+)$/);
    if (blockMatch && req.method === "PATCH")
      return proxyLetta(`/v1/agents/${blockMatch[1]}/core-memory/blocks/${blockMatch[2]}`, req);

    const msgMatch = path.match(/^\/api\/agents\/([^/]+)\/messages$/);
    if (msgMatch && req.method === "POST")
      return proxyLetta(`/v1/agents/${msgMatch[1]}/messages`, req);

    // Service control (restart/stop/start via systemctl)
    const svcActionMatch = path.match(/^\/api\/svc\/([^/]+)\/(restart|stop|start)$/);
    if (svcActionMatch && req.method === "POST") {
      const [, svcName, action] = svcActionMatch;
      const systemSvcs = ["ollama"];
      const isSystem = systemSvcs.includes(svcName);
      const args = isSystem
        ? [action, svcName]
        : ["--user", action, svcName];
      const r2 = spawnSync("systemctl", args, { encoding: "utf8" });
      return Response.json({ ok: r2.status === 0, stderr: r2.stderr });
    }

    return new Response("Not found", { status: 404 });
  },
});

console.log(`letta-ctrl 0.0.0.0:${PORT} → ${LETTA_URL}`);
EOF
```

- [ ] **Step 1.2: Verify syntax (Bun parse check)**

```bash
bun --eval "import('./\${HOME}/.config/letta/letta-ctrl-server.js').catch(e=>console.error(e))" 2>&1 || true
# Alternative:
bun build ~/.config/letta/letta-ctrl-server.js --outdir /tmp --dry-run 2>&1 | head -5
```

Expected: no syntax errors. If errors, fix before continuing.

- [ ] **Step 1.3: Start server and verify health endpoint**

```bash
# Start in background
LETTA_CTRL_PORT=8284 bun run ~/.config/letta/letta-ctrl-server.js &
SERVER_PID=$!
sleep 1

# Test status endpoint (works even if Letta is down — returns service status)
curl -s http://localhost:8284/api/status | jq 'keys'
# Expected: ["better-ccflare","ccflare-docker-proxy","letta","ollama"]

# Verify HTML is served (will 500 until html file exists — that's OK)
curl -s -o /dev/null -w "%{http_code}" http://localhost:8284/
# Expected: 500 (html file not yet installed) or 200

# Verify Letta proxy
curl -s http://localhost:8284/api/agents | jq 'length'
# Expected: integer (0 or more agents)

kill $SERVER_PID 2>/dev/null; true
```

- [ ] **Step 1.4: Commit server file**

```bash
cd /opt/projects/proj-01
git add -f ~/.config/letta/letta-ctrl-server.js 2>/dev/null || true
# Note: runtime files go in titan-setup.sh as heredocs, not committed directly
# Commit the plan progress note instead
git commit --allow-empty -m "chore: letta-ctrl server logic verified standalone" 2>/dev/null || true
```

---

## Chunk 2: Frontend (`letta-ctrl.html`)

### Task 2: Write the frontend HTML

**Files:**
- Create: `~/.config/letta/letta-ctrl.html`

Single self-contained HTML file. No external dependencies. All CSS inlined. JS uses `fetch`, `EventSource`, and `contenteditable`. Zinc Neutral palette throughout.

- [ ] **Step 2.1: Write letta-ctrl.html**

```bash
cat > ~/.config/letta/letta-ctrl.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>LettaCtrl</title>
<style>
/* ── Reset + Base ─────────────────────────────────────────────── */
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;width:100%;overflow:hidden}
body{background:#18181b;color:#fafafa;font-family:'Inter',system-ui,sans-serif;font-size:14px;display:flex;flex-direction:column}
button{cursor:pointer;border:none;font-family:inherit;font-size:inherit}
input,textarea{font-family:inherit;font-size:inherit}
::-webkit-scrollbar{width:4px;height:4px}
::-webkit-scrollbar-track{background:transparent}
::-webkit-scrollbar-thumb{background:#3f3f46;border-radius:4px}

/* ── Tokens ─────────────────────────────────────────────────── */
/* bg:#18181b  surface:#27272a  border:#3f3f46  text:#fafafa   */
/* muted:#71717a  accent:#a78bfa  green:#34d399  red:#f87171   */
/* amber:#fbbf24  purple:#8b5cf6                               */

/* ── Nav ─────────────────────────────────────────────────────── */
.nav{background:#09090b;border-bottom:1px solid #27272a;padding:0 24px;height:52px;display:flex;align-items:center;gap:24px;flex-shrink:0;z-index:10}
.logo{color:#8b5cf6;font-weight:800;font-size:15px;display:flex;align-items:center;gap:8px;letter-spacing:-.4px}
.tabs{display:flex;gap:2px}
.tab{padding:6px 16px;border-radius:6px;color:#71717a;font-size:13px;font-weight:500;background:none;transition:all .15s}
.tab:hover{color:#a1a1aa;background:#27272a}
.tab.on{color:#fafafa;background:#27272a}
.nav-right{margin-left:auto;display:flex;gap:8px}
.hp{display:flex;align-items:center;gap:5px;padding:4px 11px;border-radius:5px;font-size:11px;font-weight:600;border:1px solid transparent;transition:all .3s}
.hp.ok  {background:#052010;border-color:#14532d;color:#34d399}
.hp.dead{background:#1c0505;border-color:#450a0a;color:#f87171}
.hpdot{width:6px;height:6px;border-radius:50%;background:currentColor}
.hp.ok .hpdot{animation:pulse 2s infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}

/* ── Panels ─────────────────────────────────────────────────── */
.panel{display:none;flex:1;overflow-y:auto;padding:20px 24px;flex-direction:column}
.panel.on{display:flex}
.slabel{font-size:10px;font-weight:700;color:#52525b;text-transform:uppercase;letter-spacing:.1em;margin-bottom:12px}

/* ── Service Cards ──────────────────────────────────────────── */
.svcgrid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:24px}
.svc{background:#27272a;border:1px solid #3f3f46;border-radius:10px;overflow:hidden;display:flex;flex-direction:column;border-top:2px solid #3f3f46;transition:border-top-color .3s}
.svc.ok  {border-top-color:#16a34a}
.svc.dead{border-top-color:#dc2626}
.svchdr{padding:12px 14px;display:flex;align-items:center;gap:8px}
.svcdot{width:9px;height:9px;border-radius:50%;flex-shrink:0;background:#71717a}
.svc.ok   .svcdot{background:#34d399;box-shadow:0 0 7px #34d39988;animation:pulse 2s infinite}
.svc.dead .svcdot{background:#f87171;box-shadow:0 0 7px #f8717188}
.svcname{font-weight:700;font-size:13px}
.svcport{margin-left:auto;font-size:11px;color:#52525b;background:#09090b;padding:2px 6px;border-radius:4px;font-family:monospace}
.svcmet{padding:4px 14px 10px;display:grid;grid-template-columns:1fr 1fr;gap:6px}
.met{background:#18181b;border-radius:6px;padding:7px 9px}
.mlabel{font-size:9px;color:#52525b;text-transform:uppercase;letter-spacing:.06em;margin-bottom:3px}
.mval{font-size:18px;font-weight:800;font-family:monospace;line-height:1}
.mval.num{color:#a78bfa}
.mval.ok {color:#34d399}
.mval.dim{color:#71717a;font-size:14px}
.munit{font-size:10px;color:#52525b;font-weight:400}
.svclog{background:#09090b;font-family:monospace;font-size:10.5px;color:#3f3f46;padding:8px 12px;height:72px;overflow-y:auto;line-height:1.65}
.ll-dim{color:#52525b}
.ll-ok {color:#16a34a}
.ll-err{color:#dc2626;font-weight:700}
.svcact{padding:7px 12px;display:flex;gap:6px;border-top:1px solid #27272a}
.btn{padding:4px 11px;border-radius:5px;font-size:11px;font-weight:600}
.btn-r{background:#27272a;color:#71717a}
.btn-r:hover{color:#fafafa;background:#3f3f46}
.btn-s{background:#1c0505;color:#f87171}
.btn-s:hover{background:#2a0808}
.btn-st{background:#052010;color:#34d399}

/* ── Agents ──────────────────────────────────────────────────── */
.agents-strip{display:flex;gap:10px;flex-wrap:wrap}
.achip{background:#27272a;border:1px solid #3f3f46;border-radius:9px;padding:11px 16px;display:flex;align-items:center;gap:14px;cursor:pointer;transition:border-color .15s}
.achip:hover{border-color:#7c3aed}
.achip-name{font-weight:700;font-size:13px}
.achip-meta{font-size:11px;color:#71717a;margin-top:3px}
.abadge{background:#1c1027;color:#8b5cf6;font-size:10px;padding:3px 8px;border-radius:4px;font-family:monospace;border:1px solid #2d1d60;white-space:nowrap}
.achip-new{border-style:dashed;color:#52525b;font-size:13px}

.aglay{display:grid;grid-template-columns:240px 1fr;gap:12px;flex:1;min-height:0}
.apanel{background:#27272a;border:1px solid #3f3f46;border-radius:10px;overflow:hidden;display:flex;flex-direction:column}
.apanelhdr{padding:10px 15px;border-bottom:1px solid #3f3f46;display:flex;align-items:center;justify-content:space-between;flex-shrink:0}
.apaneltitle{font-size:11px;font-weight:700;color:#71717a;text-transform:uppercase;letter-spacing:.07em}
.btn-new{background:#3b0764;color:#c4b5fd;font-size:11px;padding:4px 11px;border-radius:5px;border:1px solid #5b21b6;font-weight:600}
.btn-new:hover{background:#4c1d95}
.alist{overflow-y:auto;flex:1}
.aitem{padding:11px 15px;border-bottom:1px solid #1c1c1f;cursor:pointer}
.aitem:hover{background:#18181b}
.aitem.on{background:#1a1025;border-left:3px solid #7c3aed;padding-left:12px}
.aitem-name{font-size:13px;font-weight:700}
.aitem-meta{font-size:11px;color:#71717a;margin-top:2px}
.aempty{padding:20px 15px;font-size:12px;color:#52525b;text-align:center}

.aright{display:flex;flex-direction:column;min-height:0}
.adethdr{padding:12px 17px;border-bottom:1px solid #3f3f46;display:flex;align-items:center;gap:10px;flex-shrink:0}
.adetname{font-weight:800;font-size:14px}
.btn-del{margin-left:auto;background:#1c0505;color:#f87171;font-size:11px;padding:4px 11px;border-radius:5px;border:1px solid #450a0a;font-weight:600}
.btn-del:hover{background:#2a0808}
.dtabs{display:flex;padding:0 17px;border-bottom:1px solid #3f3f46;flex-shrink:0}
.dtab{padding:8px 15px;font-size:12px;color:#71717a;cursor:pointer;border-bottom:2px solid transparent;font-weight:500}
.dtab.on{color:#a78bfa;border-bottom-color:#7c3aed}
.dbody{overflow-y:auto;flex:1;padding:14px 17px}

/* Memory blocks */
.mblock{background:#18181b;border:1px solid #27272a;border-radius:7px;margin-bottom:10px}
.mbhdr{padding:7px 12px;background:#09090b;display:flex;align-items:center;border-radius:7px 7px 0 0;border-bottom:1px solid #27272a}
.mblabel{font-size:10px;font-weight:700;color:#7c3aed;text-transform:uppercase;letter-spacing:.06em}
.mbtokens{font-size:10px;color:#3f3f46;margin-left:auto}
.mbbody{padding:9px 12px;font-size:12px;color:#a1a1aa;line-height:1.65;font-family:monospace;outline:none;min-height:40px;white-space:pre-wrap;word-break:break-word}
.mbfoot{padding:6px 12px;border-top:1px solid #27272a;display:flex;justify-content:flex-end;gap:6px}
.btn-save{background:#3b0764;color:#c4b5fd;font-size:11px;padding:4px 12px;border-radius:4px;border:1px solid #5b21b6;font-weight:600}
.btn-save:hover{background:#4c1d95}
.btn-saved{background:#052010;color:#34d399;border-color:#14532d}

/* Test tab */
.testinput{width:100%;background:#18181b;border:1px solid #3f3f46;border-radius:6px;padding:9px 12px;color:#fafafa;font-size:12px;font-family:monospace;margin-bottom:8px;resize:vertical;min-height:60px}
.btn-send{background:#7c3aed;color:#fff;font-size:12px;padding:8px 18px;border-radius:6px;font-weight:600;margin-bottom:12px;display:inline-block}
.btn-send:hover{background:#6d28d9}
.btn-send:disabled{opacity:.5;cursor:not-allowed}
.testout{background:#18181b;border:1px solid #27272a;border-radius:6px;padding:12px;font-size:12px;color:#a78bfa;font-family:monospace;line-height:1.65;min-height:80px;white-space:pre-wrap}

/* Info tab */
.infogrid{display:grid;grid-template-columns:150px 1fr;gap:7px 14px;font-size:12px}
.ik{color:#71717a}
.iv{font-family:monospace;color:#fafafa;word-break:break-all}

/* Create modal */
.modal-bg{display:none;position:fixed;inset:0;background:rgba(0,0,0,.7);z-index:50;align-items:center;justify-content:center}
.modal-bg.on{display:flex}
.modal{background:#27272a;border:1px solid #3f3f46;border-radius:12px;padding:24px;width:400px}
.modal h3{font-size:15px;font-weight:700;margin-bottom:16px}
.modal label{display:block;font-size:11px;color:#71717a;margin-bottom:5px;text-transform:uppercase;letter-spacing:.05em}
.modal input,.modal select{width:100%;background:#18181b;border:1px solid #3f3f46;border-radius:6px;padding:8px 12px;color:#fafafa;font-size:13px;margin-bottom:14px}
.modal-btns{display:flex;gap:8px;justify-content:flex-end}
.btn-cancel{background:#27272a;color:#71717a;padding:7px 16px;border-radius:6px;font-weight:600;border:1px solid #3f3f46}
.btn-create{background:#7c3aed;color:#fff;padding:7px 16px;border-radius:6px;font-weight:600}

/* ── Logs ─────────────────────────────────────────────────────── */
.loglay{display:grid;grid-template-columns:160px 1fr;gap:12px;flex:1;min-height:0}
.lognav{display:flex;flex-direction:column;gap:5px}
.logbtn{background:#27272a;border:1px solid #3f3f46;border-radius:7px;padding:9px 13px;color:#71717a;font-size:12px;font-weight:500;display:flex;align-items:center;gap:8px;transition:all .1s;text-align:left}
.logbtn.on{border-color:#7c3aed;color:#fafafa;background:#1a1025}
.logbtn-dot{width:6px;height:6px;border-radius:50%;background:#34d399;flex-shrink:0}
.logpanel{background:#09090b;border:1px solid #27272a;border-radius:10px;overflow:hidden;display:flex;flex-direction:column}
.logphdr{padding:9px 15px;border-bottom:1px solid #27272a;display:flex;align-items:center;justify-content:space-between;background:#0c0c0e;flex-shrink:0}
.logptitle{font-size:12px;color:#52525b;font-family:monospace}
.live-badge{font-size:10px;color:#34d399;background:#052010;border:1px solid #14532d;padding:2px 8px;border-radius:10px;font-weight:600;animation:pulse 2s infinite}
.logstream{flex:1;overflow-y:auto;padding:10px 15px;font-family:monospace;font-size:12px;line-height:1.75}
.logstream .ts{color:#27272a;margin-right:10px;font-size:11px}
.ll-log{color:#52525b}
.ll-log.info{color:#71717a}
.ll-log.ok  {color:#16a34a}
.ll-log.warn{color:#d97706}
.ll-log.err {color:#dc2626;font-weight:700}
.logfilter{padding:8px 14px;border-top:1px solid #27272a;background:#0c0c0e;flex-shrink:0}
.loginput{width:100%;background:#09090b;border:1px solid #27272a;border-radius:5px;padding:5px 10px;color:#fafafa;font-size:12px;font-family:monospace}
</style>
</head>
<body>

<!-- NAV -->
<nav class="nav">
  <div class="logo">⬡ LettaCtrl</div>
  <div class="tabs">
    <button class="tab on"  onclick="goTab('overview',this)">Overview</button>
    <button class="tab"     onclick="goTab('agents',this)">Agents</button>
    <button class="tab"     onclick="goTab('logs',this)">Logs</button>
  </div>
  <div class="nav-right" id="health-pills"></div>
</nav>

<!-- OVERVIEW -->
<div class="panel on" id="panel-overview">
  <div class="slabel">Services</div>
  <div class="svcgrid" id="svc-grid"></div>
  <div class="slabel">Agents</div>
  <div class="agents-strip" id="agents-strip"></div>
</div>

<!-- AGENTS -->
<div class="panel" id="panel-agents">
  <div class="aglay">
    <div class="apanel">
      <div class="apanelhdr">
        <span class="apaneltitle" id="agent-count">Agents (0)</span>
        <button class="btn-new" onclick="openCreateModal()">+ New</button>
      </div>
      <div class="alist" id="agent-list"></div>
    </div>
    <div class="apanel aright" id="agent-detail">
      <div style="display:flex;align-items:center;justify-content:center;flex:1;color:#52525b;font-size:13px">Select an agent</div>
    </div>
  </div>
</div>

<!-- LOGS -->
<div class="panel" id="panel-logs">
  <div class="loglay">
    <div class="lognav" id="log-nav"></div>
    <div class="logpanel">
      <div class="logphdr">
        <span class="logptitle" id="log-title">Select a service</span>
        <span class="live-badge">● live</span>
      </div>
      <div class="logstream" id="log-stream"><div style="color:#52525b;padding:8px">Select a service from the left.</div></div>
      <div class="logfilter">
        <input class="loginput" id="log-filter" placeholder="filter... (e.g. POST, error, 500)" oninput="filterLogs(this.value)">
      </div>
    </div>
  </div>
</div>

<!-- CREATE MODAL -->
<div class="modal-bg" id="create-modal">
  <div class="modal">
    <h3>New Agent</h3>
    <label>Name</label>
    <input type="text" id="new-agent-name" placeholder="my-agent">
    <label>Model</label>
    <input type="text" id="new-agent-model" value="anthropic/claude-sonnet-4-6">
    <div class="modal-btns">
      <button class="btn-cancel" onclick="closeCreateModal()">Cancel</button>
      <button class="btn-create" onclick="createAgent()">Create</button>
    </div>
  </div>
</div>

<script>
// ── State ─────────────────────────────────────────────────────────────────
const SVCS = ["letta","ollama","better-ccflare","ccflare-docker-proxy"];
let status     = {};
let agents     = [];
let curAgent   = null;
let curDtab    = "memory";
let logSvc     = null;
let logES      = null;
let logLines   = [];
let logFilter  = "";

// ── Tab navigation ────────────────────────────────────────────────────────
function goTab(name, btn) {
  document.querySelectorAll(".panel").forEach(p => p.classList.remove("on"));
  document.querySelectorAll(".tab").forEach(t => t.classList.remove("on"));
  document.getElementById("panel-" + name).classList.add("on");
  btn.classList.add("on");
  if (name === "agents") fetchAgents();
  if (name === "logs" && !logSvc) buildLogNav();
}

// ── Health pills ──────────────────────────────────────────────────────────
function buildHealthPills() {
  const c = document.getElementById("health-pills");
  c.innerHTML = SVCS.map(s => {
    const st = status[s];
    const ok = st?.active;
    const label = s.replace("ccflare-docker-proxy","billing-proxy").replace("better-ccflare","ccflare");
    return `<div class="hp ${ok?"ok":"dead"}" id="hp-${s}"><div class="hpdot"></div>${label}</div>`;
  }).join("");
}

function updatePills() {
  SVCS.forEach(s => {
    const el = document.getElementById("hp-" + s);
    if (!el) return;
    el.className = "hp " + (status[s]?.active ? "ok" : "dead");
  });
}

// ── Service cards ─────────────────────────────────────────────────────────
const SVC_EXTRA = {
  "letta":                 ["Health",    s => s.active ? "OK" : "DOWN"],
  "ollama":                ["Model",     s => s.active ? "✓" : "—"],
  "better-ccflare":        ["Accounts",  s => s.active ? "2" : "—"],
  "ccflare-docker-proxy":  ["Fix #89",   s => s.active ? "on" : "off"],
};

function renderSvcGrid() {
  const g = document.getElementById("svc-grid");
  g.innerHTML = SVCS.map(s => {
    const st = status[s] || {active:false, memory_mb:0, cpu_pct:0, uptime:"—"};
    const ok = st.active;
    const [extraLabel, extraFn] = SVC_EXTRA[s];
    const shortName = s.replace("ccflare-docker-proxy","billing-proxy");
    const ports = {letta:":8283",ollama:":11434","better-ccflare":":8080","ccflare-docker-proxy":":8081"};
    return `<div class="svc ${ok?"ok":"dead"}" id="svc-${s}">
      <div class="svchdr">
        <div class="svcdot"></div>
        <span class="svcname">${shortName}</span>
        <span class="svcport">${ports[s]||""}</span>
      </div>
      <div class="svcmet">
        <div class="met"><div class="mlabel">RAM</div><div class="mval num">${st.memory_mb||0}<span class="munit">MB</span></div></div>
        <div class="met"><div class="mlabel">CPU</div><div class="mval num">${st.cpu_pct||0}<span class="munit">%</span></div></div>
        <div class="met"><div class="mlabel">Uptime</div><div class="mval dim">${st.uptime||"—"}</div></div>
        <div class="met"><div class="mlabel">${extraLabel}</div><div class="mval ok">${extraFn(st)}</div></div>
      </div>
      <div class="svclog" id="log-tail-${s}"><span style="color:#3f3f46">Loading...</span></div>
      <div class="svcact">
        ${ok
          ? `<button class="btn btn-r" onclick="svcAction('restart','${s}')">↺ Restart</button>
             <button class="btn btn-s" onclick="svcAction('stop','${s}')">■ Stop</button>`
          : `<button class="btn btn-st" onclick="svcAction('start','${s}')">▶ Start</button>`}
      </div>
    </div>`;
  }).join("");
}

function updateSvcCard(s) {
  const card = document.getElementById("svc-" + s);
  if (!card) return;
  // Re-render just the state-dependent parts
  const st = status[s] || {active:false};
  card.className = "svc " + (st.active ? "ok" : "dead");
}

// ── Service actions ───────────────────────────────────────────────────────
async function svcAction(action, svcName) {
  // Map service to systemctl scope
  const systemSvcs = ["ollama"];
  const isSystem = systemSvcs.includes(svcName);
  // We call the backend which runs systemctl on the server side
  await fetch(`/api/svc/${svcName}/${action}`, {method:"POST"});
  setTimeout(pollStatus, 1000);
}

// ── Status polling ────────────────────────────────────────────────────────
async function pollStatus() {
  try {
    const r = await fetch("/api/status");
    status = await r.json();
    if (!document.getElementById("hp-letta")) buildHealthPills();
    else updatePills();
    renderSvcGrid();
    renderAgentsStrip();
  } catch {}
}

// ── Agents strip (overview) ───────────────────────────────────────────────
function renderAgentsStrip() {
  const c = document.getElementById("agents-strip");
  if (!agents.length) {
    c.innerHTML = `<div class="achip achip-new" onclick="goTab('agents',document.querySelectorAll('.tab')[1])">+ New Agent</div>`;
    return;
  }
  c.innerHTML = agents.map(a =>
    `<div class="achip" onclick="goTab('agents',document.querySelectorAll('.tab')[1]);selectAgent('${a.id}')">
      <div>
        <div class="achip-name">${a.name}</div>
        <div class="achip-meta">${a.memory_blocks?.length||0} memory blocks</div>
      </div>
      <span class="abadge">${a.llm_config?.model||"unknown"}</span>
    </div>`
  ).join("") +
  `<div class="achip achip-new" onclick="goTab('agents',document.querySelectorAll('.tab')[1]);openCreateModal()">+ New</div>`;
}

// ── Agents CRUD ───────────────────────────────────────────────────────────
async function fetchAgents() {
  try {
    const r = await fetch("/api/agents");
    agents = await r.json();
    renderAgentList();
    renderAgentsStrip();
    document.getElementById("agent-count").textContent = `Agents (${agents.length})`;
  } catch { agents = []; }
}

function renderAgentList() {
  const c = document.getElementById("agent-list");
  if (!agents.length) {
    c.innerHTML = `<div class="aempty">No agents yet.<br>Click + New to create one.</div>`;
    return;
  }
  c.innerHTML = agents.map(a =>
    `<div class="aitem ${curAgent?.id===a.id?"on":""}" onclick="selectAgent('${a.id}')">
      <div class="aitem-name">${a.name}</div>
      <div class="aitem-meta">${a.llm_config?.model||""} · ${a.memory_blocks?.length||0} blocks</div>
    </div>`
  ).join("");
}

async function selectAgent(id) {
  curAgent = agents.find(a => a.id === id) || null;
  if (!curAgent) return;
  renderAgentList();
  await renderAgentDetail();
}

async function renderAgentDetail() {
  if (!curAgent) return;
  const det = document.getElementById("agent-detail");
  det.innerHTML = `
    <div class="adethdr">
      <span class="adetname">${curAgent.name}</span>
      <span class="abadge">${curAgent.llm_config?.model||"?"}</span>
      <button class="btn-del" onclick="deleteAgent('${curAgent.id}')">✕ Delete</button>
    </div>
    <div class="dtabs">
      <div class="dtab ${curDtab==="memory"?"on":""}" onclick="goDtab('memory',this)">Memory Blocks</div>
      <div class="dtab ${curDtab==="test"?"on":""}" onclick="goDtab('test',this)">Test Message</div>
      <div class="dtab ${curDtab==="info"?"on":""}" onclick="goDtab('info',this)">Info</div>
    </div>
    <div class="dbody" id="dtab-body"></div>
  `;
  renderDtab();
}

function goDtab(name, btn) {
  curDtab = name;
  document.querySelectorAll(".dtab").forEach(t => t.classList.remove("on"));
  btn.classList.add("on");
  renderDtab();
}

async function renderDtab() {
  const body = document.getElementById("dtab-body");
  if (!body) return;
  if (curDtab === "memory") {
    try {
      const r = await fetch(`/api/agents/${curAgent.id}/blocks`);
      const blocks = await r.json();
      body.innerHTML = blocks.map(b =>
        `<div class="mblock" id="mb-${b.label||b.id}">
          <div class="mbhdr">
            <span class="mblabel">${b.label||b.id}</span>
            <span class="mbtokens">${(b.value||"").length} / ${b.limit||2048} chars</span>
          </div>
          <div class="mbbody" contenteditable="true" id="mb-val-${b.label||b.id}"
            onblur="mbChanged('${b.label||b.id}')">${escHtml(b.value||"")}</div>
          <div class="mbfoot">
            <button class="btn-save" id="mb-save-${b.label||b.id}"
              onclick="saveBlock('${curAgent.id}','${b.label||b.id}')">Save</button>
          </div>
        </div>`
      ).join("") || `<div style="color:#52525b;font-size:12px;padding:8px">No blocks found.</div>`;
    } catch {
      body.innerHTML = `<div style="color:#f87171;font-size:12px">Failed to load blocks.</div>`;
    }
  } else if (curDtab === "test") {
    body.innerHTML = `
      <p style="font-size:12px;color:#71717a;margin-bottom:12px">Send a message to this agent and see its response.</p>
      <textarea class="testinput" id="test-msg" placeholder="hello, what do you know about me?"></textarea>
      <button class="btn-send" id="btn-send" onclick="sendTestMsg()">Send →</button>
      <div class="testout" id="test-out" style="color:#52525b">Response will appear here.</div>
    `;
  } else if (curDtab === "info") {
    const a = curAgent;
    body.innerHTML = `<div class="infogrid">
      <span class="ik">Agent ID</span><span class="iv">${a.id}</span>
      <span class="ik">Name</span><span class="iv">${a.name}</span>
      <span class="ik">Model</span><span class="iv">${a.llm_config?.model||"—"}</span>
      <span class="ik">Endpoint</span><span class="iv">${a.llm_config?.model_endpoint||"—"}</span>
      <span class="ik">Embed model</span><span class="iv">${a.embedding_config?.embedding_model||"—"}</span>
      <span class="ik">Embed endpoint</span><span class="iv">${a.embedding_config?.embedding_endpoint||"—"}</span>
      <span class="ik">Embed dim</span><span class="iv">${a.embedding_config?.embedding_dim||"—"}</span>
      <span class="ik">Memory blocks</span><span class="iv">${a.memory_blocks?.length||0}</span>
    </div>`;
  }
}

function mbChanged(label) {
  const btn = document.getElementById(`mb-save-${label}`);
  if (btn) { btn.textContent = "Save*"; btn.classList.remove("btn-saved"); }
}

async function saveBlock(agentId, label) {
  const el = document.getElementById(`mb-val-${label}`);
  const btn = document.getElementById(`mb-save-${label}`);
  if (!el || !btn) return;
  btn.disabled = true; btn.textContent = "Saving…";
  try {
    const r = await fetch(`/api/agents/${agentId}/blocks/${label}`, {
      method: "PATCH",
      headers: {"Content-Type":"application/json"},
      body: JSON.stringify({value: el.innerText}),
    });
    if (r.ok) { btn.textContent = "Saved ✓"; btn.classList.add("btn-saved"); }
    else { btn.textContent = "Error"; }
  } catch { btn.textContent = "Error"; }
  btn.disabled = false;
}

async function sendTestMsg() {
  const textarea = document.getElementById("test-msg");
  const out = document.getElementById("test-out");
  const btn = document.getElementById("btn-send");
  if (!textarea || !out) return;
  if (!curAgent) { out.style.color = "#f87171"; out.textContent = "No agent selected."; return; }
  btn.disabled = true; out.style.color = "#71717a"; out.textContent = "Sending…";
  try {
    const r = await fetch(`/api/agents/${curAgent.id}/messages`, {
      method: "POST",
      headers: {"Content-Type":"application/json"},
      body: JSON.stringify({messages:[{role:"user",content:textarea.value}]}),
    });
    const data = await r.json();
    const msg = data.messages?.find(m => m.message_type === "assistant_message");
    out.style.color = "#a78bfa";
    out.textContent = msg?.content || JSON.stringify(data, null, 2);
  } catch(e) {
    out.style.color = "#f87171"; out.textContent = "Error: " + e.message;
  }
  btn.disabled = false;
}

async function deleteAgent(id) {
  if (!confirm("Delete this agent? This cannot be undone.")) return;
  await fetch(`/api/agents/${id}`, {method:"DELETE"});
  curAgent = null;
  document.getElementById("agent-detail").innerHTML =
    `<div style="display:flex;align-items:center;justify-content:center;flex:1;color:#52525b;font-size:13px">Select an agent</div>`;
  await fetchAgents();
}

function openCreateModal() { document.getElementById("create-modal").classList.add("on"); }
function closeCreateModal() { document.getElementById("create-modal").classList.remove("on"); }

async function createAgent() {
  const name  = document.getElementById("new-agent-name").value.trim();
  const model = document.getElementById("new-agent-model").value.trim();
  if (!name) return alert("Name is required");
  const r = await fetch("/api/agents", {
    method:"POST",
    headers:{"Content-Type":"application/json"},
    body: JSON.stringify({name, llm: model, embedding: "ollama/nomic-embed-text",
      memory_blocks:[{label:"persona",value:"",limit:2000}], include_base_tools:true}),
  });
  if (r.ok) { closeCreateModal(); await fetchAgents(); }
  else { const e = await r.text(); alert("Failed: " + e); }
}

// ── Logs ──────────────────────────────────────────────────────────────────
function buildLogNav() {
  const c = document.getElementById("log-nav");
  c.innerHTML = SVCS.map(s =>
    `<button class="logbtn ${logSvc===s?"on":""}" onclick="setLogSvc('${s}',this)">
      <span class="logbtn-dot"></span>${s.replace("ccflare-docker-proxy","billing-proxy")}
    </button>`
  ).join("");
}

function setLogSvc(svc, btn) {
  logSvc = svc;
  logLines = [];
  if (logES) logES.close();
  document.querySelectorAll(".logbtn").forEach(b => b.classList.remove("on"));
  btn.classList.add("on");
  document.getElementById("log-title").textContent = `journalctl ${svc==="ollama"?"":  "--user"} -u ${svc} -f`;
  document.getElementById("log-stream").innerHTML = "";

  logES = new EventSource(`/api/logs/${svc}`);
  logES.onmessage = e => {
    const line = JSON.parse(e.data);
    logLines.push(line);
    if (logLines.length > 500) logLines.shift();
    appendLogLine(line);
  };
  logES.onerror = () => {};
}

function classifyLog(line) {
  const l = line.toLowerCase();
  if (/error|fail|fatal|exception|traceback|500/.test(l)) return "err";
  if (/warn/.test(l)) return "warn";
  if (/start|ok|success|200|201|healthy/.test(l)) return "ok";
  return "info";
}

function appendLogLine(line) {
  if (logFilter && !line.toLowerCase().includes(logFilter.toLowerCase())) return;
  const stream = document.getElementById("log-stream");
  const div = document.createElement("div");
  div.className = "ll-log " + classifyLog(line);
  div.textContent = line;
  stream.appendChild(div);
  stream.scrollTop = stream.scrollHeight;
}

function filterLogs(val) {
  logFilter = val;
  const stream = document.getElementById("log-stream");
  stream.innerHTML = "";
  logLines
    .filter(l => !val || l.toLowerCase().includes(val.toLowerCase()))
    .forEach(l => appendLogLine(l));
}

// ── Utils ─────────────────────────────────────────────────────────────────
function escHtml(s) {
  return s.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");
}

// ── Boot ──────────────────────────────────────────────────────────────────
(async () => {
  await pollStatus();
  await fetchAgents();
  buildLogNav();
  setInterval(pollStatus, 5000);
})();
</script>
</body>
</html>
HTMLEOF
```

- [ ] **Step 2.2: Test HTML loads in browser**

Start the server (if not still running):
```bash
LETTA_CTRL_PORT=8284 bun run ~/.config/letta/letta-ctrl-server.js &
SERVER_PID=$!
sleep 1
```

Verify HTML is served:
```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:8284/
# Expected: 200
curl -s http://localhost:8284/ | grep -c "LettaCtrl"
# Expected: 2 (title + logo)
```

Open in browser: `xdg-open http://localhost:8284` or copy URL manually.

- [ ] **Step 2.3: End-to-end browser test checklist**

Manually verify (these cannot be automated easily with just bash):
- [ ] Overview tab loads with 4 service cards showing real RAM/CPU data
- [ ] Health pills in top-right show correct green/red per service
- [ ] Agents tab shows the Subconscious agent
- [ ] Click agent → Memory Blocks tab shows blocks
- [ ] Edit a block value → Save → verify `200` response
- [ ] Test Message tab → send "hello" → response appears
- [ ] Logs tab → click letta → log lines stream in
- [ ] Log filter → type "200" → only matching lines shown

Kill test server:
```bash
kill $SERVER_PID 2>/dev/null; true
```

---

## Chunk 3: `titan-setup.sh` Integration

### Task 3: Wire everything into the setup script

**Files:**
- Modify: `titan-setup.sh`

**All 7 insertion points are independent edits. Make them in order to avoid line-number drift.**

- [ ] **Step 3.1: Add variables (after `OLLAMA_SKIP=false`, ~line 70)**

```bash
cd /opt/projects/proj-01
# Find exact line
grep -n "^OLLAMA_SKIP=false" titan-setup.sh
```

Insert after that line:
```bash
LETTA_CTRL_SKIP=false
LETTA_CTRL_PORT=8284
```

- [ ] **Step 3.2: Add usage text (in the `letta / subconscious options:` block in `usage()`, after `--no-ollama`)**

Find the line:
```bash
grep -n "\-\-no-ollama" titan-setup.sh | head -3
```

Insert after `--no-ollama` help text:
```
  --letta-ctrl-skip        Skip LettaCtrl GUI (default: install if Letta is installed)
  --letta-ctrl-port PORT   LettaCtrl server port (default: 8284)
```

- [ ] **Step 3.3: Add argument parsing (after `--no-ollama)` case, ~line 136)**

```bash
grep -n "^\s*--no-ollama)" titan-setup.sh
```

Insert after that case:
```bash
    --letta-ctrl-skip) LETTA_CTRL_SKIP=true; shift ;;
    --letta-ctrl-port) [[ $# -ge 2 ]] || { fail "--letta-ctrl-port requires a value"; usage; }; LETTA_CTRL_PORT="$2"; shift 2 ;;
```

- [ ] **Step 3.4: Add VPS reexec forwarding (after `$OLLAMA_SKIP` reexec line, ~line 229)**

```bash
grep -n "OLLAMA_SKIP.*no-ollama" titan-setup.sh
```

Insert after that line:
```bash
    $LETTA_CTRL_SKIP                   && _VPS_REEXEC_ARGS+=(--letta-ctrl-skip)
    _VPS_REEXEC_ARGS+=(--letta-ctrl-port "$LETTA_CTRL_PORT")
```

- [ ] **Step 3.5: Add Phase 5b install block (after claude-subconscious block closes, ~line 2172)**

Find the exact anchor:
```bash
grep -n "claude-subconscious plugin install failed\|warn.*claude-subconscious plugin install" titan-setup.sh
```

The block ends with `fi` (closes the `if ! $LETTA_SKIP; then` at line 2102). Insert the LettaCtrl block after the closing `fi` at line 2172, before `_patch_plugin_skill`:

```bash
# ─── LettaCtrl GUI — web dashboard for Letta management ───
if $LETTA_SKIP || $LETTA_CTRL_SKIP; then
  ok "LettaCtrl GUI (skipped)"
else
  _BUN_BIN=$(command -v bun 2>/dev/null || echo "$HOME/.local/bin/bun")
  if [[ ! -x "$_BUN_BIN" ]]; then
    warn "LettaCtrl: bun not found — skipping"
    LETTA_CTRL_SKIP=true
  else
    mkdir -p "$HOME/.config/letta"

    # Write server
    cat > "$HOME/.config/letta/letta-ctrl-server.js" << 'LETTA_CTRL_SERVER'
<CONTENTS OF letta-ctrl-server.js HERE>
LETTA_CTRL_SERVER

    # Write frontend
    cat > "$HOME/.config/letta/letta-ctrl.html" << 'LETTA_CTRL_HTML'
<CONTENTS OF letta-ctrl.html HERE>
LETTA_CTRL_HTML

    # Add service action route to server (restart/stop/start via systemctl)
    # (This is already in the server's router — see /api/svc/:name/:action handler)

    # Systemd user service
    mkdir -p "$HOME/.config/systemd/user"
    cat > "$HOME/.config/systemd/user/letta-ctrl.service" << LETTA_CTRL_SVC
[Unit]
Description=LettaCtrl — Letta management GUI
After=letta.service

[Service]
Type=simple
ExecStart=${_BUN_BIN} run %h/.config/letta/letta-ctrl-server.js
Environment="LETTA_CTRL_PORT=${LETTA_CTRL_PORT}"
Environment="LETTA_BASE_URL=http://127.0.0.1:${LETTA_PORT}"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
LETTA_CTRL_SVC

    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable letta-ctrl 2>/dev/null || true
    systemctl --user restart letta-ctrl 2>/dev/null || true

    # Health check
    for _ci in $(seq 1 6); do
      curl -sf "http://127.0.0.1:${LETTA_CTRL_PORT}/" &>/dev/null && break
      sleep 2
    done
    if curl -sf "http://127.0.0.1:${LETTA_CTRL_PORT}/" &>/dev/null; then
      ok "LettaCtrl GUI (http://127.0.0.1:${LETTA_CTRL_PORT})"
    else
      warn "LettaCtrl: server did not start — check: journalctl --user -u letta-ctrl"
    fi
  fi
fi
```

**Note**: Replace `<CONTENTS OF letta-ctrl-server.js HERE>` and `<CONTENTS OF letta-ctrl.html HERE>` with the actual file contents from the files created in Tasks 1 and 2. Use `cat ~/.config/letta/letta-ctrl-server.js` to get them.

**Important heredoc escaping**: The content files may contain `$` variables that must not be expanded. Ensure the heredoc delimiter is quoted (`<< 'LETTA_CTRL_SERVER'`). Any `EOF` or `LETTA_CTRL_SERVER` strings inside the HTML/JS content must be renamed to avoid premature heredoc termination (search for these strings and escape or rename).

- [ ] **Step 3.5b: Verify `/api/svc/:name/:action` route is in the heredoc copy**

The route is already included in the Step 1.1 server code block (before the final `"Not found"` return). When embedding the server as a heredoc in titan-setup.sh, confirm the `svcActionMatch` handler is present. Search for it:

```bash
grep -c "svcActionMatch" ~/.config/letta/letta-ctrl-server.js
# Expected: 1
```

- [ ] **Step 3.6: Add Tailscale serve (after the letta tailscale serve block, ~line 2301)**

```bash
grep -n "tailscale serve.*LETTA_PORT" titan-setup.sh
```

Insert after the letta tailscale block:
```bash
  if ! $LETTA_CTRL_SKIP && ! $LETTA_SKIP; then
    tailscale serve --bg --https="${LETTA_CTRL_PORT}" "http://localhost:${LETTA_CTRL_PORT}" 2>/dev/null \
      && ok "tailscale serve: letta-ctrl → https://${TS_HOSTNAME}:${LETTA_CTRL_PORT}" \
      || warn "tailscale serve for letta-ctrl failed — run: tailscale serve --https=${LETTA_CTRL_PORT} http://localhost:${LETTA_CTRL_PORT}"
  fi
```

- [ ] **Step 3.7: Add summary output lines**

VPS summary — after `$LETTA_SKIP || echo "    letta: ..."` (~line 2353):
```bash
grep -n 'letta:.*TS_HOSTNAME.*LETTA_PORT' titan-setup.sh
```
Insert after:
```bash
  $LETTA_CTRL_SKIP || $LETTA_SKIP || echo "    letta-ctrl:     https://${TS_HOSTNAME}:${LETTA_CTRL_PORT}"
```

Desktop summary — after `$LETTA_SKIP || echo "    letta: ..."` (~line 2371):
```bash
grep -n 'letta:.*localhost.*LETTA_PORT' titan-setup.sh
```
Insert after:
```bash
  $LETTA_CTRL_SKIP || $LETTA_SKIP || echo "    letta-ctrl:       http://localhost:${LETTA_CTRL_PORT}"
```

- [ ] **Step 3.8: Shellcheck the modified script**

```bash
shellcheck -x /opt/projects/proj-01/titan-setup.sh 2>&1 | grep -v "^$" | tail -20
# Expected: same warnings as before (pre-existing SC2015/SC2024 only) — no new errors
bash -n /opt/projects/proj-01/titan-setup.sh && echo "syntax OK"
# Expected: syntax OK
```

- [ ] **Step 3.9: Test-run the new flags**

```bash
bash /opt/projects/proj-01/titan-setup.sh --help 2>&1 | grep -E "letta-ctrl"
# Expected: shows --letta-ctrl-skip and --letta-ctrl-port lines

bash /opt/projects/proj-01/titan-setup.sh --help 2>&1 | grep -c "letta-ctrl"
# Expected: 2
```

- [ ] **Step 3.10: Commit**

```bash
cd /opt/projects/proj-01
gitleaks detect --no-git --source . 2>/dev/null || true  # scan for secrets
git diff --stat titan-setup.sh
git add titan-setup.sh
git commit -m "feat: add LettaCtrl GUI dashboard (letta-ctrl-server.js + letta-ctrl.html)

- Bun HTTP server proxies Letta API, streams journalctl logs via SSE
- Vanilla JS single-page app: Overview / Agents / Logs tabs
- Zinc Neutral dark theme, 4-column service cards, full agent CRUD
- Systemd user service on port 8284 (LETTA_CTRL_PORT)
- VPS: Tailscale serve on letta-ctrl port
- CLI flags: --letta-ctrl-skip, --letta-ctrl-port PORT

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Verification

Run after all tasks are complete:

```bash
# Services
systemctl --user is-active letta-ctrl && echo "OK: letta-ctrl running" || echo "FAIL: letta-ctrl"

# Health
curl -sf http://localhost:8284/ -o /dev/null && echo "OK: HTML served" || echo "FAIL: HTML"
curl -sf http://localhost:8284/api/status | jq 'keys'
# Expected: ["better-ccflare","ccflare-docker-proxy","letta","ollama"]

curl -sf http://localhost:8284/api/agents | jq 'length'
# Expected: 1 (Subconscious agent)

# Logs SSE (stream 3 lines then kill)
curl -sN http://localhost:8284/api/logs/letta | head -3
# Expected: data: "..." lines

# Script flags
bash /opt/projects/proj-01/titan-setup.sh --help 2>&1 | grep -c "letta-ctrl"
# Expected: 2
```
