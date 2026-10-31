# Goose - install and configure (AI agent layer)

Goose is the open-source agent runtime we use instead of a custom orchestrator. It
runs locally (desktop app + CLI), talks to 25+ model providers plus local models via
Ollama, and supports a conductor -> subagents hierarchy: a strong model plans and
cheap/local models do the bulk (ranks by model, to minimise cost).

> Since 2.1 the main path is Claude Code with role subagents plus the local gateway
> (`docs/AI-SETUP.md`). Goose stays an alternative runtime; point it at the gateway (section 6)
> so it uses the same roles, fallbacks and budgets.

## 1. Install

- Desktop app or CLI from the official Goose docs (goose-docs.ai). On macOS/Linux
  the CLI installs via the official script; on Windows use the desktop app or WSL.
- Verify: `goose --version`.

## 2. Configure providers (your API keys)

Run `goose configure` and add the providers you have keys for - Anthropic, OpenAI,
Google Gemini, DeepSeek, Groq, OpenRouter, etc. Keys are stored by Goose (config
file / OS keyring), not in this repo.

Local models (no API cost, limit = your hardware):

```text
# install Ollama, then:
ollama pull qwen3-coder      # or llama3.3, qwen3, devstral...
# add Ollama in `goose configure` as an OpenAI-compatible provider:
#   base URL http://localhost:11434
```

## 3. Model tiers (the "ranks") to minimise cost

Two mechanisms, use both:

- **Lead / worker split**: set a strong model as the lead (planning/decisions) and a
  cheaper or local model as the worker (execution). This is the quickest 2-tier cost
  split.
- **Recipes**: define one recipe per role - orchestrator, architect, backend, tests,
  boilerplate - each with its own prompt (your `AGENTS.md`), tools, and model. Point
  the low tiers at free/local models and the top tier at a strong model.

Suggested mapping (adjust to your keys):

| Rank | Role | Model tier |
| ------ | ------ | ----------- |
| 0 | Orchestrator / architect | strong (paid, or best free) |
| 1 | Backend / frontend / DB | good free (Groq/Cerebras/Gemini) |
| 2 | Tests / boilerplate / docs | cheap free or local (Ollama) |

## 4. Hierarchy / teams

A conductor recipe decomposes a requirement and delegates to subagents that run
concurrently; subagents can even be other coding agents (Aider, Claude Code) via the
Agent Client Protocol.

Reliability note (from 2026 testing): autonomous multi-domain decomposition on
free/local models drifts past ~2-3 hand-offs. Keep human checkpoints and scope each
worker to a concrete task; do not expect a fully autonomous org chart.

## 5. Which models to plug in

See `docs/PROVIDERS.md` (free / freemium / paid / local inventory) and
`docs/MODELS.md` (models mapped to tiers).

## 6. Through the gateway (fallback / routing)

Start `ai-stack` (`docs/AI-SETUP.md`, section 3) and add it in `goose configure` as an
OpenAI-compatible provider: base URL `http://localhost:4000/v1`, API key = your LiteLLM virtual
key (`QS_GATEWAY_KEY`), model = a role alias (`role-dev`, `role-intern`, `role-local`). A role's
request then cascades across providers (fallbacks in `ai-stack/litellm/config.yaml`).
