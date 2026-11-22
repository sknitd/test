// Builder-view UI: agent roster, activity feed, pipeline progress and the
// Plan / Design / Eval inspector.
import { state, resolveAgentProvider, providerLabel } from "./store.js";
import { RUBRIC, KINDS } from "./agents.js";
import { contrast } from "./site.js";

const $ = (s, r = document) => r.querySelector(s);
const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

const STATE_LABEL = { idle: "Idle", thinking: "Thinking", working: "Creating", done: "Done", error: "Error", off: "Disabled" };
const STAGES = [
  ["plan", "Plan"],
  ["design", "Design"],
  ["build", "Build"],
  ["review", "Review"],
  ["evaluate", "Evaluate"],
];

export class BuilderUI {
  constructor() {
    this.roster = $("#roster");
    this.feed = $("#feed");
    this.pipeline = $("#pipeline");
    this.states = new Map();
    this.usageByAgent = new Map();
    this.stageReached = -1;
    this.renderRoster();
    this.renderPipeline(null);
    for (const b of document.querySelectorAll(".itab")) b.addEventListener("click", () => this.showInspector(b.dataset.insp));
  }

  // ----------------------------------------------------------------- roster
  renderRoster() {
    const agents = state.agents;
    this.roster.innerHTML = agents
      .map((a) => {
        const st = a.enabled ? this.states.get(a.id)?.status || "idle" : "off";
        const detail = this.states.get(a.id)?.detail || "";
        const { provider, model } = resolveAgentProvider(a);
        return `<div class="ag ag-${st}" style="--c:${a.color}" data-id="${a.id}" title="${esc(a.role)}">
          <span class="ag-av">${a.icon || "🤖"}</span>
          <span class="ag-main"><b>${esc(a.name)}</b><small>${esc(a.role)}</small></span>
          <span class="ag-st"><i>${STATE_LABEL[st]}</i><small>${esc(detail || (a.enabled ? (provider === "demo" ? "offline demo" : model) : ""))}</small></span>
        </div>`;
      })
      .join("");
    $("#team-count").textContent = `${agents.filter((a) => a.enabled).length} agents`;
  }

  agentState(agent, status, detail = "") {
    this.states.set(agent.id, { status, detail });
    const el = this.roster.querySelector(`[data-id="${agent.id}"]`);
    if (!el) return;
    el.className = `ag ag-${status}`;
    el.querySelector(".ag-st i").textContent = STATE_LABEL[status] || status;
    el.querySelector(".ag-st small").textContent = detail || (status === "done" ? "✓" : "");
  }

  usage(agent, u) {
    const cur = this.usageByAgent.get(agent.id) || { calls: 0, ms: 0, input: 0, output: 0, provider: u.provider, model: u.model };
    cur.calls++;
    cur.ms += u.ms || 0;
    cur.input += u.usage?.input || 0;
    cur.output += u.usage?.output || 0;
    cur.provider = u.provider;
    cur.model = u.model;
    this.usageByAgent.set(agent.id, cur);
  }

  // -------------------------------------------------------------------- feed
  log({ agent, type = "info", title, text, reasoning, source, details }) {
    const el = document.createElement("div");
    el.className = `ev ev-${type}`;
    el.style.setProperty("--c", agent.color);
    const icon = { think: "💭", create: "🧱", info: "ℹ️", warn: "⚠️", error: "⛔", success: "🎉" }[type] || "•";
    const time = new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
    const det = details && Object.keys(details).length
      ? `<dl class="ev-dl">${Object.entries(details).map(([k, v]) => `<dt>${esc(k)}</dt><dd>${esc(typeof v === "object" ? JSON.stringify(v) : v)}</dd>`).join("")}</dl>`
      : "";
    el.innerHTML = `<div class="ev-h"><span class="ev-who">${agent.icon || ""} ${esc(agent.name)}</span><span class="ev-type">${icon}</span><time>${time}</time></div>
      <div class="ev-title">${esc(title || "")}${source && source !== "demo" ? ` <span class="src">${esc(source === "demo-fallback" ? "fallback" : providerLabel(source))}</span>` : ""}</div>
      ${text ? `<div class="ev-text">${esc(text)}</div>` : ""}
      ${det}
      ${reasoning ? `<details class="ev-reason"><summary>Model reasoning</summary><div>${esc(reasoning)}</div></details>` : ""}`;
    this.feed.appendChild(el);
    this.feed.scrollTop = this.feed.scrollHeight;
  }

