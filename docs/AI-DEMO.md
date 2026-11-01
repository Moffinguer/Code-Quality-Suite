# Free demo: the whole agent team on free API keys

Try the AI layer without paying anything: every role of the gateway runs on free tiers, the agents
run in **OpenCode** (open source, free) or in **Claude Code** if your Claude plan is Pro, Max or
Team (it is included in those plans: you log in, no API key). When the demo convinces you, switch
the roles to the paid configuration (last section).

```text
OpenCode (free)  ──or──  Claude Code (Pro/Max/Team login)
   │ primary agent + subagents systems-analyst, developer, qa, reviewer, docs-writer, intern...
   │ (.opencode/agents is generated from .claude/agents: one definition for both)
   ▼
LiteLLM gateway, LITELLM_CONFIG=demo.yaml  http://localhost:4000
   role-lead / role-review / role-dev / role-intern / role-long   (all on free tiers)
   ▼
Groq · Cerebras · Gemini · NVIDIA NIM · SambaNova · OpenRouter · Mistral · Codestral · GitHub Models · Cohere ...
```

> **Public or invented code only.** Free tiers may log prompts or train on them. Never run the demo
> on Junta code: that goes to `role-local` or to the paid configuration.

## 1. Get the keys

You do not download keys: you create a free account on each provider and generate your own key in
its console. Never use keys published by someone else (leaked keys break the providers' terms).
One account per provider; more keys = more providers in the fallback chain, not more accounts.

| Provider | Where | `.env` name | Free allowance (indicative) | Notes |
| --- | --- | --- | --- | --- |
| Groq | console.groq.com/keys | `GROQ_API_KEY` | ~1,000 requests/day per model | very fast |
| Cerebras | cloud.cerebras.ai | `CEREBRAS_API_KEY` | 1M tokens/day, 65k context | fast code model |
| Google AI Studio | aistudio.google.com/app/apikey | `GEMINI_API_KEY` | varies by model; quota per project | 1M context |
| OpenRouter | openrouter.ai/keys | `OPENROUTER_API_KEY` | 50 requests/day (1,000 with a 10 $ top-up) | free router picks a model |
| NVIDIA NIM | build.nvidia.com | `NVIDIA_NIM_API_KEY` | 40 requests/minute | phone verification |
| SambaNova | cloud.sambanova.ai | `SAMBANOVA_API_KEY` | trial credits | |
| Mistral | console.mistral.ai | `MISTRAL_API_KEY` | per model | phone; free tier trains on prompts |
| Codestral | console.mistral.ai (Codestral) | `CODESTRAL_API_KEY` | 2,000 requests/day | code model, own key |
| GitHub Models | github.com/settings/tokens (fine-grained, "Models: read") | `GITHUB_API_KEY` | ~150 requests/day (small models) | |
| Cohere | dashboard.cohere.com | `COHERE_API_KEY` | 1,000 calls/month | trial key |
| Hugging Face | huggingface.co/settings/tokens | `HUGGINGFACE_API_KEY` | 0.10 $/month | `huggingface/<model>` names only |
| Cloudflare Workers AI | dash.cloudflare.com | `CLOUDFLARE_API_KEY` + `CLOUDFLARE_ACCOUNT_ID` | 10,000 neurons/day | `cloudflare/<model>` names only |
| DeepSeek | platform.deepseek.com | `DEEPSEEK_API_KEY` | none: needs balance | servers in China |

The maintained list of free LLM APIs, with current limits, is
[cheahjs/free-llm-api-resources](https://github.com/cheahjs/free-llm-api-resources). Limits change
often; the gateway falls over to the next provider when one is exhausted.

## 2. Gateway in demo mode

```bash
cd /c/dev/code-quality-suite/ai-stack
cp .env.example .env                 # then paste your keys; leave the others empty
# in .env:  LITELLM_CONFIG=demo.yaml   and the three secrets (see docs/AI-SETUP.md, section 3)
docker compose up -d
bash ../scripts/ai-keys.sh           # which keys work, and which model answers each role
```

`ai-keys.sh` sends one tiny request to every model and every role and prints, per model, `OK`,
`no key`, `key rejected`, `quota or rate limit`, `model not found: renamed?`... Then create a key
for the agents (`docs/AI-SETUP.md`, section 3) and set `QS_GATEWAY_KEY`.

Any model of a provider can also be called by its own id, without editing anything:
`bash ../scripts/ai-ask.sh nvidia_nim/meta/llama-3.3-70b-instruct "hola"`.

## 3. The project and its agents

```bash
mkdir -p /c/dev/demo && cd /c/dev/demo
git iniciar                                             # develop, quality hooks, AGENTS.md, skills, agents, opencode.json
```

**OpenCode** (needs Node.js): `npm install -g opencode-ai`, then `opencode` in the project. It reads
`AGENTS.md` and the skills by itself; `opencode.json` points it to the gateway, so its primary
agent uses `role-lead` and the subagents their own role (`developer` -> `role-dev`, `reviewer` ->
`role-review` with edits denied...). Call a subagent with `@developer ...`, or let the primary agent
delegate. Check what it loaded: `opencode agent list`.

**Claude Code** (Pro/Max/Team login): `claude` in the same project. Its subagents use your plan's
Claude models; the gateway roles are used only by `external-worker` (`ai-ask.sh`).

## 4. Community skills

```bash
bash /c/dev/code-quality-suite/scripts/ai-skills.sh list anthropics/skills
bash /c/dev/code-quality-suite/scripts/ai-skills.sh add anthropics/skills skill-creator webapp-testing
bash /c/dev/code-quality-suite/scripts/ai-skills.sh add obra/superpowers writing-plans systematic-debugging test-driven-development
bash /c/dev/code-quality-suite/scripts/ai-skills.sh installed
```

They are copied into `.agents/skills/` (OpenCode, Codex) and `.claude/skills/` (Claude Code),
pinned to the commit they came from (`.source`). A skill can make the agent run its scripts: read
it before committing it. Worth trying first: `skill-creator` (to turn your recipes into skills),
`writing-plans`, `systematic-debugging`, `test-driven-development`, `webapp-testing`.

## 5. The demo

```bash
git es <<'END'
1.0.0
  100001
    login
    styles
END
git checkout 1.0.0/100001/ORIGINAL
opencode
```

Prompts, one at a time (you approve between them):

1. *"@systems-analyst write the spec of OT 100001: a login page `login.html` with `login.css`
   and client-side validation in `login.js`, plus a `README.md`. Stop for my approval."*
2. *"Delegate to @developer: the page on branch 1.0.0/100001/login, the styles on
   1.0.0/100001/styles (git switch to each). Then @qa and @reviewer on each branch."* The whole
   loop (qa findings in a `bugfix` branch, bottom-up integration) is the `team-flow` skill.
3. You integrate and close: `git checkout 1.0.0/100001/login && git integra`, the same for
   `styles`, then `git checkout 1.0.0/100001/ORIGINAL && git integra`,
   `git changelog` (preview), `git release` (RELEASE branch with CHANGELOG.md, review it),
   `git publicar`.

What to watch: every commit passes the quality gate (format, linters, ASCII messages, encoding),
the branches follow the model, and the changelog lists what each branch brought.

## 6. When it convinces you

- **Claude Code** with your Claude plan: nothing to configure in the gateway.
- **Paid roles for every agent**: `ANTHROPIC_API_KEY` in `.env`, `LITELLM_CONFIG=config.yaml`,
  `docker compose up -d --force-recreate litellm`. Lead, dev and review go to Claude (internal
  data allowed); intern and long stay on the free tiers.

Expect from the free demo: slower answers at busy hours, fallbacks between providers, and weaker
tool use than Claude in long tasks. `bash ../scripts/ai-keys.sh --roles` shows which model is
answering each role at any moment.
