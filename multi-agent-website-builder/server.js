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

await loadStore();
server.listen(PORT, HOST, () => {
  console.log(`\n  Multi-Agent Website Builder running at http://${HOST}:${PORT}\n`);
});
