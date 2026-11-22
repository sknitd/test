# AgentForge: multi-agent website builder

Describe a website in the prompt box and a team of AI agents plans, designs, writes, codes, reviews and evaluates it while you watch. Each agent has its own named, coloured cursor on the live canvas, and the Code tab shows every agent's caret typing into `index.html`, `styles.css` and `script.js`.

Without an API key it runs in an **offline demo mode**, so the whole pipeline works out of the box. Connect one or more LLM providers in **Settings** to have real models do the work. Each agent can use a different provider and model.

```bash
cd multi-agent-website-builder
npm install
npm start          # → http://127.0.0.1:5173
```

Requires Node 18+.

## The agent team (planned pipeline)

| Stage | Agent | Role | Thinks about… | Creates… |
|---|---|---|---|---|
| 1 · Plan | 🧭 **Atlas** | Product Planner / Orchestrator | site type, audience, visitor journey | site name, tagline, goals, tone, ordered section plan |
| 2 · Design *(parallel)* | 📐 **Blueprint** | UX / Information Architect | best layout per section, page rhythm | layout spec per section + navigation |
| | 🎨 **Prism** | Brand & Visual Designer | identity, WCAG contrast, font pairing | design tokens (palette, fonts, radius, shadow) |
| | ✍️ **Quill** | Copywriter | audience, tone, benefit-led headlines | copy for every section |
| 3 · Build *(parallel)* | 🛠️ **Forge**, ⚡ **Bolt** (+ any you add) | Frontend Developers | semantic, accessible, responsive markup | scoped HTML + CSS per section, built side by side |
| | ✨ **Spark** | Interaction Engineer | minimal, gracefully-degrading interactivity | `script.js` (mobile nav, smooth scroll, reveal, forms) |
| 4 · Review | 🛡️ **Sentinel** | QA & Accessibility Reviewer | layout bugs, a11y, responsiveness, brief fit | issue list → developers fix flagged sections |
| 5 · Evaluate *(loop)* | ⚖️ **Judge** | Evaluator | calibrated rubric scoring | scores, verdict, targeted improvements → developers refine → re-score |

The **Agents** tab lets you:
- edit each agent's **Think** brief (how it reasons) and **Create** brief (what it produces)
- choose each agent's provider, model, reasoning effort and temperature
- enable or disable agents, rename them, and recolour their cursors
- **add developers** (more developers means more sections built in parallel)
- **create custom agents** (for example an SEO or brand-compliance reviewer) that run after planning, to give guidance, or after the build, to request section changes

Each kind of agent has a fixed **output contract** (JSON, or `<thoughts>/<html>/<css>` blocks) that is added to its system prompt, so the orchestrator can always parse the result.

### Evaluation

The Evaluator combines its own judgement with **automated checks** run on the real rendered DOM:

- **Accessibility:** a single `<h1>`, heading order, image alt text, form labels, accessible names, palette contrast, and sampled rendered-text contrast
- **Responsiveness:** no horizontal scroll at 375px (measured in a hidden phone-width iframe), responsive CSS, and a mobile nav pattern
- **Code quality:** no inline handlers, unique ids, few inline styles or `!important`, semantic landmarks, and every planned section built
- **Prompt fidelity:** how many of the prompt's keywords appear in the page

Rubric: prompt fidelity, visual design, content, accessibility, responsiveness and code quality, combined into a weighted overall score. If the score is below the threshold (Settings, default 85), the Judge sends targeted instructions back to the developers and scores again. The number of rounds is configurable.

### Refining

Once a site is built, the prompt box switches to **Refine this site**. Requests such as "make it dark with a green accent", "add a pricing section" or "remove the team section" go to the planner, which splits them into token changes, new sections, removals and per-section edits for the team. With the offline demo, refinement understands colours, themes, fonts and adding or removing sections. Free-form edits need a real provider.

## Providers

Settings → Providers. Each card has an enable switch, an API key field, base URL, default model, **Save & test connection** (lists the models available to the key and shows the latency, or the exact error) and a link to get a key.

| Provider | API |
|---|---|
| Anthropic (Claude) | official `@anthropic-ai/sdk`, defaults to `claude-opus-5-5` with adaptive thinking (the reasoning summary is shown in the activity feed) and server-side refusal fallback |
| OpenAI | Chat Completions |
| Google Gemini | `generateContent` |
| OpenRouter, Groq, Mistral, DeepSeek, xAI, Together | OpenAI-compatible |
| Ollama (local) | OpenAI-compatible at `http://localhost:11434/v1`, no key |
| Custom | any OpenAI-compatible endpoint |

Keys can also come from environment variables (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `OPENROUTER_API_KEY`, `GROQ_API_KEY`, `MISTRAL_API_KEY`, `DEEPSEEK_API_KEY`, `XAI_API_KEY`, `TOGETHER_API_KEY`, `CUSTOM_API_KEY`).

If a provider call fails or returns output that can't be parsed, that one step falls back to the offline generator and the activity feed says so. You can turn this off in Settings.

## Security notes

- API keys are stored by the local server in `data/providers.json` (file mode `600`, git-ignored). The browser only ever sees a masked hint such as `sk-a…f3c9`.
- The builder canvas is a sandboxed iframe **without scripts**, so generated code can't touch the app. **▶ Try it** and **Open ↗** run the site's JavaScript in a sandbox with an opaque origin, which can't reach the builder, its storage or its API.
- The API only accepts `application/json` requests. Cross-origin pages, including the sandboxed preview, can't call it without a CORS preflight, and the server never approves one.
- The server listens on `127.0.0.1` by default (`HOST` and `PORT` env vars).

## Project layout

```
server.js            static files, provider settings store, /api/test, /api/chat
providers.js         adapters: Anthropic SDK, OpenAI-compatible, Gemini
public/
  index.html, css/app.css
  js/agents.js       default team, think/create briefs, output contracts, rubric
  js/orchestrator.js the pipeline (plan → design ‖ → build ‖ → QA → eval loop) + refine
  js/canvas.js       live preview, multi-agent cursors, highlights
  js/codeview.js     code panel with per-agent typing carets
  js/checks.js       automated accessibility / responsiveness / code checks
  js/demo.js         offline stand-in for every agent
  js/site.js         workspace model, design tokens → CSS, document assembly
  js/llm.js          prompt building, API client, output parsing
  js/ui.js, views.js builder panels, Agents and Settings pages
tests/smoke.mjs      headless end-to-end test (npm test)
```

## Exporting

**Download** saves a single self-contained `index.html` with inline CSS and JS. **Copy HTML** copies the same file to the clipboard. **Open ↗** opens it in a new tab.
