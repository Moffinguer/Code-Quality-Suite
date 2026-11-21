---
name: team-flow
description: Use when the main session runs a version or work order (OT) with the agent team - business analyst (main session), systems-analyst, developers in worktrees, qa bugfix loop and bottom-up integration with human approval. Defines who does what, in which order, and where the shared context lives.
---

# Team flow

The main session is the lead and the **business analyst**: Claude Code subagents cannot start
other subagents, so only the main session delegates. Branch commands: `branch-workflow` and
`git-commands` skills.

## Shared context (git-ignored: only in the main worktree)

| Folder | Holds | Written by |
| --- | --- | --- |
| `dev_documents/` (repo root as fallback) | `Requirements.md`, `Functional_Design.md`, `Technical_Design.md`, `Tests.md` | the human |
| `docs/<version-or-ot>/` | `spec.md`, `plan.md`, optional `<branch-leaf>.md` summaries | systems-analyst, developers |
| `docs/<version-or-ot>/<req>/bugfix.md` | qa findings | qa |

Ignored folders do not exist in other worktrees: the lead passes every agent their **absolute
paths** in the main worktree.

## Steps

1. **Business analyst (main session).** Read the requirement files in `dev_documents/`. Pass the
   requirements and processes to the `systems-analyst`.
2. **Systems analyst** (`systems-analyst`, opus). Writes `spec.md` and `plan.md`: the branch tree
   `<version>/<ot>/<req>/...` as input for `git es -n`, and one task per final branch (one module
   each). **Human checkpoint: approve the spec, then the plan.** The lead creates the branches
   (`git es -n`, then `git es`; or `git np` / `git nr`).
3. **Developers**, one per final branch, each in its own worktree. Claude Code: the `developer`
   subagent (sonnet). Other models: OpenCode `role-dev` or `external-worker`, **only for
   non-regulated data**. Give each one the branch, its task and the absolute paths above.
4. **Gate before review.** Each developer runs the quality gate on its files and lets the hooks
   pass (`git subir`), then reports.
5. **QA** (`qa`) looks for failing criteria, odd code, malformed code and potential bugs. It
   writes findings to `docs/<version-or-ot>/<req>/bugfix.md` and never edits production code.
   Bugfix loop, run by the lead:
   - the requirement branch `<final-branch>` is final: `git convertir-padre` renames it to
     `<final-branch>/ORIGINAL`, then `git nr bugfix` creates `<final-branch>/bugfix`. Example:
     `3.0.0/100/ignore` -> `3.0.0/100/ignore/ORIGINAL` + `3.0.0/100/ignore/bugfix`.
     The lead runs `git convertir-padre` only when the branch is NOT on origin (local rename);
     if it is on origin, ask the human to run it. qa never runs it;
   - it is already an ORIGINAL: `git nr bugfix` creates the child `<folder>/bugfix`;
   - a developer fixes the findings on `<final-branch>/bugfix`; qa reviews again;
   - repeat until qa finds nothing. Then the `reviewer` (opus) gives its verdict.
6. **Integration**, bottom-up: from the deepest branches up to the OT `ORIGINAL`, one level
   at a time with `git integra -m "<subject>" -m "<why>"`: each level goes up as **one squash
   commit** and the integrated branch is deleted (`--yes` answers the question). To try several
   branches together first, `git testing crear <branch...>`, then `git testing repartir`.
   Fix the last commit with `git amend`. **Human checkpoint: approve each integration.**
   Integrate only from the main checkout (the real `.quality-rules.json`), check `"flow":` before
   and `git log -1 --format='%P' <ORIGINAL>` (one parent) before pushing; see the "Commit and
   merge flow" of `branch-workflow`.
   The OT then closes with `git release` inside it, the version with `git release` on
   `<version>/ORIGINAL`, and `git publicar` (one commit on `develop`): all the human's.
   Afterwards `git limpiar-unmerged`. Manual: the `git-commands` skill.
7. **Merge conflicts.** The `systems-analyst` reads both sides and suggests a resolution; the
   human decides and resolves it.

## Rules every agent follows here

- Read the requirement files before designing or coding.
- Code, identifiers and comments in English, with a doc comment on every function.
- Commits: Conventional, ASCII, subject <= 50 characters; never an AI as co-author
  (`Co-Authored-By`, "Generated with"); never `--no-verify`.
- Regulated data only to local models or paid no-training endpoints.
- Only the lead creates and integrates branches; developers never merge into an ORIGINAL.
