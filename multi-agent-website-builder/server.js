// Multi-Agent Website Builder — local server.
// - Serves the UI from ./public
// - Stores provider settings (incl. API keys) in ./data/providers.json — keys are
//   never returned to the browser, only a masked hint
// - Proxies LLM calls to the configured providers (most provider APIs can't be
//   called from a browser because of CORS)

import http from "node:http";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { PROVIDERS, MODELS_CHECKED, chat, testProvider, serverKeyStatus } from "./providers.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC = path.join(here, "public");
const DATA_DIR = process.env.DATA_DIR || path.join(here, "data");
const STORE = path.join(DATA_DIR, "providers.json");
const PROJECTS = path.join(DATA_DIR, "projects");
const VENDOR = { "/vendor/html-to-image.js": path.join(here, "node_modules", "html-to-image", "dist", "html-to-image.js") };
const MAX_VERSIONS = 40;
const PORT = Number(process.env.PORT) || 5173;
const HOST = process.env.HOST || "127.0.0.1";

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".ico": "image/x-icon",
  ".json": "application/json; charset=utf-8",
};

// ------------------------------------------------------------ settings store

let store = {};
async function loadStore() {
  try {
    store = JSON.parse(await fs.readFile(STORE, "utf8"));
  } catch {
    store = {};
  }
}
async function saveStore() {
  await fs.mkdir(DATA_DIR, { recursive: true });
  await fs.writeFile(STORE, JSON.stringify(store, null, 2), { mode: 0o600 });
}
const maskKey = (k) => (k ? (k.length > 10 ? `${k.slice(0, 4)}…${k.slice(-4)}` : "••••") : "");

function publicProviders() {
  const env = serverKeyStatus();
  const out = {};
  for (const id of Object.keys(PROVIDERS)) {
    const s = store[id] || {};
    out[id] = {
      enabled: Boolean(s.enabled),
      baseUrl: s.baseUrl || "",
      model: s.model || "",
      hasKey: Boolean(s.apiKey),
      keyHint: maskKey(s.apiKey),
      envKey: Boolean(env[id]),
      status: s.status || null,
    };
  }
  return out;
}

// ---------------------------------------------------------------- projects
// Each project is one JSON file: { id, name, createdAt, updatedAt, versions: [
//   { n, label, kind, createdAt, score, site } ] } — `site` is the full workspace.

const validId = (id) => /^[a-z0-9-]{6,48}$/.test(id);
const projectFile = (id) => path.join(PROJECTS, `${id}.json`);
async function readProject(id) {
  if (!validId(id)) throw Object.assign(new Error("Invalid project id"), { status: 400 });
  try {
    return JSON.parse(await fs.readFile(projectFile(id), "utf8"));
  } catch {
    throw Object.assign(new Error("Project not found"), { status: 404 });
  }
}
async function writeProject(p) {
  await fs.mkdir(PROJECTS, { recursive: true });
  p.updatedAt = new Date().toISOString();
  await fs.writeFile(projectFile(p.id), JSON.stringify(p));
  return p;
}
const versionMeta = ({ site, ...v }) => v;
function projectSummary(p) {
  const last = p.versions.at(-1);
  return {
    id: p.id,
    name: p.name,
    createdAt: p.createdAt,
    updatedAt: p.updatedAt,
    versionCount: p.versions.length,
    lastScore: last?.score ?? null,
    thumb: last?.site?.shots?.desktopThumb || null,
    versions: p.versions.map(versionMeta),
  };
}
async function listProjects() {
  let files = [];
  try {
    files = (await fs.readdir(PROJECTS)).filter((f) => f.endsWith(".json"));
  } catch {}
  const out = [];
  for (const f of files) {
    try {
      out.push(projectSummary(JSON.parse(await fs.readFile(path.join(PROJECTS, f), "utf8"))));
    } catch {}
  }
  return out.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
}

