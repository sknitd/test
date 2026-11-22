// Curated model catalog per provider, checked against each provider's own docs.
// `default: true` marks the model used when an agent / provider has no model set.
// status: "preview" | "previous" (still served, superseded) — current models omit it.
// Live lists from "Save & test connection" are merged in the UI, so models released
// after MODELS_CHECKED still show up for your account.

export const MODELS_CHECKED = "2026-11-22";

export const MODELS = {
  // https://platform.claude.com/docs/en/about-claude/models
  anthropic: [
    { id: "claude-opus-5-5", name: "Claude Opus 5.5", tier: "flagship", note: "Default — best balance of quality and cost for agents & code", default: true },
    { id: "claude-fable-5-2", name: "Claude Fable 5.2", tier: "frontier", note: "Most capable; higher price, longer turns" },
    { id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5", tier: "balanced", note: "Fast and capable for everyday coding" },
    { id: "claude-haiku-5-5", name: "Claude Haiku 5.5", tier: "fast", note: "Fastest and cheapest" },
    { id: "claude-fable-5-1", name: "Claude Fable 5.1", tier: "frontier", note: "Previous Fable", status: "previous" },
    { id: "claude-opus-5", name: "Claude Opus 5", tier: "flagship", note: "Previous Opus", status: "previous" },
    { id: "claude-sonnet-5", name: "Claude Sonnet 5", tier: "balanced", note: "Previous Sonnet", status: "previous" },
  ],

  // https://developers.openai.com/api/docs/models (+ /docs/deprecations). Called via the Responses API.
  openai: [
    { id: "gpt-6.2-astra", name: "GPT-6.2 Astra", tier: "frontier", note: "OpenAI's recommended starting point — most capable", default: true },
    { id: "gpt-6.2-sol", name: "GPT-6.2 Sol", tier: "balanced", note: "Everyday work & agents at scale; best intelligence/cost balance" },
    { id: "gpt-6.1-terra", name: "GPT-6.1 Terra", tier: "balanced", note: "Fast; visual reasoning and natural writing" },
    { id: "gpt-6-luna", name: "GPT-6 Luna", tier: "fast", note: "Most efficient, high-volume tasks" },
  ],

  // https://ai.google.dev/gemini-api/docs/models (now aistudio.google.com/docs/models)
  gemini: [
    { id: "gemini-4-hydrogen", name: "Gemini 4 Hydrogen", tier: "balanced", note: "Google's recommendation for new projects — fast everyday coding & agents", default: true },
    { id: "gemini-4-carbon", name: "Gemini 4 Carbon", tier: "frontier", note: "Strongest reasoning model; complex engineering" },
    { id: "gemini-4-argon", name: "Gemini 4 Argon", tier: "reasoning", note: "Efficient frontier reasoning, fewer tokens per turn than Carbon" },
    { id: "gemini-4-neon", name: "Gemini 4 Neon", tier: "flagship", note: "Frontier intelligence with fast task completion" },
    { id: "gemini-3.8-flash", name: "Gemini 3.8 Flash", tier: "fast", note: "Latest Flash; coding & agentic work" },
    { id: "gemini-3.6-flash", name: "Gemini 3.6 Flash", tier: "fast", note: "Speed / multimodal balance" },
    { id: "gemini-3.5-flash-lite", name: "Gemini 3.5 Flash-Lite", tier: "fast", note: "Cheapest, highest throughput" },
    { id: "gemini-3.1-pro-preview", name: "Gemini 3.1 Pro", tier: "flagship", note: "Previous Pro", status: "preview" },
  ],

  // OpenRouter routes to every provider; ids from https://openrouter.ai/api/v1/models
  openrouter: [
    { id: "anthropic/claude-opus-5.5", name: "Claude Opus 5.5", tier: "flagship", note: "via Anthropic", default: true },
    { id: "anthropic/claude-sonnet-5.5", name: "Claude Sonnet 5.5", tier: "balanced", note: "via Anthropic" },
    { id: "openai/gpt-6.2-astra", name: "GPT-6.2 Astra", tier: "frontier", note: "OpenAI flagship" },
    { id: "openai/gpt-6.2-sol", name: "GPT-6.2 Sol", tier: "balanced", note: "OpenAI everyday model" },
    { id: "google/gemini-4-carbon", name: "Gemini 4 Carbon", tier: "frontier", note: "Google's strongest reasoning" },
    { id: "google/gemini-4-hydrogen", name: "Gemini 4 Hydrogen", tier: "balanced", note: "Google workhorse" },
    { id: "x-ai/grok-4.7", name: "Grok 4.7", tier: "flagship", note: "xAI flagship" },
    { id: "deepseek/deepseek-v4-pro", name: "DeepSeek V4 Pro", tier: "flagship", note: "Open-weight MoE, 1M context" },
    { id: "qwen/qwen4-max", name: "Qwen4 Max", tier: "flagship", note: "Alibaba flagship" },
    { id: "moonshotai/kimi-k3.1-pro", name: "Kimi K3.1 Pro", tier: "flagship", note: "Moonshot flagship" },
    { id: "z-ai/glm-5.3", name: "GLM 5.3", tier: "balanced", note: "Z.ai" },
    { id: "mistralai/mistral-large-4-0", name: "Mistral Large 4", tier: "flagship", note: "Mistral flagship" },
    { id: "openrouter/auto", name: "Auto router", tier: "balanced", note: "OpenRouter picks a model per request" },
  ],

  // https://console.groq.com/docs/models (+ /docs/deprecations)
  groq: [
    { id: "openai/gpt-oss-120b", name: "GPT-OSS 120B", tier: "flagship", note: "Production; ~500 tok/s", default: true },
    { id: "openai/gpt-oss-20b", name: "GPT-OSS 20B", tier: "fast", note: "Production; ~1000 tok/s" },
    { id: "qwen/qwen3.8-27b", name: "Qwen 3.8 27B", tier: "balanced", note: "Thinking + instruct modes", status: "preview" },
    { id: "minimaxai/minimax-m2.7", name: "MiniMax M2.7", tier: "balanced", note: "Enterprise access", status: "preview" },
  ],

  // https://docs.mistral.ai/getting-started/models/models_overview/
  mistral: [
    { id: "mistral-large-4", name: "Mistral Large 4", tier: "flagship", note: "Flagship multimodal MoE, 1M context", default: true },
    { id: "mistral-small-2603", name: "Mistral Small 4", tier: "balanced", note: "Instruct + reasoning + coding, 256k" },
    { id: "ministral-8b-2512", name: "Ministral 3 8B", tier: "fast", note: "Small and efficient" },
  ],

  // https://api-docs.deepseek.com/quick_start/pricing
  deepseek: [
    { id: "deepseek-v4-pro", name: "DeepSeek V4 Pro", tier: "flagship", note: "Best quality; thinking on by default", default: true },
    { id: "deepseek-flash", name: "DeepSeek V4.1 Flash", tier: "fast", note: "Cheap and fast; vision" },
  ],

  // https://docs.x.ai/docs/models
  xai: [
    { id: "grok-4.7", name: "Grok 4.7", tier: "flagship", note: "xAI's recommendation for code & everything else", default: true },
    { id: "grok-4.6", name: "Grok 4.6", tier: "flagship", note: "Previous flagship", status: "previous" },
    { id: "grok-build-0.1", name: "Grok Build 0.1", tier: "coding", note: "Build-focused model" },
    { id: "grok-4.20-0309-reasoning", name: "Grok 4.20 (reasoning)", tier: "reasoning", note: "1M context" },
    { id: "grok-4.20-0309-non-reasoning", name: "Grok 4.20 (non-reasoning)", tier: "fast", note: "1M context, no thinking" },
  ],

  // https://docs.together.ai/docs/serverless-models
  together: [
    { id: "deepseek-ai/DeepSeek-V4-Pro-0813", name: "DeepSeek V4 Pro", tier: "flagship", note: "1M context, tools & structured output", default: true },
    { id: "moonshotai/Kimi-K3.1-Pro", name: "Kimi K3.1 Pro", tier: "flagship", note: "1M context" },
    { id: "Qwen/Qwen4-Max", name: "Qwen4 Max", tier: "flagship", note: "Alibaba flagship, vision" },
    { id: "zai-org/GLM-5.3", name: "GLM-5.3", tier: "flagship", note: "Z.ai, 1M context" },
    { id: "meta-models/Muse-Spark-Open-816B-A42B", name: "Muse Spark Open", tier: "flagship", note: "Meta open MoE" },
    { id: "Qwen/Qwen3.8-Flash", name: "Qwen3.8 Flash", tier: "fast", note: "Cheap and fast" },
    { id: "zai-org/GLM-5.3-Flash", name: "GLM-5.3 Flash", tier: "fast", note: "Cheap and fast" },
    { id: "deepseek-ai/DeepSeek-V4.1-Flash", name: "DeepSeek V4.1 Flash", tier: "fast", note: "Very cheap" },
    { id: "MiniMaxAI/MiniMax-M3.1-Flash", name: "MiniMax M3.1 Flash", tier: "fast", note: "1M context" },
    { id: "openai/gpt-oss-120b", name: "GPT-OSS 120B", tier: "balanced", note: "OpenAI open-weight" },
  ],

  // Local models from https://ollama.com/library — download first with `ollama pull <id>`.
  // ram = rough memory needed at Ollama's default 4-bit quantization (estimate, not from the docs).
  ollama: [
    { id: "qwen3.8:27b", name: "Qwen 3.8 27B", tier: "local", note: "Newest Qwen; strong coding & agentic work", ram: "~18 GB", default: true },
    { id: "qwen3.6:35b", name: "Qwen 3.6 35B", tier: "local", note: "Agentic coding upgrade", ram: "~24 GB" },
    { id: "gemma4:31b", name: "Gemma 4 31B", tier: "local", note: "Google; reasoning & coding", ram: "~20 GB" },
    { id: "gemma4:12b", name: "Gemma 4 12B", tier: "local", note: "Good quality on a 16 GB machine", ram: "~9 GB" },
    { id: "gpt-oss:20b", name: "GPT-OSS 20B", tier: "local", note: "OpenAI open-weight reasoning", ram: "~14 GB" },
    { id: "devstral-small-2:24b", name: "Devstral Small 2 24B", tier: "local", note: "Mistral coding agent model", ram: "~16 GB" },
    { id: "qwen3-coder:30b", name: "Qwen3 Coder 30B", tier: "local", note: "Coding MoE (older but solid)", ram: "~19 GB" },
    { id: "nemotron-3.5-lightning:30b", name: "Nemotron 3.5 Lightning 30B", tier: "local", note: "MoE, 3B active — fast", ram: "~20 GB" },
    { id: "inkling-2-mini", name: "Inkling 2 Mini", tier: "local", note: "26B MoE (5.4B active), runs on a Mac", ram: "~17 GB" },
    { id: "qwen3.5:9b", name: "Qwen 3.5 9B", tier: "local", note: "For 8–16 GB machines", ram: "~7 GB" },
    { id: "mimo-v2.6:9b", name: "MiMo v2.6 9B", tier: "local", note: "Small model for code & agents", ram: "~7 GB" },
  ],

  custom: [],
};
