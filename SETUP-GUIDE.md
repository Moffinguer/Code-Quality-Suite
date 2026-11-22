# Install, configuration, and usage guide

A full AI-assisted development system with quality control, built in layers that
each add value on their own. Recommended order: 1 -> CI -> 2 -> 3 -> 4.

## Tools used

| Area | Tools |
| ------ | ------- |
| Quality gate | 184 languages; full matrix in `docs/LANGUAGES.md` (installed on demand) |
| Rules | one editable file, `.quality-rules.json` (`docs/QUALITY-RULES.md`) |
| Base container | Docker, Ubuntu 24.04 + Python 3 (engine and installer only) |
| Model gateway | LiteLLM (roles, fallbacks, keys, budgets) + FreeLLMAPI (free pool) + Ollama (local), `ai-stack/` |
| AI agents | Claude Code (subagents by role), Codex CLI, Gemini CLI; Goose as an alternative |

## Layer 1 - Quality gate

Cross-platform install (see README). Every language gets a syntax check, one
formatter and its linters, at the quality level set in `.quality-rules.json`. The
image starts with the engine only; each language's tools are installed by the first
commit that contains it, and versions the project does not reveal are asked once.

## Layer 2 - Local Git hooks

`pre-commit` formats + analyzes staged files and blocks on failure. `pre-push`
verifies the pushed range in check mode (read-only) plus an optional heavy stage.
`commit-msg` enforces Conventional Commits. `prepare-commit-msg` preloads a
template with the changed-file manifest. For a clone-and-go flow, use
`git-integration/` (init.templateDir). The hooks live once per machine
(`~/.config/code-quality-suite/hooks`, linked from every repository) and the tools in one Docker
image per suite version shared by all repositories. Five-minute setup:
`docs/QUICKSTART-HOOKS.md`; updates: `docs/UPDATING.md`.

## Layer 3 - CI/CD

Integrate on any platform with `scripts/ci-check.sh`, which analyzes only the
changed files of the current PR/branch range, keeping pipelines fast. Local hooks
can be skipped with `--no-verify`; CI cannot.

## Layer 4 - AI-assisted development

The suite acts as an impartial referee: any AI-generated code must pass the same
local gate before entering the repo. `scripts/ai-init.sh <repo>` adds the agent files
(`AGENTS.md`, shared skills, Claude Code subagents by role, the gate hook, the norms
knowledge map) and `ai-stack/` runs the local model gateway. Step by step, from an empty
machine to a first OT: `docs/AI-SETUP.md`. Skills and the norms map: `docs/SKILLS.md`.

Model inventory to plug in: `docs/PROVIDERS.md` and `docs/MODELS.md`.
