---
name: team-flow
description: Use when the main session runs a version or work order (OT) with the agent team - business analyst (main session), systems-analyst, developers in worktrees, qa bugfix loop and bottom-up integration with human approval. Defines who does what, in which order, which branches each role may create, work on, integrate and push, and where the shared context lives.
---

# Team flow

The main session is the lead and the **business analyst**: Claude Code subagents cannot start
other subagents, so only the main session delegates. The branch model is `branch-workflow`;
command syntax and `Who:` lines are in `git-commands` (`git ayuda <cmd>`).

## Shared context (git-ignored: only in the main worktree)

- `dev_documents/` (repo root as fallback): `Requirements.md`, `Functional_Design.md`,
  `Technical_Design.md`, `Tests.md`; written by the human.
- `docs/<version-or-ot>/`: `spec.md`, `plan.md`, optional `<branch-leaf>.md`; written by the
  systems-analyst and developers. `docs/<version-or-ot>/<req>/bugfix.md`: qa findings.
- Ignored folders do not exist in other worktrees: pass every agent their **absolute paths**.

## Who may do what with branches

| Role | Create | Work on | Integrate | Push |
| --- | --- | --- | --- | --- |
| lead | trees (`git np`, `git nr`, `git es`, `git nv`, `git convertir-padre`), TESTING, ATTEMPT, REFACTOR, TESTS, SPIKE | any branch | `git integra` after the human's OK; `git aceptar` | creating aliases, `git subir` |
| systems-analyst | trees (`git es`, `np`, `nr`), TESTING, ATTEMPT, REFACTOR | spec files only | `git integra` after the human's OK | creating aliases |
| developer | CHECKPOINT-<task> | its final branch or ATTEMPT-<n> | never | `git subir` (CHECKPOINT never pushed) |
| qa | TESTS, REVIEW-<task> | TESTS, REVIEW-<task> | never; reports bugfix needs | creating aliases, `git subir` |
| reviewer | REVIEW-<task> | REVIEW-<task> only | never | creating alias, `git subir` |
| external-worker | QUARANTINE-<task> (never regulated) | QUARANTINE-<task> only | never | creating alias, `git subir` |
| docs-writer, intern | CHECKPOINT-<task> | the branch it is given | never | `git subir` |

Human only: MIGRATION, DOCS, FORMAT, `git changelog --escribir`, `git release`, `git publicar`,
`git combinar`; the human confirms every integra, `git elegir` and the merge into `develop`.
Special types: MIGRATION, DOCS, REFACTOR, FORMAT, TESTS, SPIKE, ATTEMPT, REVIEW, QUARANTINE,
CHECKPOINT, plus TESTING. The creating aliases push by themselves (`publish_on_create`).

## Steps

1. **Business analyst (main session).** Read `dev_documents/`; pass requirements to the
   `systems-analyst`.
2. **Systems analyst** (opus). Writes `spec.md` and `plan.md` (the tree for `git es -n`, one
   task per final branch). **Human checkpoint: approve the spec, then the plan.** Then the tree
   is created (`git es`, or `git np` / `git nr`).
3. **Developers**, one per final branch, each in its own worktree (`developer`, sonnet; other
   models only for non-regulated data). Give each the branch, task and absolute paths.
4. **Gate before review.** Each developer runs the gate and lets the hooks pass (`git subir`).
5. **QA** writes findings to `<req>/bugfix.md` and never edits production code. Bugfix loop,
   run by the lead: `git convertir-padre` (`<final>` -> `<final>/ORIGINAL`), then
   `git nr bugfix`; if it is already an ORIGINAL, `git nr bugfix` only. A developer fixes on
   `<final>/bugfix`; qa reviews again until it finds nothing; then the `reviewer` gives its
   verdict. Branches are on origin (publish on create): `git convertir-padre` renames them
   there too and asks the human only if the lease fails.
6. **Integration**, bottom-up, one level at a time, one squash per level (`Commits:`,
   `Files:` in the body): `git integra -m "<subject>" -m "<why>"`. **Human checkpoint:
   approve each merge.** `git release` (OT RELEASE, version RELEASE), `git publicar` and
   `git combinar` are human only; `git limpiar-unmerged` cleans what a release set aside.
   Integrate only from the main checkout (it holds the real `.quality-rules.json`): check `"flow":`
   before, and `git log -1 --format='%P' <ORIGINAL>` (one parent) before pushing.
7. **Merge conflicts.** The `systems-analyst` suggests a resolution; the human decides.

## Rules every agent follows here

- Read the requirement files first; code, identifiers and comments in English with doc comments.
- Commits: Conventional, ASCII, subject <= 50 characters; never an AI co-author, never
  `--no-verify`. Regulated data only to local models or paid no-training endpoints.
- Developers never merge into an ORIGINAL; only the lead and the systems-analyst integrate.
