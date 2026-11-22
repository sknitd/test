// Agents & Settings views.
import { state, saveAgents, saveSettings, resetAgents, providerCfg, providerLabel, usableProviders, DEFAULT_GENERAL } from "./store.js";
import { KINDS, CONTRACTS, CUSTOM_STAGES, newCustomAgent } from "./agents.js";
import { saveProvider, testConnection, loadProviders } from "./llm.js";

const $ = (s, r = document) => r.querySelector(s);
const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const debounce = (fn, ms = 300) => {
  let t;
  return (...a) => {
    clearTimeout(t);
    t = setTimeout(() => fn(...a), ms);
  };
};

function providerOptions(selected, { includeDefault = true } = {}) {
  const opts = [];
  if (includeDefault) opts.push(["default", `Team default (${providerLabel(state.settings.defaultProvider)})`]);
  opts.push(["demo", "Offline demo (no key)"]);
  for (const id of Object.keys(state.catalog)) {
    const cfg = providerCfg(id);
    opts.push([id, `${state.catalog[id].label}${cfg.enabled ? "" : " — not enabled"}`, !cfg.enabled]);
  }
  return opts.map(([v, l, dis]) => `<option value="${v}" ${v === selected ? "selected" : ""} ${dis && v !== selected ? "disabled" : ""}>${esc(l)}</option>`).join("");
}

/** Curated models (from each provider's docs) + any extra models your key can see. */
function modelList(id) {
  if (!state.catalog[id]) return [];
  const curated = state.catalog[id].models || [];
  const known = new Set(curated.map((m) => m.id));
  const live = (providerCfg(id).status?.models || []).filter((m) => !known.has(m)).map((m) => ({ id: m, name: m, note: "available to your key", live: true }));
  return [...curated, ...live];
}

const modelOptions = (models) =>
  models.map((m) => `<option value="${esc(m.id)}" label="${esc(m.live ? `${m.id} — from your account` : `${m.name}${m.status ? ` (${m.status})` : ""} — ${m.note || m.tier || ""}`)}"></option>`).join("");

function modelCatalogHtml(id) {
  const def = state.catalog[id];
  const curated = def.models || [];
  const cfg = providerCfg(id);
  const avail = new Set(cfg.status?.models || []);
  const extra = (cfg.status?.models || []).filter((m) => !curated.some((c) => c.id === m)).length;
  if (!curated.length && !extra) return id === "custom" ? `<p class="hint">Enter the model id your endpoint serves. "Save &amp; test" lists them.</p>` : "";
  const current = cfg.model || def.defaultModel;
  return `<details class="mlist"><summary>${curated.length} recommended model${curated.length === 1 ? "" : "s"}${extra ? ` · +${extra} more on your account` : ""} <small>checked against the docs ${esc(state.modelsChecked || "")}</small></summary>
    <ul>${curated
      .map(
        (m) => `<li class="${m.id === current ? "cur" : ""}">
        <div><b>${esc(m.name)}</b>${m.default ? ` <span class="tag def">default</span>` : ""}${m.status ? ` <span class="tag">${esc(m.status)}</span>` : ""} <span class="tag tier">${esc(m.tier)}</span>${cfg.status?.ok ? (avail.has(m.id) ? ` <span class="tag ok" title="Your key can use this model">✓ available</span>` : id === "ollama" ? ` <span class="tag" title="Not downloaded yet">not pulled</span>` : "") : ""}
          <code>${esc(m.id)}</code><small>${esc(m.note || "")}${m.ram ? ` · needs ${esc(m.ram)} RAM` : ""}</small>${id === "ollama" ? `<small class="pull">ollama pull ${esc(m.id)}</small>` : ""}</div>
        <button class="btn ghost sm" type="button" data-use="${esc(m.id)}" ${m.id === current ? "disabled" : ""}>${m.id === current ? "In use" : "Use"}</button>
      </li>`,
      )
      .join("")}</ul></details>`;
}

// ===================================================================== agents

