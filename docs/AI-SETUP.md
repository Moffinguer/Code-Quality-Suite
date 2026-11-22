# AI environment: from zero to a first project

> No API credits yet? `docs/AI-DEMO.md` runs the same setup with every role on free API keys.

Minimal steps to reproduce the AI working environment on **Windows 11 + Git Bash + Docker
Desktop** (Linux and macOS: same commands, without the Windows notes) and try it on a new
Java / JSP / HTML / CSS / JS / Markdown project. Every command is for **Git Bash** unless it says
PowerShell. Replace `/c/dev` with wherever you keep things.

```text
you ──> Claude Code (your Claude subscription; official CLI)
          ├─ subagents by role (.claude/agents): systems-analyst, developer, qa, reviewer, docs-writer...
          ├─ after every edit: hook -> scripts/qs-run.sh -> quality gate (Docker, offline)
          └─ external-worker -> scripts/ai-ask.sh -> LiteLLM gateway  http://localhost:4000
                                                    ├─ Anthropic / OpenAI / Gemini API keys (paid)
                                                    ├─ FreeLLMAPI  :3001  free tiers, public data only
                                                    └─ Ollama      :11434 local, the only target for regulated code
OpenCode and Codex CLI read the same AGENTS.md and .agents/skills (OpenCode also gets the agents).
git commit / git push -> hooks -> the same gate + the branch model (docs/GIT-WORKFLOW.md)
```

## 1. Prerequisites (once per machine)

| What | Why | Notes |
| --- | --- | --- |
| Git for Windows (Git Bash) | hooks, scripts, Claude Code's shell | keep "Git from the command line and also from 3rd-party software" |
| Docker Desktop (WSL 2 backend) | the quality gate and the model gateway | running before you commit |
| Python 3 | `ai-ask.sh` (JSON) | python.org installer, "Add python.exe to PATH" |
| Node.js LTS | only for OpenCode / Codex CLI | the suite itself needs no Node on the host |
| A Claude Pro/Max/Team/Enterprise plan | Claude Code | API keys for other models are optional |

Check: `git --version && docker info --format '{{.ServerVersion}}' && python --version`.

## 2. The suite (once per machine)

```bash
mkdir -p /c/dev && cd /c/dev
unzip code-quality-suite.zip                 # or clone your own copy of the suite
cd code-quality-suite
./git-integration/setup-global.sh            # git iniciar / clonar / instalar / ia / ayuda + QS_SUITE
```

The base image is built by the first `bootstrap` (section 5); each language's tools are added the
first time a commit contains it (network once, then offline). The image and the hooks are shared
by every repository on the machine; updates: `git actualizar-suite` (`INSTALL.md`).

## 3. The model gateway (ai-stack)

Three files, all in `ai-stack/`: `.env` (secrets and provider keys), `docker-compose.yml`
(services) and `litellm/config.yaml` (models, roles and fallbacks).

```bash
cd /c/dev/code-quality-suite/ai-stack
cp .env.example .env
# missing secrets (Git Bash ships openssl); keep a LITELLM_MASTER_KEY you already have (sk-...)
sed -i -e "s/^POSTGRES_PASSWORD=change-me$/POSTGRES_PASSWORD=$(openssl rand -hex 16)/" \
       -e "s/^LITELLM_MASTER_KEY=sk-change-me$/LITELLM_MASTER_KEY=sk-$(openssl rand -hex 24)/" \
       -e "s/^LITELLM_SALT_KEY=sk-change-me$/LITELLM_SALT_KEY=sk-$(openssl rand -hex 24)/" .env
```

Paste your provider keys into `.env` with exactly these names (LiteLLM looks them up by name):
`ANTHROPIC_API_KEY`, `GROQ_API_KEY`, `CEREBRAS_API_KEY`, `GEMINI_API_KEY`, `OPENROUTER_API_KEY`,
`DEEPSEEK_API_KEY`. Leave empty the ones you do not have: their models fail over to the next one of
the role. An Anthropic **API key** is billed apart from your Claude subscription, which only
works inside Claude Code. Then:

