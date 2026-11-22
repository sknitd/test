// Default agent roster. Every agent has:
//  - think:  how it reasons before producing anything (editable in the Agents tab)
//  - create: what it produces (editable)
//  - kind:   which slot in the pipeline it fills; the output contract for each kind
//            is fixed (see CONTRACTS) so the orchestrator can always parse results.

export const KINDS = {
  planner: { label: "Planner", stage: 1, stageName: "Plan" },
  architect: { label: "UX Architect", stage: 2, stageName: "Design" },
  designer: { label: "Visual Designer", stage: 2, stageName: "Design" },
  copywriter: { label: "Copywriter", stage: 2, stageName: "Design" },
  developer: { label: "Developer", stage: 3, stageName: "Build" },
  interaction: { label: "Interaction Engineer", stage: 4, stageName: "Build" },
  qa: { label: "QA Reviewer", stage: 5, stageName: "Review" },
  evaluator: { label: "Evaluator", stage: 6, stageName: "Evaluate" },
  custom: { label: "Custom", stage: 0, stageName: "Custom" },
};

export const CUSTOM_STAGES = {
  planning: "After planning — adds guidance for designers, writers and developers",
  review: "After build — reviews the site and requests section changes",
};

export const DEFAULT_AGENTS = [
  {
    id: "atlas",
    name: "Atlas",
    kind: "planner",
    role: "Product Planner / Orchestrator",
    color: "#7c5cff",
    icon: "🧭",
    enabled: true,
    provider: "default",
    model: "",
    effort: "medium",
    temperature: 0.4,
    think:
      "Read the request carefully. Work out what kind of website this is, who it is for, and what a visitor must be able to do. " +
      "Pick the sections a professional site of this kind needs — no more, no fewer — and order them as a visitor's journey. " +
      "Infer a fitting site name and tone if the request doesn't give one.",
    create:
      "A build plan: site name, tagline, site type, target audience, goals, tone of voice, and an ordered list of sections " +
      "(always a nav first and a footer last) with a one-line purpose each.",
  },
  {
    id: "blueprint",
    name: "Blueprint",
    kind: "architect",
    role: "UX / Information Architect",
    color: "#00b3a4",
    icon: "📐",
    enabled: true,
    provider: "default",
    model: "",
    effort: "low",
    temperature: 0.4,
    think:
      "For every planned section decide the layout that best serves its purpose on desktop and mobile. " +
      "Vary rhythm between sections (full-bleed, split, grid, centred) so the page doesn't feel repetitive. Keep navigation simple.",
    create: "A layout spec per section (layout pattern, components, notes for developers) and the navigation items.",
  },
  {
    id: "prism",
    name: "Prism",
    kind: "designer",
    role: "Brand & Visual Designer",
    color: "#ff4f8b",
    icon: "🎨",
    enabled: true,
    provider: "default",
    model: "",
    effort: "low",
    temperature: 0.7,
    think:
      "Choose a visual identity that matches the brand, audience and tone. Make sure text colours have at least 4.5:1 contrast " +
      "against their backgrounds and that the button text is readable on the primary colour. Pair one heading and one body Google Font.",
    create: "Design tokens: colour palette, font pair, corner radius, shadow and a short style description.",
  },
  {
    id: "quill",
    name: "Quill",
    kind: "copywriter",
    role: "Copywriter",
    color: "#ffb020",
    icon: "✍️",
    enabled: true,
    provider: "default",
    model: "",
    effort: "low",
    temperature: 0.8,
    think:
      "Write for the target audience in the planned tone. Lead with benefits, keep sentences short and concrete, " +
      "give every section a clear heading and every call to action a specific verb. Never use lorem ipsum.",
    create: "Final copy for every section: heading, subheading, body text, list items and call-to-action labels.",
  },
  {
    id: "forge",
    name: "Forge",
    kind: "developer",
    role: "Frontend Developer",
    color: "#2f80ff",
    icon: "🛠️",
    enabled: true,
    provider: "default",
    model: "",
    effort: "medium",
    temperature: 0.3,
    think:
      "Turn the layout spec and copy into semantic, accessible HTML and modern responsive CSS. " +
      "Use the design tokens via CSS variables, scope every CSS rule to the section id, and make it look polished on a 375px phone.",
    create: "Production HTML and CSS for the sections assigned to you.",
  },
  {
    id: "bolt",
    name: "Bolt",
    kind: "developer",
    role: "Frontend Developer",
    color: "#14b8f0",
    icon: "⚡",
    enabled: true,
    provider: "default",
    model: "",
    effort: "medium",
    temperature: 0.3,
    think:
      "Work in parallel with the other developers. Match the shared design language exactly so your sections look like " +
      "they were built by the same hand. Prefer CSS grid/flex, fluid type with clamp(), and generous whitespace.",
    create: "Production HTML and CSS for the sections assigned to you.",
  },
  {
    id: "spark",
    name: "Spark",
    kind: "interaction",
    role: "Interaction Engineer",
    color: "#f97316",
    icon: "✨",
    enabled: true,
    provider: "default",
    model: "",
    effort: "low",
    temperature: 0.3,
    think:
      "Add only the interactivity the page needs: mobile navigation, smooth scrolling, tasteful reveal-on-scroll and friendly " +
      "form feedback. Everything must degrade gracefully if JavaScript fails.",
    create: "A single vanilla JavaScript file (no libraries).",
  },
  {
    id: "sentinel",
    name: "Sentinel",
    kind: "qa",
    role: "QA & Accessibility Reviewer",
    color: "#22c55e",
    icon: "🛡️",
    enabled: true,
    provider: "default",
    model: "",
    effort: "medium",
    temperature: 0.2,
    think:
      "Review the built page like a strict senior engineer: broken layout, missing content, accessibility (alt text, labels, " +
      "heading order, contrast, focus states), responsiveness and anything that contradicts the request.",
    create: "A list of concrete issues, each tied to a section with a precise fix instruction for the developers.",
  },
  {
    id: "judge",
    name: "Judge",
    kind: "evaluator",
    role: "Evaluator",
    color: "#e11d48",
    icon: "⚖️",
    enabled: true,
    provider: "default",
    model: "",
    effort: "medium",
    temperature: 0.2,
    think:
      "Score the site objectively against the rubric using both the automated check results and your own reading of the page. " +
      "Be calibrated: 90+ is excellent and shippable, 70 is mediocre. Only request improvements that would raise the score.",
    create: "Scores per rubric criterion (0–100), an overall score, a verdict, and targeted improvement instructions per section.",
  },
];