async function handleProjects(req, res, pathname) {
  if (pathname === "/api/projects" && req.method === "GET") return send(res, 200, { projects: await listProjects() });
  if (pathname === "/api/projects" && req.method === "POST") {
    const body = await readJson(req);
    const now = new Date().toISOString();
    const p = { id: `p-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 7)}`, name: String(body.name || "Untitled site").slice(0, 80), createdAt: now, updatedAt: now, versions: [] };
    await writeProject(p);
    return send(res, 201, { project: projectSummary(p) });
  }
  const m = pathname.match(/^\/api\/projects\/([a-z0-9-]+)(\/versions(?:\/(\d+))?)?$/);
  if (!m) return null;
  const [, id, versionsPath, n] = m;
  if (!versionsPath) {
    if (req.method === "GET") return send(res, 200, { project: projectSummary(await readProject(id)) });
    if (req.method === "PATCH") {
      const p = await readProject(id);
      const body = await readJson(req);
      if (typeof body.name === "string" && body.name.trim()) p.name = body.name.trim().slice(0, 80);
      await writeProject(p);
      return send(res, 200, { project: projectSummary(p) });
    }
    if (req.method === "DELETE") {
      await readProject(id);
      await fs.rm(projectFile(id), { force: true });
      return send(res, 200, { ok: true });
    }
  } else if (n) {
    if (req.method === "GET") {
      const v = (await readProject(id)).versions.find((x) => x.n === Number(n));
      if (!v) return send(res, 404, { error: "Version not found" });
      return send(res, 200, { version: v });
    }
  } else if (req.method === "POST") {
    const p = await readProject(id);
    const body = await readJson(req, 20 * 1024 * 1024);
    if (!body.site || typeof body.site !== "object") return send(res, 400, { error: "site is required" });
    const v = {
      n: (p.versions.at(-1)?.n || 0) + 1,
      label: String(body.label || "Update").slice(0, 160),
      kind: ["build", "refine", "restore"].includes(body.kind) ? body.kind : "build",
      createdAt: new Date().toISOString(),
      score: typeof body.score === "number" ? body.score : null,
      site: body.site,
    };
    p.versions.push(v);
    if (p.versions.length > MAX_VERSIONS) p.versions = p.versions.slice(-MAX_VERSIONS);
    await writeProject(p);
    return send(res, 201, { project: projectSummary(p), version: versionMeta(v) });
  }
  return send(res, 405, { error: "Method not allowed" });
}

// ------------------------------------------------------------------- http

function send(res, status, body, type = "application/json; charset=utf-8") {
  const data = typeof body === "string" || Buffer.isBuffer(body) ? body : JSON.stringify(body);
  res.writeHead(status, {
    "Content-Type": type,
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
  });
  res.end(data);
}

async function readJson(req, limit = 5 * 1024 * 1024) {
  // Requiring a JSON content type forces a CORS preflight for cross-origin
  // callers (e.g. code running inside the sandboxed preview), which this server
  // never approves.
  if (!String(req.headers["content-type"] || "").includes("application/json")) {
    throw Object.assign(new Error("Content-Type must be application/json"), { status: 415 });
  }
  let size = 0;
  const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > limit) throw Object.assign(new Error("Request body too large"), { status: 413 });
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
  } catch {
    throw Object.assign(new Error("Invalid JSON body"), { status: 400 });
  }
}

async function serveStatic(req, res) {
  const url = new URL(req.url, "http://x");
  let rel = decodeURIComponent(url.pathname);
  if (rel === "/") rel = "/index.html";
  const file = path.normalize(path.join(PUBLIC, rel));
  if (!file.startsWith(PUBLIC + path.sep)) return send(res, 403, { error: "Forbidden" });
  try {
    const data = await fs.readFile(file);
    send(res, 200, data, MIME[path.extname(file)] || "application/octet-stream");
  } catch {
    send(res, 404, "Not found", "text/plain");
  }
}

