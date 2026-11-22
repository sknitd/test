// Server-side provider adapters.
//
// Every adapter exposes two operations:
//   test({ apiKey, baseUrl })                -> { ok, models[], message }
//   chat({ apiKey, baseUrl, model, system, messages, maxTokens, temperature, effort })
//                                            -> { text, thinking, model, stopReason, usage }
//
// API keys are saved server-side (data/providers.json, see server.js) and never
// sent back to the browser, so code generated into the preview can't read them.
// If no key is saved, the matching environment variable is used (see ENV_KEYS).

import Anthropic from "@anthropic-ai/sdk";

export const PROVIDERS = {
  anthropic: {
    label: "Anthropic (Claude)",
    kind: "anthropic",
    baseUrl: "https://api.anthropic.com",
    defaultModel: "claude-opus-5-5",
    suggestedModels: ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5", "claude-fable-5-2"],
    needsKey: true,
    docs: "https://platform.claude.com/settings/keys",
  },
  openai: {
    label: "OpenAI",
    kind: "openai",
    baseUrl: "https://api.openai.com/v1",
    defaultModel: "gpt-5-mini",
    suggestedModels: [],
    needsKey: true,
    docs: "https://platform.openai.com/api-keys",
  },
  gemini: {
    label: "Google Gemini",
    kind: "gemini",
    baseUrl: "https://generativelanguage.googleapis.com/v1beta",
    defaultModel: "gemini-2.5-flash",
    suggestedModels: [],
    needsKey: true,
    docs: "https://aistudio.google.com/apikey",
  },
  openrouter: {
    label: "OpenRouter",
    kind: "openai-compatible",
    baseUrl: "https://openrouter.ai/api/v1",
    defaultModel: "openrouter/auto",
    suggestedModels: [],
    needsKey: true,
    docs: "https://openrouter.ai/keys",
  },
  groq: {
    label: "Groq",
    kind: "openai-compatible",
    baseUrl: "https://api.groq.com/openai/v1",
    defaultModel: "llama-3.3-70b-versatile",
    suggestedModels: [],
    needsKey: true,
    docs: "https://console.groq.com/keys",
  },
  mistral: {
    label: "Mistral",
    kind: "openai-compatible",
    baseUrl: "https://api.mistral.ai/v1",
    defaultModel: "mistral-large-latest",
    suggestedModels: [],
    needsKey: true,
    docs: "https://console.mistral.ai/api-keys",
  },
  deepseek: {
    label: "DeepSeek",
    kind: "openai-compatible",
    baseUrl: "https://api.deepseek.com/v1",
    defaultModel: "deepseek-chat",
    suggestedModels: [],
    needsKey: true,
    docs: "https://platform.deepseek.com/api_keys",
  },
  xai: {
    label: "xAI (Grok)",
    kind: "openai-compatible",
    baseUrl: "https://api.x.ai/v1",
    defaultModel: "grok-4",
    suggestedModels: [],
    needsKey: true,
    docs: "https://console.x.ai",
  },
  together: {
    label: "Together AI",
    kind: "openai-compatible",
    baseUrl: "https://api.together.xyz/v1",
    defaultModel: "meta-llama/Llama-3.3-70B-Instruct-Turbo",
    suggestedModels: [],
    needsKey: true,
    docs: "https://api.together.ai/settings/api-keys",
  },
  ollama: {
    label: "Ollama (local)",
    kind: "openai-compatible",
    baseUrl: "http://localhost:11434/v1",
    defaultModel: "llama3.1",
    suggestedModels: [],
    needsKey: false,
    docs: "https://ollama.com",
  },
  custom: {
    label: "Custom (OpenAI-compatible)",
    kind: "openai-compatible",
    baseUrl: "",
    defaultModel: "",
    suggestedModels: [],
    needsKey: false,
    docs: "",
  },
};

const ENV_KEYS = {
  anthropic: "ANTHROPIC_API_KEY",
  openai: "OPENAI_API_KEY",
  gemini: "GEMINI_API_KEY",
  openrouter: "OPENROUTER_API_KEY",
  groq: "GROQ_API_KEY",
  mistral: "MISTRAL_API_KEY",
  deepseek: "DEEPSEEK_API_KEY",
  xai: "XAI_API_KEY",
  together: "TOGETHER_API_KEY",
  custom: "CUSTOM_API_KEY",
};

export function serverKeyStatus() {
  const out = {};
  for (const [id, env] of Object.entries(ENV_KEYS)) out[id] = Boolean(process.env[env]);
  return out;
}

class ProviderError extends Error {
  constructor(message, status = 502) {
    super(message);
    this.status = status;
  }
}

function resolve(providerId, cfg, stored = {}) {
  const def = PROVIDERS[providerId];
  if (!def) throw new ProviderError(`Unknown provider "${providerId}"`, 400);
  // Priority: key saved in Settings (server-side store) → environment variable.
  const apiKey = (stored.apiKey || "").trim() || process.env[ENV_KEYS[providerId]] || "";
  const baseUrl = ((stored.baseUrl || "").trim() || def.baseUrl).replace(/\/+$/, "");
  if (!baseUrl) throw new ProviderError("A base URL is required for this provider.", 400);
  return { def, apiKey, baseUrl };
}

