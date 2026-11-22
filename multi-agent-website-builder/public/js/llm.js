// Browser-side LLM client: builds agent prompts, calls the local server proxy and
// parses the structured output each agent kind promises.
import { CONTRACTS, KINDS } from "./agents.js";
import { state, resolveAgentProvider } from "./store.js";

export function systemPrompt(agent, contractKey) {
  const team = state.agents
    .filter((a) => a.enabled)
    .map((a) => `${a.name} (${a.role})`)
    .join(", ");
  return [
    `You are ${agent.name}, the ${agent.role} on a team of AI agents that collaboratively design and build complete, production-quality single-page websites from a user's request.`,
    `Your teammates: ${team}. You only do your own job; your output is handed to the next agent automatically.`,
    `## How you think\n${agent.think}`,
    `## What you create\n${agent.create}`,
    `## Output contract (must follow exactly)\n${CONTRACTS[contractKey]}`,
  ].join("\n\n");
}

export async function callProvider(agent, { system, user, maxTokens }) {
  const { provider, model } = resolveAgentProvider(agent);
  const res = await fetch("/api/chat", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      provider,
      model,
      system,
      messages: [{ role: "user", content: user }],
      maxTokens: maxTokens || state.settings.general.maxTokens,
      temperature: typeof agent.temperature === "number" ? agent.temperature : undefined,
      effort: agent.effort || undefined,
    }),
  });
  const j = await res.json().catch(() => ({ error: `HTTP ${res.status}` }));
  if (!res.ok || j.error) throw new Error(j.error || `HTTP ${res.status}`);
  if (!j.text || !j.text.trim()) throw new Error(`Empty response from ${provider}${j.stopReason ? ` (stop: ${j.stopReason})` : ""}`);
  return { ...j, provider };
}

async function api(method, url, body) {
  const res = await fetch(url, {
    method,
    headers: body ? { "Content-Type": "application/json" } : {},
    body: body ? JSON.stringify(body) : undefined,
  });
  const j = await res.json().catch(() => ({ error: `HTTP ${res.status}` }));
  if (j.providers) state.providers = j.providers;
  if (!res.ok || j.error) throw new Error(j.error || `HTTP ${res.status}`);
  return j;
}

export async function loadProviders() {
  const j = await api("GET", "/api/providers");
  state.catalog = j.catalog;
  state.modelsChecked = j.modelsChecked;
  state.providers = j.providers;
  state.serverOnline = true;
  return j;
}

/** Save provider settings on the server. An empty apiKey keeps the saved key. */
export const saveProvider = (id, patch) => api("PUT", `/api/providers/${id}`, patch);

export const testConnection = (id) => api("POST", "/api/test", { provider: id });

// ------------------------------------------------------------------ parsing

function stripFences(s) {
  return String(s)
    .replace(/^\s*```[a-zA-Z]*\s*\n?/, "")
    .replace(/\n?```\s*$/, "")
    .trim();
}

export function parseJson(text) {
  let s = stripFences(text);
  const start = s.indexOf("{");
  if (start === -1) throw new Error("No JSON object in response");
  // find the matching closing brace, respecting strings
  let depth = 0;
  let inStr = false;
  let esc = false;
  let end = -1;
  for (let i = start; i < s.length; i++) {
    const ch = s[i];
    if (inStr) {
      if (esc) esc = false;
      else if (ch === "\\") esc = true;
      else if (ch === '"') inStr = false;
      continue;
    }
    if (ch === '"') inStr = true;
    else if (ch === "{") depth++;
    else if (ch === "}") {
      depth--;
      if (depth === 0) {
        end = i;
        break;
      }
    }
  }
  const raw = s.slice(start, end === -1 ? undefined : end + 1);
  try {
    return JSON.parse(raw);
  } catch {
    // common LLM slips: trailing commas, comments
    const cleaned = raw.replace(/\/\/[^\n"]*$/gm, "").replace(/,\s*([}\]])/g, "$1");
    return JSON.parse(cleaned);
  }
}

export function extractTag(text, tag) {
  const open = new RegExp(`<${tag}>`, "i");
  const m = open.exec(text);
  if (!m) return null;
  const from = m.index + m[0].length;
  const close = text.toLowerCase().indexOf(`</${tag}>`, from);
  return stripFences(text.slice(from, close === -1 ? undefined : close)).trim();
}

/** Parse a developer response (<thoughts>/<html>/<css>). */
export function parseSection(text, id) {
  const html = extractTag(text, "html");
  if (!html) throw new Error("Response did not contain an <html> block");
  let clean = html.replace(/<script[\s\S]*?<\/script>/gi, "").replace(/\son[a-z]+\s*=\s*("[^"]*"|'[^']*')/gi, "");
  // Ensure the root element carries the section id so CSS scoping & navigation work.
  const root = clean.match(/^\s*<([a-z0-9-]+)([^>]*)>/i);
  if (root && !new RegExp(`\\bid=["']${id}["']`).test(root[2])) {
    if (/\bid=["'][^"']*["']/.test(root[2])) clean = clean.replace(/^(\s*<[a-z0-9-]+[^>]*?)\bid=["'][^"']*["']/i, `$1id="${id}"`);
    else clean = clean.replace(/^\s*<([a-z0-9-]+)/i, `<$1 id="${id}"`);
  }
  return {
    thoughts: extractTag(text, "thoughts") || "",
    html: clean,
    css: (extractTag(text, "css") || "").replace(/<\/?style[^>]*>/gi, ""),
  };
}

export const kindLabel = (k) => KINDS[k]?.label || k;