export function renderAgents() {
  const root = $("#view-agents");
  const byStage = (k) => state.agents.filter((a) => a.kind === k);
  const chip = (a) => `<span class="pchip ${a.enabled ? "" : "off"}" style="--c:${a.color}">${a.icon} ${esc(a.name)}</span>`;
  const customs = (st) => state.agents.filter((a) => a.kind === "custom" && (a.customStage || "review") === st);
  root.innerHTML = `
  <div class="page">
    <div class="page-h">
      <div><h1>Agents</h1><p class="muted">Each agent has a <b>Think</b> brief (how it reasons) and a <b>Create</b> brief (what it produces). Agents in the same stage run in parallel; every agent can use a different provider and model.</p></div>
      <div class="row-btns"><button class="btn" id="add-dev">+ Add developer</button><button class="btn primary" id="add-agent">+ New agent</button><button class="btn ghost" id="reset-agents">Reset to defaults</button></div>
    </div>
    <div class="flow">
      <div class="fcol"><h5>1 · Plan</h5>${byStage("planner").map(chip).join("")}${customs("planning").map(chip).join("")}</div>
      <div class="farrow">→</div>
      <div class="fcol"><h5>2 · Design <small>parallel</small></h5>${[...byStage("architect"), ...byStage("designer"), ...byStage("copywriter")].map(chip).join("")}</div>
      <div class="farrow">→</div>
      <div class="fcol"><h5>3 · Build <small>parallel</small></h5>${byStage("developer").map(chip).join("")}${byStage("interaction").map(chip).join("")}</div>
      <div class="farrow">→</div>
      <div class="fcol"><h5>4 · Review</h5>${byStage("qa").map(chip).join("")}${customs("review").map(chip).join("")}</div>
      <div class="farrow">→</div>
      <div class="fcol"><h5>5 · Evaluate <small>⟲ refine</small></h5>${byStage("evaluator").map(chip).join("")}</div>
    </div>
    <div class="agent-grid">${state.agents.map(agentCard).join("")}</div>
  </div>`;

  root.querySelectorAll(".acard").forEach(bindAgentCard);
  $("#add-agent").onclick = () => {
    state.agents.push(newCustomAgent(state.agents.filter((a) => a.kind === "custom").length + 1));
    saveAgents();
    renderAgents();
    root.querySelector(".acard:last-child")?.scrollIntoView({ behavior: "smooth", block: "center" });
  };
  $("#add-dev").onclick = () => {
    const base = state.agents.find((a) => a.kind === "developer");
    const n = state.agents.filter((a) => a.kind === "developer").length + 1;
    const names = ["Nova", "Pixel", "Ember", "Rivet", "Cobalt", "Flux"];
    const colors = ["#8b5cf6", "#06b6d4", "#84cc16", "#f43f5e", "#0ea5e9", "#d946ef"];
    state.agents.splice(state.agents.lastIndexOf(state.agents.filter((a) => a.kind === "developer").at(-1)) + 1, 0, {
      ...(base ? structuredClone(base) : newCustomAgent(n)),
      id: `dev-${Date.now().toString(36)}`,
      kind: "developer",
      name: names[(n - 3 + names.length) % names.length],
      color: colors[n % colors.length],
      icon: "💻",
    });
    saveAgents();
    renderAgents();
  };
  $("#reset-agents").onclick = () => {
    if (!confirm("Reset all agents to the default team? Custom agents and edits will be lost.")) return;
    resetAgents();
    renderAgents();
  };
}

function agentDefaultModel(a) {
  const pid = !a.provider || a.provider === "default" ? state.settings.defaultProvider : a.provider;
  if (pid === "demo") return "offline demo (no model)";
  return providerCfg(pid).model || state.catalog[pid]?.defaultModel || "provider default";
}

