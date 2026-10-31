# AI development system — design (knowledge flywheel)

Design only, except layer 0 (the code-quality-suite), which is built. Last revised
2026-10-06. Facts about third-party tools and terms are dated: re-check them before building.

## Vision

- **Fence the field.** AI output will not always be right, but it can be bounded. The
  suite's hooks are the fence: branch model, code rules, quality levels. Nothing an agent
  produces enters the repository without passing them.
- **Agents do the volume, the human decides the essentials.** A team of agents is faster
  than a human team; what experience gives a human is replaced by saved context,
  information and lessons learned.
- **Hierarchical team, decomposed work.** Work is delegated only after the human has
  analysed and approved it. The project-manager orchestrator, and the leads at certain
  levels, can raise problems to the human.
- **Tunable orchestrator.** It stores information, spawns subagents, uses role-specific
  plugins and spends as little as possible.
- **Butler as a daily extra.** A personal agent (Hermes, OpenClaw…) is the front door: the
  human handles only the important details, and the heavy work is delegated.

## Principles

- **One orchestration brain: LangGraph.** It provides explicit shared state, checkpointing
  and bounded delegation (depth cap of about 2–3 hops). Never run a second full
  orchestrator alongside it. Worker agents may have their own subagents inside their
  sandbox.
- **Agents ask for roles, not models.** Every call names a role alias (`role-pm`,
  `role-dev`, …). A database decides which models serve it, in which order. Models change
  every month; agents and recipes do not.
- **One context for every agent.** The vault and `AGENTS.md` are shared, recipes use one
  format, and memory is reached through one protocol (MCP). Whether a worker is Claude,
  Codex, Gemini or a local model makes no difference to the context it gets.
- **Each layer is useful on its own.** If the loop never fully closes, every piece still
  pays off.

## Architecture

```text
            human ── approves: spec · plan · merge ── receives: escalations, reports
              │                                                      ▲
   butler (Hermes/OpenClaw: chat, cron, personal tasks) ─────────────┤
              │ hands development work over                          │
              ▼                                                      │
   L2 orchestrator (LangGraph PM) ── risk + data label ── roles ── escalation
              │ delegates decomposed tasks (git worktree each)
              ▼
   L3 workforce:  subscription CLIs   │  API models (gateway)   │  local models
                  Claude Code, Codex, │  paid + free tiers       │  Ollama/LM Studio/vLLM
                  Gemini CLI          │                          │  (homelab)
              │            ▲                      ▲
              │            └──── L4 model catalog (LiteLLM + Postgres): roles → ordered models
              ▼
   L0 fence: code-quality-suite (hooks, .quality-rules.json, levels) ── pass / fail back
              │ pass
              ▼
   git flow (feature/<HU>.<TR>, squash, develop) ── L5 knowledge: vault + lessons learned
```

## L0 — The fence (built)

The code-quality-suite has five pieces:

- one rules file;
- quality levels;
- the branch model;
- on-demand tools;
- logs with a SUCCESS or ERROR result per file and tool.

Two bridges to agents are still to be built:

1. **Immediate feedback.** A Claude Code `PostToolUse` hook, and the Codex equivalent, run
   the engine in `check` mode on the files the agent just edited. The agent then fixes
   lint and format issues before it asks for review, instead of discovering them at
   commit time.
2. **Failure log as learning input.** Errors that keep recurring in
   `.git/quality-suite/quality-suite.log`, for the same tool, rule or language, are
   promoted to a skill, an `AGENTS.md` rule or a change in `.quality-rules.json` (see L5).

## L1 — Human checkpoints

| Gate | Human decides | Delegated |
| --- | --- | --- |
| Spec | scope, acceptance criteria, risk and data label | drafting the spec from requirement docs |
| Plan | decomposition into tasks (HU/TR branches), roles, budget | analysis, estimates, dependency map |
| Merge to develop | final review of the squashed increment | implementation, tests, fixes, review rounds |

Escalation goes the other way. The PM orchestrator, and the leads at certain levels, file
"problems to consider" in a vault inbox, and the butler forwards them to the human's
channel. Agents never escalate by changing scope themselves.

## L2 — Orchestrator (LangGraph)

- **Roles:**
  - PM: owns the plan and escalates;
  - Analyst/Architect;
  - Lead dev: integrator;
  - Developers;
  - QA/Test;
  - Reviewer;
  - Docs;
  - Interns: bulk, low risk.
- **Two labels per task**, set at triage and approved at the Plan gate:
  - risk (very-low … very-high) picks the role tier;
  - data class (`public`, `internal`, `regulated`) restricts which pools may see the code.
- **Subagents:** a node may spawn workers up to the depth cap. A worker that is itself a
  CLI agent can use its own subagents inside its sandbox, where they do not count against
  the orchestrator's cap.
- **Budgets:** one gateway virtual key per role, with a spend limit (see L4). The PM sees
  spend per task.

