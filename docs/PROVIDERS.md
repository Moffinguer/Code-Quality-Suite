# Model provider inventory

> Work in progress: AI-agent development is only tested and configured with Claude Code.
> OpenCode and other models, the model gateway and the ai-stack database are not functional yet.

Reference for feeding the router and the DB. **Limits change every few weeks**;
figures are indicative (verified ~Aug 2026). Keep it current with the aggregators
at the end.

Four categories: **permanently free** (the substrate), **credits/trial** (one-off,
to evaluate), **paid** (archived for when there is revenue), and **local** (no API
limit; limit = your hardware).

## 1. Permanently free (no expiry; the limit is the quota)

| Provider | Best for | Free limits (indicative) | LiteLLM prefix | Card |
| ---------- | ---------- | -------------------------- | ---------------- | ------ |
| **Google Gemini** (AI Studio) | Large context, architecture | ~20 RPD/model, 1M context; quota **per project, not per key** | `gemini/` | No |
| **Groq** | Speed (many short calls) | llama-3.3-70b: 30 RPM, 1,000 RPD, 100K TPD; llama-3.1-8b more generous | `groq/` | No |
| **Cerebras** | Very fast code generation | ~1M tokens/day (most generous by volume); volatile catalog | `cerebras/` | No |
| **NVIDIA NIM** (build.nvidia.com) | Huge variety | 40 RPM; ~121 free models; some log prompts | `nvidia_nim/` | Phone verif. |
| **GitHub Models** | Prototyping, fallback | 2,000 req/day per user; low 15 RPM/150 RPD, high 10 RPM/50 RPD; 8K in/4K out | `github/` | No (PAT) |
| **Cloudflare Workers AI** | Edge helper tasks | 10,000 "neurons"/day; small context; ~39 models | `cloudflare/` | No |
| **Mistral** | Coding (Codestral, Devstral) | Experiment tier always-free; **requires training opt-in** | `mistral/` | No |
| **Scaleway** (EU) | Privacy, EU (devstral, voxtral) | 100 RPM, 200K TPM, ~1M tokens/account | OpenAI-compat (`api_base`) | No |
| **SambaNova** | Large models (Llama 405B) | Permanent free 20 RPM / 20 RPD / 200K TPD per model (+$5 initial credit) | `sambanova/` | No |
| **Cohere** | RAG, embeddings | Trial key ~100 req/day (Command R+) | `cohere/` | No |
| **Z.ai / Zhipu** | Experimentation | GLM-4.5/4.7-Flash genuinely free, no published cap | OpenAI-compat | No |
| **OVHcloud AI** (EU) | EU alternative | ~12 free models | OpenAI-compat | No |
| **Hugging Face Inference** | 200+ open models | ~$0.10/month free credit | `huggingface/` | No |
| **OpenRouter** | ONE key for many models | 20 RPM, **50 req/day** free (1,000 if you buy $10 of credits) | `openrouter/` | No |
| **Pollinations** | Text+image+audio+video | No signup for basics; per-IP hourly | OpenAI-compat | No |

> Important Gemini note: quotas are **per Google project, not per API key** -
> generating several keys in the same project does NOT multiply the quota.

## 2. Credits / trial (one-off; to evaluate paid models)

| Provider | Initial gift | Note |
| ---------- | -------------- | ------ |
| **DeepSeek** | ~5M tokens (~2,500 calls) | Then very cheap; ideal as the "first paid step" |
| **SambaNova** | $5 (30 days) | On top of the permanent free |
| **AI21** | $10 (3 months) | Jamba family |
| **Fireworks** | $1 on signup | -- |
| **NVIDIA NIM** | 1,000 credits | On top of the RPM free tier |
| **Vercel AI Gateway** | $5/month | Gateway with monthly credit |
| **Baseten** | $30 on deploy | For deploying models |
| **Hyperbolic** | credit | Early access (DeepSeek-V3.1, Qwen3-235B) |

## 3. Paid - ARCHIVE for when there is revenue

| Provider | Cost (indicative) | When to use it |
| ---------- | ------------------- | ---------------- |
| **DeepSeek** (own API) | Cheapest (cents/MTok) | First paid jump; no free-tier limits |
| **Anthropic Claude** | Opus ~$5/$25 per MTok | High quality on critical decisions |
| **OpenAI** | Pay per token | Ecosystem and tooling |
| **Groq / Cerebras / Together / Fireworks** (paid) | Cheap + fast | Volume when the free tier falls short |

> Together AI **no longer has a free trial**; Groq lowered quotas in 2026.

## 4. LOCAL models (Ollama) - no API limit, limit = hardware

| Model | Sizes | Approx. RAM (Q4) | Use |
| ------- | ------- | ------------------ | ----- |
| **Qwen2.5-Coder / Qwen3-Coder** | 0.5B-32B | 7B~=6GB, 14B~=10GB, 32B~=20GB | Best open coding; workhorse |
| **DeepSeek-Coder-V2** | 16B | ~=10GB | Code generation |
| **Codestral** (Mistral) | 22B | ~=14GB | Coding, autocomplete |
| **Devstral** (Mistral) | 24B | ~=15GB | **Tuned for agents** (tool use) |
| **Llama 3.1 / 3.3** | 8B / 70B | 8B~=6GB, 70B~=40GB+ | General purpose |
| **Gemma 3** | 4B-27B | 4B~=4GB, 27B~=18GB | Light to medium |
| **StarCoder2** | 3B-15B | by size | Autocomplete, boilerplate |

Rule of thumb: a local model for the **high-volume work** (boilerplate, tests,
docs, mechanical refactors) and reserve the good free/paid ones for the
**decisions** (architecture, hard bugs).

## Legitimate split by task type

| Task level | Quality | Suggested providers |
| ------------ | --------- | --------------------- |
| Architecture / large context / hard bugs | HIGH | Gemini, (paid: Claude/DeepSeek) |
| Fast code generation / iteration | MEDIUM | Cerebras, Groq |
| Boilerplate / tests / docs / mass refactors | LOW/volume | **Local (Ollama)**, Groq 8B |
| Fallback / alternative reasoning | -- | GitHub Models, NVIDIA NIM, OpenRouter |
| Helper tasks (embed, classification, summary) | -- | Cloudflare Workers AI, Cohere |

## Ethics and legality (important)

- Use **only legitimate free tiers**. No account rotation, no multiple keys to
  bypass quotas, no fake accounts: it is fragile, violates the ToS, and ends in a
  ban. (It would not work on Gemini anyway: the quota is per project.)
- Some providers ask for **phone verification** (NVIDIA, Mistral) as a legitimate
  anti-abuse measure.
- Community principle: do not scrape, resell, or abuse. These resources exist
  because they are respected.
- Realistic path: **$0 on free to prototype and validate -> first revenue -> paid
  DeepSeek/Claude for quality**. Free has an honest ceiling.

## Live sources (to keep this inventory current)

- `freellm.net` - 30+ providers, live online status.
- `models.dev` - catalog with a JSON API (for the automatic generator).
- GitHub: `amardeeplakshkar/awesome-free-llm-apis`, `cheahjs/free-llm-api-resources`,
  `mnfst/awesome-free-llm-apis`, `CYBIRD-D/FREE-LLM-API-Provider`.
