// Automated quality checks used by the QA agent and the Evaluator. They run on
// the real rendered DOM (the preview iframe) plus a hidden 375px-wide iframe for
// a mobile overflow test, so scores are grounded in what was actually built.

import { assembleDocument, contrast, normalizeTokens } from "./site.js";

const STOP = new Set(
  "a an and are as at be but by for from has have i in into is it its me my of on or our so that the their them this to us we with you your website site page build create make want need please should would like some also very modern simple nice good great beautiful landing one".split(" "),
);

function parseRgb(str) {
  const m = String(str).match(/rgba?\(([^)]+)\)/);
  if (!m) return null;
  const p = m[1].split(/[,\s/]+/).filter(Boolean).map(Number);
  return { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 };
}
const toHex = ({ r, g, b }) => "#" + [r, g, b].map((v) => Math.round(v).toString(16).padStart(2, "0")).join("");

function effectiveBg(el, win) {
  let node = el;
  while (node && node.nodeType === 1) {
    const cs = win.getComputedStyle(node);
    if (cs.backgroundImage && cs.backgroundImage !== "none") return null; // gradient/image: can't judge reliably
    const c = parseRgb(cs.backgroundColor);
    if (c && c.a > 0.85) return toHex(c);
    node = node.parentElement;
  }
  return "#ffffff";
}

const sectionOf = (el) => el.closest?.("[data-wb]")?.dataset.wb || el.closest?.("section,header,footer")?.id || null;