async function readError(res) {
  const body = await res.text().catch(() => "");
  let msg = body;
  try {
    const j = JSON.parse(body);
    msg = j.error?.message || j.error || j.message || body;
    if (typeof msg !== "string") msg = JSON.stringify(msg);
  } catch {}
  return `${res.status} ${res.statusText}${msg ? ` — ${String(msg).slice(0, 400)}` : ""}`;
}

async function fetchWithTimeout(url, opts = {}, ms = 600_000) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), ms);
  try {
    return await fetch(url, { ...opts, signal: ctrl.signal });
  } catch (e) {
    if (e.name === "AbortError") throw new ProviderError(`Request timed out after ${ms / 1000}s`, 504);
    throw new ProviderError(`Network error reaching ${new URL(url).host}: ${e.cause?.code || e.message}`, 502);
  } finally {
    clearTimeout(t);
  }
}

// ---------------------------------------------------------------- Anthropic

// Models that accept adaptive thinking + output_config.effort.
const ADAPTIVE_RE = /claude-(opus-(4-[6-9]|5)|sonnet-(4-6|5)|haiku-5|fable|mythos)/;
// Models for which the server-side refusal fallback ("fallbacks": "default") is available.
const FALLBACK_MODELS = new Set(["claude-fable-5-2", "claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"]);

function anthropicClient(apiKey, baseUrl) {
  const opts = { maxRetries: 2, timeout: 600_000 };
  if (apiKey) opts.apiKey = apiKey;
  if (baseUrl && baseUrl !== PROVIDERS.anthropic.baseUrl) opts.baseURL = baseUrl;
  return new Anthropic(opts);
}

function anthropicError(e) {
  if (e instanceof Anthropic.AuthenticationError) return new ProviderError(`Authentication failed — check the API key. (${e.message})`, 401);
  if (e instanceof Anthropic.PermissionDeniedError) return new ProviderError(`Permission denied: ${e.message}`, 403);
  if (e instanceof Anthropic.NotFoundError) return new ProviderError(`Not found (is the model id right?): ${e.message}`, 404);
  if (e instanceof Anthropic.RateLimitError) return new ProviderError(`Rate limited — retry shortly. (${e.message})`, 429);
  if (e instanceof Anthropic.BadRequestError) return new ProviderError(`Bad request: ${e.message}`, 400);
  if (e instanceof Anthropic.APIConnectionError) return new ProviderError(`Could not reach Anthropic: ${e.message}`, 502);
  if (e instanceof Anthropic.APIError) return new ProviderError(`Anthropic API error ${e.status}: ${e.message}`, e.status || 502);
  if (e instanceof Anthropic.AnthropicError) {
    if (/authentication method/i.test(e.message)) return new ProviderError("No API key provided — add one in Settings.", 400);
    return new ProviderError(e.message, 400);
  }
  return e;
}

async function anthropicTest({ apiKey, baseUrl }) {
  const client = anthropicClient(apiKey, baseUrl);
  try {
    const page = await client.models.list({ limit: 100 });
    const models = (page.data || []).map((m) => m.id);
    return { ok: true, models, message: `Connected — ${models.length} models available` };
  } catch (e) {
    throw anthropicError(e);
  }
}

async function anthropicChat({ apiKey, baseUrl, model, system, messages, maxTokens, effort }) {
  const client = anthropicClient(apiKey, baseUrl);
  const params = {
    model,
    max_tokens: maxTokens || 16000,
    system,
    messages: messages.map((m) => ({ role: m.role, content: m.content })),
  };
  if (ADAPTIVE_RE.test(model)) {
    // Summarized thinking lets the UI show what the agent was reasoning about.
    params.thinking = { type: "adaptive", display: "summarized" };
    if (effort) params.output_config = { effort };
  }
  try {
    let res;
    if (FALLBACK_MODELS.has(model)) {
      // Server-side refusal fallback: if a safety classifier declines, the API
      // re-runs the request on a fallback model inside the same call.
      res = await client.beta.messages.create({
        ...params,
        betas: ["server-side-fallback-2026-07-01"],
        fallbacks: "default",
      });
    } else {
      res = await client.messages.create(params);
    }
    if (res.stop_reason === "refusal") {
      const why = res.stop_details?.explanation || res.stop_details?.category || "no details";
      throw new ProviderError(`The model declined this request (${why}).`, 422);
    }
    let text = "";
    let thinking = "";
    for (const block of res.content) {
      if (block.type === "text") text += block.text;
      else if (block.type === "thinking" && block.thinking) thinking += block.thinking + "\n";
    }
    return {
      text,
      thinking: thinking.trim(),
      model: res.model,
      stopReason: res.stop_reason,
      usage: { input: res.usage?.input_tokens, output: res.usage?.output_tokens },
    };
  } catch (e) {
    throw anthropicError(e);
  }
}

// ------------------------------------------------------- OpenAI-compatible

function bearer(apiKey) {
  return apiKey ? { Authorization: `Bearer ${apiKey}` } : {};
}

