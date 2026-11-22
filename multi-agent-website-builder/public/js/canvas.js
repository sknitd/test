// Live preview canvas: an iframe the agents build into, plus an overlay layer that
// renders one named, coloured cursor per agent, section highlights and score badges.

import { assembleDocument, baseCss, fontsHref, normalizeTokens, scopeCss } from "./site.js";
import { state } from "./store.js";

const BUILDER_CSS = `
.wb-wrap{display:contents}
.wb-skel{position:relative;margin:14px auto;width:min(100% - 2.5rem,1160px);border-radius:18px;padding:28px;
  background:color-mix(in srgb,var(--color-surface,#eef0f6) 90%,transparent);border:2px dashed color-mix(in srgb,var(--color-primary,#7c5cff) 35%,transparent);
  overflow:hidden;animation:wbIn .45s ease both;font-family:var(--font-body,system-ui);color:var(--color-text,#222)}
.wb-skel::after{content:"";position:absolute;inset:0;background:linear-gradient(100deg,transparent 20%,rgba(255,255,255,.35) 50%,transparent 80%);transform:translateX(-100%);animation:wbShimmer 2.2s infinite}
.wb-skel.is-active{border-style:solid;border-color:var(--wb-c,#7c5cff);box-shadow:0 0 0 4px color-mix(in srgb,var(--wb-c,#7c5cff) 18%,transparent)}
.wb-skel-top{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:12px}
.wb-pill{font:600 11px/1 ui-sans-serif,system-ui;letter-spacing:.06em;text-transform:uppercase;padding:6px 9px;border-radius:999px;background:var(--color-primary,#7c5cff);color:var(--color-on-primary,#fff)}
.wb-pill.alt{background:transparent;color:var(--color-muted,#667);border:1px solid currentColor}
.wb-skel-h{font-family:var(--font-heading,system-ui);font-size:clamp(1.2rem,2.6vw,1.9rem);font-weight:700;min-height:1.3em;margin:4px 0 14px}
.wb-skel-h:empty::before{content:"";display:block;width:55%;height:.9em;border-radius:8px;background:color-mix(in srgb,var(--color-text,#222) 12%,transparent)}
.wb-lines span{display:block;height:10px;border-radius:6px;margin:9px 0;background:color-mix(in srgb,var(--color-text,#222) 9%,transparent)}
.wb-blocks{display:flex;gap:12px;margin-top:16px}.wb-blocks i{flex:1;height:70px;border-radius:12px;background:color-mix(in srgb,var(--color-primary,#7c5cff) 12%,transparent)}
.wb-skel[data-type=nav]{padding:14px 22px;margin-top:0;border-radius:0 0 14px 14px}.wb-skel[data-type=nav] .wb-lines,.wb-skel[data-type=nav] .wb-blocks{display:none}
.wb-skel[data-type=hero]{min-height:300px}.wb-skel[data-type=footer]{min-height:120px}
.wb-empty{min-height:92vh;display:grid;place-items:center;text-align:center;font-family:system-ui;color:#8a8fa3;background:radial-gradient(600px 300px at 50% 40%,#f3f0ff,transparent)}
.wb-empty b{display:block;font-size:22px;color:#4b4f63;margin-bottom:6px}
@keyframes wbIn{from{opacity:0;transform:translateY(14px) scale(.98)}to{opacity:1;transform:none}}
@keyframes wbShimmer{to{transform:translateX(100%)}}
`;