## L3 — Workforce pools

**Subscription CLI agents.** Flat fee, the strongest models. They are driven headless:
`claude -p`, `codex exec`, `gemini -p`, or through the Agent Client Protocol (ACP) with
`acpx`, which keeps persistent sessions and emits NDJSON for automation. Each task runs in
its own git worktree. Vibe Kanban is a ready-made UI for this pattern (Claude Code, Codex,
Gemini CLI, Amp).

| Agent | Extensibility | Terms to respect (checked 2026-10) |
| --- | --- | --- |
| Claude Code | CLAUDE.md, skills, subagents (per-agent `model`), agent teams, hooks, MCP, plugins and marketplaces | Subscription OAuth only inside the unmodified Claude Code / Anthropic apps. Third-party harnesses (OpenClaw, OpenCode…) must use an API key. Pro/Max limits assume ordinary individual use. Anthropic does not support routing Claude Code to non-Claude models through gateways. |
| Codex CLI | AGENTS.md, skills, subagents (`.codex/agents/*.toml`), MCP, plugins (Agent Plugins 1.0) | ChatGPT sign-in is publicly endorsed in third-party harnesses (Pi, OpenCode), but informally: no contractual guarantee. |
| Gemini CLI | GEMINI.md, extensions (e.g. Conductor), MCP | Google-account login: 1,000 requests/day; free API key: 250/day, Flash only. Free AI Studio prompts may be used for training. |
| Qwen Code, OpenCode, Goose, Crush… | various | Qwen's free OAuth tier ended on 2026-04-15. |

**API models through the gateway.** Paid models for the top tiers, and free tiers for
bulk work on `public` code:

| Free tier | Limit | Training on prompts |
| --- | --- | --- |
| OpenRouter free models | 50/day (1,000/day after a $10 top-up) | depends on the upstream provider |
| Groq | free tier | no training by default |
| Cloudflare Workers AI | free tier | no training |
| Google AI Studio | free tier | trains on free prompts |
| GitHub Models, NVIDIA NIM, Mistral, Cerebras | free tiers | varies |

**Local models.** Ollama, LM Studio, llama.cpp or vLLM on the homelab: interns,
embeddings, and anything `regulated`.

**Rule:** `regulated` code (Junta de Andalucía work) never goes to free tiers or to
providers that train on prompts. It goes only to local models or to paid endpoints with
no-training terms.

## L4 — Model catalog in a database

Requirements: models are defined once and persist, can be deleted, and can be reordered;
agents do not change when models do.

- **LiteLLM proxy + Postgres** with `STORE_MODEL_IN_DB=True`:
  - models are added, edited and deleted from the Admin UI or the API (`/model/new`,
    `/model/delete`) without a restart, and persist;
  - provider credentials are stored once and reused;
  - fallbacks are an ordered list per model, changed at runtime (`POST/GET/DELETE
    /fallback`), and persisted. **Reordering = editing that list.**
  - virtual keys carry a budget per role or agent, and spend is tracked;
  - it exposes OpenAI- and Anthropic-format endpoints.
- **Role aliases:** a model group per role (`role-pm`, `role-dev`, `role-review`,
  `role-intern`, `role-local`). Its fallback list is the ordered preference: strongest
  first for PM and review, cheapest or free first for interns, local only for
  `role-local`.
- **Free-model scout:** `free-coding-models` (MIT) probes about 220 free models across 20
  providers and ranks them by latency and stability. It is used only to *propose* new
  entries for the catalog. Its own router on `:19280` is not used: there must be one
  gateway, not two.
- **Security:**
  - LiteLLM on PyPI was compromised on 2026-03-24 (1.82.7 and 1.82.8 stole credentials).
    Use the official Docker image pinned by digest, and version 1.82.9 or later.
  - Keep provider keys only in the gateway.
  - Do not expose the gateway outside the homelab network.
- **Alternatives:**
  - Portkey (MIT);
  - new-api: priority and weight per channel, SQLite/MySQL/Postgres. It is declared "for
    personal learning use" and states no licence, so it is not fit for work use.

## L5 — Shared context and lessons learned

- **Vault (Obsidian, Markdown)** is the source of truth for project knowledge, decisions and
  lessons. **Basic Memory** exposes it over MCP to Claude Code, Codex, Gemini CLI, Cursor,
  Hermes and OpenClaw (local Markdown, Obsidian-compatible, several projects).
- **Project constitution:** `AGENTS.md` per repository, generated from the vault. It holds
  build and test commands, conventions, and the suite's rules summary. `CLAUDE.md` and
  `GEMINI.md` just point to it.
- **Recipes:** Agent Skills (`SKILL.md`, an open format read by 30+ tools: Claude Code,
  Codex, Gemini CLI, Copilot, Cursor…) are the single recipe format. Recipes that need a
  different model per step use Goose subrecipes or LangGraph nodes.