async function openaiTest({ apiKey, baseUrl, def }) {
  if (def.needsKey && !apiKey) throw new ProviderError("No API key provided.", 400);
  const res = await fetchWithTimeout(`${baseUrl}/models`, { headers: { ...bearer(apiKey) } }, 20_000);
  if (!res.ok) throw new ProviderError(await readError(res), res.status);
  const j = await res.json().catch(() => ({}));
  const models = (j.data || j.models || []).map((m) => m.id || m.name).filter(Boolean).sort();
  return { ok: true, models, message: `Connected — ${models.length} models available` };
}

async function openaiChat({ apiKey, baseUrl, model, system, messages, maxTokens, temperature, providerId, def }) {
  if (def.needsKey && !apiKey) throw new ProviderError("No API key provided.", 400);
  const body = {
    model,
    messages: [{ role: "system", content: system }, ...messages],
  };
  if (providerId === "openai") {
    // Newer OpenAI models use max_completion_tokens and only accept the default temperature.
    body.max_completion_tokens = maxTokens || 16000;
  } else {
    body.max_tokens = maxTokens || 8000;
    if (typeof temperature === "number") body.temperature = temperature;
  }
  const headers = { "Content-Type": "application/json", ...bearer(apiKey) };
  if (providerId === "openrouter") {
    headers["X-Title"] = "Multi-Agent Website Builder";
  }
  const res = await fetchWithTimeout(`${baseUrl}/chat/completions`, { method: "POST", headers, body: JSON.stringify(body) });
  if (!res.ok) throw new ProviderError(await readError(res), res.status);
  const j = await res.json();
  const choice = j.choices?.[0];
  const msg = choice?.message || {};
  return {
    text: typeof msg.content === "string" ? msg.content : (msg.content || []).map((p) => p.text || "").join(""),
    thinking: msg.reasoning_content || msg.reasoning || "",
    model: j.model || model,
    stopReason: choice?.finish_reason,
    usage: { input: j.usage?.prompt_tokens, output: j.usage?.completion_tokens },
  };
}

// ------------------------------------------------------------------ Gemini

async function geminiTest({ apiKey, baseUrl }) {
  if (!apiKey) throw new ProviderError("No API key provided.", 400);
  const res = await fetchWithTimeout(`${baseUrl}/models?pageSize=200`, { headers: { "x-goog-api-key": apiKey } }, 20_000);
  if (!res.ok) throw new ProviderError(await readError(res), res.status);
  const j = await res.json();
  const models = (j.models || [])
    .filter((m) => (m.supportedGenerationMethods || []).includes("generateContent"))
    .map((m) => m.name.replace(/^models\//, ""));
  return { ok: true, models, message: `Connected — ${models.length} models available` };
}

async function geminiChat({ apiKey, baseUrl, model, system, messages, maxTokens, temperature }) {
  if (!apiKey) throw new ProviderError("No API key provided.", 400);
  const body = {
    systemInstruction: { parts: [{ text: system }] },
    contents: messages.map((m) => ({ role: m.role === "assistant" ? "model" : "user", parts: [{ text: m.content }] })),
    generationConfig: { maxOutputTokens: maxTokens || 16000 },
  };
  if (typeof temperature === "number") body.generationConfig.temperature = temperature;
  const res = await fetchWithTimeout(`${baseUrl}/models/${encodeURIComponent(model)}:generateContent`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new ProviderError(await readError(res), res.status);
  const j = await res.json();
  const cand = j.candidates?.[0];
  if (!cand) throw new ProviderError(`Gemini returned no candidates${j.promptFeedback?.blockReason ? ` (blocked: ${j.promptFeedback.blockReason})` : ""}.`, 422);
  const parts = cand.content?.parts || [];
  return {
    text: parts.filter((p) => !p.thought).map((p) => p.text || "").join(""),
    thinking: parts.filter((p) => p.thought).map((p) => p.text || "").join("\n"),
    model,
    stopReason: cand.finishReason,
    usage: { input: j.usageMetadata?.promptTokenCount, output: j.usageMetadata?.candidatesTokenCount },
  };
}

// ---------------------------------------------------------------- dispatch

export async function testProvider(providerId, stored = {}) {
  const { def, apiKey, baseUrl } = resolve(providerId, {}, stored);
  const args = { apiKey, baseUrl, def, providerId };
  if (def.kind === "anthropic") return anthropicTest(args);
  if (def.kind === "gemini") return geminiTest(args);
  return openaiTest(args);
}

export async function chat(providerId, cfg = {}, stored = {}) {
  const { def, apiKey, baseUrl } = resolve(providerId, cfg, stored);
  const model = (cfg.model || "").trim() || (stored.model || "").trim() || def.defaultModel;
  if (!model) throw new ProviderError("No model configured for this provider.", 400);
  if (!cfg.system || !Array.isArray(cfg.messages) || cfg.messages.length === 0) {
    throw new ProviderError("system and messages are required.", 400);
  }
  const args = { ...cfg, apiKey, baseUrl, def, providerId, model };
  if (def.kind === "anthropic") return anthropicChat(args);
  if (def.kind === "gemini") return geminiChat(args);
  return openaiChat(args);
}
