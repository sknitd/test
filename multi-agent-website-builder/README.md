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

| Provider | API | Default model | Other models in the catalog |
|---|---|---|---|
| Anthropic (Claude) | official `@anthropic-ai/sdk` (adaptive thinking, refusal fallback) | `claude-opus-5-5` | Fable 5.2, Sonnet 5.5, Haiku 5.5, plus previous Fable 5.1 / Opus 5 / Sonnet 5 |
| OpenAI | Responses API | `gpt-6.2-astra` | GPT-6.2 Sol, GPT-6.1 Terra, GPT-6 Luna |
| Google Gemini | `generateContent` | `gemini-4-hydrogen` | Gemini 4 Carbon / Argon / Neon, 3.8 Flash, 3.6 Flash, 3.5 Flash-Lite, 3.1 Pro (preview) |
| OpenRouter | OpenAI-compatible | `anthropic/claude-opus-5.5` | top models from every lab, plus `openrouter/auto` |
| Groq | OpenAI-compatible | `openai/gpt-oss-120b` | GPT-OSS 20B, Qwen 3.8 27B (preview), MiniMax M2.7 (preview) |
| Mistral | OpenAI-compatible | `mistral-large-4` | Mistral Small 4, Ministral 3 8B |
| DeepSeek | OpenAI-compatible | `deepseek-v4-pro` | `deepseek-flash` (V4.1 Flash) |
| xAI (Grok) | OpenAI-compatible | `grok-4.7` | Grok 4.6, Grok Build 0.1, Grok 4.20 reasoning / non-reasoning |
| Together AI | OpenAI-compatible | `deepseek-ai/DeepSeek-V4-Pro-0813` | Kimi K3.1 Pro, Qwen4 Max, GLM-5.3, Muse Spark Open, and fast Flash models |
| Ollama (local) | OpenAI-compatible at `http://localhost:11434/v1`, no key | `qwen3.8:27b` | Qwen 3.6, Gemma 4 (31B / 12B), GPT-OSS 20B, Devstral Small 2, Qwen3 Coder, small 9B models |
| Custom | any OpenAI-compatible endpoint (LM Studio, llama.cpp, vLLM…) | — | whatever your server lists |

The curated list lives in [`models.js`](models.js), checked against each provider's model and deprecation docs on 2026-11-22. Models those docs mark as deprecated or shut down are left out (for example `gpt-5-mini`, `gemini-2.5-flash` and Groq's Llama 3.x models). **Save & test connection** also lists every chat model your key can use, so newer models appear automatically. Each provider card has a "recommended models" list with a **Use** button and shows which models your key can access.

### Offline / local models

- **Offline demo:** built in. It needs no key and no model, and is selected automatically when no provider is configured. It's a template generator, not an AI.
- **Ollama** (real models on your computer):
  1. Install from https://ollama.com/download.
  2. Download a model with `ollama pull qwen3.8:27b`. On a 16 GB machine use `gemma4:12b`; on 8 GB use `qwen3.5:9b`.
  3. In Settings, enable **Ollama (local)** and click **Save & test connection**.
  4. Choose it as the default provider, or set it on individual agents.

  The builder's server must run on the same computer as Ollama. Models smaller than about 14B parameters often break the output format; those steps then fall back to the offline generator.
- **LM Studio / llama.cpp / vLLM:** start their local server, then put its URL into the **Custom** provider, e.g. `http://localhost:1234/v1`.

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
