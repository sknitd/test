// Code panel: shows the files the agents are writing, with a live, labelled caret
// for every agent that is currently typing.
import { baseCss, normalizeTokens, scopeCss } from "./site.js";

const esc = (s) => String(s).replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[c]);

function highlight(code, lang) {
  let s = esc(code);
  if (lang === "html") {
    s = s.replace(/(&lt;\/?)([a-z0-9-]+)((?:\s+[^&]*?)?)(\/?&gt;)/gi, (m, a, tag, attrs, b) => {
      const at = attrs.replace(/([a-z-:]+)(=)("[^"]*"|'[^']*')/gi, '<i class="t-at">$1</i>$2<i class="t-str">$3</i>');
      return `<i class="t-pn">${a}</i><i class="t-tag">${tag}</i>${at}<i class="t-pn">${b}</i>`;
    });
  } else if (lang === "css") {
    // declarations first (they always follow "{" or ";"), then selectors
    s = s
      .replace(/([{;]\s*)([a-z-]+)(\s*:)([^;{}]+)/g, '$1<i class="t-at">$2</i>$3<i class="t-str">$4</i>')
      .replace(/([^{}\n][^{}]*?)(\{)/g, '<i class="t-sel">$1</i>$2');
  } else if (lang === "js") {
    s = s
      .replace(/(\/\/[^\n]*)/g, '<i class="t-com">$1</i>')
      .replace(/\b(const|let|var|function|return|if|else|for|new|true|false|null|try|catch|=>)\b/g, '<i class="t-tag">$1</i>');
  }
  return s;
}

export class CodeView {
  constructor(el, tabs) {
    this.el = el;
    this.tabs = tabs;
    this.file = "index.html";
    this.site = null;
    this.typing = new Map(); // sectionId -> { agent, html, css }
    this.jsTyping = null;
    this.dirty = true;
    this.visible = false;
    this.followCaret = true;
    tabs.addEventListener("click", (e) => {
      const b = e.target.closest("[data-file]");
      if (!b) return;
      this.file = b.dataset.file;
      for (const t of tabs.querySelectorAll("[data-file]")) t.classList.toggle("active", t === b);
      this.dirty = true;
      this.render(true);
    });
    setInterval(() => this.render(), 120);
  }

  setSite(site) {
    this.site = site;
    this.dirty = true;
  }

  setVisible(v) {
    this.visible = v;
    if (v) this.render(true);
  }

  startTyping(sectionId, agent) {
    this.typing.set(sectionId, { agent, html: "", css: "" });
    this.dirty = true;
  }
  updateTyping(sectionId, part) {
    const t = this.typing.get(sectionId);
    if (t) Object.assign(t, part);
    this.lastTyped = sectionId;
    this.dirty = true;
  }
  stopTyping(sectionId) {
    this.typing.delete(sectionId);
    this.dirty = true;
  }
  touch() {
    this.dirty = true;
  }

  caret(agent) {
    return `<span class="caret" style="--c:${agent.color}"><span class="caret-tag">${esc(agent.name)}</span></span>`;
  }

  render(force = false) {
    if (!this.visible || (!this.dirty && !force) || !this.site) return;
    this.dirty = false;
    const site = this.site;
    let out = "";
    if (this.file === "index.html") {
      out += highlight(`<!doctype html>\n<html lang="en">\n<head>\n  <meta charset="utf-8">\n  <title>${site.plan?.siteName || "Website"}</title>\n  <link rel="stylesheet" href="styles.css">\n</head>\n<body>\n`, "html");
      for (const s of site.sections) {
        const t = this.typing.get(s.id);
        if (t) out += highlight(t.html, "html") + this.caret(t.agent) + "\n\n";
        else if (s.html) out += highlight(s.html, "html") + "\n\n";
        else out += `<i class="t-com">  &lt;!-- ${esc(s.title)}: waiting for a developer --&gt;</i>\n\n`;
      }
      out += highlight(`  <script src="script.js"></script>\n</body>\n</html>`, "html");
    } else if (this.file === "styles.css") {
      out += highlight(site.tokens ? baseCss(normalizeTokens(site.tokens)) : "/* waiting for the designer's tokens */\n", "css") + "\n";
      for (const s of site.sections) {
        const t = this.typing.get(s.id);
        if (t && t.css) out += `<i class="t-com">/* ${esc(s.title)} */</i>\n` + highlight(t.css, "css") + this.caret(t.agent) + "\n\n";
        else if (s.css && !t) out += `<i class="t-com">/* ${esc(s.title)} */</i>\n` + highlight(scopeCss(s.css, s.id), "css") + "\n";
      }
    } else {
      if (this.jsTyping) out += highlight(this.jsTyping.js, "js") + this.caret(this.jsTyping.agent);
      else out += site.js ? highlight(site.js, "js") : '<i class="t-com">// waiting for the interaction engineer</i>';
    }
    const atBottom = this.el.scrollTop + this.el.clientHeight >= this.el.scrollHeight - 30;
    this.el.innerHTML = out;
    const carets = this.el.querySelectorAll(".caret");
    if (this.followCaret && carets.length) {
      const target = carets[carets.length - 1];
      const top = target.offsetTop - this.el.clientHeight * 0.6;
      this.el.scrollTop = Math.max(0, top);
    } else if (atBottom && force) this.el.scrollTop = this.el.scrollHeight;
  }
}