function shellDoc() {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<link id="wb-fonts" rel="stylesheet" href="">
<style id="wb-base">${baseCss({})}</style>
<style id="wb-sections"></style>
<style id="wb-builder">${BUILDER_CSS}</style></head>
<body><div id="wb-root"><div class="wb-empty"><div><b>Blank canvas</b>Agents are joining…</div></div></div></body></html>`;
}

function idleDoc() {
  return `<!doctype html><html><head><style>${BUILDER_CSS}</style></head><body style="margin:0"><div class="wb-empty"><div><b>Your website will appear here</b>Describe it in the prompt box and press Build.</div></div></body></html>`;
}

const SKEL = (s) => `<div class="wb-skel" data-type="${s.type}">
  <div class="wb-skel-top"><span class="wb-pill">${s.title.replace(/</g, "&lt;")}</span><span class="wb-pill alt wb-layout">${s.type}</span><span class="wb-pill alt wb-status" hidden></span></div>
  <div class="wb-skel-h"></div>
  <div class="wb-lines"><span style="width:82%"></span><span style="width:64%"></span><span style="width:71%"></span></div>
  ${["nav", "footer"].includes(s.type) ? "" : `<div class="wb-blocks"><i></i><i></i><i></i></div>`}
</div>`;

export class Canvas {
  constructor({ stage, frame, overlay }) {
    this.stage = stage;
    this.frame = frame;
    this.overlay = overlay;
    this.cursors = new Map();
    this.marks = new Map();
    this.lastFollow = 0;
    this.frame.srcdoc = idleDoc();
    requestAnimationFrame(() => this.tick());
  }

  get doc() {
    return this.frame.contentDocument;
  }
  get win() {
    return this.frame.contentWindow;
  }

  async load(html) {
    const scrollY = this.win?.scrollY || 0;
    await new Promise((res) => {
      this.frame.onload = () => res();
      this.frame.srcdoc = html;
      setTimeout(res, 4000);
    });
    try {
      this.win.scrollTo(0, scrollY);
    } catch {}
  }

  async reset() {
    this.clearMarks();
    await this.load(shellDoc());
  }

  idle() {
    this.clearMarks();
    this.frame.srcdoc = idleDoc();
  }

  root() {
    return this.doc?.getElementById("wb-root");
  }

  setTokens(tokens) {
    const d = this.doc;
    if (!d) return;
    const t = normalizeTokens(tokens);
    const base = d.getElementById("wb-base");
    if (base) base.textContent = baseCss(t);
    const link = d.getElementById("wb-fonts");
    if (link) link.href = fontsHref(t);
  }

  wrap(id) {
    return this.doc?.querySelector(`[data-wb="${CSS.escape(id)}"]`);
  }

  addSkeleton(section, afterId) {
    const root = this.root();
    if (!root) return;
    root.querySelector(".wb-empty")?.remove();
    const w = this.doc.createElement("div");
    w.className = "wb-wrap";
    w.dataset.wb = section.id;
    w.innerHTML = SKEL(section);
    const after = afterId && this.wrap(afterId);
    if (after) after.after(w);
    else root.appendChild(w);
  }

  removeSection(id) {
    this.wrap(id)?.remove();
    this.doc?.querySelector(`style[data-css="${CSS.escape(id)}"]`)?.remove();
  }

  annotate(id, { layout, heading, status, color, active } = {}) {
    const w = this.wrap(id);
    const sk = w?.querySelector(".wb-skel");
    if (!sk) return;
    if (layout != null) sk.querySelector(".wb-layout").textContent = layout;
    if (heading != null) sk.querySelector(".wb-skel-h").textContent = heading;
    if (status != null) {
      const st = sk.querySelector(".wb-status");
      st.hidden = !status;
      st.textContent = status;
    }
    if (color) sk.style.setProperty("--wb-c", color);
    if (active != null) sk.classList.toggle("is-active", active);
  }

  setSectionCss(id, css) {
    const d = this.doc;
    if (!d) return;
    let el = d.querySelector(`style[data-css="${CSS.escape(id)}"]`);
    if (!el) {
      el = d.createElement("style");
      el.dataset.css = id;
      d.head.appendChild(el);
    }
    el.textContent = scopeCss(css, id);
  }

  setSectionHtml(id, html) {
    const w = this.wrap(id);
    if (w) w.innerHTML = html;
  }

  /** Replace the canvas with the fully assembled document (wrappers kept for targeting). */
  async renderFull(site) {
    // Scripts never run on the builder canvas (it's sandboxed without allow-scripts);
    // "Try it" runs them in a separate opaque-origin sandbox.
    const html = assembleDocument({ ...site, js: "" }, { wrappers: true }).replace("</head>", `<style id="wb-builder">${BUILDER_CSS}</style></head>`);
    await this.load(html);
  }

  // ---------------------------------------------------------------- geometry

  sectionRect(id) {
    const w = this.wrap(id);
    if (!w) return null;
    const range = this.doc.createRange();
    range.selectNodeContents(w);
    const r = range.getBoundingClientRect();
    if (!r.width && !r.height) return null;
    return r;
  }

  frameOffset() {
    const f = this.frame.getBoundingClientRect();
    const o = this.overlay.getBoundingClientRect();
    return { x: f.left - o.left, y: f.top - o.top, w: f.width, h: f.height };
  }

  follow(id, force = false) {
    if (!state.settings.general.follow && !force) return;
    const now = performance.now();
    if (!force && now - this.lastFollow < 900) return;
    const r = this.sectionRect(id);
    if (!r || !this.win) return;
    const vh = this.win.innerHeight;
    const visible = Math.min(r.bottom, vh) - Math.max(r.top, 0);
    if (visible > Math.min(r.height, vh) * 0.6) return;
    this.lastFollow = now;
    this.win.scrollBy({ top: r.top - 70, behavior: state.settings.general.speed === "instant" ? "auto" : "smooth" });
  }

  // ----------------------------------------------------------------- cursors

  cursor(agent) {
    let c = this.cursors.get(agent.id);
    if (!c) {
      const el = document.createElement("div");
      el.className = "cursor";
      el.style.setProperty("--c", agent.color);
      el.innerHTML = `<svg width="22" height="22" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 2l7.5 19 2.6-7.9L21 10.5z" fill="var(--c)" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>
        <div class="cursor-tag"><span class="cursor-icon">${agent.icon || ""}</span><b>${agent.name}</b><span class="cursor-state"></span><span class="cursor-off" hidden></span></div>
        <div class="cursor-bubble" hidden></div>`;
      this.overlay.appendChild(el);
      const o = this.frameOffset();
      c = { el, agent, x: o.x + o.w / 2, y: o.y + 40, target: null, fx: 0.5, fy: 0.3, nextWander: 0, visible: false };
      this.cursors.set(agent.id, c);
    }
    return c;
  }

  /** Move an agent's cursor to a section (or a point when no section). */
  moveTo(agent, sectionId, { fx, fy, wander = true, state: st } = {}) {
    const c = this.cursor(agent);
    c.target = sectionId || null;
    c.fx = fx ?? 0.15 + Math.random() * 0.7;
    c.fy = fy ?? 0.2 + Math.random() * 0.5;
    c.wander = wander;
    c.progress = null;
    c.visible = true;
    c.el.classList.add("on");
    if (st !== undefined) this.setCursorState(agent, st);
    if (sectionId) this.follow(sectionId);
  }

  /** While typing, the cursor sweeps down the section with the given progress (0..1). */
  progress(agent, p) {
    const c = this.cursor(agent);
    c.progress = p;
  }

  point(agent, fx, fy, st) {
    const c = this.cursor(agent);
    c.target = null;
    c.fx = fx;
    c.fy = fy;
    c.wander = true;
    c.visible = true;
    c.el.classList.add("on");
    if (st !== undefined) this.setCursorState(agent, st);
  }

  setCursorState(agent, text) {
    const c = this.cursor(agent);
    c.el.querySelector(".cursor-state").textContent = text ? `· ${text}` : "";
  }

  say(agent, text, ms = 3200) {
    const c = this.cursor(agent);
    const b = c.el.querySelector(".cursor-bubble");
    if (!text) {
      b.hidden = true;
      return;
    }
    b.textContent = text.length > 140 ? text.slice(0, 137) + "…" : text;
    b.hidden = false;
    clearTimeout(c.sayT);
    c.sayT = setTimeout(() => (b.hidden = true), ms * Math.max(0.5, state.settings.general.speed === "instant" ? 0.5 : 1));
  }

  hide(agent) {
    const c = this.cursors.get(agent.id);
    if (!c) return;
    c.visible = false;
    c.el.classList.remove("on");
  }

  hideAll() {
    for (const c of this.cursors.values()) {
      c.visible = false;
      c.el.classList.remove("on");
    }
  }

  removeCursors() {
    for (const c of this.cursors.values()) c.el.remove();
    this.cursors.clear();
  }

  // ------------------------------------------------------------ highlights

  mark(id, { color, label, kind = "box" } = {}) {
    let m = this.marks.get(id + kind);
    if (!m) {
      const el = document.createElement("div");
      el.className = `mark mark-${kind}`;
      this.overlay.appendChild(el);
      m = { el, id };
      this.marks.set(id + kind, m);
    }
    m.el.style.setProperty("--c", color || "#22c55e");
    m.el.innerHTML = label ? `<span>${label}</span>` : "";
    return m;
  }

  unmark(id, kind = "box") {
    const m = this.marks.get(id + kind);
    if (m) {
      m.el.remove();
      this.marks.delete(id + kind);
    }
  }

  clearMarks(kind) {
    for (const [k, m] of this.marks) {
      if (!kind || k.endsWith(kind)) {
        m.el.remove();
        this.marks.delete(k);
      }
    }
  }

  // ------------------------------------------------------------- animation

  tick() {
    const now = performance.now();
    const o = this.frameOffset();
    for (const c of this.cursors.values()) {
      if (!c.visible) continue;
      let tx;
      let ty;
      const r = c.target ? this.sectionRect(c.target) : null;
      if (c.wander && now > c.nextWander) {
        c.fx = Math.min(0.92, Math.max(0.06, c.fx + (Math.random() - 0.5) * 0.35));
        c.fy = Math.min(0.9, Math.max(0.08, c.fy + (Math.random() - 0.5) * 0.3));
        c.nextWander = now + 500 + Math.random() * 900;
      }
      if (r) {
        const h = Math.min(r.height, 900);
        const fy = c.progress != null ? Math.min(0.97, c.progress) : c.fy;
        tx = o.x + r.left + r.width * c.fx;
        ty = o.y + r.top + Math.max(12, h * fy);
      } else {
        tx = o.x + o.w * c.fx;
        ty = o.y + Math.min(o.h, 700) * c.fy;
      }
      // Clamp to the visible frame and flag off-screen agents.
      const off = ty < o.y + 6 ? "↑" : ty > o.y + o.h - 30 ? "↓" : "";
      tx = Math.min(o.x + o.w - 140, Math.max(o.x + 4, tx));
      ty = Math.min(o.y + o.h - 30, Math.max(o.y + 6, ty));
      c.x += (tx - c.x) * 0.12;
      c.y += (ty - c.y) * 0.12;
      c.el.style.transform = `translate(${c.x}px, ${c.y}px)`;
      const offEl = c.el.querySelector(".cursor-off");
      offEl.hidden = !off;
      offEl.textContent = off;
    }
    for (const m of this.marks.values()) {
      const r = this.sectionRect(m.id);
      if (!r) {
        m.el.style.display = "none";
        continue;
      }
      const top = Math.max(o.y, o.y + r.top);
      const bottom = Math.min(o.y + o.h, o.y + r.bottom);
      if (bottom <= top) {
        m.el.style.display = "none";
        continue;
      }
      m.el.style.display = "";
      m.el.style.transform = `translate(${o.x + r.left}px, ${top}px)`;
      m.el.style.width = `${r.width}px`;
      m.el.style.height = `${bottom - top}px`;
    }
    requestAnimationFrame(() => this.tick());
  }
}
