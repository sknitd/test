// Visual review: render the built page at desktop and phone widths and turn it
// into JPEG tiles the QA reviewer and evaluator can look at (multimodal input).
// Runs entirely in the browser with html-to-image (served from node_modules).
import { assembleDocument } from "./site.js";

let libPromise;
function loadLib() {
  if (window.htmlToImage) return Promise.resolve(window.htmlToImage);
  libPromise ||= new Promise((resolve, reject) => {
    const s = document.createElement("script");
    s.src = "/vendor/html-to-image.js";
    s.onload = () => resolve(window.htmlToImage);
    s.onerror = () => reject(new Error("Screenshot library missing — run npm install"));
    document.head.appendChild(s);
  });
  return libPromise;
}

const timeout = (p, ms) => Promise.race([p, new Promise((r) => setTimeout(r, ms))]);

// html-to-image can't read cross-origin Google Fonts stylesheets, so embed the
// fonts ourselves (Latin subset only) — otherwise text renders in a fallback
// font with different widths and wraps differently from the real page.
const fontCache = new Map();
function base64(buf) {
  const bytes = new Uint8Array(buf);
  let bin = "";
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  return btoa(bin);
}
function fontCss(doc) {
  const link = doc.querySelector('link[rel="stylesheet"][href*="fonts.googleapis.com"]');
  if (!link) return Promise.resolve("");
  if (!fontCache.has(link.href)) {
    fontCache.set(
      link.href,
      (async () => {
        try {
          const css = await (await fetch(link.href)).text();
          let out = css
            .split(/(?=\/\* [a-z-]+ \*\/)/)
            .filter((b) => b.startsWith("/* latin */"))
            .join("\n");
          const urls = [...new Set((out.match(/url\((https:[^)]+)\)/g) || []).map((u) => u.slice(4, -1)))];
          await Promise.all(
            urls.map(async (u) => {
              const b64 = base64(await (await fetch(u)).arrayBuffer());
              out = out.split(u).join(`data:font/woff2;base64,${b64}`);
            }),
          );
          return out;
        } catch {
          return ""; // offline: fall back to system fonts
        }
      })(),
    );
  }
  return fontCache.get(link.href);
}

async function renderFrame(site, width) {
  const frame = document.createElement("iframe");
  // No scripts: generated code never runs with the app's privileges.
  frame.setAttribute("sandbox", "allow-same-origin");
  frame.setAttribute("aria-hidden", "true");
  frame.tabIndex = -1;
  frame.style.cssText = `position:fixed;left:-30000px;top:0;width:${width}px;height:900px;border:0;pointer-events:none`;
  await new Promise((resolve) => {
    frame.onload = resolve;
    frame.srcdoc = assembleDocument({ ...site, js: "" });
    document.body.appendChild(frame);
    setTimeout(resolve, 5000);
  });
  const doc = frame.contentDocument;
  if (doc?.fonts) await timeout(doc.fonts.ready, 3000);
  await new Promise((r) => setTimeout(r, 150));
  return frame;
}

function toJpeg(canvas, quality = 0.72) {
  return canvas.toDataURL("image/jpeg", quality);
}

function slice(source, { outWidth, tileHeight, maxTiles }) {
  const scale = outWidth / source.width;
  const fullH = Math.round(source.height * scale);
  const tiles = [];
  for (let y = 0; y < fullH && tiles.length < maxTiles; y += tileHeight) {
    const h = Math.min(tileHeight, fullH - y);
    if (h < 40) break;
    const c = document.createElement("canvas");
    c.width = outWidth;
    c.height = h;
    const ctx = c.getContext("2d");
    ctx.drawImage(source, 0, y / scale, source.width, h / scale, 0, 0, outWidth, h);
    tiles.push(toJpeg(c));
  }
  return { tiles, truncated: fullH > tileHeight * maxTiles };
}

function thumb(source, width, aspect) {
  const c = document.createElement("canvas");
  c.width = width;
  c.height = Math.round(width * aspect);
  const srcH = Math.min(source.height, source.width * aspect);
  c.getContext("2d").drawImage(source, 0, 0, source.width, srcH, 0, 0, width, Math.round((width * srcH) / source.width));
  return toJpeg(c, 0.7);
}

async function shoot(lib, site, width, maxHeight) {
  const frame = await renderFrame(site, width);
  try {
    const doc = frame.contentDocument;
    const height = Math.min(doc.documentElement.scrollHeight, maxHeight);
    frame.style.height = `${height}px`;
    const fonts = await fontCss(doc);
    const opts = { width, height, pixelRatio: 1, backgroundColor: frame.contentWindow.getComputedStyle(doc.body).backgroundColor || "#ffffff", cacheBust: false };
    if (fonts) opts.fontEmbedCSS = fonts;
    else opts.skipFonts = true;
    try {
      return await lib.toCanvas(doc.documentElement, opts);
    } catch {
      return await lib.toCanvas(doc.documentElement, { ...opts, fontEmbedCSS: undefined, skipFonts: true });
    }
  } finally {
    frame.remove();
  }
}

/**
 * @returns {Promise<{desktop: string[], mobile: string[], desktopThumb: string, mobileThumb: string, truncated: boolean}>}
 *          image data URLs (JPEG)
 */
export async function captureSite(site, { maxDesktopTiles = 4, maxMobileTiles = 4 } = {}) {
  const lib = await loadLib();
  const desk = await shoot(lib, site, 1280, 9000);
  const mob = await shoot(lib, site, 390, 12000);
  const d = slice(desk, { outWidth: 1000, tileHeight: 1400, maxTiles: maxDesktopTiles });
  const m = slice(mob, { outWidth: 390, tileHeight: 1400, maxTiles: maxMobileTiles });
  return {
    desktop: d.tiles,
    mobile: m.tiles,
    truncated: d.truncated || m.truncated,
    desktopThumb: thumb(desk, 360, 0.62),
    mobileThumb: thumb(mob, 120, 2),
  };
}

/** Turn captured screenshots into message parts for a multimodal model. */
export function imageParts(shots) {
  if (!shots) return [];
  const parts = [];
  const add = (label, list) =>
    list.forEach((url, i) => {
      parts.push({ type: "text", text: `${label} — part ${i + 1} of ${list.length}${shots.truncated && i === list.length - 1 ? " (page continues below)" : ""}:` });
      parts.push({ type: "image", mediaType: "image/jpeg", data: url.slice(url.indexOf(",") + 1) });
    });
  add("Screenshot: desktop, 1280px wide (scaled)", shots.desktop);
  add("Screenshot: phone, 390px wide", shots.mobile);
  return parts;
}