function agentCard(a) {
  const contractKey = a.kind === "custom" ? `custom_${a.customStage || "review"}` : a.kind;
  const models = modelList(a.provider === "default" ? state.settings.defaultProvider : a.provider);
  return `<article class="acard ${a.enabled ? "" : "disabled"}" data-id="${a.id}" style="--c:${a.color}">
    <header>
      <span class="a-icon" contenteditable="true" spellcheck="false" data-f="icon" aria-label="Icon">${esc(a.icon)}</span>
      <div class="a-names">
        <input class="a-name" data-f="name" value="${esc(a.name)}" aria-label="Agent name">
        <input class="a-role" data-f="role" value="${esc(a.role)}" aria-label="Role">
      </div>
      <input type="color" data-f="color" value="${esc(a.color)}" aria-label="Cursor colour" title="Cursor colour">
      <label class="switch" title="Enabled"><input type="checkbox" data-f="enabled" ${a.enabled ? "checked" : ""}><span></span></label>
    </header>
    <div class="a-meta">
      <span class="kind">${esc(KINDS[a.kind]?.label || a.kind)}</span>
      ${a.kind === "custom" ? `<select data-f="customStage" aria-label="Runs">${Object.entries(CUSTOM_STAGES).map(([k, v]) => `<option value="${k}" ${a.customStage === k ? "selected" : ""}>${esc(v)}</option>`).join("")}</select>` : ""}
    </div>
    <div class="a-tabs" role="tablist">
      <button class="active" data-tab="think">Think</button><button data-tab="create">Create</button><button data-tab="model">Model</button><button data-tab="contract">Output contract</button>
    </div>
    <div class="a-pane" data-pane="think"><textarea data-f="think" rows="6" aria-label="How this agent thinks">${esc(a.think)}</textarea></div>
    <div class="a-pane" data-pane="create" hidden><textarea data-f="create" rows="6" aria-label="What this agent creates">${esc(a.create)}</textarea></div>
    <div class="a-pane" data-pane="model" hidden>
      <label>Provider<select data-f="provider">${providerOptions(a.provider || "default")}</select></label>
      <label>Model <small>(blank = provider default)</small><input data-f="model" list="ml-${a.id}" value="${esc(a.model)}" placeholder="${esc(agentDefaultModel(a))}"><datalist id="ml-${a.id}">${modelOptions(models)}</datalist></label>
      <div class="two">
        <label>Reasoning effort<select data-f="effort">${["low", "medium", "high", "xhigh", "max"].map((e) => `<option ${a.effort === e ? "selected" : ""}>${e}</option>`).join("")}</select></label>
        <label>Temperature <output>${a.temperature}</output><input type="range" min="0" max="1" step="0.1" data-f="temperature" value="${a.temperature}"></label>
      </div>
      <p class="hint">Effort applies to Claude models that support it; temperature applies to providers that accept it.</p>
    </div>
    <div class="a-pane" data-pane="contract" hidden><pre class="contract">${esc(CONTRACTS[contractKey] || "")}</pre><p class="hint">Fixed format the orchestrator parses — appended to the agent's system prompt.</p></div>
    <footer>
      ${["custom", "developer"].includes(a.kind) && state.agents.filter((x) => x.kind === a.kind).length > (a.kind === "developer" ? 1 : 0) ? `<button class="btn ghost danger" data-del>Remove</button>` : "<span></span>"}
      <span class="saved" hidden>Saved ✓</span>
    </footer>
  </article>`;
}

