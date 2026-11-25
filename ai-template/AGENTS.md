# AGENTS.md - instructions for every AI agent in this repository

Single source of truth for Claude Code (CLAUDE.md imports it), OpenCode and Codex (read it
directly) and Gemini CLI (.gemini/settings.json points to it). Keep it short; details live in
skills and in `knowledge/`.

## Project

- Name: <PROJECT>   Client: <CLIENT>   Data class: <public|internal|regulated>
- Stack: <Java 8/11/17, JSP, Maven, Oracle PL/SQL, HTML/CSS/JS, Markdown>
- Build and tests: `<mvn -B verify>`   Run locally: `<...>`

## Rules that always apply

1. **Norms first.** When `knowledge/norms/INDEX.md` lists norms, use the `norms` skill before
   designing or writing code: it tells you which norms apply. Otherwise say "no norms" and skip
   it. Cite the norm ids you applied in the commit body (`Norms: ARCH-003, SEC-010`).
2. **Quality gate.** After editing files, run `bash <SUITE>/scripts/qs-run.sh <files>` (Claude
   Code does it automatically through a hook). Fix every finding; never weaken a rule in
   `.quality-rules.json` to make a finding disappear.
3. **Encoding.** Every file is UTF-8 without BOM unless `.quality-rules.json` declares another
   charset for it. Never convert a file's encoding. If the gate reports damaged text
   (`ENCODING`), `git encoding --fix <file>` repairs it; check the diff.
4. **Commits.** Conventional Commits, subject <= 50 characters, **ASCII only** (no accents, n-tilde
   or diaeresis: write "anadir validacion", not "añadir validación").
5. **Branches.** Use the git aliases (skill `git-commands` is the manual of all of them; `git ayuda
   <command>` prints one): `git np` (parent), `git nr` (final branch), `git subir`, `git integra`.
   Never rebase or force-push an `ORIGINAL` branch, with one exception: under `branches.flow =
   squash`, `git integra` rebases a `<F>/ORIGINAL` onto its parent `ORIGINAL` before it squashes
   it up (only when all its children are in; never a `<v>/ORIGINAL` or an OT `ORIGINAL`, and
   never a force push by hand). Versions, CHANGELOG.md and the README badge are written by
   `git np` / `git release`, not by hand.
   **Known bugs.** A bug found in a released version is documented first: `git bug-conocido
   "<where>" "<symptom>"` adds its row to `KNOWN_BUGS.md` on every open branch (develop,
   ORIGINALs, finals); only then are the fix commits made, and the fix updates or removes the row.
6. **Data class.** `regulated` code and data never go to free model tiers or third-party
   endpoints that train on prompts; only to local models or paid no-training endpoints.
7. **Lessons.** When something surprised you (a failed approach, a hidden rule), record it with
   the `lessons-learned` skill so the next agent does not repeat it.
8. **Requirement files.** At the start of every task read, if they exist, `Requirements.md`,
   `Functional_Design.md`, `Technical_Design.md` and `Tests.md`: look in `dev_documents/` first,
   then in the repo root. A missing file is not an error. They are local and git-ignored; you
   may update them.
9. **Language and doc comments.** The requirement files may be in English or Spanish; code,
   identifiers and comments are always English. Every function, method or procedure has a doc
   comment in its language's style (Javadoc, JSDoc, docstring, PL/SQL header, shell header)
   stating purpose, parameters, return value and errors.
10. **Co-authors.** Human co-authors are fine. Never add Claude or any AI model as co-author
    (no `Co-Authored-By:` naming an AI) nor a "Generated with ..." line in commits or PRs.
    `.claude/settings.json` sets `attribution` to empty (legacy key: `includeCoAuthoredBy: false`).
11. **Integration flow.** Under `branches.flow = squash` an ORIGINAL moves only through
    `git integra` (one single-parent commit): never `git merge`, `git pull` without `--rebase`,
    cherry-pick or a push of a rebuilt ORIGINAL. Integrate from the main checkout only (a worktree
    may lack the real `.quality-rules.json`), and check `git log -1 --format=%P <ORIGINAL>` shows
    one parent before pushing. Details: skill `branch-workflow`.

## Roles (Claude Code subagents in .claude/agents; OpenCode gets the same ones in .opencode/agents)

| Role | Model | Does | Never |
| --- | --- | --- | --- |
| main session (project lead, business analyst) | strongest available | reads `dev_documents/`, delegates (one developer per final branch, a phase's branches in parallel, only once their dependencies are integrated), creates and integrates branches, escalates to the human | writes large code itself |
| systems-analyst | opus | spec, plan, branch tree (`git es`, `git np`, `git nr`), one task per final branch, `git integra` after the human's OK, merge-conflict suggestions | edits source code |
| developer | sonnet | implements one task on its own final branch; gate and hooks before review | merges into ORIGINAL |
| reviewer | opus | reviews diffs against norms and quality rules; commits only on REVIEW-<task> | edits code of the reviewed branch |
| qa | sonnet | tests, gate runs, regression checks; findings open the `<final-branch>/bugfix` loop | changes production code |
| docs-writer | haiku | documentation from recipes | invents requirements |
| intern | haiku | boilerplate, renames, small mechanical edits | touches security code |
| external-worker | haiku | hands cheap, non-regulated tasks to other models via the gateway | sends regulated data |

Flow: skill `team-flow`. Other models work as developers through OpenCode `role-dev` or
`external-worker`, for non-regulated data only. Human checkpoints: approve the spec, approve the
plan, approve each merge (bottom-up) and the merge into `develop`. Who creates, works on,
integrates and pushes which branch: the matrix in `team-flow` and the `## Branches` section of
each agent. `git release`, `git publicar` and `git combinar` are human only.

## Where things are

- `knowledge/norms/` norms map (INDEX.md, one note per norm), `knowledge/recipes/` the team's
  recipe book, `knowledge/lessons/` lessons learned, `knowledge/decisions/` ADRs.
- `.agents/skills/` skills for all agents (Claude Code reads the synced copy in `.claude/skills/`).
