---
name: branch-workflow
description: Use when creating, syncing, integrating or naming git branches, tags or commits, or when closing a version, in a repository that uses the code-quality-suite branch model (<version>/<ot>/.../ORIGINAL).
---

# Branch model and workflow

Short version and rules. Syntax of every command: the `git-commands` skill (`git ayuda <cmd>`).
Full workflow: `<SUITE>/docs/GIT-WORKFLOW.md`.

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
- A branch with children is a parent and ends in `ORIGINAL` (git cannot have a branch and a
  folder with the same name). Any other branch is final. Siblings share a folder; the parent of
  `<F>/<x>` is `<F>/ORIGINAL`, derived from the name.
- A final branch that needs children: `git convertir-padre` (`<F>/<x>` -> `<F>/<x>/ORIGINAL`,
  local rename), then `git nr <child>`.

## Rebase or merge

| Branch | Gets parent changes (`git subir`) | Goes up (`git integra`) |
| --- | --- | --- |
| final | rebase onto its ORIGINAL | rebase, then merge `--no-ff` (or squash) into its ORIGINAL |
| ORIGINAL | merge of its parent; never rebased | merge `--no-ff` into the parent ORIGINAL once all children are in |
| `<version>/ORIGINAL` | merge of `develop` | `git release`, then `git publicar` (below) |

## Creating branches

- From `develop`: `git np <version>` or `git np patch|minor|major` (version tree). From an
  ORIGINAL: `git np <name>` (parent) or `git nr <name>` (final). In a worktree, where the ORIGINAL
  is checked out elsewhere: `git nr <name> --from <ORIGINAL>`.
- A whole tree at once (stdin, indented children or paths): `git es -n` to preview, then
  `git es`. Existing branches are only checked. See it with `git arbol`.

## Versions

- Creating a version tree commits `chore(version): <version>` on its ORIGINAL: `VERSION`, the
  `pom.xml` versions and `package.json`. A merge driver keeps each tree's own version.
- Never edit `VERSION`, the `<version>` of pom.xml, CHANGELOG.md or the README badge by hand.

## Closing a version (two steps)

1. `git changelog`: preview only. Then, when the human asks, `git release`: creates
   `<version>/RELEASE` with the version, CHANGELOG.md and README badge commits, sets aside never
   integrated branches as `unmerged/<name>` and deletes the rest of the tree. Review it there.
2. `git publicar` (the human's): merges RELEASE into `develop`, tags, pushes, deletes RELEASE.
   Several trees: `git publicar --version <v>` one at a time, or join them first with
   `git combinar` (the human's).

## Hooks

| Hook | Runs on | Checks |
| --- | --- | --- |
| prepare-commit-msg | editor commits | preloads a Conventional Commits template with the file list |
| commit-msg | every commit | ASCII only, Conventional Commits, subject <= 50 characters |
| pre-commit | every commit | the quality gate on the staged files |
| pre-push | `git push`, `git subir` | branch names, a final branch contains its ORIGINAL, no force-push of shared branches, the gate |
| pre-rebase | `git rebase` | finals rebase onto their parent; shared branches only onto their remote |
| pre-merge-commit | `git merge`, `git integra` | into an ORIGINAL only its children or parent; never into a final |
| post-checkout | `git checkout`, `git switch` | refreshes config and aliases; warns about off-model names |

## Rules

- Only the lead integrates, and only into ORIGINAL branches; merging into `develop` is the human's.
  Agents pass the message: `git integra -m "feat(login): add login page" -m "<why>"`; the subject
  becomes a CHANGELOG.md line.
- Commits: `type(scope): subject`, ASCII, <= 50 characters, body explains why, `Norms: <ids>`;
  never an AI co-author, never `--no-verify`.
- Never force-push an ORIGINAL, develop or main; never merge into a final branch.
