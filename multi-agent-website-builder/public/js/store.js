// Persistent settings + agent roster (browser localStorage) and a tiny event bus.
import { DEFAULT_AGENTS } from "./agents.js";

const KEY = "mawb.settings.v1";
const AGENTS_KEY = "mawb.agents.v1";

export const bus = new EventTarget();
export const emit = (type, detail) => bus.dispatchEvent(new CustomEvent(type, { detail }));
export const on = (type, fn) => bus.addEventListener(type, (e) => fn(e.detail));

export const DEFAULT_GENERAL = {
  refineIterations: 1, // evaluator-driven improvement rounds
  evalThreshold: 85, // overall score that counts as "pass"
  speed: "normal", // slow | normal | fast | instant
  follow: true, // preview auto-scrolls to where agents are working
  fallbackToDemo: true, // if a provider call fails, use the offline generator for that step
  runQa: true,
  maxTokens: 16000,
  stream: true, // show model output live as it's generated
  visualReview: true, // send desktop + phone screenshots to the QA reviewer and evaluator
};

function safeGet(key) {
  try {
    return JSON.parse(localStorage.getItem(key) || "null");
  } catch {
    return null;
  }
}
function safeSet(key, value) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {}
}

export const state = {
  catalog: {}, // provider catalog from the server
  providers: {}, // id -> { enabled, baseUrl, model, hasKey, keyHint, envKey, status } (keys stay on the server)
  serverOnline: false,
  settings: {
    defaultProvider: "demo",
    general: { ...DEFAULT_GENERAL },
  },
  agents: structuredClone(DEFAULT_AGENTS),
};

export function loadState() {
  const s = safeGet(KEY);
  if (s) {
    state.settings.defaultProvider = s.defaultProvider || "demo";
    state.settings.general = { ...DEFAULT_GENERAL, ...(s.general || {}) };
  }
  const a = safeGet(AGENTS_KEY);
  if (Array.isArray(a) && a.length) state.agents = a;
}

export function saveSettings() {
  safeSet(KEY, state.settings);
  emit("settings-changed");
}

export function saveAgents() {
  safeSet(AGENTS_KEY, state.agents);
  emit("agents-changed");
}

export function resetAgents() {
  state.agents = structuredClone(DEFAULT_AGENTS);
  saveAgents();
}

export function providerCfg(id) {
  return state.providers[id] || { enabled: false, baseUrl: "", model: "", hasKey: false, status: null };
}

/** Providers that can be selected for agents: enabled in Settings. */
export function usableProviders() {
  return Object.keys(state.catalog).filter((id) => providerCfg(id).enabled);
}

export function providerLabel(id) {
  if (id === "demo") return "Offline demo";
  return state.catalog[id]?.label || id;
}

/** Resolve which provider + model an agent will actually use. */
export function resolveAgentProvider(agent) {
  const pid = !agent.provider || agent.provider === "default" ? state.settings.defaultProvider : agent.provider;
  if (pid === "demo" || !state.catalog[pid] || !state.serverOnline) return { provider: "demo", model: "offline" };
  const cfg = providerCfg(pid);
  const model = (agent.model || "").trim() || (cfg.model || "").trim() || state.catalog[pid].defaultModel;
  return { provider: pid, model, cfg };
}

export const SPEED = { slow: 1.6, normal: 1, fast: 0.45, instant: 0 };
export const speedFactor = () => SPEED[state.settings.general.speed] ?? 1;
export const sleep = (ms) => new Promise((r) => setTimeout(r, ms * speedFactor()));