- **Specs and plans in the repository:** Conductor (Gemini CLI) keeps product, tech stack,
  workflow, and per-track spec and plan as Markdown files, so work can be resumed on
  another machine or by another agent.
- **Code retrieval:** Serena (an LSP-backed MCP server) and Claude Code's code-intelligence
  plugins answer "where is X used" without reading whole files.
- **Lessons-learned loop**, the "compound" step from Every's compound-engineering plugin,
  runs after each increment:
  1. Write a note: what was done, decisions, mistakes, review comments.
  2. Promote whatever recurs. A correction seen twice becomes an `AGENTS.md` rule. A
     prompt pasted three times becomes a skill. A lint failure that keeps returning
     becomes a `.quality-rules.json` change or a skill.
  3. claude-mem, or Codex/Gemini memory, keeps per-session continuity. The vault keeps
     what must outlive sessions.

## L6 — Plugins and skills per role

| Role | Plugins / skills / MCP |
| --- | --- |
| PM, Analyst | Conductor (specs and plans); superpowers (brainstorming, writing plans); feature-dev (Anthropic) |
| Developer | superpowers (TDD, systematic debugging); Serena; code-intelligence plugin per language |
| Reviewer, QA | code-review and pr-review-toolkit (Anthropic, multi-agent review with confidence filtering); security-guidance; suite feedback hook (L0) |
| Cross-model | PAL MCP: `clink` lets one CLI ask Gemini CLI, Codex or Claude in an isolated subagent, with threaded context (second opinions, delegation) |
| Memory | Basic Memory (vault); claude-mem (session compression) |
| Everyone | `cqs` plugin, ours (see below) |

**Packaging.** Claude Code plugins bundle skills, subagents, hooks and MCP servers, and are
distributed through marketplaces. Agent Plugins 1.0 (2026-08-06, published by OpenAI,
Microsoft, AWS, Cursor and Vercel) bundles skills and MCP in a portable `plugin.json` for
Codex, Copilot, Cursor, VS Code and Kiro. Claude Code was not listed among its launch
clients. The same `skills/` directory serves both formats.

**Our `cqs` plugin** packages:

- skills: `git integra`, `git subir`, reading and editing `.quality-rules.json`, the
  lessons-learned step;
- the suite feedback hook;
- the vault MCP;
- the role subagents.

## L7 — Butler

Hermes Agent, or OpenClaw, is the front door: Telegram, cron in natural language,
personal tasks. It hands development work to the orchestrator and relays its reports and
escalations. It uses Basic Memory on the same vault. When it uses Claude, it uses an API
key: subscription login is not allowed in third-party harnesses. It runs in Docker on
the homelab, behind Tailscale, with an allowlist of Telegram IDs.

## Spending less

- **Route by tier:**
  - subscriptions for heavy coding;
  - free tiers for bulk `public` work;
  - local models for interns and `regulated` code;
  - paid API only for PM and review when the subscription quota runs out.
- **Context discipline:**
  - skills load on demand;
  - subagents isolate their context;
  - MCP tool search defers tool schemas;
  - retrieval instead of reading whole files;
  - short `AGENTS.md`.
- **Budget per role** in the gateway, and spend visible per task.

## Build order (each step must work before the next)

Status at 2.5.0 (October 2026): steps 1-3 are built; step 4 is next.

1. **Built.** Suite feedback hook for Claude Code (`scripts/qs-run.sh --hook`, PostToolUse,
   exit 2 feeds the findings back); Codex and Gemini run the same script from `AGENTS.md`.
2. **Built.** `scripts/ai-init.sh` generates `AGENTS.md` (+ `CLAUDE.md`, `GEMINI.md`), shared
   skills (`.agents/skills`, synced to `.claude/skills`), subagents by role and the `knowledge/`
   map with the Junta norms (ingest from an inbox). Basic Memory over `knowledge/` is optional.
3. **Built.** `ai-stack/`: LiteLLM + Postgres catalog with role aliases, fallbacks, virtual keys
   and budgets; FreeLLMAPI as the free pool; Ollama for regulated code. The free-model scout
   that feeds the catalog automatically is still to do (manual today, `docs/PROVIDERS.md`).
4. LangGraph: triage, then one worker (a headless CLI in a worktree), then the gate, then
   the lessons note. Until then the Claude Code main session is the lead (`docs/AI-SETUP.md`).
5. Add roles, risk and data routing, parallel worktrees, and escalation to the inbox.
6. Butler on top: Telegram front door, reports, approvals.

## Open points

- The terms for subscriptions and free tiers move fast. Re-check them at each build step
  and keep the pools swappable through the catalog.
- Running many subscription CLI agents in parallel can exhaust the five-hour and weekly
  quotas. The catalog must fall back to API or local models automatically.
- Code retrieval for Java/JSP needs a real index (Serena/LSP covers Java; JSP is weak).
- Measure before scaling: tokens, spend and pass rate at the gate, per role.