function bindAgentCard(card) {
  const agent = state.agents.find((a) => a.id === card.dataset.id);
  const flash = debounce(() => {
    const s = card.querySelector(".saved");
    s.hidden = false;
    setTimeout(() => (s.hidden = true), 1200);
  }, 150);
  const persist = debounce(() => {
    saveAgents();
    flash();
  }, 350);
  card.querySelectorAll("[data-f]").forEach((el) => {
    const f = el.dataset.f;
    const handler = () => {
      let v = el.type === "checkbox" ? el.checked : el.isContentEditable ? el.textContent.trim().slice(0, 4) : el.value;
      if (f === "temperature") {
        v = Number(v);
        el.previousElementSibling.textContent = v;
      }
      agent[f] = v;
      if (f === "color") card.style.setProperty("--c", v);
      if (f === "enabled") card.classList.toggle("disabled", !v);
      persist();
      if (["enabled", "name", "icon", "color", "customStage"].includes(f)) refreshFlow();
      if (f === "provider") {
        const models = modelList(v === "default" ? state.settings.defaultProvider : v);
        card.querySelector("datalist").innerHTML = modelOptions(models);
        card.querySelector('[data-f="model"]').placeholder = agentDefaultModel(agent);
      }
    };
    el.addEventListener(el.type === "checkbox" || el.tagName === "SELECT" ? "change" : "input", handler);
  });
  card.querySelectorAll(".a-tabs button").forEach((b) =>
    b.addEventListener("click", () => {
      card.querySelectorAll(".a-tabs button").forEach((x) => x.classList.toggle("active", x === b));
      card.querySelectorAll(".a-pane").forEach((p) => (p.hidden = p.dataset.pane !== b.dataset.tab));
    }),
  );
  card.querySelector("[data-del]")?.addEventListener("click", () => {
    if (!confirm(`Remove ${agent.name}?`)) return;
    state.agents = state.agents.filter((a) => a !== agent);
    saveAgents();
    renderAgents();
  });
}

const refreshFlow = debounce(() => {
  const scroll = window.scrollY;
  const active = document.activeElement;
  const id = active?.closest?.(".acard")?.dataset.id;
  const f = active?.dataset?.f;
  renderAgents();
  window.scrollTo(0, scroll);
  if (id && f) {
    const el = document.querySelector(`.acard[data-id="${id}"] [data-f="${f}"]`);
    el?.focus();
  }
}, 600);

// =================================================================== settings