  // ---------------------------------------------------------------- pipeline
  stage(name) {
    const idx = STAGES.findIndex(([k]) => k === name);
    if (idx >= 0) this.stageReached = Math.max(this.stageReached, idx);
    this.renderPipeline(name);
  }

  renderPipeline(current) {
    const terminal = ["done", "error", "stopped"].includes(current);
    this.pipeline.innerHTML =
      STAGES.map(([k, label], i) => {
        const cls = terminal ? (current === "done" ? "ok" : i <= this.stageReached ? "ok" : "") : k === current ? "now" : i < this.stageReached || (i <= this.stageReached && k !== current) ? "ok" : "";
        return `<span class="ps ${cls}"><i>${i + 1}</i>${label}</span>`;
      }).join('<span class="ps-sep"></span>') +
      (current === "error" ? `<span class="ps-flag err">failed</span>` : current === "stopped" ? `<span class="ps-flag">stopped</span>` : current === "done" ? `<span class="ps-flag ok">complete</span>` : "");
  }

  // --------------------------------------------------------------- lifecycle
  reset(site, note) {
    this.states.clear();
    this.usageByAgent.clear();
    this.stageReached = -1;
    this.shots = null;
    this.feed.innerHTML = "";
    this.renderRoster();
    if (note) this.log({ agent: { name: "History", color: "#94a3b8", icon: "🕘" }, type: "info", title: note, text: site.prompt });
    else this.log({ agent: { name: "You", color: "#94a3b8", icon: "🧑" }, type: "info", title: "New website request", text: site.prompt });
    $("#insp-plan").innerHTML = `<p class="muted">Atlas is planning…</p>`;
    $("#insp-design").innerHTML = `<p class="muted">Waiting for the designer…</p>`;
    $("#insp-eval").innerHTML = `<p class="muted">The evaluator scores the site once it is built.</p>`;
    this.showInspector("plan");
  }

  beginRefine(request) {
    this.states.clear();
    this.stageReached = -1;
    this.renderRoster();
    this.log({ agent: { name: "You", color: "#94a3b8", icon: "🧑" }, type: "info", title: "Change request", text: request });
  }

  done(site, failed = false) {
    this.renderUsage();
    document.dispatchEvent(new CustomEvent("build-finished", { detail: { site, failed } }));
  }

  showInspector(name) {
    for (const b of document.querySelectorAll(".itab")) b.classList.toggle("active", b.dataset.insp === name);
    for (const p of document.querySelectorAll(".insp")) p.hidden = p.id !== `insp-${name}`;
  }