export function keywordCoverage(prompt, text) {
  const words = [...new Set((prompt.toLowerCase().match(/[a-z][a-z'-]{3,}/g) || []).filter((w) => !STOP.has(w)))];
  if (!words.length) return { coverage: 1, missing: [] };
  const t = text.toLowerCase();
  const missing = words.filter((w) => !t.includes(w.replace(/(ing|es|s|ed)$/, "")));
  return { coverage: (words.length - missing.length) / words.length, missing, total: words.length };
}

async function mobileOverflow(site) {
  const frame = document.createElement("iframe");
  frame.setAttribute("aria-hidden", "true");
  frame.setAttribute("sandbox", "allow-same-origin"); // never run generated scripts with the app's privileges
  frame.style.cssText = "position:fixed;left:-10000px;top:0;width:375px;height:800px;border:0;visibility:hidden";
  frame.srcdoc = assembleDocument({ ...site, js: "" }, { wrappers: true });
  document.body.appendChild(frame);
  try {
    await new Promise((res) => {
      frame.onload = res;
      setTimeout(res, 3000);
    });
    await new Promise((r) => setTimeout(r, 250));
    const doc = frame.contentDocument;
    if (!doc?.body) return { ok: true, offenders: [] };
    const width = doc.documentElement.clientWidth || 375;
    const offenders = new Set();
    for (const el of doc.body.querySelectorAll("*")) {
      const r = el.getBoundingClientRect();
      if (r.width && r.right > width + 2) {
        // ignore children of elements that clip their content
        let clipped = false;
        for (let p = el.parentElement; p && p !== doc.body; p = p.parentElement) {
          const ov = frame.contentWindow.getComputedStyle(p).overflowX;
          if (ov === "hidden" || ov === "clip" || ov === "auto" || ov === "scroll") {
            clipped = true;
            break;
          }
        }
        if (!clipped) {
          const s = sectionOf(el);
          if (s) offenders.add(s);
        }
      }
    }
    return { ok: offenders.size === 0, offenders: [...offenders] };
  } finally {
    frame.remove();
  }
}

/**
 * @param {Document} doc  the live preview document
 * @param {object} site   the workspace
 */
export async function runChecks(doc, site) {
  const items = [];
  const add = (o) => items.push({ severity: "medium", ...o });
  const win = doc.defaultView;
  const tokens = normalizeTokens(site.tokens || {});

  // --- Accessibility
  const h1s = doc.querySelectorAll("h1");
  add({ id: "h1", group: "accessibility", label: "Exactly one <h1>", pass: h1s.length === 1, detail: `${h1s.length} <h1> elements found`, fix: "Heading structure: use exactly one <h1> (in the hero); demote other headings to <h2>.", sectionId: h1s.length > 1 ? sectionOf(h1s[1]) : site.sections.find((s) => s.type === "hero")?.id, severity: "high" });

  let skip = null;
  let prev = 0;
  for (const h of doc.querySelectorAll("h1,h2,h3,h4,h5,h6")) {
    const lvl = +h.tagName[1];
    if (prev && lvl > prev + 1 && !skip) skip = h;
    prev = lvl;
  }
  add({ id: "heading-order", group: "accessibility", label: "Heading levels don't skip", pass: !skip, detail: skip ? `"${skip.textContent.trim().slice(0, 40)}" skips a level` : "Heading outline is sequential", fix: "Heading structure: use sequential heading levels (h2 → h3) without skipping.", sectionId: skip && sectionOf(skip), severity: "low" });

  const imgs = [...doc.querySelectorAll("img")];
  const noAlt = imgs.filter((i) => !i.hasAttribute("alt"));
  add({ id: "alt", group: "accessibility", label: "Images have alt text", pass: noAlt.length === 0, detail: noAlt.length ? `${noAlt.length} image(s) missing alt` : `${imgs.length} image(s) OK`, fix: "Add meaningful alt text to every <img>.", sectionId: noAlt[0] && sectionOf(noAlt[0]), severity: "high" });

  const fields = [...doc.querySelectorAll("input:not([type=hidden]):not([type=submit]),textarea,select")];
  const unlabeled = fields.filter((f) => !(f.closest("label") || (f.id && doc.querySelector(`label[for="${CSS.escape(f.id)}"]`)) || f.getAttribute("aria-label") || f.getAttribute("aria-labelledby")));
  add({ id: "labels", group: "accessibility", label: "Form fields are labelled", pass: unlabeled.length === 0, detail: unlabeled.length ? `${unlabeled.length} unlabelled field(s)` : `${fields.length} field(s) OK`, fix: "Wrap each form field in a <label> or add aria-label.", sectionId: unlabeled[0] && sectionOf(unlabeled[0]), severity: "high" });

  const badLinks = [...doc.querySelectorAll("a, button")].filter((a) => !(a.textContent.trim() || a.getAttribute("aria-label") || a.querySelector("img[alt]")));
  add({ id: "names", group: "accessibility", label: "Links & buttons have accessible names", pass: badLinks.length === 0, detail: badLinks.length ? `${badLinks.length} without a name` : "All named", fix: "Give every link/button visible text or an aria-label.", sectionId: badLinks[0] && sectionOf(badLinks[0]) });

  add({ id: "lang", group: "accessibility", label: "Document language set", pass: true, detail: '<html lang="en">' });

  const tc = contrast(tokens.text, tokens.bg);
  const pc = contrast(tokens.onPrimary, tokens.primary);
  add({ id: "token-contrast", group: "accessibility", label: "Palette contrast ≥ 4.5:1", pass: tc >= 4.5 && pc >= 4.5, detail: `text ${tc.toFixed(1)}:1 · button ${pc.toFixed(1)}:1`, fix: "Adjust colours so body text and button text reach 4.5:1." });

  // Sampled computed contrast on real text
  const lowContrast = [];
  const textEls = [...doc.body.querySelectorAll("p,li,h1,h2,h3,a,span,small,label,dd,dt,blockquote,summary")].slice(0, 400);
  for (const el of textEls) {
    if (!el.childNodes.length || ![...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim())) continue;
    const cs = win.getComputedStyle(el);
    if (cs.visibility === "hidden" || cs.display === "none" || +cs.opacity === 0) continue;
    const fg = parseRgb(cs.color);
    const bg = effectiveBg(el, win);
    if (!fg || !bg || fg.a < 0.5) continue;
    const size = parseFloat(cs.fontSize);
    const large = size >= 24 || (size >= 18.6 && +cs.fontWeight >= 700);
    const ratio = contrast(toHex(fg), bg);
    if (ratio < (large ? 3 : 4.5)) lowContrast.push({ el, ratio });
  }
  add({ id: "contrast", group: "accessibility", label: "Rendered text contrast", pass: lowContrast.length === 0, detail: lowContrast.length ? `${lowContrast.length} element(s) below WCAG AA (worst ${Math.min(...lowContrast.map((x) => x.ratio)).toFixed(1)}:1)` : `${textEls.length} text elements sampled`, fix: "Increase text contrast against its background to at least 4.5:1.", sectionId: lowContrast[0] && sectionOf(lowContrast[0].el), severity: lowContrast.length > 3 ? "high" : "medium" });

  // --- Responsiveness
  const overflow = await mobileOverflow(site);
  add({ id: "mobile-overflow", group: "responsiveness", label: "No horizontal scroll at 375px", pass: overflow.ok, detail: overflow.ok ? "Fits a 375px phone screen" : `Overflow in: ${overflow.offenders.join(", ")}`, fix: "Prevent horizontal overflow on mobile: use fluid widths, wrap flex rows, stack grids below 700px.", sectionId: overflow.offenders[0], severity: "high" });
  const allCss = site.sections.map((s) => s.css || "").join("\n");
  const hasMedia = /@media/.test(allCss) || /auto-fit|auto-fill|clamp\(/.test(allCss + site.sections.map((s) => s.html).join(""));
  add({ id: "media", group: "responsiveness", label: "Uses responsive techniques", pass: hasMedia, detail: hasMedia ? "Media queries / fluid grids present" : "No media queries or fluid grids found", fix: "Add media queries or fluid grid layouts." });
  const navMenu = doc.querySelector("[data-nav-menu]");
  add({ id: "mobile-nav", group: "responsiveness", label: "Mobile navigation pattern", pass: !!navMenu && !!doc.querySelector("[data-nav-toggle]"), detail: navMenu ? "Toggle + menu present" : "No collapsible mobile menu", fix: "Add a [data-nav-toggle] button that toggles [data-nav-menu] on small screens.", sectionId: site.sections.find((s) => s.type === "nav")?.id, severity: "low" });

  // --- Code quality
  const allHtml = site.sections.map((s) => s.html || "").join("\n");
  const inlineHandlers = (allHtml.match(/\son[a-z]+\s*=/gi) || []).length;
  add({ id: "handlers", group: "code", label: "No inline event handlers", pass: inlineHandlers === 0, detail: `${inlineHandlers} inline handler(s)`, fix: "Move inline on* handlers into script.js.", severity: "low" });
  const ids = [...doc.querySelectorAll("[id]")].map((e) => e.id);
  const dupes = ids.filter((v, i) => ids.indexOf(v) !== i);
  add({ id: "dup-ids", group: "code", label: "Unique element ids", pass: dupes.length === 0, detail: dupes.length ? `Duplicate: ${[...new Set(dupes)].join(", ")}` : `${ids.length} ids unique`, fix: "Make every id unique.", severity: "low" });
  const inlineStyles = doc.querySelectorAll("[data-wb] [style]").length;
  add({ id: "inline-styles", group: "code", label: "Styles live in CSS, not inline", pass: inlineStyles <= 3, detail: `${inlineStyles} inline style attribute(s)`, fix: "Move inline styles into the section CSS.", severity: "low" });
  const important = (allCss.match(/!important/g) || []).length;
  add({ id: "important", group: "code", label: "Minimal !important", pass: important <= 3, detail: `${important} !important`, fix: "Remove unnecessary !important declarations.", severity: "low" });
  const semantic = doc.querySelectorAll("header,nav,section,footer,main,article,figure").length;
  add({ id: "semantic", group: "code", label: "Semantic landmarks", pass: semantic >= 4, detail: `${semantic} semantic elements`, fix: "Use header/nav/section/footer/article elements." });
  const missingSections = site.sections.filter((s) => !s.html || !doc.querySelector(`[data-wb="${s.id}"] > *`));
  add({ id: "complete", group: "code", label: "All planned sections built", pass: missingSections.length === 0, detail: missingSections.length ? `Missing: ${missingSections.map((s) => s.id).join(", ")}` : `${site.sections.length}/${site.sections.length} built`, fix: "Build the missing section.", sectionId: missingSections[0]?.id, severity: "high" });

  // --- Prompt coverage (used for fidelity)
  const kc = keywordCoverage(site.prompt, doc.body.innerText || "");

  const groupScore = (g) => {
    const list = items.filter((i) => i.group === g);
    const w = { high: 3, medium: 2, low: 1 };
    const total = list.reduce((s, i) => s + w[i.severity], 0);
    const got = list.reduce((s, i) => s + (i.pass ? w[i.severity] : 0), 0);
    return total ? Math.round(55 + 45 * (got / total)) : 100;
  };
  return {
    items,
    keywordCoverage: kc.coverage,
    missingKeywords: kc.missing,
    scores: { accessibility: groupScore("accessibility"), responsiveness: groupScore("responsiveness"), codeQuality: groupScore("code") },
    passed: items.filter((i) => i.pass).length,
  };
}
