# Inventario de modelos por categoría (ago 2026)

Clasificado como pediste: **solo gratis**, **gratis y de pago (freemium)**,
**solo de pago**, y **local**. Cifras orientativas — cambian casi cada mes.

> IMPORTANTE: "modelos" ≠ "agentes". No hay 185 modelos distintos buenos. Tienes
> un POOL curado (abajo) y muchos AGENTES que lo reutilizan. La proporción es la
> composición del pool de cada nivel, no 185 modelos únicos.

---

## 1. SOLO GRATIS (open-weights vía free tiers; sin versión de pago propia)

| Modelo | Proveedor(es) free | Notas |
|--------|--------------------|-------|
| GPT-OSS 120B / 20B | Groq, Cerebras, GitHub | Abierto de OpenAI, rápido |
| Llama 3.3 70B / 4 Scout | Groq, OpenRouter | ~320 tok/s en Groq |
| Qwen3 32B / Qwen3-Coder | Groq, OpenRouter :free | Coding |
| Qwen3 235B | Cerebras | Grande y rápido en free |
| GLM-4.7-Flash | Z.ai | Sin tope publicado |
| Gemma 3 27B, DeepSeek-R1 | OpenRouter :free | Rotan |
| gpt-4o-mini | GitHub Models | Free tier de GitHub |

Fuentes free: Groq, Cerebras, OpenRouter (~24 `:free`), GitHub Models, Cloudflare,
NVIDIA NIM, Z.ai, Pollinations, Kilo, LLM7. **Tu dato no cambia con los prompts**.

## 2. GRATIS Y DE PAGO (freemium: free tier + API de pago del mismo proveedor)

| Familia | Free | De pago | Prefijo LiteLLM |
|---------|------|---------|-----------------|
| **Gemini** | Flash / Flash-Lite | Pro ($2/$12), Flash de pago | `gemini/` |
| **Mistral** | Experiment (Codestral, Devstral, Large) | API de pago | `mistral/` |
| **DeepSeek** | Grant ~5M tokens | V4 Flash $0.14/$0.28 (el más barato) | `deepseek/` |
| **Groq / Cerebras** | Free tier | Dev/paid tier | `groq/` `cerebras/` |

## 3. SOLO DE PAGO (frontier propietario; sin API gratis)

| Modelo | Precio in/out por MTok | Prefijo |
|--------|------------------------|---------|
| Claude Opus 5 / 4.8 | $5 / $25 | `anthropic/` |
| Claude Sonnet 5 | $2-3 / $15 | `anthropic/` |
| Claude Haiku 4.5 | $1 / $5 | `anthropic/` |
| GPT-5.5 / 5.6 | ~$5 / $30 | `openai/` |
| GPT-5 mini / nano | $0.25/$2 · $0.05/$0.40 | `openai/` |
| Gemini 3.1 Pro | $2 / $12 | `gemini/` |
| Grok 4.x | $0.20 / $0.50 – $3/$15 | `xai/` |
| DeepSeek V4 Flash | $0.14 / $0.28 (el más barato) | `deepseek/` |
| GLM-5.2 · Kimi K3 · MiniMax M3 | bajo, open-weights | varios |

## 4. LOCAL (Ollama) — sin coste ni límite de API; límite = tu hardware

**Consumer (un GPU / Mac):**

| Modelo | VRAM (Q4) | Uso |
|--------|-----------|-----|
| Qwen3-Coder 30B | ~19 GB (24 GB GPU) | El mejor coder local (256K ctx) |
| Qwen3.6 27B | ~17 GB | Mejor dense general+coding |
| Devstral 24B | ~14 GB | **Agéntico** (46.8% SWE-Bench) |
| GPT-OSS 20B | 16 GB | Buen todoterreno |
| Codestral 22B | ~14 GB | Autocompletado (FIM) |
| DeepSeek-Coder-V2 16B | 16 GB | Presupuesto |
| Qwen3 8B / Llama 3.1 8B | ~5-6 GB | 8 GB de RAM |

**Server-class (open-weight pero 80 GB+ / multi-GPU):** DeepSeek V4-Pro, GLM-5.2,
Kimi K2.6/K3, Qwen3-Coder 480B. Frontier abierto, pero de facto son de API salvo
que tengas hardware de datacenter.

---

## Mapeo a tus 5 niveles (proporción 1 pago : 2 free : 1 freemium : 1 local)

| Nivel | Agentes | Pago | Free | Freemium | Local |
|-------|--------:|-----:|-----:|---------:|------:|
| Orquestador | 5 | 1 | 2 | 1 | 1 |
| Analistas | 10 | 2 | 4 | 2 | 2 |
| QA / Testing | 50 | 10 | 20 | 10 | 10 |
| Desarrolladores | 40 | 8 | 16 | 8 | 8 |
| Becarios | 80 | 16 | 32 | 16 | 16 |

> Recuerda: son **agentes** que reutilizan el pool, no modelos únicos.

## Aviso: la proporción uniforme NO es óptima en coste

Poner **16 becarios de pago** haciendo boilerplate contradice el criterio
free-first que ya montamos: gastas dinero en lo trivial. Lo cost-racional es
concentrar el pago ARRIBA (donde la calidad decide) y dejar el fondo casi todo
gratis+local:

| Nivel | Pago | Freemium | Free | Local |
|-------|-----:|---------:|-----:|------:|
| Orquestador | 40% | 20% | 20% | 20% |
| Analistas | 20% | 30% | 30% | 20% |
| QA / Testing | 5% | 25% | 40% | 30% |
| Desarrolladores | 10% | 20% | 40% | 30% |
| Becarios | 0-5% | 15% | 40% | 40% |

Tú decides; la BD soporta cualquiera de las dos (es solo `quality_tier` + coste
por modelo y `min_quality_tier` por rol).

## Fuentes vivas
freellm.net · models.dev · cheahjs/free-llm-api-resources · morphllm.com/best-ollama-models
