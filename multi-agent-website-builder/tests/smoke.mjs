// End-to-end smoke test: starts the server, builds a site in offline demo mode
// with headless Chromium, and checks every pipeline stage ran.
//   npm test            (uses the pre-installed Playwright)
import { spawn } from "node:child_process";
import { createRequire } from "node:module";
import path from "node:path";
import fs from "node:fs";
import os from "node:os";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
const here = path.dirname(fileURLToPath(import.meta.url));
const PORT = 5300 + Math.floor(Math.random() * 500);
const OUT = process.env.SHOTS || path.join(os.tmpdir(), "mawb-shots");
fs.mkdirSync(OUT, { recursive: true });
const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), "mawb-data-"));

const server = spawn(process.execPath, [path.join(here, "..", "server.js")], { env: { ...process.env, PORT: String(PORT), DATA_DIR: dataDir }, stdio: ["ignore", "ignore", "inherit"] });
process.on("unhandledRejection", (e) => fail(e?.stack || e));
process.on("uncaughtException", (e) => fail(e?.stack || e));
function fail(msg) {
  console.error("✗", msg);
  server.kill();
  process.exit(1);
}
await new Promise((r) => setTimeout(r, 800));

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1500, height: 920 } });
const errors = [];
page.on("pageerror", (e) => errors.push(e.message));
page.on("console", (m) => m.type() === "error" && !/fonts\.(googleapis|gstatic)|ERR_|net::/i.test(m.text()) && errors.push(m.text()));

await page.goto(`http://127.0.0.1:${PORT}/`);
await page.evaluate(() => localStorage.setItem("mawb.settings.v1", JSON.stringify({ defaultProvider: "demo", general: { speed: "fast" } })));
await page.reload();
await page.fill("#prompt", "A cosy Italian trattoria called Nonna Rosa in Boston with a menu, photo gallery, pricing for catering and online reservations");
await page.click("#build-btn");

// mid-build screenshot with cursors
await page.waitForFunction(() => document.querySelectorAll(".cursor.on").length >= 2, null, { timeout: 30000 }).catch(() => {});
await page.waitForTimeout(1200);
await page.screenshot({ path: path.join(OUT, "1-design.png") });
await page.waitForFunction(() => [...document.querySelectorAll(".ag-working")].some((e) => /Developer/.test(e.textContent)), null, { timeout: 60000 }).catch(() => {});
await page.waitForTimeout(700);
const parallel = await page.evaluate(() => [...document.querySelectorAll(".cursor.on b")].map((b) => b.textContent));
await page.screenshot({ path: path.join(OUT, "2-build.png") });

await page.waitForSelector(".ev-success", { timeout: 120000 }).catch(() => fail("build did not finish"));
await page.screenshot({ path: path.join(OUT, "3-done.png") });

const result = await page.evaluate(() => {
  const s = window.__orch.site;
  return {
    name: s.plan.siteName,
    sections: s.sections.map((x) => `${x.id}:${x.html ? "built" : "missing"}`),
    evals: s.evals.map((e) => e.overall),
    checks: s.evals.at(-1)?.checks.items.filter((c) => !c.pass).map((c) => c.label),
    js: s.js.length,
    feed: document.querySelectorAll(".ev").length,
  };
});
console.log(JSON.stringify({ parallel, ...result }, null, 2));

// code view
await page.click('[data-mode="code"]');
await page.waitForTimeout(300);
const codeLen = await page.evaluate(() => document.querySelector("#code").textContent.length);
await page.screenshot({ path: path.join(OUT, "4-code.png") });
await page.click('[data-mode="preview"]');

// refine
await page.fill("#prompt", "Make it dark and add a FAQ section");
await page.click("#build-btn");
await page.waitForFunction(() => document.querySelectorAll(".ev-success").length >= 2, null, { timeout: 120000 }).catch(() => fail("refine did not finish"));
const refined = await page.evaluate(() => ({ bg: window.__orch.site.tokens.bg, faq: window.__orch.site.sections.some((s) => s.type === "faq" && s.html) }));
console.log("refined:", refined);
await page.screenshot({ path: path.join(OUT, "5-refined.png") });

// interactive preview
await page.click("#try-btn");
await page.waitForTimeout(800);
await page.click("#try-btn");

// mobile overflow check on the export
await page.goto(`http://127.0.0.1:${PORT}/#agents`);
await page.waitForSelector(".acard");
const agentCards = await page.locator(".acard").count();
await page.screenshot({ path: path.join(OUT, "6-agents.png"), fullPage: false });
await page.goto(`http://127.0.0.1:${PORT}/#settings`);
await page.waitForSelector(".pcard");
const providerCards = await page.locator(".pcard").count();
await page.screenshot({ path: path.join(OUT, "7-settings.png") });

await browser.close();
server.kill();
fs.rmSync(dataDir, { recursive: true, force: true });

if (errors.length) fail("page errors:\n" + errors.join("\n"));
if (result.sections.some((s) => s.endsWith("missing"))) fail("not all sections were built");
if (!result.evals.length) fail("evaluator did not run");
if (!result.js) fail("no script.js produced");
if (codeLen < 2000) fail("code view empty");
if (!refined.faq || refined.bg !== "#0f1115") fail("refine did not apply");
if (agentCards < 9 || providerCards < 10) fail("agents/settings pages incomplete");
console.log(`✓ smoke test passed — ${agentCards} agents, ${providerCards} providers, screenshots in ${OUT}`);
