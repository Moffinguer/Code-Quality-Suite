---
name: branch-workflow
description: Use when creating, syncing, integrating or naming git branches, tags or commits in a repository that uses the code-quality-suite branch model (<version>/<ot>/.../ORIGINAL).
---

# Branch model

The manual of every command (syntax, when, who) is the `git-commands` skill; this one is the
short version and the rules.

- Names: `<version>/<ot>/<detail>...` with `/`. A branch that has children is `<folder>/ORIGINAL`;
  every other branch is final. Example: `6.22.6/188858/RF001/ORIGINAL`, `6.22.6/188858/RF001/login`.
- Create: from `develop`, `git np 6.22.6` or `git np patch|minor|major` (a Semantic Versioning
  version; it commits VERSION and pom.xml); from an ORIGINAL, `git np <name>` (parent) or
  `git nr <name>` (final). A final branch that needs children: `git convertir-padre`.
  In a worktree (the ORIGINAL is checked out elsewhere): `git nr <name> --from <ORIGINAL>`.
- Sync: `git subir` (final branches rebase onto their ORIGINAL; ORIGINAL branches merge their
  parent, never rebase).
- Integrate: `git integra` (final -> its ORIGINAL; ORIGINAL -> parent ORIGINAL once all its
  children are in). The subject becomes a line of CHANGELOG.md: write it for the reader.
  It opens an editor with a generated message: fill subject and description in ASCII. Agents
  pass the message instead: `git integra -m "feat(login): add login page" -m "<why>"`. Only
  the lead integrates, and only into ORIGINAL branches; merging into `develop` is the human's.
- See the tree: `git arbol`. Create a whole tree at once (stdin, one branch per line, indented
  children): `git es -n` to preview, then `git es`; existing branches are only checked.
- Close a version: `git changelog` (preview: changelog per branch, CHANGELOG.md entry, checks).
  Only when the human asks: `git release` (prepares `<version>/RELEASE` with VERSION, CHANGELOG.md
  and the README badge for review). `git publicar` (into develop) and `git combinar` are the
  human's.
- Never edit `VERSION`, the `<version>` of pom.xml or the README badge by hand: the aliases do it.
- Commit messages: `type(scope): subject`, ASCII only, <= 50 characters; body explains why; add
  `Norms: <ids>` when Junta norms applied.
- Never: force-push an ORIGINAL, develop or main; merge into a final branch; create a branch named
  only `<version>`.