```bash
docker compose up -d                          # db + litellm
docker compose ps                             # "running"/"healthy" after ~1 minute
curl -s http://localhost:4000/health/liveliness
```

What `litellm/config.yaml` sets up:

| Role (what agents call) | First model | Fallbacks, in order | Data allowed |
| --- | --- | --- | --- |
| `role-lead`, `role-review` | Claude Opus (API) | Claude Sonnet | internal |
| `role-dev` | Claude Sonnet (API) | Claude Haiku | internal |
| `role-intern` | Groq gpt-oss-120b | Cerebras gpt-oss-120b, Gemini Flash, OpenRouter free router, DeepSeek Flash, Claude Haiku | public |
| `role-long` | Gemini Flash (1M context) | Gemini Flash-Lite, DeepSeek Flash | public |
| `role-local` | Ollama qwen2.5-coder (profile `local`) | none | regulated |

A free tier that answers 429 is benched for a minute and the next entry answers. Change a model or
the order in that file (or in the UI) and restart: `docker compose restart litellm`.

**A key for your agents** (budget-capped; never give them the master key):

```bash
set -a; . ./.env; set +a
curl -s http://localhost:4000/key/generate -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"key_alias":"me","max_budget":20,"models":["role-lead","role-dev","role-review","role-intern","role-long","role-local"]}'
# copy "key": "sk-..." from the answer
setx QS_GATEWAY_KEY "sk-..."                  # for every new terminal and for Claude Code
export QS_GATEWAY_KEY="sk-..."                # for this terminal
bash ../scripts/ai-ask.sh role-intern "Say hello in five words"
```

The admin UI is `http://localhost:4000/ui` (user `admin`, password = `LITELLM_MASTER_KEY`): models,
roles, fallbacks, keys, budgets and spend per model.

**FreeLLMAPI (optional)**: one more pool of free tiers behind a single key, useful when you add
providers beyond the ones above. `FREELLMAPI_ENCRYPTION_KEY=$(openssl rand -hex 32)` in `.env`,
`docker compose --profile free up -d`, create the dashboard account at `http://localhost:3001`,
add keys on its **Keys** page, copy the unified key into `.env` as `FREELLMAPI_KEY`, uncomment
`free-pool` in `litellm/config.yaml`, add it to the `role-intern` fallbacks and
`docker compose up -d --force-recreate litellm`. Public data only.

**Local models (optional; the only target for regulated code):**

```bash
docker compose --profile local up -d
docker compose exec ollama ollama pull qwen2.5-coder:7b     # ~5 GB; bigger models need more RAM/VRAM
bash ../scripts/ai-ask.sh role-local "Write a Java method that reverses a string"
```

With an NVIDIA GPU, uncomment the `deploy:` block of the `ollama` service. A 7B model is a helper
(summaries, boilerplate, tests), not a replacement for the lead/developer roles.

## 4. The agents

**Claude Code** (PowerShell, once):

```powershell
irm https://claude.ai/install.ps1 | iex      # or: winget install Anthropic.ClaudeCode
```

Open a new terminal, run `claude`, log in with your subscription, and check with `claude doctor`.
Claude Code needs a Pro, Max, Team, Enterprise or Console (API) account; the free claude.ai plan
does not include it. With a plan you log in: no API key and nothing else to pay.
Data: on Free/Pro/Max plans Anthropic trains on your sessions only when the model-improvement
setting is on; turn it off at `https://claude.ai/settings/data-privacy-controls` before using
Claude Code on client code. Team/Enterprise and API keys are under commercial terms (no training by default).

**OpenCode** (open source; the free way to run the whole team on the gateway roles):

```bash
npm install -g opencode-ai            # then, in the project: opencode
```

