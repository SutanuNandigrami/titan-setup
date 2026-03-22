import { spawnSync, spawn } from "node:child_process";
import { readFileSync, writeFileSync, existsSync, mkdirSync, chmodSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { randomBytes, timingSafeEqual } from "node:crypto";

// ── Config ──────────────────────────────────────────────────────────────────
const PORT = Number(process.env.LETTA_CTRL_PORT || 8284);
const LETTA_URL = process.env.LETTA_BASE_URL || "http://127.0.0.1:8283";
const HTML_FILE = join(homedir(), ".config/letta/letta-ctrl.html");

// ── Auth token ──────────────────────────────────────────────────────────────
// Set LETTA_CTRL_TOKEN=disable to skip auth (safe when behind tailscale serve)
const TOKEN_FILE = join(homedir(), ".config/letta/ctrl-token");
const AUTH_DISABLED = process.env.LETTA_CTRL_TOKEN === "disable";
let AUTH_TOKEN = AUTH_DISABLED ? "" : (process.env.LETTA_CTRL_TOKEN || "");
if (!AUTH_DISABLED && !AUTH_TOKEN) {
  if (existsSync(TOKEN_FILE)) {
    AUTH_TOKEN = readFileSync(TOKEN_FILE, "utf8").trim();
  }
  if (!AUTH_TOKEN) {
    AUTH_TOKEN = randomBytes(32).toString("hex");
    const tokenDir = join(homedir(), ".config/letta");
    if (!existsSync(tokenDir)) mkdirSync(tokenDir, { recursive: true });
    writeFileSync(TOKEN_FILE, AUTH_TOKEN + "\n", { mode: 0o600 });
    try { chmodSync(TOKEN_FILE, 0o600); } catch {}
    console.log(`Generated LettaCtrl token: ${AUTH_TOKEN}`);
    console.log(`Token saved to: ${TOKEN_FILE}`);
  }
}
if (AUTH_DISABLED) console.log("Auth disabled (LETTA_CTRL_TOKEN=disable)");

function checkTokenValue(val) {
  if (!val) return false;
  const a = Buffer.from(AUTH_TOKEN);
  const b = Buffer.from(val);
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

function checkAuth(req, url) {
  if (AUTH_DISABLED) return true;
  // Bearer header
  const hdr = req.headers.get("authorization") || "";
  if (hdr.startsWith("Bearer ") && checkTokenValue(hdr.slice(7))) return true;
  // Query-param fallback (needed for EventSource which can't send headers)
  if (url) {
    const qtoken = url.searchParams.get("token");
    if (qtoken && checkTokenValue(qtoken)) return true;
  }
  return false;
}

// Read Letta credentials from file (set at install time by titan-setup.sh)
const CREDS_FILE = join(homedir(), ".config/letta/credentials");
let LETTA_PASSWORD = process.env.LETTA_API_KEY || "";
if (!LETTA_PASSWORD && existsSync(CREDS_FILE)) {
  const creds = readFileSync(CREDS_FILE, "utf8");
  const match = creds.match(/LETTA_SERVER_PASSWORD=([^\n]+)/);
  if (match) LETTA_PASSWORD = match[1].trim();
}
if (!LETTA_PASSWORD) console.warn("WARNING: No LETTA_PASSWORD found — Letta API proxy will fail");

// Services: letta/better-ccflare/ccflare-docker-proxy are --user; ollama is system-level
// container: docker container name for services running in docker (memory/cpu from docker stats)
const SERVICES = [
  { name: "letta",                user: true,  container: "letta-server" },
  { name: "ollama",               user: false },
  { name: "better-ccflare",       user: true  },
  { name: "ccflare-docker-proxy", user: true  },
];

// CPU delta tracking for non-docker services
const _cpuPrev = new Map();

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

function getDockerStats(containerName) {
  try {
    const r = spawnSync("docker", [
      "stats", containerName, "--no-stream", "--format",
      '{"mem":"{{.MemUsage}}","cpu":"{{.CPUPerc}}"}'
    ], { encoding: "utf8", timeout: 3000 });
    if (r.status !== 0 || !r.stdout) return null;
    const d = JSON.parse(r.stdout.trim());
    // Parse mem: "242.8MiB / 7.77GiB" → extract first number + unit
    const memMatch = (d.mem || "").match(/([\d.]+)\s*(MiB|GiB|KiB)/);
    let memMb = 0;
    if (memMatch) {
      const val = parseFloat(memMatch[1]);
      if (memMatch[2] === "GiB") memMb = Math.round(val * 1024);
      else if (memMatch[2] === "KiB") memMb = Math.round(val / 1024);
      else memMb = Math.round(val);
    }
    // Parse cpu: "0.12%" → 0.12
    const cpuPct = parseFloat((d.cpu || "0").replace("%", "")) || 0;
    return { memory_mb: memMb, cpu_pct: Math.round(cpuPct * 10) / 10 };
  } catch { return null; }
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

  // For docker services, get real container stats
  let memMb = 0, cpuPct = 0;
  if (svc.container && active) {
    const ds = getDockerStats(svc.container);
    if (ds) { memMb = ds.memory_mb; cpuPct = ds.cpu_pct; }
  } else {
    // Native service: memory from systemctl, cpu from delta
    const memBytes = parseInt(props.MemoryCurrent || "0", 10);
    memMb = isNaN(memBytes) || memBytes <= 0 ? 0 : Math.round(memBytes / 1024 / 1024);
    const cpuNs = parseInt(props.CPUUsageNSec || "0", 10);
    const now = Date.now();
    const prev = _cpuPrev.get(svc.name);
    if (prev && (now - prev.time) > 1000) {
      const deltaNs = cpuNs - prev.ns;
      const deltaMs = now - prev.time;
      cpuPct = Math.round((deltaNs / (deltaMs * 1e6)) * 1000) / 10;
      if (cpuPct < 0) cpuPct = 0;
    }
    _cpuPrev.set(svc.name, { ns: cpuNs, time: now });
  }

  return {
    active,
    memory_mb: memMb,
    cpu_pct: cpuPct,
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
    console.error(`Letta proxy error on ${path}:`, e.message);
    return Response.json({ error: "Letta server unavailable" }, { status: 502 });
  }
}

function handleLogTail(svcName, count = 4) {
  const svc = SERVICES.find(s => s.name === svcName);
  if (!svc) return Response.json([], { status: 404 });
  const n = Math.min(Math.max(count, 1), 100).toString();
  const args = svc.user
    ? ["--user", "-u", svcName, "-n", n, "--no-pager", "--output=short-iso"]
    : ["-u", svcName, "-n", n, "--no-pager", "--output=short-iso"];
  const r = spawnSync("journalctl", args, { encoding: "utf8", timeout: 3000 });
  const lines = (r.stdout || "").trim().split("\n").filter(l => l.trim());
  return Response.json(lines);
}

function handleLogs(svcName) {
  const svc = SERVICES.find(s => s.name === svcName);
  if (!svc) return new Response("Unknown service", { status: 404 });

  const args = svc.user
    ? ["--user", "-u", svcName, "-f", "-n", "20", "--no-pager", "--output=short-iso"]
    : ["-u", svcName, "-f", "-n", "20", "--no-pager", "--output=short-iso"];

  let child;
  let closed = false;
  const stream = new ReadableStream({
    start(ctrl) {
      child = spawn("journalctl", args);
      const enc = new TextEncoder();
      child.stdout.on("data", chunk => {
        if (closed) return;
        try {
          for (const line of chunk.toString().split("\n")) {
            if (line.trim()) ctrl.enqueue(enc.encode(`data: ${JSON.stringify(line)}\n\n`));
          }
        } catch { closed = true; }
      });
      child.stderr.on("data", () => {});
      child.on("close", () => { if (!closed) { closed = true; try { ctrl.close(); } catch {} } });
    },
    cancel() { closed = true; child?.kill(); },
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
  hostname: "127.0.0.1",
  idleTimeout: 255, // max: keep SSE connections alive
  async fetch(req) {
    const url = new URL(req.url);
    const path = url.pathname;

    // Static — inject auth token so the UI auto-authenticates (no manual paste)
    if (path === "/" || path === "/index.html") {
      try {
        let html = readFileSync(HTML_FILE, "utf8");
        const inject = AUTH_DISABLED ? '""' : JSON.stringify(AUTH_TOKEN);
        html = html.replace("</head>",
          `<script>window.__LETTA_CTRL_TOKEN__=${inject};</script>\n</head>`);
        return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
      } catch {
        return new Response("letta-ctrl.html not found", { status: 500 });
      }
    }

    // CORS preflight
    if (req.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET,POST,PATCH,DELETE,OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Authorization",
        },
      });
    }

    // Auth check for all /api/* routes (supports Bearer header + ?token= query param)
    if (path.startsWith("/api/")) {
      if (!checkAuth(req, url)) {
        return Response.json({ error: "Unauthorized" }, { status: 401 });
      }
    }

    // API
    if (path === "/api/ping") return Response.json({ ok: true });
    if (path === "/api/status") return handleStatus();
    if (path.startsWith("/api/logtail/")) {
      const count = parseInt(url.searchParams.get("n") || "4", 10);
      return handleLogTail(path.slice("/api/logtail/".length), count);
    }
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

    const blockMatch = path.match(/^\/api\/agents\/([^/]+)\/blocks\/(.+)$/);
    if (blockMatch && req.method === "PATCH")
      return proxyLetta(`/v1/agents/${blockMatch[1]}/core-memory/blocks/${decodeURIComponent(blockMatch[2])}`, req);

    const msgMatch = path.match(/^\/api\/agents\/([^/]+)\/messages$/);
    if (msgMatch && req.method === "POST")
      return proxyLetta(`/v1/agents/${msgMatch[1]}/messages`, req);

    // Service control (restart/stop/start via systemctl)
    const svcActionMatch = path.match(/^\/api\/svc\/([^/]+)\/(restart|stop|start)$/);
    if (svcActionMatch && req.method === "POST") {
      const [, svcName, action] = svcActionMatch;
      const svc = SERVICES.find(s => s.name === svcName);
      if (!svc) return new Response("Unknown service", { status: 404 });
      const args = svc.user ? ["--user", action, svcName] : [action, svcName];
      const r2 = spawnSync("systemctl", args, { encoding: "utf8" });
      return Response.json({ ok: r2.status === 0, stderr: r2.stderr });
    }

    return new Response("Not found", { status: 404 });
  },
});

console.log(`letta-ctrl 127.0.0.1:${PORT} → ${LETTA_URL}`);