export function newCustomAgent(n) {
  const colors = ["#a855f7", "#0ea5e9", "#84cc16", "#ef4444", "#eab308", "#06b6d4"];
  return {
    id: `custom-${Date.now().toString(36)}`,
    name: `Agent ${n}`,
    kind: "custom",
    customStage: "review",
    role: "Specialist",
    color: colors[n % colors.length],
    icon: "🤖",
    enabled: true,
    provider: "default",
    model: "",
    effort: "low",
    temperature: 0.5,
    think: "Describe how this agent should reason, e.g. 'Think like an SEO specialist: check headings, keywords and meta descriptions.'",
    create: "Describe what this agent produces, e.g. 'Precise change requests for sections that hurt search ranking.'",
  };
}

// Output contracts — appended to every system prompt. Not user-editable because
// the orchestrator parses these formats.
export const CONTRACTS = {
  planner: `Respond with ONLY a JSON object, no prose, in this shape:
{"thoughts":"2-4 sentences of your reasoning",
 "siteName":"...","tagline":"...","siteType":"e.g. restaurant | saas | portfolio | agency | fitness | shop | event | nonprofit | clinic | education | travel | realestate | other",
 "audience":"...","goals":["..."],"tone":"...",
 "sections":[{"id":"kebab-case-id","type":"nav|hero|features|about|services|menu|products|pricing|testimonials|gallery|stats|team|faq|cta|contact|footer|custom","title":"...","purpose":"..."}]}
Use 6-11 sections. The first must be type "nav" with id "nav", the last type "footer" with id "footer". ids must be unique.`,

  planner_refine: `The site already exists. Decide what must change to satisfy the user's change request.
Respond with ONLY a JSON object:
{"thoughts":"...","tokens":{ /* optional: only design tokens that should change, same keys as the design tokens */ },
 "changes":[{"sectionId":"existing-id","instruction":"precise instruction for the developer"}],
 "newSections":[{"id":"kebab-id","type":"...","title":"...","purpose":"...","after":"existing-section-id"}],
 "removeSections":["section-id"]}
Use empty arrays when nothing applies.`,

  architect: `Respond with ONLY a JSON object:
{"thoughts":"...","nav":[{"label":"...","href":"#section-id"}],
 "layouts":{"<section-id>":{"layout":"e.g. split-image-right | centered | 3-col-cards | masonry | timeline | accordion","components":["..."],"notes":"..."}}}
Include every section id from the plan in "layouts".`,

  designer: `Respond with ONLY a JSON object:
{"thoughts":"...",
 "tokens":{"primary":"#hex","secondary":"#hex","accent":"#hex","bg":"#hex","surface":"#hex","text":"#hex","muted":"#hex","onPrimary":"#hex",
           "headingFont":"Google Font family name","bodyFont":"Google Font family name","radius":"e.g. 14px","shadow":"CSS box-shadow value",
           "style":"short description of the visual style"}}
All colours must be 6-digit hex. "text" on "bg" and "onPrimary" on "primary" must have contrast >= 4.5.`,

  copywriter: `Respond with ONLY a JSON object:
{"thoughts":"...",
 "copy":{"<section-id>":{"eyebrow":"short label","heading":"...","subheading":"...","body":"...",
          "items":[{"title":"...","text":"...","meta":"optional: price, role, rating, etc."}],
          "cta":{"label":"...","href":"#section-id"},"secondaryCta":{"label":"...","href":"#..."}}}}
Include every section id from the plan. Omit fields that don't apply to a section.`,

  developer: `Respond in EXACTLY this format, with no other text and no markdown code fences:
<thoughts>2-3 sentences about your approach</thoughts>
<html>
the section markup — a single root element (<header>, <section> or <footer>) whose id attribute is the section id
</html>
<css>
CSS for this section only; every selector must start with #<section-id>
</css>
Rules:
- Available CSS variables: --color-primary --color-secondary --color-accent --color-bg --color-surface --color-text --color-muted --color-on-primary --color-primary-text (primary tuned for readable text on --color-bg; use it for coloured text) --font-heading --font-body --radius --shadow --container.
- Available utility classes: .container (centred max-width wrapper), .btn .btn-primary .btn-outline, .eyebrow, .section-pad (vertical padding), .card, .grid-auto (responsive auto-fit grid).
- Add class "reveal" to blocks that should fade in on scroll.
- Navigation: use <header id="nav" class="site-nav">, a <button class="nav-toggle" data-nav-toggle aria-expanded="false" aria-label="Open menu"> and a <nav data-nav-menu aria-label="Main">.
- Forms: <form data-demo-form> with a <label> for every field.
- Images: no external image files. Use CSS gradients, inline SVG or emoji for visuals; any <img> needs meaningful alt text.
- Must be fully responsive (test mentally at 375px) and accessible. No <script> tags, no inline event handlers.`,

  developer_revise: `You are revising an existing section. Apply the instructions while keeping everything else intact.
Respond in EXACTLY the same <thoughts>…</thoughts><html>…</html><css>…</css> format as before, returning the COMPLETE updated section.`,

  interaction: `Respond in EXACTLY this format, no other text:
<thoughts>...</thoughts>
<js>
vanilla JavaScript (no imports, no libraries). It runs at the end of <body>.
Must handle: [data-nav-toggle] toggling [data-nav-menu] (set aria-expanded and an "is-open" class on the menu),
smooth scrolling for in-page links (closing the mobile menu), reveal-on-scroll: add class "js-reveal" to <html> then add
"is-visible" to .reveal elements with IntersectionObserver, and [data-demo-form] submit -> preventDefault and show a friendly
inline confirmation message. Guard every query against missing elements.
</js>`,

  qa: `Respond with ONLY a JSON object:
{"thoughts":"...","summary":"one sentence",
 "issues":[{"sectionId":"id or 'global'","severity":"high|medium|low","issue":"what is wrong","fix":"precise instruction for a developer"}]}
Only report real problems. Return at most 8 issues, most severe first.
When screenshots are attached, look for visual problems the code hides: overlapping or cramped elements, text running off the edge, broken alignment, unreadable contrast, awkward phone layouts.
Review it as a static front-end prototype: forms, cart and checkout are demo-only by design. Never ask for backend, CMS, e-commerce platform or template-language integrations; invented sample details (address, hours, prices) are expected, not issues.`,

  evaluator: `Respond with ONLY a JSON object:
{"thoughts":"...",
 "scores":{"promptFidelity":0-100,"visualDesign":0-100,"content":0-100,"accessibility":0-100,"responsiveness":0-100,"codeQuality":0-100},
 "verdict":"one or two sentences",
 "strengths":["..."],
 "improvements":[{"sectionId":"id","instruction":"precise instruction that would raise the score"}]}
When screenshots are attached, base visual design and responsiveness on what they show (layout, spacing, overflow, legibility at phone width).
Score it as a static front-end prototype: demo-only forms/cart/checkout and invented sample details are expected and must not lower the score. Never request backend, CMS, e-commerce platform or template-language integrations. Do penalize leftover placeholders or template syntax.`,

  custom_planning: `Respond with ONLY a JSON object:
{"thoughts":"...","guidance":"concise guidance that will be shared with the designers, copywriter and developers"}`,

  custom_review: `Respond with ONLY a JSON object:
{"thoughts":"...","summary":"...","changes":[{"sectionId":"existing-id","instruction":"precise instruction for a developer"}]}
Return an empty "changes" array if nothing needs to change.`,
};

export const RUBRIC = [
  { key: "promptFidelity", label: "Prompt fidelity", weight: 0.22 },
  { key: "visualDesign", label: "Visual design", weight: 0.18 },
  { key: "content", label: "Content quality", weight: 0.15 },
  { key: "accessibility", label: "Accessibility", weight: 0.17 },
  { key: "responsiveness", label: "Responsiveness", weight: 0.14 },
  { key: "codeQuality", label: "Code quality", weight: 0.14 },
];
