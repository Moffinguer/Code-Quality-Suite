# Inventario de proveedores de modelos

Referencia para alimentar el router y la BD. **Los límites cambian cada pocas
semanas**; las cifras son orientativas (verificadas ~ago 2026). Mantén la versión
viva con los agregadores del final.

Cuatro categorías: **permanentes gratis** (el sustrato), **créditos/trial** (una
vez, para evaluar), **de pago** (archivar para cuando haya ingresos) y **locales**
(sin límite de API, límite = tu hardware).

---

## 1. Permanentes gratis (sin caducidad; el límite son las cuotas)

| Proveedor | Mejor para | Límites free (orientativos) | Prefijo LiteLLM | Tarjeta |
|-----------|-----------|-----------------------------|-----------------|---------|
| **Google Gemini** (AI Studio) | Contexto grande, arquitectura | ~20 RPD/modelo, 1M contexto (recortado 50-80% en 2025); cuota **por proyecto, no por key** | `gemini/` | No |
| **Groq** | Velocidad (muchas llamadas cortas) | llama-3.3-70b: 30 RPM, 1.000 RPD, 100K TPD; llama-3.1-8b más generoso | `groq/` | No |
| **Cerebras** | Generación de código rapidísima | ~1M tokens/día (el más generoso en volumen); catálogo volátil | `cerebras/` | No |
| **NVIDIA NIM** (build.nvidia.com) | Variedad enorme | 40 RPM; ~121 modelos free; algunos loguean prompts | `nvidia_nim/` | Verif. tel. |
| **GitHub Models** | Prototipado, fallback | 2.000 req/día por usuario; low 15 RPM/150 RPD, high 10 RPM/50 RPD; 8K in/4K out | `github/` | No (PAT) |
| **Cloudflare Workers AI** | Tareas auxiliares en el edge | 10.000 "neurons"/día; contexto pequeño; ~39 modelos | `cloudflare/` | No |
| **Mistral** | Coding (Codestral, Devstral) | Tier Experiment always-free; **requiere opt-in a training** | `mistral/` | No |
| **Scaleway** (EU) | Privacidad, EU (devstral, voxtral) | 100 RPM, 200K TPM, ~1M tokens/cuenta | OpenAI-compat (`api_base`) | No |
| **SambaNova** | Modelos grandes (Llama 405B) | Free permanente 20 RPM / 20 RPD / 200K TPD por modelo (+$5 crédito inicial) | `sambanova/` | No |
| **Cohere** | RAG, embeddings | Trial key ~100 req/día (Command R+) | `cohere/` | No |
| **Z.ai / Zhipu** | Experimentación | GLM-4.5/4.7-Flash genuinamente gratis, sin tope publicado | OpenAI-compat | No |
| **OVHcloud AI** (EU) | Alternativa EU | ~12 modelos free | OpenAI-compat | No |
| **Hugging Face Inference** | 200+ modelos open | ~$0.10/mes de crédito free | `huggingface/` | No |
| **OpenRouter** | UNA key para muchos modelos | 20 RPM, **50 req/día** free (1.000 si compras $10 en créditos) | `openrouter/` | No |
| **Pollinations** | Texto+imagen+audio+vídeo | Sin registro para lo básico; por-IP horario | OpenAI-compat | No |

> Nota Gemini importante: las cuotas son **por proyecto Google, no por API key** —
> generar varias keys en el mismo proyecto NO multiplica la cuota.

## 2. Créditos / trial (una vez; para evaluar modelos de pago)

| Proveedor | Regalo inicial | Nota |
|-----------|----------------|------|
| **DeepSeek** | ~5M tokens (~2.500 llamadas) | Luego baratísimo; ideal como "primer paso de pago" |
| **SambaNova** | $5 (30 días) | Sobre el free permanente |
| **AI21** | $10 (3 meses) | Familia Jamba |
| **Fireworks** | $1 al registrarse | — |
| **NVIDIA NIM** | 1.000 créditos | Sobre el free por RPM |
| **Vercel AI Gateway** | $5/mes | Gateway con crédito mensual |
| **Baseten** | $30 en deploy | Para desplegar modelos |
| **Hyperbolic** | crédito | Acceso temprano (DeepSeek-V3.1, Qwen3-235B) |