  // -------------------------------------------------------------- inspector
  renderPlan(site) {
    const p = site.plan;
    if (!p) return;
    const owner = (id) => state.agents.find((a) => a.id === id);
    $("#insp-plan").innerHTML = `
      <h3 class="i-title">${esc(p.siteName)}</h3>
      <p class="i-tag">${esc(p.tagline)}</p>
      <div class="kv"><span>Type</span><b>${esc(p.siteType)}</b><span>Audience</span><b>${esc(p.audience)}</b><span>Tone</span><b>${esc(p.tone)}</b></div>
      ${p.goals?.length ? `<h4>Goals</h4><ul class="goals">${p.goals.map((g) => `<li>${esc(g)}</li>`).join("")}</ul>` : ""}
      <h4>Sections <small>${site.sections.filter((s) => s.html).length}/${site.sections.length} built</small></h4>
      <ol class="sec-list">${site.sections
        .map((s) => {
          const o = owner(s.owner);
          return `<li class="sec sec-${s.status || "planned"}"><span class="sec-dot" style="--c:${o?.color || "#cbd5e1"}"></span><span><b>${esc(s.title)}</b><small>${esc(site.layouts[s.id]?.layout || s.type)}${o ? ` · ${esc(o.name)}` : ""}${s.revisions ? ` · ${s.revisions} rev` : ""}</small></span></li>`;
        })
        .join("")}</ol>`;
  }

  renderDesign(site) {
    const t = site.tokens;
    if (!t) return;
    const sw = ["primary", "secondary", "accent", "bg", "surface", "text", "muted", "onPrimary"];
    $("#insp-design").innerHTML = `
      <div class="swatches">${sw.map((k) => `<div class="sw"><span style="background:${t[k]}"></span><small>${k}</small><code>${t[k]}</code></div>`).join("")}</div>
      <div class="type-sample" style="--hf:'${esc(t.headingFont)}';--bf:'${esc(t.bodyFont)}'">
        <div class="ts-h">${esc(t.headingFont)}</div><div class="ts-b">${esc(t.bodyFont)} — body text for paragraphs and UI.</div>
      </div>
      <div class="kv"><span>Radius</span><b>${esc(t.radius)}</b><span>Style</span><b>${esc(t.style)}</b>
        <span>Text contrast</span><b>${contrast(t.text, t.bg).toFixed(1)}:1</b><span>Button contrast</span><b>${contrast(t.onPrimary, t.primary).toFixed(1)}:1</b></div>
      <div class="btn-sample" style="background:${t.primary};color:${t.onPrimary};border-radius:${esc(t.radius)}">Primary button</div>`;
    // make fonts available to the sample
    const href = `https://fonts.googleapis.com/css2?family=${encodeURIComponent(t.headingFont).replace(/%20/g, "+")}:wght@700&family=${encodeURIComponent(t.bodyFont).replace(/%20/g, "+")}&display=swap`;
    let link = document.getElementById("insp-fonts");
    if (!link) {
      link = document.createElement("link");
      link.id = "insp-fonts";
      link.rel = "stylesheet";
      document.head.appendChild(link);
    }
    link.href = href;
  }

  renderQa(site) {
    this.renderEval(site);
  }

  renderEval(site) {
    const evs = site.evals;
    const last = evs.at(-1);
    const thr = state.settings.general.evalThreshold;
    const qa = site.qa;
    let html = "";
    if (last) {
      const pass = last.overall >= thr;
      const deg = Math.round((last.overall / 100) * 360);
      html += `<div class="score">
        <div class="ring ${pass ? "pass" : "fail"}" style="--deg:${deg}deg"><span>${last.overall}</span></div>
        <div><b>${pass ? "Passed" : "Below threshold"}</b><small>Threshold ${thr} · evaluation #${last.round}${last.source && last.source !== "demo" ? ` · ${esc(last.source === "demo-fallback" ? "fallback" : providerLabel(last.source))}` : ""}</small>
        <p>${esc(last.verdict)}</p></div></div>
        <div class="bars">${RUBRIC.map((r) => {
          const v = last.scores[r.key];
          const prev = evs.length > 1 ? evs.at(-2).scores[r.key] : null;
          const delta = prev != null && v !== prev ? `<em class="${v > prev ? "up" : "down"}">${v > prev ? "+" : ""}${v - prev}</em>` : "";
          return `<div class="bar"><span>${r.label}</span><div><i style="width:${v}%;background:${v >= 85 ? "#22c55e" : v >= 70 ? "#f59e0b" : "#ef4444"}"></i></div><b>${v}${delta}</b></div>`;
        }).join("")}</div>`;
      if (evs.length > 1) html += `<h4>Iterations</h4><div class="iters">${evs.map((e) => `<span class="${e.overall >= thr ? "ok" : ""}">#${e.round}: ${e.overall}</span>`).join("→")}</div>`;
      if (last.strengths?.length) html += `<h4>Strengths</h4><ul class="goals">${last.strengths.map((s) => `<li>${esc(s)}</li>`).join("")}</ul>`;
      if (last.improvements?.length) html += `<h4>Improvements requested</h4><ul class="issues">${last.improvements.map((i) => `<li><code>#${esc(i.sectionId)}</code> ${esc(i.instruction)}</li>`).join("")}</ul>`;
    }
    const checks = last?.checks || qa?.checks;
    if (checks) {
      html += `<h4>Automated checks <small>${checks.passed}/${checks.items.length} passed · prompt coverage ${Math.round(checks.keywordCoverage * 100)}%</small></h4>
        <ul class="checks">${checks.items.map((c) => `<li class="${c.pass ? "ok" : "bad"}"><span>${c.pass ? "✓" : "✗"}</span><div><b>${esc(c.label)}</b><small>${esc(c.detail)}</small></div></li>`).join("")}</ul>`;
    }
    if (qa) {
      html += `<h4>QA review <small>${esc(qa.summary)}</small></h4>${
        qa.issues.length
          ? `<ul class="issues">${qa.issues.map((i) => `<li><span class="sev sev-${esc(i.severity)}">${esc(i.severity)}</span> <code>#${esc(i.sectionId)}</code> ${esc(i.issue)}</li>`).join("")}</ul>`
          : `<p class="muted">No issues reported.</p>`
      }`;
    }
    html += this.shotsHtml(site);
    $("#insp-eval").innerHTML = html || `<p class="muted">The evaluator scores the site once it is built.</p>`;
    this.bindShots();
    if (last) this.showInspector("eval");
  }

  // Screenshots the QA reviewer and evaluator looked at.
  renderShots(shots) {
    this.shots = shots;
  }

  shotsHtml(site) {
    const sh = this.shots;
    if (sh) {
      const imgs = [...sh.desktop.map((u, i) => [u, `Desktop ${i + 1}`]), ...sh.mobile.map((u, i) => [u, `Phone ${i + 1}`])];
      return `<h4>What the reviewers saw <small>${imgs.length} screenshots sent to the models</small></h4>
        <div class="shots">${imgs.map(([u, l]) => `<button type="button" class="shot" data-full="${u}" title="${l} — click to enlarge"><img src="${u}" alt="${l} screenshot"><span>${l}</span></button>`).join("")}</div>`;
    }
    if (site.shots?.desktopThumb) {
      return `<h4>Last screenshots</h4><div class="shots"><button type="button" class="shot" data-full="${site.shots.desktopThumb}"><img src="${site.shots.desktopThumb}" alt="Desktop screenshot"><span>Desktop</span></button>${site.shots.mobileThumb ? `<button type="button" class="shot" data-full="${site.shots.mobileThumb}"><img src="${site.shots.mobileThumb}" alt="Phone screenshot"><span>Phone</span></button>` : ""}</div>`;
    }
    return "";
  }

  bindShots() {
    for (const b of document.querySelectorAll("#insp-eval .shot")) {
      b.onclick = () => {
        const box = document.createElement("div");
        box.className = "lightbox";
        box.innerHTML = `<button type="button" aria-label="Close">✕</button><img src="${b.dataset.full}" alt="Screenshot">`;
        box.onclick = () => box.remove();
        document.addEventListener("keydown", function esc(e) {
          if (e.key === "Escape") {
            box.remove();
            document.removeEventListener("keydown", esc);
          }
        });
        document.body.appendChild(box);
      };
    }
  }

  renderUsage() {
    const rows = [...this.usageByAgent.entries()];
    if (!rows.length) return;
    const tbl = `<h4>Agent calls</h4><table class="usage"><tr><th>Agent</th><th>Model</th><th>Calls</th><th>Tokens in/out</th><th>Time</th></tr>${rows
      .map(([id, u]) => {
        const a = state.agents.find((x) => x.id === id) || { name: id };
        return `<tr><td>${esc(a.name)}</td><td>${esc(u.provider === "demo" ? "offline" : u.model)}</td><td>${u.calls}</td><td>${u.input || u.output ? `${u.input.toLocaleString()} / ${u.output.toLocaleString()}` : "—"}</td><td>${(u.ms / 1000).toFixed(1)}s</td></tr>`;
      })
      .join("")}</table>`;
    $("#insp-eval").insertAdjacentHTML("beforeend", tbl);
  }
}

export { KINDS };
