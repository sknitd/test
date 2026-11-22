import { state, loadState, saveSettings, on, providerLabel, resolveAgentProvider } from "./store.js";
import { Canvas } from "./canvas.js";
import { CodeView } from "./codeview.js";
import { BuilderUI } from "./ui.js";
import { Orchestrator } from "./orchestrator.js";
import { renderAgents, renderSettings, refreshProviders } from "./views.js";
import { assembleDocument } from "./site.js";

const $ = (s) => document.querySelector(s);

const EXAMPLES = [
  "A cosy Italian trattoria called Nonna Rosa in Boston with a menu, photo gallery and online reservations",
  "Landing page for an AI note-taking app for remote teams, with pricing tiers and FAQ",
  "Portfolio for a wedding photographer in Lisbon — elegant, dark theme, with a gallery and contact form",
  "A boutique yoga studio with class schedule, teacher profiles and membership pricing",
  "Nonprofit animal rescue that needs volunteers and donations, warm and friendly",
  "Two-day developer conference in Berlin with speakers, ticket tiers and FAQ",
];

loadState();
await refreshProviders();

const canvas = new Canvas({ stage: $("#stage"), frame: $("#frame"), overlay: $("#overlay") });
const code = new CodeView($("#code"), $("#code-tabs"));
const ui = new BuilderUI();
const orch = new Orchestrator({ canvas, code, ui });
window.__orch = orch; // handy for debugging in the console

// ------------------------------------------------------------------ routing
function show(view) {
  if (!["builder", "agents", "settings"].includes(view)) view = "builder";
  for (const v of document.querySelectorAll(".view")) v.hidden = v.id !== `view-${view}`;
  for (const t of document.querySelectorAll(".tabs a")) t.classList.toggle("active", t.dataset.view === view);
  if (view === "agents") renderAgents();
  if (view === "settings") renderSettings();
  if (view === "builder") {
    ui.renderRoster();
    updateProviderPill();
  }
}
window.addEventListener("hashchange", () => show(location.hash.slice(1)));
show(location.hash.slice(1) || "builder");

function updateProviderPill() {
  const pid = state.settings.defaultProvider;
  const live = state.agents.filter((a) => a.enabled && resolveAgentProvider(a).provider !== "demo").length;
  const pill = $("#provider-pill");
  pill.innerHTML = `<span class="dot ${pid === "demo" ? "" : "ok"}"></span>${providerLabel(pid)}${live && pid === "demo" ? ` <small>+${live} live</small>` : ""}`;
  pill.title = pid === "demo" ? "Agents use the built-in offline generator. Configure a provider in Settings." : `Team default provider: ${providerLabel(pid)}`;
}
on("settings-changed", updateProviderPill);
on("agents-changed", () => {
  ui.renderRoster();
  updateProviderPill();
});

// ----------------------------------------------------------------- composer
const promptEl = $("#prompt");
const buildBtn = $("#build-btn");
const stopBtn = $("#stop-btn");
$("#examples").innerHTML = EXAMPLES.map((e) => `<button type="button" class="ex" title="${e}">${e.split(/[,—]/)[0].replace(/^(A|An)\s/, "").slice(0, 38)}</button>`).join("");
$("#examples").addEventListener("click", (e) => {
  const b = e.target.closest(".ex");
  if (!b) return;
  promptEl.value = b.title;
  promptEl.focus();
});

function setRunning(running) {
  buildBtn.hidden = running;
  stopBtn.hidden = !running;
  promptEl.disabled = running;
  document.body.classList.toggle("is-running", running);
  for (const b of document.querySelectorAll("[data-needs-site]")) b.disabled = running || !orch.site?.plan;
  if (running) setLive(false);
}

$("#composer").addEventListener("submit", async (e) => {
  e.preventDefault();
  const text = promptEl.value.trim();
  if (!text || orch.running) return;
  const mode = document.querySelector('input[name="mode"]:checked')?.value || "new";
  setRunning(true);
  promptEl.value = "";
  if (mode === "refine" && orch.site?.plan) await orch.refine(text);
  else await orch.build(text);
});
promptEl.addEventListener("keydown", (e) => {
  if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) $("#composer").requestSubmit();
});
stopBtn.addEventListener("click", () => orch.stop());

document.addEventListener("build-finished", (e) => {
  setRunning(false);
  const hasSite = !!e.detail.site?.plan && e.detail.site.sections.some((s) => s.html);
  $("#mode-row").hidden = !hasSite;
  if (hasSite) {
    document.querySelector('input[name="mode"][value="refine"]').checked = true;
    promptEl.placeholder = "Ask for changes, e.g. “make it dark with a green accent” or “add a pricing section” — or switch to New site.";
  }
  for (const b of document.querySelectorAll("[data-needs-site]")) b.disabled = !hasSite;
  promptEl.focus();
});

// ------------------------------------------------------------- stage tools
const codeWrap = $("#code-wrap");
const live = $("#live");
document.querySelectorAll("[data-mode]").forEach((b) =>
  b.addEventListener("click", () => {
    document.querySelectorAll("[data-mode]").forEach((x) => x.classList.toggle("active", x === b));
    const isCode = b.dataset.mode === "code";
    codeWrap.hidden = !isCode;
    code.setVisible(isCode);
  }),
);
document.querySelectorAll("[data-device]").forEach((b) =>
  b.addEventListener("click", () => {
    document.querySelectorAll("[data-device]").forEach((x) => x.classList.toggle("active", x === b));
    $("#stage").dataset.device = b.dataset.device;
  }),
);
const follow = $("#follow");
follow.checked = state.settings.general.follow;
follow.addEventListener("change", () => {
  state.settings.general.follow = follow.checked;
  saveSettings();
});

// Interactive preview runs the generated JavaScript in a sandboxed iframe with
// an opaque origin, so it can't touch the builder, its storage or its API.
function setLive(on) {
  $("#try-btn").classList.toggle("active", on);
  $("#try-btn").textContent = on ? "■ Exit interactive" : "▶ Try it";
  live.hidden = !on;
  $("#overlay").hidden = on;
  if (on) live.srcdoc = assembleDocument(orch.site);
  else live.removeAttribute("srcdoc");
}
$("#try-btn").addEventListener("click", () => setLive(live.hidden));

$("#open-btn").addEventListener("click", () => {
  const w = window.open("", "_blank");
  if (!w) return alert("Pop-up blocked — allow pop-ups to open the preview.");
  const doc = assembleDocument(orch.site).replace(/&/g, "&amp;").replace(/"/g, "&quot;");
  w.document.write(`<!doctype html><meta charset="utf-8"><title>${orch.site.plan.siteName} — preview</title><style>html,body{margin:0;height:100%}iframe{border:0;width:100%;height:100%;display:block}</style><iframe sandbox="allow-scripts allow-forms allow-popups" srcdoc="${doc}"></iframe>`);
  w.document.close();
});

$("#download-btn").addEventListener("click", () => {
  const html = assembleDocument(orch.site);
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([html], { type: "text/html" }));
  a.download = `${(orch.site.plan.siteName || "website").toLowerCase().replace(/[^a-z0-9]+/g, "-")}.html`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 2000);
});

$("#copy-btn").addEventListener("click", async (e) => {
  try {
    await navigator.clipboard.writeText(assembleDocument(orch.site));
    e.target.textContent = "Copied ✓";
  } catch {
    e.target.textContent = "Copy failed";
  }
  setTimeout(() => (e.target.textContent = "Copy HTML"), 1500);
});

$("#clear-log").addEventListener("click", () => ($("#feed").innerHTML = ""));
setRunning(false);
