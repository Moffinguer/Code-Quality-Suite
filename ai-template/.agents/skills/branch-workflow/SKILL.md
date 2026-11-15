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

## Rebase and squash (flow `squash`, the 5.x default)

| Branch | Gets parent changes (`git subir`) | Goes up (`git integra`) |
| --- | --- | --- |
| final | rebase onto its ORIGINAL | rebase, then **one squash commit** in its ORIGINAL; the branch is deleted (asks) |
| `<F>/ORIGINAL` | merge of its parent | rebased onto the parent, then squashed into it once all children are in (the one allowed rebase of an ORIGINAL) |
| `<v>/<ot>/ORIGINAL`, `<v>/ORIGINAL` | merge of its parent | not integrated: `git release` |

Every commit lists its files (`Files:`); a squash keeps the commits in `Commits:`. To change the
last commit use `git amend` (it recomputes `Files:`), never a bare `git commit --amend`.
A repository kept on `branches.flow = merge` (4.x) merges `--no-ff` instead; it is deprecated.

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

## Releases (the human's; preview with `git changelog`)

1. **OT release**: inside `<v>/<ot>/...`, `git release` creates `<v>/<ot>/RELEASE` (one
   `docs(changelog)` commit), tags `ot/<v>/<ot>` and deletes the OT subtree.
2. **Version release**: on `<v>/ORIGINAL`, `git release` (refused while an OT has no RELEASE)
   builds `<v>/RELEASE` from every OT RELEASE, with the version, CHANGELOG.md and README badge
   commits. Review it there.
3. `git publicar` lands RELEASE on `develop` as **one commit** `chore(release): <tag>`, tags,
   pushes, deletes RELEASE; conflicts on release-owned lines are solved, others stop with steps.
   Several trees: `git publicar --version <v>`, or join them first with `git combinar`.
4. `git limpiar-unmerged -n`, then without `-n`: deletes the archived `unmerged/...` branches
   already in `develop`.

## TESTING sandbox

`git testing crear <branch...>` builds `<F>/TESTING` to try several branches together;
`git testing repartir` cherry-picks its commits to the right branches. TESTING is never merged,
rebased, integrated or pushed to an ORIGINAL (the hooks refuse it).

## Hooks

| Hook | Runs on | Checks |
| --- | --- | --- |
| prepare-commit-msg | every commit | writes the `Files:` block |
| commit-msg | every commit | ASCII only, Conventional Commits, subject <= 50 characters |
| pre-commit | every commit | the quality gate on the staged files |
| pre-push | `git push`, `git subir` | branch names, a final branch contains its ORIGINAL, no force-push of shared branches, the gate |
| pre-rebase | `git rebase` | finals rebase onto their parent; shared branches only onto their remote; TESTING never |
| pre-merge-commit (squash) | `git merge` | into an ORIGINAL only its parent (children go up with `git integra`); never into a final; never TESTING |
| post-checkout | `git checkout`, `git switch` | refreshes config and aliases; warns about off-model names |
| post-commit | `git commit`, `git amend` | checks the `Files:` block against the commit's files after commit/amend |
| reference-transaction | any ref update | reports a non-TESTING branch that now contains TESTING commits (fast-forward or plumbing merge) |

## Rules

- Only the lead integrates, and only into ORIGINAL branches; merging into `develop` is the human's.
  Agents pass the message: `git integra -m "feat(login): add login page" -m "<why>"`; the subject
  becomes a CHANGELOG.md line.
- Commits: `type(scope): subject`, ASCII, <= 50 characters, body explains why, `Norms: <ids>`;
  never an AI co-author, never `--no-verify`.
- Never force-push an ORIGINAL, develop or main; never merge into a final branch.
- Never rebase an ORIGINAL by hand; `git integra` does it.
