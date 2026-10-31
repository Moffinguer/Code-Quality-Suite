# Model inventory by category (Aug 2026)

Classified as requested: **free only**, **free and paid (freemium)**, **paid
only**, and **local**. Figures are indicative -- they change almost monthly.

> IMPORTANT: "models" != "agents". There are not 185 distinct good models. You have
> a curated POOL (below) and many AGENTS that reuse it. The proportion is the pool
> composition of each level, not 185 unique models.

## 1. FREE ONLY (open weights via free tiers; no own paid version)

| Model | Free provider(s) | Notes |
| ------- | ------------------ | ------- |
| GPT-OSS 120B / 20B | Groq, Cerebras, GitHub | OpenAI open weights, fast |
| Llama 3.3 70B / 4 Scout | Groq, OpenRouter | ~320 tok/s on Groq |
| Qwen3 32B / Qwen3-Coder | Groq, OpenRouter :free | Coding |
| Qwen3 235B | Cerebras | Large and fast on free |
| GLM-4.7-Flash | Z.ai | No published cap |
| Gemma 3 27B, DeepSeek-R1 | OpenRouter :free | Rotate |
| gpt-4o-mini | GitHub Models | GitHub free tier |

Free sources: Groq, Cerebras, OpenRouter (~24 `:free`), GitHub Models, Cloudflare,
NVIDIA NIM, Z.ai, Pollinations, Kilo, LLM7.

## 2. FREE AND PAID (freemium: free tier + paid API from the same provider)

| Family | Free | Paid | LiteLLM prefix |
| -------- | ------ | ------ | ---------------- |
| **Gemini** | Flash / Flash-Lite | Pro ($2/$12), paid Flash | `gemini/` |
| **Mistral** | Experiment (Codestral, Devstral, Large) | Paid API | `mistral/` |
| **DeepSeek** | Grant ~5M tokens | V4 Flash $0.14/$0.28 (cheapest) | `deepseek/` |
| **Groq / Cerebras** | Free tier | Dev/paid tier | `groq/` `cerebras/` |

## 3. PAID ONLY (proprietary frontier; no free API)

| Model | Price in/out per MTok | Prefix |
| ------- | ----------------------- | -------- |
| Claude Opus 5 / 4.8 | $5 / $25 | `anthropic/` |
| Claude Sonnet 5 | $2-3 / $15 | `anthropic/` |
| Claude Haiku 4.5 | $1 / $5 | `anthropic/` |
| GPT-5.5 / 5.6 | ~$5 / $30 | `openai/` |
| GPT-5 mini / nano | $0.25/$2 · $0.05/$0.40 | `openai/` |
| Gemini 3.1 Pro | $2 / $12 | `gemini/` |
| Grok 4.x | $0.20 / $0.50 - $3/$15 | `xai/` |
| DeepSeek V4 Flash | $0.14 / $0.28 (cheapest) | `deepseek/` |
| GLM-5.2 · Kimi K3 · MiniMax M3 | low, open weights | various |

## 4. LOCAL (Ollama) - no cost or API limit; limit = your hardware

**Consumer (single GPU / Mac):**

| Model | VRAM (Q4) | Use |
| ------- | ----------- | ----- |
| Qwen3-Coder 30B | ~19 GB (24 GB GPU) | Best local coder (256K ctx) |
| Qwen3.6 27B | ~17 GB | Best dense general+coding |
| Devstral 24B | ~14 GB | **Agentic** (46.8% SWE-Bench) |
| GPT-OSS 20B | 16 GB | Good all-rounder |
| Codestral 22B | ~14 GB | Autocomplete (FIM) |
| DeepSeek-Coder-V2 16B | 16 GB | Budget |
| Qwen3 8B / Llama 3.1 8B | ~5-6 GB | 8 GB of RAM |

**Server-class (open weights but 80 GB+ / multi-GPU):** DeepSeek V4-Pro, GLM-5.2,
Kimi K2.6/K3, Qwen3-Coder 480B. Open frontier, but de facto API-only unless you
have datacenter hardware.

## Mapping to your 5 levels (proportion 1 paid : 2 free : 1 freemium : 1 local)

| Level | Agents | Paid | Free | Freemium | Local |
| ------- | -------: | -----: | -----: | ---------: | ------: |
| Orchestrator | 5 | 1 | 2 | 1 | 1 |
| Analysts | 10 | 2 | 4 | 2 | 2 |
| QA / Testing | 50 | 10 | 20 | 10 | 10 |
| Developers | 40 | 8 | 16 | 8 | 8 |
| Interns | 80 | 16 | 32 | 16 | 16 |

> Remember: these are **agents** reusing the pool, not unique models.

## Note: the uniform proportion is NOT cost-optimal

Putting **16 paid interns** on boilerplate contradicts the free-first criterion we
built: you spend money on the trivial. The cost-rational move is to concentrate
paid at the TOP (where quality decides) and leave the bottom almost all free+local:

| Level | Paid | Freemium | Free | Local |
| ------- | -----: | ---------: | -----: | ------: |
| Orchestrator | 40% | 20% | 20% | 20% |
| Analysts | 20% | 30% | 30% | 20% |
| QA / Testing | 5% | 25% | 40% | 30% |
| Developers | 10% | 20% | 40% | 30% |
| Interns | 0-5% | 15% | 40% | 40% |

Your call; the DB supports either (just `quality_tier` + per-model cost and
`min_quality_tier` per role).

## Live sources

freellm.net · models.dev · cheahjs/free-llm-api-resources · morphllm.com/best-ollama-models