const server = http.createServer(async (req, res) => {
  const { pathname } = new URL(req.url, "http://x");
  try {
    if (pathname === "/api/providers" && req.method === "GET") {
      return send(res, 200, { catalog: PROVIDERS, providers: publicProviders(), modelsChecked: MODELS_CHECKED });
    }

    // Save provider settings. apiKey: string sets it, "" leaves it, clearKey removes it.
    const m = pathname.match(/^\/api\/providers\/([a-z0-9-]+)$/);
    if (m && req.method === "PUT") {
      const id = m[1];
      if (!PROVIDERS[id]) return send(res, 404, { error: "Unknown provider" });
      const body = await readJson(req);
      const cur = store[id] || {};
      const next = { ...cur };
      for (const k of ["baseUrl", "model"]) if (typeof body[k] === "string") next[k] = body[k].trim();
      if (typeof body.enabled === "boolean") next.enabled = body.enabled;
      if (typeof body.apiKey === "string" && body.apiKey.trim()) next.apiKey = body.apiKey.trim();
      if (body.clearKey) delete next.apiKey;
      if (next.apiKey !== cur.apiKey || next.baseUrl !== cur.baseUrl) next.status = null;
      store[id] = next;
      await saveStore();
      return send(res, 200, { providers: publicProviders() });
    }

    if (pathname === "/api/test" && req.method === "POST") {
      const body = await readJson(req);
      if (!PROVIDERS[body.provider]) return send(res, 404, { error: "Unknown provider" });
      const started = Date.now();
      const cur = store[body.provider] || {};
      try {
        const result = await testProvider(body.provider, cur);
        const latencyMs = Date.now() - started;
        cur.status = { ok: true, message: result.message, models: result.models.slice(0, 300), latencyMs, testedAt: new Date().toISOString() };
        store[body.provider] = cur;
        await saveStore();
        return send(res, 200, { ...result, latencyMs, providers: publicProviders() });
      } catch (e) {
        cur.status = { ok: false, message: e.message, testedAt: new Date().toISOString() };
        store[body.provider] = cur;
        await saveStore();
        return send(res, e.status && e.status < 600 ? e.status : 502, { ok: false, error: e.message, providers: publicProviders() });
      }
    }

    // Streaming chat: newline-delimited JSON — {"t":"d","text"} / {"t":"k","thinking"}
    // fragments, then {"t":"done",...result} or {"t":"error",...}.
    if (pathname === "/api/chat-stream" && req.method === "POST") {
      const body = await readJson(req);
      const started = Date.now();
      const abort = new AbortController();
      res.on("close", () => {
        if (!res.writableEnded) abort.abort(); // browser went away (e.g. Stop) — cancel upstream
      });
      res.writeHead(200, { "Content-Type": "application/x-ndjson; charset=utf-8", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" });
      const line = (o) => !res.writableEnded && res.write(JSON.stringify(o) + "\n");
      try {
        const result = await chat(body.provider, body, store[body.provider] || {}, {
          signal: abort.signal,
          onDelta: (d) => line(d.text != null ? { t: "d", text: d.text } : { t: "k", thinking: d.thinking }),
        });
        line({ t: "done", ...result, latencyMs: Date.now() - started });
      } catch (e) {
        if (!abort.signal.aborted) line({ t: "error", error: e.message || String(e), status: e.status || 500 });
      }
      return res.end();
    }

    if (pathname.startsWith("/api/projects")) {
      const handled = await handleProjects(req, res, pathname);
      if (handled !== null) return handled;
    }

    if (VENDOR[pathname] && req.method === "GET") {
      try {
        return send(res, 200, await fs.readFile(VENDOR[pathname]), MIME[".js"]);
      } catch {
        return send(res, 404, "Run npm install", "text/plain");
      }
    }

    if (pathname === "/api/chat" && req.method === "POST") {
      const body = await readJson(req);
      const started = Date.now();
      const result = await chat(body.provider, body, store[body.provider] || {});
      return send(res, 200, { ...result, latencyMs: Date.now() - started });
    }

    if (pathname.startsWith("/api/")) return send(res, 404, { error: "Unknown endpoint" });
    if (req.method !== "GET" && req.method !== "HEAD") return send(res, 405, { error: "Method not allowed" });
    return serveStatic(req, res);
  } catch (e) {
    const status = e.status && e.status >= 400 && e.status < 600 ? e.status : 500;
    if (status >= 500) console.error(`[${pathname}]`, e.message);
    return send(res, status, { ok: false, error: e.message || String(e) });
  }
});

// Node's built-in fetch ignores HTTPS_PROXY unless NODE_USE_ENV_PROXY=1 is set at
// startup. Behind a proxy (corporate networks, cloud sandboxes), restart this
// process with it enabled so provider calls go through the proxy.
const proxied = process.env.HTTPS_PROXY || process.env.https_proxy || process.env.HTTP_PROXY || process.env.http_proxy;
if (proxied && !process.env.NODE_USE_ENV_PROXY) {
  const { spawn } = await import("node:child_process");
  const child = spawn(process.execPath, [...process.execArgv, ...process.argv.slice(1)], {
    stdio: "inherit",
    env: { ...process.env, NODE_USE_ENV_PROXY: "1" },
  });
  for (const sig of ["SIGINT", "SIGTERM"]) process.on(sig, () => child.kill(sig));
  child.on("exit", (code) => process.exit(code ?? 0));
} else {
  await loadStore();
  server.listen(PORT, HOST, () => {
    console.log(`\n  Multi-Agent Website Builder running at http://${HOST}:${PORT}${proxied ? " (using HTTPS proxy)" : ""}\n`);
  });
}