It reads `AGENTS.md` and the skills of `.agents/skills`; `ai-init.sh` adds `opencode.json` (the
gateway as provider, `role-lead` for the primary agent) and `ai-sync.sh` generates
`.opencode/agents/` from the Claude Code subagents, each on its role (`developer` -> `role-dev`,
`reviewer` -> `role-review` with edits denied...). Free demo with every role on free tiers:
`docs/AI-DEMO.md`.

**Codex CLI** (optional, cheap or second-opinion worker):

```bash
npm install -g @openai/codex          # then: codex   (ChatGPT login or OPENAI_API_KEY)
```

Gemini CLI: since 2026-06-18 Google moved its unpaid and Google One users to Antigravity CLI
(geminicli.com, "Quotas and pricing"); `GEMINI.md` and `.gemini/settings.json` stay for whoever
still uses Gemini CLI with a paid key.

Codex reads `AGENTS.md` and the skills in `.agents/skills`. To make it use the gateway's roles
instead of its own login, add to `~/.codex/config.toml`:

```toml
model = "role-dev"
model_provider = "qsgw"

[model_providers.qsgw]
name = "code-quality-suite gateway"
base_url = "http://localhost:4000/v1"
env_key = "QS_GATEWAY_KEY"
wire_api = "responses"
```

## 5. A new project from scratch

```bash
mkdir -p /c/dev/demo && cd /c/dev/demo
git init --bare /c/dev/demo.git                          # optional remote to try push (any empty repo works)
git iniciar --remoto /c/dev/demo.git                     # git init (develop), hooks, files, AI files (git ia)
```

The AI files (`AGENTS.md`, `CLAUDE.md`, `.claude/`, `.agents/`, `knowledge/`..., and the local folders `docs/<version-or-ot>/` and `dev_documents/`) are
git-ignored:
they stay on your machine. The agents get the manual of every git command as the `git-commands`
skill (`git ayuda` shows the same to you).

`git ia` also creates `dev_documents/` with four ID-based templates (`Requirements.md`,
`Functional_Design.md`, `Technical_Design.md`, `Tests.md`) only when they are missing;
`--actualizar` never overwrites them. In this suite repo, run `bash scripts/ai-init.sh .` (or `git ia`) to create the local, git-ignored `dev_documents/`.

Edit the **Project** section of `AGENTS.md` (name, data class, stack, build command), then:

```bash
git add -A && git commit -m "chore: initial project skeleton"   # first run installs the tools
git push -u origin develop
```

`bootstrap` may ask once for versions the project does not reveal (Java version, for example).
`.quality-rules.json` appears after the first commit: that is where every rule and policy lives
(`docs/QUALITY-RULES.md`).

## 6. First OT with the agents

```bash
git np 1.0.0          # 1.0.0/ORIGINAL           (version)
git np 100001         # 1.0.0/100001/ORIGINAL    (OT: letters and digits, e.g. ABC123)
# or the whole planned tree at once:  printf '1.0.0\n  100001\n    login\n    styles\n' | git es
claude
```

Prompts for the session (one at a time; you approve at each stop):

1. *"Use the systems-analyst subagent to write the spec of OT 100001: a login page `login.jsp` posting
   to a `LoginServlet` (Java 17), a `login.css`, client-side validation in `login.js`, and a
   `README.md`. Apply the Junta norms that exist. Stop for my approval."*
2. *"Plan it as tasks with one final branch each under 1.0.0/100001/ORIGINAL and stop."*
3. *"Delegate each task to the developer subagent, then run qa and reviewer on each branch."*
   Each developer works in its own worktree, creates its branch with
   `git nr <task> --from 1.0.0/100001/ORIGINAL`, and the gate runs after every edit.
4. *"Integrate the approved branches into 1.0.0/100001/ORIGINAL."* The lead runs
   `git integra -m "<subject>"` per branch (Claude Code asks you before running it).