## 3. De pago — ARCHIVAR para cuando haya ingresos

| Proveedor | Coste (orientativo) | Cuándo usarlo |
|-----------|---------------------|---------------|
| **DeepSeek** (API propia) | El más barato (céntimos/MTok) | Primer salto de pago; sin límites de free |
| **Anthropic Claude** | Opus 4.6 ~$5/$25 por MTok | Calidad alta en decisiones críticas |
| **OpenAI** | Pago por token | Ecosistema y tooling |
| **Groq / Cerebras / Together / Fireworks** (paid) | Barato + rápido | Volumen cuando el free se queda corto |

> Together AI **ya no tiene trial gratis**; Groq bajó cuotas en 2026.

## 4. Modelos LOCALES (Ollama) — sin límite de API, límite = hardware

| Modelo | Tamaños | RAM aprox. (Q4) | Uso |
|--------|---------|-----------------|-----|
| **Qwen2.5-Coder / Qwen3-Coder** | 0.5B–32B | 7B≈6GB, 14B≈10GB, 32B≈20GB | El mejor coding open; workhorse |
| **DeepSeek-Coder-V2** | 16B | ≈10GB | Generación de código |
| **Codestral** (Mistral) | 22B | ≈14GB | Coding, autocompletado |
| **Devstral** (Mistral) | 24B | ≈15GB | **Afinado para agentes** (tool use) |
| **Llama 3.1 / 3.3** | 8B / 70B | 8B≈6GB, 70B≈40GB+ | Propósito general |
| **Gemma 3** | 4B–27B | 4B≈4GB, 27B≈18GB | Ligero a medio |
| **StarCoder2** | 3B–15B | según tamaño | Autocompletado, boilerplate |

Regla práctica: un modelo local para el **trabajo de mucho volumen** (boilerplate,
tests, docs, refactors mecánicos) y reservar los buenos gratis/de pago para las
**decisiones** (arquitectura, bugs difíciles).

---

## Estrategia legítima de reparto por tipo de tarea

| Nivel de tarea | Calidad | Proveedores sugeridos |
|----------------|---------|-----------------------|
| Arquitectura / contexto grande / bugs difíciles | ALTA | Gemini, (de pago: Claude/DeepSeek) |
| Generación rápida de código / iteración | MEDIA | Cerebras, Groq |
| Boilerplate / tests / docs / refactors masivos | BAJA/volumen | **Local (Ollama)**, Groq 8B |
| Fallback / razonamiento alternativo | — | GitHub Models, NVIDIA NIM, OpenRouter |
| Tareas auxiliares (embed, clasificación, resumen) | — | Cloudflare Workers AI, Cohere |

---

## Ética y legalidad (importante)

- Usa **solo free tiers legítimos**. Nada de rotación de cuentas, keys múltiples
  para saltar cuotas, ni cuentas falsas: es frágil, va contra los ToS y termina
  en bloqueo. (Además, en Gemini no funcionaría: la cuota es por proyecto.)
- Algunos proveedores piden **verificación por teléfono** (NVIDIA, Mistral) como
  medida anti-abuso legítima.
- Principio de la comunidad: no scrapear, no revender, no abusar. Estos recursos
  existen porque se respetan.
- Modelo de negocio realista: **€0 en free para prototipar y validar → primer
  ingreso → DeepSeek/Claude de pago para calidad**. El free tiene techo honesto.

## Fuentes vivas (para mantener este inventario al día)

- `freellm.net` — 30+ proveedores, estado online en vivo.
- `models.dev` — catálogo con API JSON (para el generador automático).
- GitHub: `amardeeplakshkar/awesome-free-llm-apis`, `cheahjs/free-llm-api-resources`,
  `mnfst/awesome-free-llm-apis`, `CYBIRD-D/FREE-LLM-API-Provider`.
