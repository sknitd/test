// Projects & version history. Every finished build or refine is saved on the
// server as a new version of the current project; any version can be restored.
import { assembleDocument } from "./site.js";
import { captureSite } from "./capture.js";

const $ = (s, r = document) => r.querySelector(s);
const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const LAST = "mawb.lastProject.v1";
const when = (iso) => {
  const d = new Date(iso);
  const today = new Date().toDateString() === d.toDateString();
  return today ? d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }) : d.toLocaleDateString([], { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
};

async function api(method, url, body) {
  const res = await fetch(url, { method, headers: body ? { "Content-Type": "application/json" } : {}, body: body ? JSON.stringify(body) : undefined });
  const j = await res.json().catch(() => ({ error: `HTTP ${res.status}` }));
  if (!res.ok || j.error) throw new Error(j.error || `HTTP ${res.status}`);
  return j;
}

export function openSiteInNewTab(site, title) {
  const w = window.open("", "_blank");
  if (!w) return alert("Pop-up blocked — allow pop-ups to open the preview.");
  const doc = assembleDocument(site).replace(/&/g, "&amp;").replace(/"/g, "&quot;");
  w.document.write(`<!doctype html><meta charset="utf-8"><title>${esc(title)}</title><style>html,body{margin:0;height:100%}iframe{border:0;width:100%;height:100%;display:block}</style><iframe sandbox="allow-scripts allow-forms allow-popups" srcdoc="${doc}"></iframe>`);
  w.document.close();
}

export class Projects {
  constructor({ orch, onOpened, onNew }) {
    this.orch = orch;
    this.onOpened = onOpened; // (hasSite) => void
    this.onNew = onNew;
    this.current = null; // project summary { id, name, versions: [meta] }
    this.activeVersion = null;
    this.available = true;
    $("#projects-btn").addEventListener("click", () => this.showDialog());
    this.renderHistory();
  }

  remember() {
    try {
      if (this.current) localStorage.setItem(LAST, this.current.id);
      else localStorage.removeItem(LAST);
    } catch {}
  }

  /** Re-open the project that was open last time. */
  async init() {
    let id = null;
    try {
      id = localStorage.getItem(LAST);
    } catch {}
    if (!id) return;
    try {
      await this.open(id, { quiet: true });
    } catch {
      this.current = null;
      this.remember();
      this.renderHistory();
    }
  }

  /** Start fresh: the next build creates a new project. */
  startNew() {
    this.current = null;
    this.activeVersion = null;
    this.remember();
    this.renderHistory();
  }

  /** Save a finished build/refine as a new version. */
  async saveVersion(site, action = { kind: "build", label: "Build" }) {
    try {
      if (!this.current) {
        const { project } = await api("POST", "/api/projects", { name: site.plan?.siteName || "Untitled site" });
        this.current = project;
      }
      // Fresh thumbnail of exactly what is being saved (also shown in the Projects list).
      try {
        const shot = await captureSite(site, { maxDesktopTiles: 1, maxMobileTiles: 1 });
        site.shots = { ...(site.shots || {}), desktopThumb: shot.desktopThumb, mobileThumb: shot.mobileThumb, at: new Date().toISOString() };
      } catch {}
      const score = site.evals?.at(-1)?.overall ?? null;
      const label = action.kind === "refine" ? `Refine: ${action.label}` : action.label;
      const { project, version } = await api("POST", `/api/projects/${this.current.id}/versions`, { site, label, kind: action.kind, score });
      this.current = project;
      this.activeVersion = version.n;
      this.remember();
      this.renderHistory(`Saved as version ${version.n}`);
    } catch (e) {
      this.renderHistory(`Couldn't save this version: ${e.message}`);
    }
  }

  async open(id, { quiet = false } = {}) {
    const { project } = await api("GET", `/api/projects/${id}`);
    this.current = project;
    const last = project.versions.at(-1);
    if (last) await this.restore(last.n, { note: quiet ? `Reopened “${project.name}” — version ${last.n}` : `Opened “${project.name}” — version ${last.n}` });
    else {
      this.activeVersion = null;
      this.onNew?.();
    }
    this.remember();
    this.renderHistory();
  }

  async fetchVersion(n) {
    const { version } = await api("GET", `/api/projects/${this.current.id}/versions/${n}`);
    return version;
  }

  async restore(n, { note } = {}) {
    if (this.orch.running) return;
    const v = await this.fetchVersion(n);
    await this.orch.load(v.site, note || `Restored version ${n}: ${v.label}`);
    this.activeVersion = n;
    this.renderHistory();
    this.onOpened?.(true);
  }

  async rename(name) {
    if (!this.current || !name.trim()) return;
    const { project } = await api("PATCH", `/api/projects/${this.current.id}`, { name });
    this.current = project;
    this.renderHistory("Renamed");
  }

  // ------------------------------------------------------------- History tab
  renderHistory(flash) {
    const el = $("#insp-history");
    if (!el) return;
    const p = this.current;
    if (!p) {
      el.innerHTML = `<p class="muted">Each build and refine is saved here as a version you can restore. Build a site to start a project.</p>
        <button class="btn sm" type="button" data-open-projects>Open a saved project…</button>`;
      el.querySelector("[data-open-projects]").onclick = () => this.showDialog();
      return;
    }
    el.innerHTML = `
      <label class="proj-name"><span class="sr-only">Project name</span><input id="proj-name" value="${esc(p.name)}" aria-label="Project name"></label>
      <div class="row-btns"><button class="btn sm" type="button" data-new>+ New project</button><button class="btn sm ghost" type="button" data-open-projects>All projects…</button></div>
      ${flash ? `<p class="flash">${esc(flash)}</p>` : ""}
      <h4>Versions <small>${p.versions.length} saved · newest first</small></h4>
      <ol class="versions">${[...p.versions]
        .reverse()
        .map(
          (v) => `<li class="${v.n === this.activeVersion ? "cur" : ""}">
          <div><b>v${v.n}</b> <span class="vlabel">${esc(v.label)}</span>
            <small>${when(v.createdAt)}${v.score != null ? ` · <span class="vscore ${v.score >= 85 ? "ok" : ""}">${v.score}/100</span>` : ""}${v.n === this.activeVersion ? " · showing" : ""}</small></div>
          <div class="vbtns">
            <button class="btn ghost sm" type="button" data-restore="${v.n}" ${v.n === this.activeVersion ? "disabled" : ""}>Restore</button>
            <button class="btn ghost sm" type="button" data-open-v="${v.n}" title="Open this version in a new tab">↗</button>
          </div></li>`,
        )
        .join("")}</ol>`;
    el.querySelector("#proj-name").onchange = (e) => this.rename(e.target.value).catch((err) => this.renderHistory(err.message));
    el.querySelector("[data-new]").onclick = () => {
      if (this.orch.running) return;
      this.startNew();
      this.onNew?.();
    };
    el.querySelector("[data-open-projects]").onclick = () => this.showDialog();
    el.querySelectorAll("[data-restore]").forEach((b) => (b.onclick = () => this.restore(Number(b.dataset.restore)).catch((err) => this.renderHistory(err.message))));
    el.querySelectorAll("[data-open-v]").forEach(
      (b) =>
        (b.onclick = async () => {
          const v = await this.fetchVersion(Number(b.dataset.openV));
          openSiteInNewTab(v.site, `${p.name} — v${v.n}`);
        }),
    );
  }

  // ---------------------------------------------------------- Projects dialog
  async showDialog() {
    const dlg = document.createElement("div");
    dlg.className = "modal";
    dlg.innerHTML = `<div class="modal-card" role="dialog" aria-modal="true" aria-labelledby="pj-title">
      <header><h2 id="pj-title">Projects</h2><button class="btn ghost sm" type="button" data-close aria-label="Close">✕</button></header>
      <div class="pj-grid"><p class="muted">Loading…</p></div></div>`;
    const close = () => dlg.remove();
    dlg.addEventListener("click", (e) => e.target === dlg && close());
    dlg.querySelector("[data-close]").onclick = close;
    dlg.addEventListener("keydown", (e) => e.key === "Escape" && close());
    document.body.appendChild(dlg);
    dlg.querySelector("[data-close]").focus();
    const grid = dlg.querySelector(".pj-grid");
    const render = async () => {
      let projects;
      try {
        ({ projects } = await api("GET", "/api/projects"));
      } catch (e) {
        grid.innerHTML = `<p class="err-text">Couldn't load projects: ${esc(e.message)}</p>`;
        return;
      }
      grid.innerHTML =
        `<button type="button" class="pj-card pj-new" data-new><span>＋</span>New project</button>` +
        projects
          .map(
            (p) => `<article class="pj-card ${this.current?.id === p.id ? "cur" : ""}">
          <button type="button" class="pj-open" data-open="${p.id}">
            ${p.thumb ? `<img src="${p.thumb}" alt="">` : `<div class="pj-ph">No preview</div>`}
            <b>${esc(p.name)}</b>
            <small>${p.versionCount} version${p.versionCount === 1 ? "" : "s"} · ${when(p.updatedAt)}${p.lastScore != null ? ` · ${p.lastScore}/100` : ""}</small>
          </button>
          <button type="button" class="btn ghost sm danger pj-del" data-del="${p.id}" aria-label="Delete ${esc(p.name)}">Delete</button>
        </article>`,
          )
          .join("");
      grid.querySelector("[data-new]").onclick = () => {
        if (this.orch.running) return;
        this.startNew();
        this.onNew?.();
        close();
      };
      grid.querySelectorAll("[data-open]").forEach(
        (b) =>
          (b.onclick = async () => {
            if (this.orch.running) return;
            close();
            await this.open(b.dataset.open);
          }),
      );
      grid.querySelectorAll("[data-del]").forEach(
        (b) =>
          (b.onclick = async () => {
            const p = projects.find((x) => x.id === b.dataset.del);
            if (!confirm(`Delete “${p.name}” and all ${p.versionCount} versions? This can't be undone.`)) return;
            await api("DELETE", `/api/projects/${p.id}`);
            if (this.current?.id === p.id) this.startNew();
            render();
          }),
      );
    };
    render();
  }
}