The whole flow (the lead as business analyst, `systems-analyst`, developers, the qa bugfix loop,
bottom-up integration) is the `team-flow` skill; the branch model is the `branch-workflow` skill.

Then you close the OT and the version yourself:

```bash
git checkout 1.0.0/100001/ORIGINAL && git integra      # -> 1.0.0/ORIGINAL (editor opens)
git changelog                                          # preview of the release
git release                                            # 1.0.0/RELEASE: VERSION, CHANGELOG.md, README badge
git publicar                                           # after your review: develop, tag 1.0.0, push
git arbol                                              # what is merged / pending
```

Commit messages are ASCII Conventional Commits (`feat(login): anadir validacion`), and every
file is UTF-8 unless the rules say otherwise; the hooks reject anything else.

## 7. Feeding the Junta norms

Drop each new Junta notification (PDF, DOCX, mail export) into `knowledge/norms/inbox/` and ask:
*"Ingest the inbox"*. The `jda-ingest` skill splits it into one note per norm under
`knowledge/norms/norms/`, updates `knowledge/norms/INDEX.md`, and proposes rule changes for
`.quality-rules.json` in `knowledge/norms/proposals/` for you to approve. From then on every task
starts with the `jda-norms` checklist. Your own procedures become recipes: copy
`.agents/skills/recipe-template/` (see `docs/SKILLS.md`), then `bash <suite>/scripts/ai-sync.sh`.

## 8. Data and cost rules

| Data class (AGENTS.md) | May go to | Never to |
| --- | --- | --- |
| public | any role, the free pool included | - |
| internal | Claude Code, paid API roles (`role-lead`, `role-dev`, `role-review`) | `role-intern`, `role-long` (free tiers, DeepSeek) |
| regulated | `role-local` (Ollama), and Claude Code only if your contract allows it | free tiers, any endpoint that trains on prompts |

- Free tiers (Groq, Cerebras, Gemini free quota, OpenRouter free models, FreeLLMAPI, Gemini CLI
  with a personal account) may log or train on prompts, and DeepSeek processes data in China:
  public data only. FreeLLMAPI is "for personal experimentation, not production".
- Paid roles never fall back to the free pool (`litellm/config.yaml`), so a fallback cannot move
  a prompt to a lower data class.
- Whether Junta code may leave your machine at all is decided by the contract, not by this setup.
- Budgets: per key in the LiteLLM UI (`max_budget`), spend per role under **Usage**.

## 9. When something fails

| Symptom | Fix |
| --- | --- |
| The Claude Code hook says `qs-run.sh: No such file` | `bash` resolved to WSL's bash: put `C:\Program Files\Git\bin` before `C:\Windows\System32` in PATH, or write Git's `bash.exe` full path in `.claude/settings.json` |
| `ai-ask.sh` 401 | `QS_GATEWAY_KEY` not set in that terminal (`setx` applies to new terminals) or the key lacks that role |
| `ai-ask.sh role-intern` fails | none of its providers has a key in `.env`, or all hit their free quota: `bash ../scripts/ai-keys.sh` says which |
| `402 Insufficient Balance` from DeepSeek | the key has no balance; top it up or leave `DEEPSEEK_API_KEY` empty |
| a model "not found" / 404 | the provider renamed it: look up the new id in its model list and change that line of `litellm/config.yaml` |
| LiteLLM restarts in a loop | `docker compose logs litellm`; usually `.env` secrets left as `change-me` or a YAML typo |
| `git nr` "is a final branch" inside an agent worktree | use `git nr <name> --from <ORIGINAL>` |
| Commit rejected for accents | the message must be ASCII; the hook prints the suggested text |

## Next steps

When the manual loop works, the planned orchestration (LangGraph triage -> worker -> gate ->
review, with the inbox and escalation) is described in `docs/KNOWLEDGE-FLYWHEEL.md`.
