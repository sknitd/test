// The orchestrator runs the agent pipeline:
//   Plan → (Architecture ‖ Visual design ‖ Copy) → parallel Build → Interaction
//   → QA review & fixes → custom reviewers → Evaluate ⟲ refine until the score passes.
// Each step calls the agent's configured provider (or the offline demo), and
// drives the canvas cursors / code view so the build is visible as it happens.

import { state, sleep, speedFactor, resolveAgentProvider, providerLabel } from "./store.js";
import { RUBRIC } from "./agents.js";
import { systemPrompt, callProvider, parseJson, parseSection, extractTag } from "./llm.js";
import { emptySite, normalizeTokens, assembleDocument } from "./site.js";
import { runChecks } from "./checks.js";
import * as demo from "./demo.js";

class Aborted extends Error {}

const SYSTEM_AGENT = { id: "system", name: "System", role: "Fallback", color: "#64748b", icon: "⚙️", think: "", create: "" };

const slug = (s) =>
  String(s || "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(0, 40) || "section";

export class Orchestrator {
  constructor({ canvas, code, ui }) {
    this.canvas = canvas;
    this.code = code;
    this.ui = ui;
    this.site = null;
    this.running = false;
    this.abortFlag = false;
  }

  stop() {
    this.abortFlag = true;
  }

  check() {
    if (this.abortFlag) throw new Aborted("Stopped by user");
  }

  agentsOf(kind) {
    return state.agents.filter((a) => a.enabled && a.kind === kind);
  }
  firstOf(kind) {
    return this.agentsOf(kind)[0] || null;
  }

  // ------------------------------------------------------------- agent call

  /**
   * Run one agent step. `llm` describes the real call; `fallback` produces the
   * offline result. Returns { data, thinking, source }.
   */
  async step(agent, { contract, user, parse = "json", fallback, label }) {
    this.check();
    const a = agent || SYSTEM_AGENT;
    const { provider, model } = agent ? resolveAgentProvider(agent) : { provider: "demo", model: "offline" };
    this.ui.agentState(a, "thinking", label);
    const started = performance.now();
    if (provider === "demo") {
      await sleep(500 + Math.random() * 900);
      this.check();
      const data = fallback();
      this.ui.usage(a, { provider: "demo", model: "offline", ms: performance.now() - started });
      return { data, thinking: "", source: "demo" };
    }
    try {
      const res = await callProvider(a, { system: systemPrompt(a, contract), user });
      this.check();
      let data;
      if (parse === "json") data = parseJson(res.text);
      else if (parse === "section") data = parseSection(res.text, label);
      else if (parse === "js") {
        const js = extractTag(res.text, "js");
        if (!js) throw new Error("Response did not contain a <js> block");
        data = { thoughts: extractTag(res.text, "thoughts") || "", js: js.replace(/<\/?script[^>]*>/gi, "") };
      }
      this.ui.usage(a, { provider, model: res.model || model, ms: res.latencyMs, usage: res.usage });
      return { data, thinking: res.thinking || "", source: provider };
    } catch (e) {
      if (e instanceof Aborted) throw e;
      this.ui.log({ agent: a, type: "error", title: `${providerLabel(provider)} step failed`, text: e.message });
      if (!state.settings.general.fallbackToDemo) {
        this.ui.agentState(a, "error", e.message);
        throw e;
      }
      this.ui.log({ agent: a, type: "warn", title: "Falling back to the offline generator for this step" });
      return { data: fallback(), thinking: "", source: "demo-fallback" };
    }
  }

  context() {
    const s = this.site;
    const p = s.plan || {};
    return {
      request: s.prompt,
      siteName: p.siteName,
      tagline: p.tagline,
      siteType: p.siteType,
      audience: p.audience,
      tone: p.tone,
      goals: p.goals,
      guidance: s.guidance.length ? s.guidance : undefined,
    };
  }

  // ------------------------------------------------------------------ build

  async build(prompt) {
    this.running = true;
    this.abortFlag = false;
    this.site = emptySite(prompt);
    const site = this.site;
    this.code.setSite(site);
    this.canvas.removeCursors();
    this.ui.reset(site);
    await this.canvas.reset();
    const t0 = performance.now();
    try {
      await this.planStage();
      await this.customStage("planning");
      await this.designStage();
      await this.buildStage(site.sections);
      await this.interactionStage();
      if (state.settings.general.runQa) await this.qaStage();
      await this.customStage("review");
      await this.evalLoop();
      this.finish(t0);
    } catch (e) {
      this.fail(e);
    } finally {
      this.running = false;
    }
  }

  finish(t0) {
    this.canvas.hideAll();
    this.canvas.clearMarks("box");
    for (const a of state.agents) if (a.enabled) this.ui.agentState(a, "done");
    this.ui.stage("done");
    const last = this.site.evals.at(-1);
    this.ui.log({
      agent: SYSTEM_AGENT,
      type: "success",
      title: `Website ready in ${((performance.now() - t0) / 1000).toFixed(1)}s`,
      text: last
        ? `Final evaluation score: ${last.overall}/100${last.overall < state.settings.general.evalThreshold ? ` (below the ${state.settings.general.evalThreshold} threshold after ${this.site.evals.length} evaluation(s) — raise "Max refinement rounds" in Settings or refine with a prompt)` : ""} — ${last.verdict || ""}`
        : "",
    });
    this.ui.done(this.site);
  }

  fail(e) {
    this.canvas.hideAll();
    if (e instanceof Aborted) {
      this.ui.log({ agent: SYSTEM_AGENT, type: "warn", title: "Build stopped" });
      this.ui.stage("stopped");
    } else {
      console.error(e);
      this.ui.log({ agent: SYSTEM_AGENT, type: "error", title: "Build failed", text: e.message });
      this.ui.stage("error");
    }
    this.ui.done(this.site, true);
  }

  logResult(agent, res, title, extra) {
    this.ui.log({
      agent,
      type: "think",
      title,
      text: res.data?.thoughts || "",
      reasoning: res.thinking,
      source: res.source,
      details: extra,
    });
    if (res.data?.thoughts) this.canvas.say(agent, res.data.thoughts, 4200);
  }

  // ---- 1. plan
  async planStage() {
    this.ui.stage("plan");
    const site = this.site;
    const planner = this.firstOf("planner");
    const pa = planner || SYSTEM_AGENT;
    this.canvas.point(pa, 0.5, 0.35, "reading the brief");
    this.canvas.say(pa, "Reading the brief…");
    const res = await this.step(planner, {
      contract: "planner",
      user: `User request:\n"""${site.prompt}"""\n\nPlan the website.`,
      fallback: () => demo.demoPlan(site.prompt),
    });
    const plan = this.sanitizePlan(res.data) || demo.demoPlan(site.prompt);
    site.plan = plan;
    site.sections = plan.sections.map((s) => ({ ...s, html: "", css: "", status: "planned", owner: null }));
    this.logResult(pa, res, `Planned "${plan.siteName}" — ${plan.sections.length} sections`, { Type: plan.siteType, Audience: plan.audience, Tone: plan.tone });
    this.ui.renderPlan(site);
    this.ui.agentState(pa, "working", "laying out sections");
    for (const s of site.sections) {
      this.check();
      this.canvas.addSkeleton(s);
      this.canvas.moveTo(pa, s.id, { fy: 0.4, wander: false, state: `adding ${s.title}` });
      await sleep(260);
    }
    this.code.touch();
    this.ui.agentState(pa, "done");
    this.canvas.hide(pa);
  }

  sanitizePlan(p) {
    if (!p || !Array.isArray(p.sections) || p.sections.length < 2) return null;
    const seen = new Set();
    let sections = p.sections
      .filter((s) => s && (s.id || s.title || s.type))
      .map((s) => {
        let id = slug(s.id || s.title || s.type);
        while (seen.has(id)) id += "-2";
        seen.add(id);
        return { id, type: slug(s.type || "custom"), title: String(s.title || s.type || id).slice(0, 60), purpose: String(s.purpose || "") };
      });
    if (sections[0].type !== "nav") sections.unshift({ id: seen.has("nav") ? "site-nav" : "nav", type: "nav", title: "Navigation", purpose: "Site navigation" });
    if (sections.at(-1).type !== "footer") sections.push({ id: seen.has("footer") ? "site-footer" : "footer", type: "footer", title: "Footer", purpose: "Footer" });
    sections = sections.slice(0, 14);
    return {
      thoughts: p.thoughts,
      siteName: String(p.siteName || "Untitled").slice(0, 60),
      tagline: String(p.tagline || ""),
      siteType: String(p.siteType || "other"),
      audience: String(p.audience || ""),
      goals: Array.isArray(p.goals) ? p.goals.map(String) : [],
      tone: String(p.tone || ""),
      sections,
    };
  }

  // ---- custom agents (planning guidance / review requests)
  async customStage(stage) {
    const agents = this.agentsOf("custom").filter((a) => (a.customStage || "review") === stage);
    if (!agents.length) return;
    this.ui.stage(stage === "planning" ? "plan" : "review");
    const site = this.site;
    await Promise.all(
      agents.map(async (agent) => {
        this.canvas.point(agent, 0.3 + Math.random() * 0.4, 0.3, stage === "planning" ? "advising" : "reviewing");
        const user =
          stage === "planning"
            ? `Project context:\n${JSON.stringify(this.context(), null, 2)}\n\nPlanned sections:\n${JSON.stringify(site.plan.sections, null, 2)}`
            : `Project context:\n${JSON.stringify(this.context(), null, 2)}\n\nSection ids: ${site.sections.map((s) => s.id).join(", ")}\n\nCurrent page HTML:\n${assembleDocument(site)}`;
        const res = await this.step(agent, { contract: `custom_${stage}`, user, fallback: () => demo.demoCustom(agent, stage) });
        this.logResult(agent, res, stage === "planning" ? "Shared guidance with the team" : res.data?.summary || "Review complete");
        if (stage === "planning" && res.data?.guidance) site.guidance.push(`${agent.name} (${agent.role}): ${res.data.guidance}`);
        if (stage === "review" && Array.isArray(res.data?.changes) && res.data.changes.length) {
          await this.fixPass(res.data.changes.map((c) => ({ sectionId: c.sectionId, instruction: c.instruction, from: agent })));
        }
        this.ui.agentState(agent, "done");
        this.canvas.hide(agent);
      }),
    );
    if (stage === "review") await this.canvas.renderFull(site);
  }

  // ---- 2. architecture + visual design + copy, in parallel
  async designStage(onlySections) {
    this.ui.stage("design");
    const site = this.site;
    const targets = onlySections || site.sections;
    const planJson = JSON.stringify({ ...this.context(), sections: targets.map(({ id, type, title, purpose }) => ({ id, type, title, purpose })) }, null, 2);

    const architect = async () => {
      const agent = this.firstOf("architect");
      const a = agent || SYSTEM_AGENT;
      this.canvas.moveTo(a, targets[0]?.id, { state: "thinking" });
      const res = await this.step(agent, {
        contract: "architect",
        user: `Plan:\n${planJson}`,
        fallback: () => demo.demoArchitect({ ...site, plan: { ...site.plan, sections: targets } }),
      });
      const d = res.data || {};
      if (Array.isArray(d.nav) && !onlySections) site.nav = d.nav.filter((n) => n && n.label && n.href).slice(0, 7);
      Object.assign(site.layouts, d.layouts && typeof d.layouts === "object" ? d.layouts : {});
      this.logResult(a, res, "Information architecture ready", { Navigation: site.nav.map((n) => n.label).join(" · ") });
      this.ui.agentState(a, "working", "annotating layouts");
      for (const s of targets) {
        this.check();
        this.canvas.moveTo(a, s.id, { fy: 0.12, wander: false, state: "layout" });
        await sleep(330);
        this.canvas.annotate(s.id, { layout: site.layouts[s.id]?.layout || s.type });
      }
      this.ui.agentState(a, "done");
      this.canvas.hide(a);
    };

    const designer = async () => {
      if (onlySections) return;
      const agent = this.firstOf("designer");
      const a = agent || SYSTEM_AGENT;
      this.canvas.point(a, 0.75, 0.25, "picking a palette");
      const res = await this.step(agent, {
        contract: "designer",
        user: `Project:\n${JSON.stringify(this.context(), null, 2)}`,
        fallback: () => demo.demoDesigner(site),
      });
      site.tokens = normalizeTokens(res.data?.tokens || demo.demoDesigner(site).tokens);
      this.logResult(a, res, "Design system created", { Style: site.tokens.style, Fonts: `${site.tokens.headingFont} / ${site.tokens.bodyFont}` });
      this.ui.agentState(a, "working", "applying tokens");
      // sweep across the page while the palette is applied
      for (const s of site.sections.filter((_, i) => i % 2 === 0)) {
        this.check();
        this.canvas.moveTo(a, s.id, { wander: true, state: "styling" });
        await sleep(240);
      }
      this.canvas.setTokens(site.tokens);
      this.ui.renderDesign(site);
      this.code.touch();
      await sleep(300);
      this.ui.agentState(a, "done");
      this.canvas.hide(a);
    };

    const writer = async () => {
      const agent = this.firstOf("copywriter");
      const a = agent || SYSTEM_AGENT;
      this.canvas.point(a, 0.25, 0.5, "drafting");
      const res = await this.step(agent, {
        contract: "copywriter",
        user: `Plan:\n${planJson}`,
        fallback: () => demo.demoCopy({ ...site, plan: { ...site.plan, sections: targets } }),
      });
      const fb = demo.demoCopy({ ...site, plan: { ...site.plan, sections: targets } }).copy;
      const copy = res.data?.copy && typeof res.data.copy === "object" ? res.data.copy : {};
      for (const s of targets) site.copy[s.id] = copy[s.id] || fb[s.id];
      this.logResult(a, res, `Wrote copy for ${targets.length} sections`);
      this.ui.agentState(a, "working", "writing headlines");
      for (const s of targets) {
        this.check();
        const h = site.copy[s.id]?.heading || s.title;
        this.canvas.moveTo(a, s.id, { fy: 0.3, fx: 0.2, wander: false, state: "writing" });
        const steps = speedFactor() ? Math.min(14, h.length) : 1;
        for (let i = 1; i <= steps; i++) {
          this.canvas.annotate(s.id, { heading: h.slice(0, Math.ceil((h.length * i) / steps)) });
          await sleep(28);
        }
        await sleep(90);
      }
      this.ui.agentState(a, "done");
      this.canvas.hide(a);
    };

    await Promise.all([architect(), designer(), writer()]);
    if (!site.tokens) site.tokens = normalizeTokens(demo.demoDesigner(site).tokens);
  }

  // ---- 3. parallel build by the developer agents
  devPrompt(section) {
    const site = this.site;
    return [
      `Project:\n${JSON.stringify(this.context(), null, 2)}`,
      `Design tokens (already available as CSS variables):\n${JSON.stringify(site.tokens, null, 2)}`,
      `All sections on the page (for in-page links): ${site.sections.map((s) => `#${s.id} (${s.title})`).join(", ")}`,
      section.type === "nav" || section.type === "footer" ? `Navigation items:\n${JSON.stringify(site.nav, null, 2)}` : "",
      `YOUR SECTION — build ONLY this one:\n${JSON.stringify({ id: section.id, type: section.type, title: section.title, purpose: section.purpose }, null, 2)}`,
      `Layout spec from the architect:\n${JSON.stringify(site.layouts[section.id] || {}, null, 2)}`,
      `Copy from the copywriter (use it verbatim where sensible):\n${JSON.stringify(site.copy[section.id] || {}, null, 2)}`,
      section.type === "hero" ? "This section must contain the page's only <h1>." : "Use <h2> for the section heading (never <h1>).",
    ]
      .filter(Boolean)
      .join("\n\n");
  }

  async typeSection(agent, section, html, css) {
    this.code.startTyping(section.id, agent);
    this.canvas.setSectionCss(section.id, css);
    const animate = speedFactor() > 0;
    const total = html.length + css.length;
    const ticks = animate ? Math.max(12, Math.min(70, Math.round(total / 60))) : 1;
    for (let i = 1; i <= ticks; i++) {
      this.check();
      const n = Math.ceil((total * i) / ticks);
      const h = html.slice(0, Math.min(n, html.length));
      const c = n > html.length ? css.slice(0, n - html.length) : "";
      const cut = h.lastIndexOf(">");
      this.canvas.setSectionHtml(section.id, cut > 0 ? h.slice(0, cut + 1) : "");
      this.code.updateTyping(section.id, { html: h, css: c });
      this.canvas.progress(agent, Math.min(1, n / html.length));
      await sleep(42);
    }
    this.canvas.setSectionHtml(section.id, html);
    this.code.stopTyping(section.id);
  }

  async buildStage(sections) {
    this.ui.stage("build");
    const site = this.site;
    let devs = this.agentsOf("developer");
    if (!devs.length) devs = [null];
    const queue = [...sections];
    const worker = async (agent) => {
      const a = agent || SYSTEM_AGENT;
      while (queue.length) {
        this.check();
        const section = queue.shift();
        section.owner = a.id;
        section.status = "building";
        this.ui.renderPlan(site);
        this.canvas.annotate(section.id, { status: `${a.name} is coding…`, color: a.color, active: true });
        this.canvas.moveTo(a, section.id, { state: `thinking · ${section.title}` });
        const res = await this.step(agent, {
          contract: "developer",
          user: this.devPrompt(section),
          parse: "section",
          label: section.id,
          fallback: () => demo.demoSection(section, site),
        });
        this.ui.log({ agent: a, type: "think", title: `Building ${section.title}`, text: res.data.thoughts, reasoning: res.thinking, source: res.source });
        this.ui.agentState(a, "working", `coding ${section.title}`);
        this.canvas.setCursorState(a, `coding · ${section.title}`);
        this.canvas.say(a, res.data.thoughts, 3000);
        await this.typeSection(a, section, res.data.html, res.data.css);
        section.html = res.data.html;
        section.css = res.data.css;
        section.status = "built";
        this.ui.renderPlan(site);
        this.ui.log({ agent: a, type: "create", title: `Shipped ${section.title}`, text: `${res.data.html.length.toLocaleString()} chars HTML · ${res.data.css.length.toLocaleString()} chars CSS` });
      }
      this.ui.agentState(a, "done");
      this.canvas.hide(a);
    };
    await Promise.all(devs.map(worker));
  }

  // ---- 4. interaction
  async interactionStage() {
    this.ui.stage("build");
    const site = this.site;
    const agent = this.firstOf("interaction");
    const a = agent || SYSTEM_AGENT;
    const nav = site.sections.find((s) => s.type === "nav");
    this.canvas.moveTo(a, nav?.id || site.sections[0]?.id, { state: "wiring interactions" });
    const html = site.sections.map((s) => s.html).join("\n");
    const hooks = ["data-nav-toggle", "data-nav-menu", "data-demo-form", "class=\"reveal", "data-year", "<details"].filter((h) => html.includes(h));
    const res = await this.step(agent, {
      contract: "interaction",
      user: `Hooks present in the markup: ${hooks.join(", ") || "none"}\nSection ids: ${site.sections.map((s) => s.id).join(", ")}\n\nPage markup:\n${html}`,
      parse: "js",
      fallback: () => demo.demoInteraction(),
    });
    this.logResult(a, res, "Interactions wired up");
    this.ui.agentState(a, "working", "writing script.js");
    // type the JS in the code view
    const js = res.data.js;
    const ticks = speedFactor() ? 30 : 1;
    this.code.jsTyping = { agent: a, js: "" };
    for (let i = 1; i <= ticks; i++) {
      this.check();
      this.code.jsTyping.js = js.slice(0, Math.ceil((js.length * i) / ticks));
      this.code.touch();
      if (i % 6 === 0) this.canvas.moveTo(a, site.sections[Math.floor(Math.random() * site.sections.length)].id, { state: "scripting" });
      await sleep(40);
    }
    this.code.jsTyping = null;
    site.js = js;
    this.code.touch();
    await this.canvas.renderFull(site);
    this.ui.agentState(a, "done");
    this.canvas.hide(a);
  }

  // ---- 5. QA review
  async qaStage() {
    this.ui.stage("review");
    const site = this.site;
    const agent = this.firstOf("qa");
    if (!agent) return;
    this.canvas.moveTo(agent, site.sections[0].id, { state: "running checks" });
    const checks = await runChecks(this.canvas.doc, site);
    // scan the page top to bottom
    for (const s of site.sections) {
      this.check();
      this.canvas.moveTo(agent, s.id, { fx: 0.85, wander: false, state: "inspecting" });
      this.canvas.mark(s.id, { color: agent.color });
      await sleep(170);
      this.canvas.unmark(s.id);
    }
    const res = await this.step(agent, {
      contract: "qa",
      user: `Original request:\n"""${site.prompt}"""\n\nAutomated check results:\n${this.checksText(checks)}\n\nSection ids: ${site.sections.map((s) => s.id).join(", ")}\n\nFull page:\n${assembleDocument(site)}`,
      fallback: () => demo.demoQa(site, checks),
    });
    const issues = (Array.isArray(res.data?.issues) ? res.data.issues : []).filter((i) => i && i.issue);
    site.qa = { summary: res.data?.summary || "", issues, checks };
    this.logResult(agent, res, issues.length ? `Found ${issues.length} issue(s)` : "QA passed — no issues", Object.fromEntries(issues.slice(0, 6).map((i, n) => [`${n + 1}. ${i.sectionId}`, `[${i.severity}] ${i.issue}`])));
    this.ui.renderQa(site);
    for (const i of issues) {
      if (site.sections.some((s) => s.id === i.sectionId)) this.canvas.mark(i.sectionId, { color: i.severity === "high" ? "#ef4444" : "#f59e0b", label: `⚠ ${i.issue.slice(0, 60)}` });
    }
    await sleep(900);
    const fixes = issues.filter((i) => i.severity !== "low" && site.sections.some((s) => s.id === i.sectionId)).map((i) => ({ sectionId: i.sectionId, instruction: i.fix || i.issue, from: agent }));
    this.ui.agentState(agent, "done");
    this.canvas.hide(agent);
    if (fixes.length) {
      await this.fixPass(fixes);
      await this.canvas.renderFull(site);
    }
    this.canvas.clearMarks("box");
  }

  checksText(checks) {
    return checks.items.map((c) => `- [${c.pass ? "PASS" : "FAIL"}] ${c.label}: ${c.detail}${c.sectionId && !c.pass ? ` (section: ${c.sectionId})` : ""}`).join("\n") + `\nPrompt keyword coverage: ${Math.round(checks.keywordCoverage * 100)}%${checks.missingKeywords.length ? ` (missing: ${checks.missingKeywords.join(", ")})` : ""}`;
  }

  // ---- developers revise sections in parallel
  async fixPass(fixes) {
    const site = this.site;
    const bySection = new Map();
    for (const f of fixes) {
      if (!site.sections.some((s) => s.id === f.sectionId)) continue;
      if (!bySection.has(f.sectionId)) bySection.set(f.sectionId, []);
      bySection.get(f.sectionId).push(f);
    }
    if (!bySection.size) return;
    this.ui.stage("build");
    let devs = this.agentsOf("developer");
    if (!devs.length) devs = [null];
    const queue = [...bySection.entries()];
    const worker = async (agent) => {
      const a = agent || SYSTEM_AGENT;
      while (queue.length) {
        this.check();
        const [id, list] = queue.shift();
        const section = site.sections.find((s) => s.id === id);
        const instruction = list.map((f) => `- ${f.instruction}${f.from ? ` (from ${f.from.name})` : ""}`).join("\n");
        this.canvas.moveTo(a, id, { state: `revising ${section.title}` });
        this.canvas.mark(id, { color: a.color, label: `🔧 ${a.name} revising` });
        const res = await this.step(agent, {
          contract: "developer",
          user: `${this.devPrompt(section)}\n\n${systemFix()}\n\nCURRENT HTML:\n${section.html}\n\nCURRENT CSS:\n${section.css}\n\nINSTRUCTIONS:\n${instruction}`,
          parse: "section",
          label: section.id,
          fallback: () => demo.demoRevise(section, instruction, site),
        });
        this.ui.log({ agent: a, type: "create", title: `Revised ${section.title}`, text: res.data.thoughts, reasoning: res.thinking, source: res.source, details: { Instructions: instruction } });
        this.ui.agentState(a, "working", `revising ${section.title}`);
        await this.typeSection(a, section, res.data.html, res.data.css);
        section.html = res.data.html;
        section.css = res.data.css;
        section.revisions = (section.revisions || 0) + 1;
        this.canvas.unmark(id);
        this.ui.renderPlan(site);
      }
      this.ui.agentState(a, "done");
      this.canvas.hide(a);
    };
    await Promise.all(devs.map(worker));
    function systemFix() {
      return "You are REVISING this existing section. Return the complete updated section in the same <thoughts>/<html>/<css> format.";
    }
  }

  // ---- 6. evaluation loop
  async evalLoop() {
    const site = this.site;
    const judge = this.firstOf("evaluator");
    if (!judge) return;
    const g = state.settings.general;
    for (let round = 0; round <= g.refineIterations; round++) {
      this.check();
      this.ui.stage("evaluate");
      this.canvas.clearMarks("badge");
      this.canvas.moveTo(judge, site.sections[0].id, { state: round ? `re-evaluating (round ${round + 1})` : "evaluating" });
      const checks = await runChecks(this.canvas.doc, site);
      for (const s of site.sections) {
        this.check();
        this.canvas.moveTo(judge, s.id, { fx: 0.8, wander: false, state: "scoring" });
        await sleep(130);
      }
      const res = await this.step(judge, {
        contract: "evaluator",
        user: `Original request:\n"""${site.prompt}"""\n\nPlan:\n${JSON.stringify(this.context(), null, 2)}\n\nRubric (0-100 each): ${RUBRIC.map((r) => r.label).join(", ")}\nPass threshold: ${g.evalThreshold}\n\nAutomated check results:\n${this.checksText(checks)}\n\nSection ids: ${site.sections.map((s) => s.id).join(", ")}\n\nFull page:\n${assembleDocument(site)}`,
        fallback: () => demo.demoEvaluate(site, checks),
      });
      const ev = this.combineScores(res.data || {}, checks);
      ev.round = site.evals.length + 1;
      ev.source = res.source;
      site.evals.push(ev);
      this.logResult(judge, res, `Evaluation #${ev.round}: ${ev.overall}/100 — ${ev.overall >= g.evalThreshold ? "PASS" : "below threshold"}`, Object.fromEntries(RUBRIC.map((r) => [r.label, ev.scores[r.key]])));
      this.ui.renderEval(site);
      const perSection = new Map();
      for (const imp of ev.improvements) perSection.set(imp.sectionId, (perSection.get(imp.sectionId) || 0) + 1);
      for (const s of site.sections) {
        const n = perSection.get(s.id);
        this.canvas.mark(s.id, { kind: "badge", color: n ? "#f59e0b" : "#22c55e", label: n ? `${n} improvement${n > 1 ? "s" : ""}` : "✓" });
      }
      await sleep(900);
      if (ev.overall >= g.evalThreshold || round === g.refineIterations || !ev.improvements.length) {
        this.ui.agentState(judge, "done");
        break;
      }
      this.ui.log({ agent: judge, type: "info", title: `Requesting ${ev.improvements.length} improvement(s) before re-scoring` });
      await this.fixPass(ev.improvements.map((i) => ({ ...i, from: judge })));
      await this.canvas.renderFull(site);
    }
    this.canvas.hide(judge);
    await sleep(600);
    this.canvas.clearMarks("badge");
  }

  combineScores(data, checks) {
    const raw = data.scores || {};
    const clamp = (v) => Math.max(0, Math.min(100, Math.round(Number(v) || 0)));
    const scores = {};
    for (const r of RUBRIC) scores[r.key] = raw[r.key] != null ? clamp(raw[r.key]) : null;
    // Blend measured scores with the judge's opinion so the number stays grounded.
    const measured = { accessibility: checks.scores.accessibility, responsiveness: checks.scores.responsiveness, codeQuality: checks.scores.codeQuality };
    for (const [k, v] of Object.entries(measured)) scores[k] = scores[k] == null ? v : Math.round(scores[k] * 0.5 + v * 0.5);
    for (const r of RUBRIC) if (scores[r.key] == null) scores[r.key] = 75;
    const overall = Math.round(RUBRIC.reduce((s, r) => s + scores[r.key] * r.weight, 0) / RUBRIC.reduce((s, r) => s + r.weight, 0));
    const ids = new Set(this.site.sections.map((s) => s.id));
    return {
      scores,
      overall,
      verdict: String(data.verdict || ""),
      strengths: Array.isArray(data.strengths) ? data.strengths.map(String).slice(0, 5) : [],
      improvements: (Array.isArray(data.improvements) ? data.improvements : []).filter((i) => i && ids.has(i.sectionId) && i.instruction).slice(0, 6),
      checks,
    };
  }

  // ------------------------------------------------------------------ refine

  async refine(request) {
    if (!this.site?.plan) return this.build(request);
    this.running = true;
    this.abortFlag = false;
    const site = this.site;
    const t0 = performance.now();
    this.ui.beginRefine(request);
    try {
      this.ui.stage("plan");
      const planner = this.firstOf("planner");
      const pa = planner || SYSTEM_AGENT;
      this.canvas.point(pa, 0.5, 0.3, "reading your change");
      const res = await this.step(planner, {
        contract: "planner_refine",
        user: `Original request:\n"""${site.prompt}"""\n\nCurrent design tokens:\n${JSON.stringify(site.tokens)}\n\nCurrent sections:\n${JSON.stringify(site.sections.map(({ id, type, title }) => ({ id, type, title })))}\n\nCHANGE REQUEST:\n"""${request}"""`,
        fallback: () => demo.demoRefinePlan(site, request),
      });
      const d = res.data || {};
      this.logResult(pa, res, "Change plan ready");
      this.ui.agentState(pa, "done");
      this.canvas.hide(pa);
      site.prompt += `\n\nChange request: ${request}`;

      if (d.tokens && Object.keys(d.tokens).length) {
        const designer = this.firstOf("designer") || SYSTEM_AGENT;
        this.canvas.point(designer, 0.7, 0.3, "updating tokens");
        this.ui.agentState(designer, "working", "updating design tokens");
        await sleep(500);
        site.tokens = normalizeTokens({ ...site.tokens, ...d.tokens });
        this.ui.renderDesign(site);
        this.ui.log({ agent: designer, type: "create", title: "Design tokens updated", details: d.tokens });
        this.ui.agentState(designer, "done");
        this.canvas.hide(designer);
      }
      for (const id of Array.isArray(d.removeSections) ? d.removeSections : []) {
        const idx = site.sections.findIndex((s) => s.id === id);
        if (idx < 0) continue;
        this.canvas.moveTo(pa, id, { state: "removing" });
        await sleep(400);
        this.canvas.removeSection(id);
        site.sections.splice(idx, 1);
      }
      const added = [];
      for (const ns of Array.isArray(d.newSections) ? d.newSections : []) {
        let id = slug(ns.id || ns.title || ns.type);
        while (site.sections.some((s) => s.id === id)) id += "-2";
        const sec = { id, type: slug(ns.type || "custom"), title: String(ns.title || id), purpose: String(ns.purpose || ""), html: "", css: "", status: "planned" };
        const after = site.sections.findIndex((s) => s.id === ns.after);
        const at = after >= 0 ? after + 1 : Math.max(1, site.sections.length - 1);
        site.sections.splice(at, 0, sec);
        added.push(sec);
      }
      await this.canvas.renderFull(site);
      for (const s of added) this.canvas.addSkeleton(s, site.sections[site.sections.indexOf(s) - 1]?.id);
      this.ui.renderPlan(site);
      if (added.length) {
        await this.designStage(added);
        await this.buildStage(added);
      }
      const changes = (Array.isArray(d.changes) ? d.changes : []).filter((c) => c && c.sectionId && !added.some((a) => a.id === c.sectionId));
      if (changes.length) await this.fixPass(changes.map((c) => ({ sectionId: c.sectionId, instruction: c.instruction || request, from: planner })));
      await this.canvas.renderFull(site);
      await this.evalLoop();
      this.finish(t0);
    } catch (e) {
      this.fail(e);
    } finally {
      this.running = false;
    }
  }
}
