// The shared "workspace" all agents write into, plus helpers that assemble it
// into a real HTML document.

export function emptySite(prompt) {
  return {
    prompt,
    plan: null,
    nav: [],
    layouts: {},
    tokens: null,
    copy: {},
    guidance: [],
    sections: [], // [{ id, type, title, purpose, html, css, owner, status }]
    js: "",
    evals: [],
    qa: null,
  };
}

// ------------------------------------------------------------ colour helpers

export function hexToRgb(hex) {
  let h = String(hex || "").trim().replace("#", "");
  if (h.length === 3) h = h.split("").map((c) => c + c).join("");
  if (!/^[0-9a-f]{6}$/i.test(h)) return null;
  return [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16));
}
function luminance([r, g, b]) {
  const f = (c) => {
    c /= 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
}
export function contrast(a, b) {
  const ra = hexToRgb(a);
  const rb = hexToRgb(b);
  if (!ra || !rb) return 21;
  const [l1, l2] = [luminance(ra), luminance(rb)].sort((x, y) => y - x);
  return (l1 + 0.05) / (l2 + 0.05);
}
export function mix(hexA, hexB, t) {
  const a = hexToRgb(hexA) || [0, 0, 0];
  const b = hexToRgb(hexB) || [255, 255, 255];
  return "#" + a.map((v, i) => Math.round(v + (b[i] - v) * t).toString(16).padStart(2, "0")).join("");
}

const DEFAULT_TOKENS = {
  primary: "#4f46e5",
  secondary: "#0f172a",
  accent: "#f59e0b",
  bg: "#ffffff",
  surface: "#f4f5fb",
  text: "#111827",
  muted: "#5b6475",
  onPrimary: "#ffffff",
  headingFont: "Poppins",
  bodyFont: "Inter",
  radius: "14px",
  shadow: "0 10px 30px rgba(15, 23, 42, 0.08)",
  style: "Clean and modern",
};

/** Fill gaps and repair contrast problems so a bad token set can't make text unreadable. */
export function normalizeTokens(t = {}) {
  const out = { ...DEFAULT_TOKENS };
  for (const k of Object.keys(DEFAULT_TOKENS)) {
    if (t[k] && typeof t[k] === "string") out[k] = t[k].trim();
  }
  for (const k of ["primary", "secondary", "accent", "bg", "surface", "text", "muted", "onPrimary"]) {
    if (!hexToRgb(out[k])) out[k] = DEFAULT_TOKENS[k];
  }
  const darkBg = luminance(hexToRgb(out.bg)) < 0.3;
  if (contrast(out.text, out.bg) < 4.5) out.text = darkBg ? "#f5f7fb" : "#111827";
  if (Math.min(contrast(out.muted, out.bg), contrast(out.muted, out.surface)) < 4.5) out.muted = mix(out.text, out.bg, 0.3);
  if (contrast(out.onPrimary, out.primary) < 4.5) {
    out.onPrimary = contrast("#ffffff", out.primary) >= contrast("#111111", out.primary) ? "#ffffff" : "#111111";
  }
  for (const f of ["headingFont", "bodyFont"]) out[f] = out[f].replace(/["';{}<>]/g, "").slice(0, 60);
  // Derived (not chosen by the designer): primary nudged toward the text colour
  // until it is readable as text on the page background.
  out.primaryText = out.primary;
  // (sections use both bg and surface as backgrounds, so it must pass on both)
  const readable = (c) => Math.min(contrast(c, out.bg), contrast(c, out.surface)) >= 4.6;
  for (let t = 0.1; !readable(out.primaryText) && t <= 1.001; t += 0.1) out.primaryText = mix(out.primary, out.text, t);
  return out;
}

export function fontsHref(tokens) {
  const fams = [...new Set([tokens.headingFont, tokens.bodyFont])].filter(Boolean);
  if (!fams.length) return "";
  return (
    "https://fonts.googleapis.com/css2?" +
    fams.map((f) => `family=${encodeURIComponent(f).replace(/%20/g, "+")}:wght@400;500;600;700;800`).join("&") +
    "&display=swap"
  );
}

export function baseCss(tokens) {
  const t = normalizeTokens(tokens);
  return `:root{
  --color-primary:${t.primary};--color-secondary:${t.secondary};--color-accent:${t.accent};
  --color-bg:${t.bg};--color-surface:${t.surface};--color-text:${t.text};--color-muted:${t.muted};
  --color-on-primary:${t.onPrimary};--color-primary-text:${t.primaryText};
  --font-heading:"${t.headingFont}",system-ui,sans-serif;--font-body:"${t.bodyFont}",system-ui,sans-serif;
  --radius:${t.radius};--shadow:${t.shadow};--container:1160px;
}
*,*::before,*::after{box-sizing:border-box}
html{scroll-behavior:smooth;-webkit-text-size-adjust:100%}
body{margin:0;background:var(--color-bg);color:var(--color-text);font-family:var(--font-body);font-size:1.0625rem;line-height:1.65;overflow-x:hidden}
h1,h2,h3,h4{font-family:var(--font-heading);line-height:1.15;margin:0 0 .6em;letter-spacing:-.01em}
h1{font-size:clamp(2.2rem,5.5vw,4rem)}h2{font-size:clamp(1.7rem,3.6vw,2.6rem)}h3{font-size:1.25rem}
p{margin:0 0 1em}a{color:var(--color-primary-text)}img,svg{max-width:100%;display:block}
:focus-visible{outline:3px solid var(--color-accent);outline-offset:3px}
.container{width:min(100% - 2.5rem,var(--container));margin-inline:auto}
.section-pad{padding-block:clamp(3.5rem,8vw,6.5rem)}
.eyebrow{display:inline-block;font-size:.8rem;font-weight:700;letter-spacing:.14em;text-transform:uppercase;color:var(--color-primary-text);margin-bottom:.8rem}
.btn{display:inline-flex;align-items:center;justify-content:center;gap:.5rem;padding:.85rem 1.5rem;border-radius:999px;font-weight:600;font-family:var(--font-body);font-size:1rem;text-decoration:none;border:2px solid transparent;cursor:pointer;transition:transform .2s ease,box-shadow .2s ease,background .2s ease}
.btn:hover{transform:translateY(-2px)}
.btn-primary{background:var(--color-primary);color:var(--color-on-primary);box-shadow:0 8px 20px color-mix(in srgb,var(--color-primary) 35%,transparent)}
.btn-outline{background:transparent;color:inherit;border-color:currentColor}
.card{background:var(--color-surface);border-radius:var(--radius);padding:1.6rem;box-shadow:var(--shadow)}
.grid-auto{display:grid;gap:1.5rem;grid-template-columns:repeat(auto-fit,minmax(min(100%,240px),1fr))}
.js-reveal .reveal{opacity:0;transform:translateY(24px);transition:opacity .7s ease,transform .7s ease}
.js-reveal .reveal.is-visible{opacity:1;transform:none}
@media (prefers-reduced-motion:reduce){html{scroll-behavior:auto}.js-reveal .reveal{opacity:1;transform:none;transition:none}}
`;
}

/** Ensure a section's CSS can't leak: prefix any selector that doesn't start with the section id. */
export function scopeCss(css, id) {
  if (!css) return "";
  const prefix = `#${id}`;
  // Very small CSS transformer: handles plain rules and @media/@supports blocks; leaves @keyframes alone.
  let out = "";
  let i = 0;
  const src = css.replace(/\/\*[\s\S]*?\*\//g, "");
  const scopeSelectors = (sel) =>
    sel
      .split(",")
      .map((s) => {
        s = s.trim();
        if (!s) return s;
        if (s.startsWith(prefix)) return s;
        if (/^(html|body|:root)\b/.test(s)) return `${prefix} ${s.replace(/^(html|body|:root)\s*/, "")}`.trim();
        return `${prefix} ${s}`;
      })
      .join(", ");
  while (i < src.length) {
    const open = src.indexOf("{", i);
    if (open === -1) break;
    const head = src.slice(i, open).trim();
    if (head.startsWith("@keyframes") || head.startsWith("@font-face") || head.startsWith("@-webkit-keyframes")) {
      let depth = 1;
      let j = open + 1;
      while (j < src.length && depth) {
        if (src[j] === "{") depth++;
        else if (src[j] === "}") depth--;
        j++;
      }
      out += src.slice(i, j).trim() + "\n";
      i = j;
    } else if (head.startsWith("@")) {
      // @media / @supports: scope the inner rules
      let depth = 1;
      let j = open + 1;
      while (j < src.length && depth) {
        if (src[j] === "{") depth++;
        else if (src[j] === "}") depth--;
        j++;
      }
      out += `${head}{\n${scopeCss(src.slice(open + 1, j - 1), id)}}\n`;
      i = j;
    } else {
      const close = src.indexOf("}", open);
      if (close === -1) break;
      out += `${scopeSelectors(head)}{${src.slice(open + 1, close).trim()}}\n`;
      i = close + 1;
    }
  }
  return out;
}

export function sectionsCss(site) {
  return site.sections.filter((s) => s.css).map((s) => `/* ${s.title || s.id} */\n${scopeCss(s.css, s.id)}`).join("\n");
}

const escapeHtml = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

/** Full standalone document — what the user downloads. */
export function assembleDocument(site, { wrappers = false } = {}) {
  const tokens = normalizeTokens(site.tokens || {});
  const title = site.plan?.siteName ? `${site.plan.siteName}${site.plan.tagline ? " — " + site.plan.tagline : ""}` : "Website";
  const desc = site.plan?.tagline || site.prompt || "";
  const body = site.sections
    .filter((s) => s.html)
    .map((s) => (wrappers ? `<div data-wb="${s.id}" class="wb-wrap">\n${s.html}\n</div>` : s.html))
    .join("\n\n");
  const fonts = fontsHref(tokens);
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
<meta name="description" content="${escapeHtml(desc).slice(0, 160)}">
${fonts ? `<link rel="preconnect" href="https://fonts.googleapis.com">\n<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>\n<link rel="stylesheet" href="${fonts}">` : ""}
<style>
${baseCss(tokens)}
${sectionsCss(site)}
</style>
</head>
<body>
${body}
${site.js ? `<script>\ntry {\n${site.js.replace(/<\/script/gi, "<\\/script")}\n} catch (e) { console.error(e); }\n</script>` : ""}
</body>
</html>`;
}

export function exportFiles(site) {
  const tokens = normalizeTokens(site.tokens || {});
  const doc = assembleDocument(site);
  return {
    "index.html": doc,
    "styles.css": baseCss(tokens) + "\n" + sectionsCss(site),
    "script.js": site.js || "",
  };
}
