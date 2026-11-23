---
name: branch-workflow
description: Use when creating, syncing, integrating or naming git branches, tags or commits, or when closing a version, in a repository that uses the code-quality-suite branch model (<version>/<ot>/.../ORIGINAL).
---

# Branch model and workflow

The model and its rules. Syntax and `Who:` of every command: the `git-commands` skill
(`git ayuda <cmd>`). Who may do what and parallel work (one developer per final branch): `team-flow`. Full workflow: `<SUITE>/docs/GIT-WORKFLOW.md`.

## Commit and merge flow (mandatory, every project)

1. Flow `squash` (`branches.flow`): every integration is ONE single-parent commit with
   `Commits:`, `Files:`, `Refs:`; a merge commit in an `ORIGINAL` is a defect.
2. Commit only on final or special branches, through the hooks; never `--no-verify`. Never
   move an ORIGINAL by hand (no merge, pull without `--rebase`, cherry-pick, reset, push).
3. Run `git integra` only from the main checkout (the personal `.quality-rules.json` is
   git-ignored; a worktree falls back to `flow: merge`). Agents never integrate.
4. Before integrating check `"flow":`; before pushing check `%P` (one parent). On a mismatch
   STOP and ask the human; a wrong pushed integration is never rewritten.

## The tree

```text
develop
└─ 6.22.6/ORIGINAL                      version (always a parent; Semantic Versioning)
   └─ 6.22.6/188858/ORIGINAL            OT 188858
      └─ 6.22.6/188858/RF001/ORIGINAL   requirement RF001
         ├─ 6.22.6/188858/RF001/login   final branch
         └─ 6.22.6/188858/RF001/bank/ORIGINAL
            ├─ 6.22.6/188858/RF001/bank/bugfix     siblings
            └─ 6.22.6/188858/RF001/bank/payments
```

- Names: `<version>/<ot>/<detail>/...`, ASCII segments, never only `<version>`.
- A branch with children ends in `ORIGINAL` (a parent); any other branch is final. The parent
  of `<F>/<x>` is `<F>/ORIGINAL`. A final branch that needs children: `git convertir-padre`.
- Create: `git np <name>` (parent), `git nr <name>` (final; in a worktree add
  `--from <ORIGINAL>`), a whole tree `git es -n` then `git es`, a version `git np <version>`.
  With `publish_on_create` (default `true`) the creating aliases push the new branch by
  themselves. See the tree: `git arbol`.

## Squash per level

- `git subir`: a final branch rebases onto its ORIGINAL; an ORIGINAL merges its parent.
- `git integra` goes up one level and makes **one squash commit** with `Commits:` and `Files:`
  in the body; the subject becomes a CHANGELOG.md line. Agents never run it; the lead does,
  after the human's OK: `git integra -m "feat(login): add login page" -m "<why>"`.

## Special branches (reserved UPPERCASE names, one table in `.quality-rules.json`)

- MIGRATION: version upgrade, before the rest of the version. DOCS: CHANGELOG.md and badge.
- REFACTOR, FORMAT, TESTS, SPIKE: controls for people (FORMAT only by the human).
- ATTEMPT-n (`git intentos`), REVIEW-<task> (`git revision`), QUARANTINE-<task>
  (`git cuarentena`), CHECKPOINT-<task> (`git checkpoint`): controls for agents. CHECKPOINT is
  never pushed.
- TESTING (`git testing`): a sandbox per level to try integrations without touching the tree.

## Closing

- OT RELEASE: `git release` inside an OT closes it (hidden ref `refs/ot/...`, subtree deleted).
- version RELEASE: `git release --version <v>`, then `git publicar` into `develop`.
  `git changelog` previews; `git limpiar-unmerged` cleans the `unmerged/...` leftovers.
- `git release`, `git publicar`, `git combinar`, `git changelog --escribir`: human only.
- Never edit `VERSION`, the `<version>` of pom.xml, CHANGELOG.md or the README badge by hand.

## Hooks

| Hook | Checks |
| --- | --- |
| commit-msg | ASCII only, Conventional Commits, subject <= 50 characters |
| pre-commit | the quality gate on the staged files |
| pre-push | branch names, a final branch contains its ORIGINAL, no force-push, the gate |
| pre-rebase, pre-merge-commit | finals rebase onto their parent; into an ORIGINAL only children or parent |

## Rules

- Commits: `type(scope): subject`, ASCII, <= 50 characters, body explains why, `Norms: <ids>`;
  never an AI co-author, never `--no-verify`.
- Never force-push an ORIGINAL, develop or main; never merge into a final branch.
