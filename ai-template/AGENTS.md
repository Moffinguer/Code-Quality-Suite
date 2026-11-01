# AGENTS.md - instructions for every AI agent in this repository

Single source of truth for Claude Code (CLAUDE.md imports it), OpenCode and Codex (read it
directly) and Gemini CLI (.gemini/settings.json points to it). Keep it short; details live in
skills and in `knowledge/`.

## Project

- Name: <PROJECT>   Client: Junta de Andalucia (public sector)   Data class: <public|internal|regulated>
- Stack: <Java 8/11/17, JSP, Maven, Oracle PL/SQL, HTML/CSS/JS, Markdown>
- Build and tests: `<mvn -B verify>`   Run locally: `<...>`

## Rules that always apply

1. **Norms first.** Before designing or writing code, use the `jda-norms` skill: it reads
   `knowledge/jda/INDEX.md` and tells you which Junta norms apply. Cite the norm ids you
   applied in the commit body (`Norms: JDA-ARQ-003, JDA-SEG-010`).
2. **Quality gate.** After editing files, run `bash <SUITE>/scripts/qs-run.sh <files>` (Claude
   Code does it automatically through a hook). Fix every finding; never weaken a rule in
   `.quality-rules.json` to make a finding disappear.
3. **Encoding.** Every file is UTF-8 without BOM unless `.quality-rules.json` declares another
   charset for it. Never convert a file's encoding. If the gate reports damaged text
   (`ENCODING`), `git encoding --fix <file>` repairs it; check the diff.
4. **Commits.** Conventional Commits, subject <= 50 characters, **ASCII only** (no accents, n-tilde
   or diaeresis: write "anadir validacion", not "añadir validación").
5. **Branches.** Use the git aliases (skill `git-commands` is the manual of all of them; `git ayuda
   <command>` prints one): `git np` (parent), `git nr` (final branch), `git subir`, `git integra`. Never rebase or force-push an `ORIGINAL` branch. Versions,
   CHANGELOG.md and the README badge are written by `git np` / `git release`, not by hand.
6. **Data class.** `regulated` code and data never go to free model tiers or third-party
   endpoints that train on prompts; only to local models or paid no-training endpoints.
7. **Lessons.** When something surprised you (a failed approach, a hidden rule), record it with
   the `lessons-learned` skill so the next agent does not repeat it.

## Roles (Claude Code subagents in .claude/agents; OpenCode gets the same ones in .opencode/agents)

| Role | Model | Does | Never |
| --- | --- | --- | --- |
| main session (project lead, business analyst) | strongest available | reads `dev_documents/`, delegates, creates and integrates branches, escalates to the human | writes large code itself |
| systems-analyst | opus | spec, plan, branch tree for `git es -n`, one task per final branch, merge-conflict suggestions | edits source code, creates branches |
| developer | sonnet | implements one task on its own final branch; gate and hooks before review | merges into ORIGINAL |
| reviewer | opus | reviews diffs against norms and quality rules | edits code |
| qa | sonnet | tests, gate runs, regression checks; findings open the `<req>/bugfix` loop | changes production code |
| docs-writer | haiku | documentation from recipes | invents requirements |
| intern | haiku | boilerplate, renames, small mechanical edits | touches security code |
| external-worker | haiku | hands cheap, non-regulated tasks to other models via the gateway | sends regulated data |

Flow: skill `team-flow`. Other models work as developers through OpenCode `role-dev` or
`external-worker`, for non-regulated data only. Human checkpoints: approve the spec, approve the
plan, approve each merge (bottom-up) and the merge into `develop`.

## Where things are

- `knowledge/jda/` norms map (INDEX.md, one note per norm), `knowledge/recipes/` the team's
  recipe book, `knowledge/lessons/` lessons learned, `knowledge/decisions/` ADRs.
- `.agents/skills/` skills for all agents (Claude Code reads the synced copy in `.claude/skills/`).