export function renderSettings() {
  const root = $("#view-settings");
  const g = state.settings.general;
  root.innerHTML = `
  <div class="page">
    <div class="page-h"><div><h1>Settings</h1><p class="muted">Connect one or more LLM providers. API keys are stored on the local server (<code>data/providers.json</code>) and never sent back to the browser.</p></div></div>
    ${state.serverOnline ? "" : `<div class="banner err">The local server isn't reachable, so only the offline demo is available. Start it with <code>npm start</code> and reload.</div>`}
    <section class="card-s">
      <h2>Team defaults</h2>
      <div class="grid-form">
        <label>Default provider for all agents<select id="g-default">${providerOptions(state.settings.defaultProvider, { includeDefault: false })}</select>
          <small>Agents set to “Team default” use this. Individual agents can override it on the Agents tab.</small></label>
        <label>Animation speed<select id="g-speed">${["slow", "normal", "fast", "instant"].map((s) => `<option ${g.speed === s ? "selected" : ""}>${s}</option>`).join("")}</select></label>
        <label>Evaluation pass threshold <output>${g.evalThreshold}</output><input id="g-threshold" type="range" min="50" max="100" value="${g.evalThreshold}"><small>Below this, the evaluator sends the developers back to improve the site.</small></label>
        <label>Max refinement rounds<select id="g-iters">${[0, 1, 2, 3].map((n) => `<option ${g.refineIterations === n ? "selected" : ""}>${n}</option>`).join("")}</select></label>
        <label>Max output tokens per call<input id="g-maxtok" type="number" min="1000" max="64000" step="1000" value="${g.maxTokens}"></label>
        <div class="checks-col">
          <label class="chk"><input type="checkbox" id="g-qa" ${g.runQa ? "checked" : ""}> Run the QA reviewer before evaluation</label>
          <label class="chk"><input type="checkbox" id="g-fallback" ${g.fallbackToDemo ? "checked" : ""}> If a provider call fails, use the offline generator for that step</label>
          <label class="chk"><input type="checkbox" id="g-follow" ${g.follow ? "checked" : ""}> Preview follows the agents while they work</label>
          <label class="chk"><input type="checkbox" id="g-stream" ${g.stream !== false ? "checked" : ""}> Stream model output live (code appears as it's written)</label>
          <label class="chk"><input type="checkbox" id="g-visual" ${g.visualReview !== false ? "checked" : ""}> Visual review: send desktop &amp; phone screenshots to the QA reviewer and evaluator</label>
        </div>
      </div>
      <div class="row-btns"><button class="btn ghost" id="g-reset">Restore defaults</button></div>
    </section>
    <h2 class="sec-h">Providers</h2>
    <div class="prov-grid">${Object.keys(state.catalog).map(providerCard).join("")}</div>
  </div>`;

  const save = () => {
    saveSettings();
  };
  $("#g-default").onchange = (e) => {
    state.settings.defaultProvider = e.target.value;
    save();
  };
  $("#g-speed").onchange = (e) => {
    g.speed = e.target.value;
    save();
  };
  $("#g-threshold").oninput = (e) => {
    g.evalThreshold = Number(e.target.value);
    e.target.previousElementSibling.textContent = g.evalThreshold;
    save();
  };
  $("#g-iters").onchange = (e) => {
    g.refineIterations = Number(e.target.value);
    save();
  };
  $("#g-maxtok").onchange = (e) => {
    g.maxTokens = Math.max(1000, Math.min(64000, Number(e.target.value) || 16000));
    save();
  };
  $("#g-qa").onchange = (e) => {
    g.runQa = e.target.checked;
    save();
  };
  $("#g-fallback").onchange = (e) => {
    g.fallbackToDemo = e.target.checked;
    save();
  };
  $("#g-follow").onchange = (e) => {
    g.follow = e.target.checked;
    save();
  };
  $("#g-stream").onchange = (e) => {
    g.stream = e.target.checked;
    save();
  };
  $("#g-visual").onchange = (e) => {
    g.visualReview = e.target.checked;
    save();
  };
  $("#g-reset").onclick = () => {
    state.settings.general = { ...DEFAULT_GENERAL };
    save();
    renderSettings();
  };
  root.querySelectorAll(".pcard").forEach(bindProviderCard);
}

function statusHtml(cfg) {
  const s = cfg.status;
  if (!s) return `<span class="pill">Not tested</span>`;
  const when = s.testedAt ? new Date(s.testedAt).toLocaleString() : "";
  return s.ok
    ? `<span class="pill ok">● Connected</span><small>${esc(s.message)}${s.latencyMs ? ` · ${s.latencyMs} ms` : ""} · ${esc(when)}</small>`
    : `<span class="pill bad">● Failed</span><small class="err-text">${esc(s.message)}</small>`;
}

function providerCard(id) {
  const def = state.catalog[id];
  const cfg = providerCfg(id);
  const models = modelList(id);
  const keyPh = cfg.hasKey ? `Saved (${cfg.keyHint}) — type to replace` : cfg.envKey ? "Using the server's environment variable" : def.needsKey ? "Paste your API key" : "Optional";
  return `<article class="pcard ${cfg.enabled ? "on" : ""}" data-id="${id}">
    <header><div><h3>${esc(def.label)}</h3><small>${esc(({ "openai-compatible": "OpenAI-compatible API", openai: "OpenAI API", anthropic: "Anthropic Messages API · official SDK", gemini: "Gemini API" })[def.kind] || def.kind)}</small></div>
      <label class="switch" title="Enable"><input type="checkbox" data-p="enabled" ${cfg.enabled ? "checked" : ""}><span></span></label></header>
    <label>API key<div class="keyrow"><input type="password" data-p="apiKey" autocomplete="off" spellcheck="false" placeholder="${esc(keyPh)}"><button class="btn ghost sm" data-show type="button" aria-label="Show key">👁</button></div></label>
    <label>Base URL<input data-p="baseUrl" value="${esc(cfg.baseUrl)}" placeholder="${esc(def.baseUrl || "https://your-endpoint/v1")}"></label>
    <label>Default model<input data-p="model" list="pm-${id}" value="${esc(cfg.model)}" placeholder="${esc(def.defaultModel || "model id")}"><datalist id="pm-${id}">${modelOptions(models)}</datalist></label>
    ${id === "ollama" ? `<p class="hint">Runs models on your own computer, no key needed. Install <a href="https://ollama.com/download" target="_blank" rel="noopener">Ollama</a>, run <code>ollama pull ${esc(def.defaultModel)}</code>, then Save &amp; test. The builder's server must run on the same machine.</p>` : ""}
    ${id === "custom" ? `<p class="hint">Any OpenAI-compatible server, e.g. LM Studio <code>http://localhost:1234/v1</code>, llama.cpp <code>http://localhost:8080/v1</code> or vLLM <code>http://localhost:8000/v1</code>.</p>` : ""}
    ${modelCatalogHtml(id)}
    <div class="pstatus">${statusHtml(cfg)}</div>
    <footer>
      <button class="btn primary sm" data-test>Save &amp; test connection</button>
      <button class="btn sm" data-save>Save</button>
      ${cfg.hasKey ? `<button class="btn ghost sm danger" data-clear>Remove key</button>` : ""}
      ${def.docs ? `<a class="link" href="${esc(def.docs)}" target="_blank" rel="noopener">${def.needsKey ? "Get a key ↗" : "Docs ↗"}</a>` : ""}
    </footer>
  </article>`;
}

function bindProviderCard(card) {
  const id = card.dataset.id;
  const val = (p) => card.querySelector(`[data-p="${p}"]`);
  const status = card.querySelector(".pstatus");
  const patch = () => ({ enabled: val("enabled").checked, apiKey: val("apiKey").value, baseUrl: val("baseUrl").value, model: val("model").value });
  const doSave = async () => {
    await saveProvider(id, patch());
    val("apiKey").value = "";
  };
  card.querySelectorAll("[data-use]").forEach((b) =>
    b.addEventListener("click", async () => {
      val("model").value = b.dataset.use;
      try {
        await doSave();
      } catch (e) {
        status.innerHTML = `<span class="pill bad">Error</span><small class="err-text">${esc(e.message)}</small>`;
        return;
      }
      const open = card.querySelector(".mlist")?.open;
      renderSettings();
      if (open) document.querySelector(`.pcard[data-id="${id}"] .mlist`)?.setAttribute("open", "");
    }),
  );
  card.querySelector("[data-show]").onclick = () => {
    const k = val("apiKey");
    k.type = k.type === "password" ? "text" : "password";
  };
  val("enabled").onchange = async () => {
    try {
      await doSave();
      renderSettings();
    } catch (e) {
      status.innerHTML = `<span class="pill bad">Error</span><small class="err-text">${esc(e.message)}</small>`;
    }
  };
  card.querySelector("[data-save]").onclick = async () => {
    try {
      await doSave();
      renderSettings();
    } catch (e) {
      status.innerHTML = `<span class="pill bad">Error</span><small class="err-text">${esc(e.message)}</small>`;
    }
  };
  card.querySelector("[data-test]").onclick = async (ev) => {
    const btn = ev.currentTarget;
    btn.disabled = true;
    status.innerHTML = `<span class="pill">Testing…</span>`;
    try {
      // Testing a provider implies you want to use it.
      val("enabled").checked = true;
      await doSave();
      await testConnection(id);
    } catch {
      /* status is stored server-side and re-rendered below */
    }
    renderSettings();
  };
  card.querySelector("[data-clear]")?.addEventListener("click", async () => {
    if (!confirm("Remove the saved API key for this provider?")) return;
    await saveProvider(id, { clearKey: true });
    renderSettings();
  });
}

export async function refreshProviders() {
  try {
    await loadProviders();
  } catch {
    state.serverOnline = false;
  }
  // Fall back to the demo if the default provider is no longer usable.
  if (state.serverOnline && state.settings.defaultProvider !== "demo" && !usableProviders().includes(state.settings.defaultProvider)) {
    state.settings.defaultProvider = "demo";
    saveSettings();
  }
}
