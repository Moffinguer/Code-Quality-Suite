# Git workflow - branch model and commands

Client-side workflow layered on the quality gate: hierarchical branches named after the
version and the work order (OT), final branches rebased onto their parent, each level squashed
into the level above, and two reviewed releases: one per OT (`<v>/<ot>/RELEASE`) and one per
version (`<v>/RELEASE`), published to `develop` as ONE commit. The release writes `CHANGELOG.md`,
the README version badge and the version in `VERSION` / `pom.xml`.
Everything is a plain git alias. Enforcement is client-side (hooks);
`examples/ci/azure-pipelines-quality.yml` repeats the name check on the server.

Version 5.0.0 changed the integration and release flow (`branches.flow = squash`). The 4.x flow
(`merge`) still works for trees started with 4.x: see [Migrating from 4.x](#migrating-from-4x).

## Branch model

```text
develop
├─ 6.22.6/ORIGINAL                         version (always a parent; Semantic Versioning)
│  └─ 6.22.6/188858/ORIGINAL               OT 188858
│     └─ 6.22.6/188858/RF001/ORIGINAL      requirement RF001
│        ├─ 6.22.6/188858/RF001/login      final branch
│        └─ 6.22.6/188858/RF001/bank/ORIGINAL
│           ├─ 6.22.6/188858/RF001/bank/bugfix
│           └─ 6.22.6/188858/RF001/bank/payments
└─ 6.22.6-SNAPSHOT/ORIGINAL                another version tree next to it (git nueva-version)
   └─ 6.22.6-SNAPSHOT/188858/ORIGINAL ...
```

- Segments: `<version>/<ot>/<detail>/...`, separated by `/`. A branch is never only
  `<version>`.
- **The version is a [Semantic Versioning](https://semver.org) version** without the `v`:
  `6.22.6`, `7.0.0`, `6.22.6-SNAPSHOT`, `6.22.6-rc.1`. `6.22` or `6.22.6.1` are refused. A fix
  after `6.22.6` is `6.22.7`; a pre-release of it is `6.22.7-rc.1` (it sorts before `6.22.7`).
- **Parent branches end in `ORIGINAL`.** why: git stores refs as files and folders, so a
  branch cannot have the same name as a folder of branches (`6.22.6/188858` and
  `6.22.6/188858/login` cannot coexist: `cannot lock ref ... exists`). The parent lives
  inside its own folder as `ORIGINAL`.
- **Reserved leaves** (`ORIGINAL`, `RELEASE`, and `TESTING` under `flow = squash`) are refused as
  ordinary segments, ignoring case. why: on Windows refs are case-insensitive files, so a folder
  `release/` and a branch `RELEASE` cannot coexist.
- Any other branch is **final** (no children). Turn it into a parent with
  `git convertir-padre`.
- **Siblings** share a folder (`bank/ORIGINAL`, `bank/bugfix`, `bank/payments`). The
  **parent** of `<F>/<x>` is `<F>/ORIGINAL`; the parent of `<F>/ORIGINAL` is the
  `ORIGINAL` one level up, and `develop` at the top. Derived from the name, so it is the
  same for everyone and needs no stored metadata.
- Several version trees can live side by side (`6.22.6`, `6.22.6-SNAPSHOT`, `6.22.7`). Each
  one reaches `develop` through its own `RELEASE` branch, one at a time, or several are joined
  first with `git combinar`.

## Rules

| Branch | Gets parent changes by | Goes up by |
| --- | --- | --- |
| final (`.../bugfix`) | **rebase** onto its `ORIGINAL` (`git subir`) | `git integra`: rebase, then **squash** into its `ORIGINAL` (one commit) |
| parent (`.../ORIGINAL`) under an OT | **merge** of its parent (`git subir`); never rebased by hand: others build on it | `git integra`, once all its children are in: rebase onto the parent `ORIGINAL`, then squash into it |
| OT `ORIGINAL` (`<v>/<ot>/ORIGINAL`) | merge of `<v>/ORIGINAL` | `git release` -> `<v>/<ot>/RELEASE` (OT release) |
| `<v>/ORIGINAL` | merge of `develop` | `git release` -> `<v>/RELEASE` (version release, after every OT is released) |
| `<v>/RELEASE` | `git subir` rebases it onto `develop` | `git publicar`: ONE commit on `develop` |

`git integra` refuses an OT `ORIGINAL` and a `<v>/ORIGINAL`: those go up only through
`git release`.

## Commands (git aliases)

The full manual, with syntax, when to use each command and who runs it:
[GIT-COMMANDS.md](GIT-COMMANDS.md) (`git ayuda`, and the `git-commands` skill of the agents).

| Command | Does |
| --- | --- |
| `git np <name>` (`git nueva-padre`) | new parent branch: from `develop` -> `<version>/ORIGINAL` with its version commit (below); from `<F>/ORIGINAL` -> `<F>/<name>/ORIGINAL` |
| `git np patch` / `minor` / `major` | from `develop`: the next version after the highest tag, version tree or `VERSION` (`6.22.6` -> `6.22.7` / `6.23.0` / `7.0.0`) |
| `git nr <name>` (`git nueva-final`) | new final branch: from `<F>/ORIGINAL` -> `<F>/<name>`. `--from <F>/ORIGINAL` (also for `np`) works from any branch, e.g. an agent's worktree |
| `git nueva-version <v> [--from <branch>]` (`git nv`) | a new version tree from any branch, next to the others (below) |
| `git convertir-padre` | `<F>/<x>` -> `<F>/<x>/ORIGINAL` (local rename; a published branch is renamed on origin in one atomic push under a lease on its old tip) |
| `git subir` | final: rebase onto its `ORIGINAL`, push `--force-with-lease`. Parent: merge its remote and its parent if behind, push. `<v>/RELEASE`: rebase onto `develop`, push `--force-with-lease` |
| `git integra` | squash the current branch into its parent (rules above), with a generated Conventional Commits message; `-m "<subject>" [-m "<body>"]` skips the editor |
| `git arbol [prefix] [--limpiar [--yes]]` | the tree with parents (`+`), finals (`-`), pending commits and the current branch; `--limpiar` (flow squash) deletes the integrated branches, locally and on origin, only when every copy is integrated into its parent on the same side (one atomic push with a lease; diverged or unpushed-squash branches are kept and reported) |
| `git estructura [file]` (`git es`) | reads a whole tree from stdin (or files) and creates every missing branch from its parent; existing branches are only checked (below) |
| `git changelog [tag]` | preview of the release that `git release` would run (OT or version): the entry, the plan; changes nothing |
| `git release [tag]` | OT release (inside `<v>/<ot>/...`) or version release (on `<v>/ORIGINAL`, `develop`, or with `--version <v>`) |
| `git publicar [tag]` | `<version>/RELEASE` rebased onto `develop`, ONE commit on `develop`, tagged, pushed, deleted |
| `git combinar` | several `<v>/RELEASE` joined into one (below) |
| `git testing crear / estado / repartir` | the TESTING sandbox: try several branches together, then move the commits back (below) |
| `git limpiar-unmerged [-n] [--yes]` | delete the archived `unmerged/...` branches that are already in `develop` (below) |
| `git amend` | `git commit --amend` that keeps the `Files:` block right (below) |
| `git encoding [--fix] [file...]` | encoding check of the changed files (UTF-8, text damaged by a wrong-encoding save); `--fix` repairs them |
| `git repo-files [NAME...]` | the standard repository files that are missing ([REPO-FILES.md](REPO-FILES.md)) |

Options: `--yes` skips confirmations, `--force` integrates a parent with pending children.

## Example

```bash
git checkout develop
git np patch             # 6.22.6/ORIGINAL (6.22.5 was the last one); VERSION and pom.xml say 6.22.6
git np 188858            # 6.22.6/188858/ORIGINAL
git np RF001             # 6.22.6/188858/RF001/ORIGINAL
git nr login             # 6.22.6/188858/RF001/login         ... commits ...
git subir                # rebase onto RF001/ORIGINAL + push
git integra -m "feat(login): add certificate login"
                         # login -> RF001/ORIGINAL: one squash commit; login is deleted
# a final branch that needs children:
git checkout 6.22.6/188858/RF001/bank
git convertir-padre      # -> 6.22.6/188858/RF001/bank/ORIGINAL
git nr bugfix && git nr payments ...
# up the tree, once the children are in (each one is one squash commit):
git integra              # bank/ORIGINAL -> RF001/ORIGINAL
git integra              # RF001/ORIGINAL -> 188858/ORIGINAL
# the OT is closed by its OT release, from any branch of the OT:
git checkout 6.22.6/188858/ORIGINAL
git changelog            # preview of the OT release
git release              # 6.22.6/188858/RELEASE + tag ot/6.22.6/188858
# when every OT of the version is released:
git checkout 6.22.6/ORIGINAL
git changelog            # preview of the version release
git release              # 6.22.6/RELEASE + CHANGELOG.md + README badge + local tag 6.22.6
git publicar             # RELEASE rebased onto develop, one commit, tag, push
```

## The version: `VERSION`, `pom.xml`, `package.json`

When a version tree is created (`git np <version>` or `git np patch` from `develop`,
`git estructura`, `git nueva-version`), its `ORIGINAL` gets a first commit,
`chore(version): <version>`, that writes the version into:

- `VERSION` (one line; `branches.version_file`),
- every `pom.xml` that shares the root project version: the root `<version>`, the module
  `<version>` elements and the `<parent><version>` of the in-repository modules (a module with its
  own version, an external parent like Spring Boot or a `${revision}` property are left alone;
  `${revision}` in the root `<properties>` is updated),
- the top-level `"version"` of `package.json`.

The commit is made without checking anything out, so every branch created below starts with the
version written down. `branches.pom_version` decides what happens to `pom.xml`:

| Value | At tree creation | At `git release` |
| --- | --- | --- |
| `update` (default) | `<version>6.22.6</version>` | stays `6.22.6` |
| `snapshot` | `<version>6.22.6-SNAPSHOT</version>` | becomes `6.22.6` |
| `check` | untouched; the gate reports a mismatch with the command to fix it | untouched |
| `off` | untouched, not checked | untouched |

Manual equivalent: `mvn versions:set -DnewVersion=6.22.6 -DgenerateBackupPoms=false`.

**Merges.** Every tree writes its own version into the same lines, so bringing `develop` into a
tree after another release would collide on them in every `git subir`. A merge driver installed
by the suite (`.git/info/attributes`: `/VERSION`, `pom.xml`, `package.json` -> `qs-version`) keeps
the branch's own version (on `develop`, the version being released into it) and merges every
other change of the file normally (a new dependency in `pom.xml`).

**Checks.** The gate blocks a commit when `VERSION` is not semver, does not match the version of
the branch (`6.22.6/...` must say `6.22.6`), is older than the last release in `CHANGELOG.md`,
or `pom.xml` says something else (except `<version>-SNAPSHOT`).

## A whole structure at once: `git estructura`

Describe the branches you want, one per line, and pipe them in. Indentation means "child of the
line above", paths with `/` work too, and both can be mixed:

```bash
git es <<'END'
6.22.6
  188858
    RF001
      login
      bank
        bugfix
        payments
END
# the same as paths:  printf '6.22.6/188858/RF001/login\n6.22.6/188858/RF001/bank/bugfix\n' | git es
```

- A node with children (or written with a trailing `/` or `/ORIGINAL`) becomes a parent
  (`<node>/ORIGINAL`); a version is always a parent; every other node is a final branch. The
  missing ancestors are created too. A new version gets its version commit.
- Existing branches are never recreated: they are listed as `=`, with `N behind <parent>` when
  they need `git subir`. New siblings are created from their parent's tip (`+`).
- Everything is validated first; if one name is invalid or a final branch would need children,
  nothing is created. `--convertir` turns such a final branch into a parent (like
  `git convertir-padre`).
- The current branch does not change. `-n` shows the plan only; `--push` publishes the branches
  of the structure that are not on origin yet. Input can be a file (`git es plan.txt`), a drawn
  tree (`├──`, `└──`), or the output of `git arbol` (to replicate a structure elsewhere).

## A version tree from any branch: `git nueva-version`

```bash
git nv 6.22.6-SNAPSHOT --from 6.22.6/188858/ORIGINAL     # -n first to see the plan
```

- `6.22.6-SNAPSHOT/ORIGINAL` starts at the chosen branch, plus its version commit
  (`VERSION` and `pom.xml`: `6.22.6-SNAPSHOT`).
- The branches below the chosen one are copied under the new version **keeping their path
  below the version**: `6.22.6/188858/login` -> `6.22.6-SNAPSHOT/188858/login`; the parents in
  between are created. Each copy keeps its work and gets a merge of its new parent (made without
  a work tree); one that conflicts is left as it was, with a warning (`git subir` on it).
- `--arbol-completo` copies every branch of the source version tree instead.
- The original tree is not touched; both live side by side and are released separately.
- `git nv patch|minor|major` takes the next version like `git np`.

## Integration: `git integra` (flow = squash)

Each level goes up by **rebase onto its own ORIGINAL, then squash into the ORIGINAL above**.
Every squash is one single-parent commit on the ORIGINAL, so the history of an OT reads as one
line per change.

1. **Final branch** `<F>/x`: rebased onto `<F>/ORIGINAL`, then `merge --squash` into it: one
   commit. The branch is then deleted, locally and on origin (confirmation; `--yes` skips it).
   A squashed branch cannot be deleted with `git branch -d`, so the command does it.
2. **`<F>/ORIGINAL`** when every child is contained: rebased onto its parent `ORIGINAL` (its sync
   merges are dropped: their content is in the new base), then squashed into it. Refused while a
   child is pending (`--force` as before) or while the branch is checked out in another worktree.
3. Repeat up to `<v>/<ot>/ORIGINAL`. That one goes up only through `git release` (OT release).

The squash commit message:

```text
feat(login): add certificate login               <- subject (Conventional Commits, <= 50, ASCII)

Body written with -m "<body>", if any.

Commits:                                          <- what was squashed, nested for squashes of squashes
- 1a2b3c4 feat(login): add certificate login
  - 9f8e7d6 fix(login): keep the link text
Files:
M engine/changelog.py
A tests/unit/test_changelog5.py
R docs/old.md -> docs/new.md

Norms: JDA-SEG-010                                <- trailers stay the last paragraph
Refs: 6.22.6/188858/RF001/login -> 6.22.6/188858/RF001/ORIGINAL
Squashed: 6.22.6/188858/RF001/login 0123456789abcdef...
```

- `Files:` lists **every** file the commit changes, as `<status> <path>` (`M` modified, `A` added,
  `D` deleted, `R old -> new` renamed). Non-ASCII names are escaped. `(none)` for an empty commit.
- `Squashed:` (full sha) lets the release check recognise squash-integrated branches.
- `Refs:` is kept for the readers of 4.x history.

### Running integra from a worktree

`.quality-rules.json` may be git-ignored, so a worktree gets the generated default
(`flow: merge`) and `git integra` there makes merge commits (two parents) in the ORIGINAL. Run it
only from the main checkout, or copy the real file into the worktree first. Before integrating,
check the `"flow":` line; before pushing, check that `git log -1 --format=%P <ORIGINAL>` prints
one parent. A wrong integration that is already pushed is never rewritten: report it.

## Closing an OT: `git release` (OT release)

Run it inside `<v>/<ot>/...` (or with `--ot <v>/<ot>`) once every branch of the OT is integrated.

1. **Checks.** Every branch under `<v>/<ot>/` is integrated (squash-aware, through `Squashed:`);
   a branch that never reached its ORIGINAL is set aside as `unmerged/<name>`, as before. The OT
   ORIGINAL has at least one commit of its own, and it does not diverge from its remote.
2. **`<v>/<ot>/RELEASE`** is created at the OT ORIGINAL tip, with one commit
   `docs(changelog): <v> <ot>` that adds the OT lines to the `## <v>` section of `CHANGELOG.md`:
   one line per first-parent commit of the OT ORIGINAL since `<v>/ORIGINAL`, all with the OT
   `<ot>`.
3. **Hidden ref `refs/ot/<v>/<ot>`** (`branches.ot_ref`, never a tag: tags are version numbers
   only) on the OT ORIGINAL tip. RELEASE and the ref are pushed, and the OT subtree is deleted.
   Hashes cited in `CHANGELOG.md` stay reachable through the ref; `git tag -l` never shows it
   and a plain clone does not fetch it (`git fetch origin 'refs/ot/*:refs/ot/*'` does).
4. No `VERSION` or README badge change. Resumable: run `git release` again after a failure.

An OT cannot be re-opened after its OT release: use a new OT.

## Closing a version: `git release` (version release) and `git publicar`

```bash
git changelog                 # 1. preview: changes nothing
git release                   # 2. <v>/RELEASE: the OT RELEASEs, version, CHANGELOG.md, README badge
                              #    ... review CHANGELOG.md on <v>/RELEASE, edit, commit ...
git publicar                  # 3. rebase onto develop, ONE commit, tag, push, delete RELEASE
```

`--version <v>` can be omitted from any branch of that version tree (or when there is only one).
The tag defaults to `branches.tag` (`{version}`: `6.22.6`); give another as the first argument.

**`git release` (version)** is refused, and changes nothing, while an OT of the version has no
`<v>/<ot>/RELEASE` or still has other branches: the refusal lists them. Otherwise, in this order:

1. `<v>/RELEASE` at the tip of `<v>/ORIGINAL`.
2. Each OT RELEASE, oldest first (author date of its oldest own commit, then name), is rebased
   onto `<v>/RELEASE` and its `docs(changelog)` commit is dropped. **On a conflict** the command
   stops with the steps: resolve, `git rebase --continue`, then `git release` again; it resumes
   with the next OT (progress in `git config qs.release.<v>.ots`).
3. `chore(version): <v>` when `VERSION` / `pom.xml` need it; `docs(changelog): <v>` = the union of
   the OT sections as reviewed on each OT RELEASE (a manual edit made there is kept);
   `docs(readme): version <v>` for the badge.
4. An annotated tag `<tag>` on the RELEASE tip, message = the `CHANGELOG.md` entry. It stays
   **local** until `git publicar`.
5. `<v>/RELEASE` is pushed; the OT RELEASEs and `<v>/ORIGINAL` are deleted (local and origin). The
   `ot/...` tags keep the history.

`git release --reset --version <v> [--yes]` forgets the resume state of a version release that
was given up. It is refused while `<v>/RELEASE` exists.

**`git publicar`** (`--version <v>` when there are several RELEASE branches):

1. If `develop` is not inside `<v>/RELEASE`, it is rebased onto `develop`. A conflict is solved
   automatically only when the commit being replayed is a release commit (`chore(version)`,
   `chore(release)`, `docs(changelog)`, `docs(readme)`) and every conflicted file is a release
   file, and only on release-owned lines:
   - the `CHANGELOG.md` entry of the version (both sides kept, in semver order);
   - `VERSION` (the RELEASE side);
   - the README badge between the `<!-- qs:version -->` markers;
   - the project's own `<version>` in `pom.xml` and the top-level `"version"` of `package.json`;
   - `version:` and `date-released:` in `CITATION.cff`.

   Edits of `develop` next to those lines are kept. **Any other conflicting line stops** (also a
   side that deleted the file): the command lists the files and the steps. Resolve it,
   `git rebase --continue`, run `git publicar` again (it resumes). Nothing is written until every
   file of the step is solved. RELEASE is pushed with `--force-with-lease`.
2. If RELEASE moved and the tag is not on origin, the tag is re-created on the new tip.
3. `develop` gets **one** commit `chore(release): <tag>`, with the tree of the RELEASE tip, and
   the body: `Commits:` (the RELEASE commits, nested), `Files:`, `Refs:`, `Squashed:` and
   `Squashes:` when several versions were combined.
4. An atomic push of `develop` and the tag; `<v>/RELEASE` is deleted (local and origin).

`git publicar --reset --version <v> [--yes]` forgets the publish state kept while RELEASE is
rebased. It is refused while a rebase is stopped; a state left by `git rebase --abort` is also
forgotten by the next `git publicar`.

### The `CHANGELOG.md` line

Each change is one line:

```md
- Tighten generated-file matching (421994d; git)
```

`- <Subject> (<commit>; <OT>)`. The commit is the short hash of the OT ORIGINAL commit (a link
when the origin is GitHub, GitLab, Azure DevOps or Bitbucket, or `branches.commit_url` is set).
Authors are not written and norm ids are not in the line; they stay in the commit trailers.
A change without OT (a direct commit on `<v>/ORIGINAL`, legacy history) is written as
`- <Subject> (<commit>)` with a console warning `change without OT: <hash> <subject>`; it never
blocks the release.

The entry is in [Common Changelog](https://common-changelog.org) format, grouped by
Conventional Commits type: `feat` -> Added, `fix` -> Fixed, `perf` / `refactor` / `build` /
`revert` -> Changed, a description starting with remove / drop / delete -> Removed; `docs`,
`test`, `ci`, `chore`, `style` are left out (the console lists them). `!` or a `BREAKING CHANGE:`
footer -> `**Breaking:**`, first in its group. Heading `## [6.22.6] - YYYY-MM-DD`, releases sorted
by semver, newest first.

The gate validates `CHANGELOG.md` on every commit that touches it. The 4.x lines with an author
(`; Ana Perez`) stay valid.

### The README badge

`git release` keeps a badge with the last released version under the title of `README.md`:

```md
<!-- qs:version -->[![version 6.22.6](https://img.shields.io/badge/version-6.22.6-blue)](CHANGELOG.md)<!-- /qs:version -->
```

The text between the markers is replaced. The gate checks that it matches the last release in
`CHANGELOG.md`.

## Several version trees: `git combinar`

With several trees at the root (`6.22.6`, `6.22.6-SNAPSHOT`, `6.22.7`...), each one first becomes
its own `RELEASE`. Then `git combinar` asks yes/no for each `<v>/RELEASE` and the version of the
result, and joins the chosen ones **in creation order**:

```bash
git combinar                                              # questions
git combinar --incluir 6.22.6,6.22.6-SNAPSHOT --version 6.22.7 --yes
```

- `develop` is merged into a RELEASE that does not contain it as a **temporary commit** (no branch
  moves). Conflicts in the release files are solved for `develop`; any other conflict stops with
  "nothing was changed" and the steps.
- The result starts at `develop` and gets one `chore(combine): <v> changes` squash per RELEASE,
  with only its own changes, in the body the squashed subjects and `Squashes: <v>/RELEASE <sha>`.
- The `CHANGELOG.md` entry is the **union** of the reviewed sections of the combined RELEASE
  branches. Then the version, changelog and badge commits of the new version.
- The joined branches are kept as `unmerged/<v>/RELEASE` (local and origin); remove them by hand.
- All or nothing: commits are made in a temporary worktree first, then the local branches move in
  one transaction, then one atomic push to origin. Any failure changes nothing.

Then `git publicar --version <version>` lands the combined version on `develop` as **one** commit,
listing the combined versions in `Squashes:`.

## Testing several branches together: `git testing`

`<F>/TESTING` is a throw-away branch, one per level, next to `<F>/ORIGINAL`
(e.g. `5.0.0-RC1/git/TESTING`). It starts at `<F>/ORIGINAL` and gets a merge of each source branch
you name, so you can build and try them together.

```bash
git testing crear 5.0.0-RC1/git/a 5.0.0-RC1/git/b      # level = the one of the current branch
git testing estado                                     # sources, and the commits made on TESTING
git testing crear --recrear                            # re-create from the sources' new tips
git testing repartir --map <commit>=<F>/a              # move TESTING commits back to their branches
```

- Creation merges each source (`--no-ff`) in the given order, then makes an empty marker commit
  `chore(testing): create` whose body lists `Sources:` with the full sha of each source, and the
  trailer `Testing-Create:`. The marker is the source of truth for the sources; a git config
  cache (`qs.testing.<F>.sources`) is rebuilt from it when missing. A conflict aborts and removes
  the half-made branch.
- Sources are **any** branch, not only children or siblings.
- New changes in a source are picked up by **re-creating** TESTING (`--recrear`), never by updating
  it. `--recrear` is refused while TESTING has commits not yet distributed, unless `--force`.
- `repartir` moves each commit made on TESTING to a branch you choose (the sources first, or any
  other branch), with `cherry-pick -x` in a temporary worktree. A commit whose change is already in
  the target is skipped by default (`--on-applied apply` tries it anyway). A conflicting
  cherry-pick is aborted and the next commit goes on. Nothing is pushed.

**Why TESTING can never be merged or rebased.** It holds copies of commits that are also on their
source branches; merging or rebasing it with anything would duplicate or rewrite them. Refused,
with "TESTING is a sandbox: it cannot be merged, rebased or integrated. Move its new commits to
their source branches with `git testing repartir`.":

- `git merge` into or from TESTING, and `git merge` of any branch while on TESTING;
- `git rebase` of TESTING, or onto it;
- `git integra` and `git subir` on TESTING;
- pushing its commits to an `ORIGINAL` or a `RELEASE` ref.

Pushing TESTING to its own name is allowed (`--force-with-lease` after a re-creation).

## Cleaning archived branches: `git limpiar-unmerged`

`git release` and `git combinar` set branches aside as `unmerged/<name>`, and nothing removed them.
`git limpiar-unmerged -n` lists every `unmerged/...` branch (local and on origin) as
**integrated**, **superseded by <ref>**, or **pending**, and `git limpiar-unmerged` deletes only
the first two, after confirmation (`--yes` answers it).

- **Integrated** means the changes are in `develop`, checked by a simulated merge: the only
  differences are release files (`VERSION`, `CHANGELOG.md`, `CITATION.cff`, the README badge,
  the version lines of `pom.xml` and `package.json`). Ancestry is not enough: releases squash.
- **Superseded**: the branch is an ancestor of, or has the same content as, an integrated archived
  branch or release tag (e.g. `4.0.2` inside `4.0.3`).
- **Pending**: anything else, including a branch with a conflict or without a merge base. Pending
  branches are never deleted; the output lists the files they would still add.
- Deleted refs are printed as `deleted <branch> (was <sha>)`: `git branch <branch> <sha>` restores
  one. A push rejected by a moved branch (`--force-with-lease`) changes nothing on origin and
  exits 1.
- Run it locally with `-n` first. Deleting on origin is a human decision.

## Amending: `git amend`

`git amend` is `git commit --amend` with `QS_AMEND=1`, so the hooks know it is an amend. The
`Files:` block of the amended commit is recomputed against `HEAD^`. A `post-commit` hook warns
when the block of the new commit does not match its files (it never rewrites anything, and
`commit.files = off` disables it). Fix it with `git amend --no-edit`.

## Hooks

| Hook | Role |
| --- | --- |
| prepare-commit-msg | writes the `Files:` block of every commit (editor, `-m`, merge, squash, amend) |
| commit-msg | the block is in the final message; restores it if removed in the editor |
| post-commit | warns when the block does not match the commit's files |
| pre-push | branch names follow the model and the reserved leaves; a final branch contains its `ORIGINAL` (else `git subir`); `<v>/<ot>/RELEASE` and `<v>/RELEASE` may be force-pushed with a lease; shared branches (`ORIGINAL`, `develop`, `main`) are never force-pushed; then the quality gate; TESTING rules |
| pre-rebase | final branches rebase onto their parent; `<F>/ORIGINAL` onto its parent when all children are in; `<v>/RELEASE` only onto `develop` (`git subir`, `git publicar`; the rebase of each OT RELEASE onto `<v>/RELEASE` is done by `git release` itself); shared branches only onto their own remote; TESTING refused |
| pre-merge-commit | refuses child -> ORIGINAL merges (use `git integra`) and RELEASE/ORIGINAL -> `develop` merges (use `git publicar`); parent -> child sync merges are allowed; TESTING refused |
| reference-transaction | after a ref update: a non-`TESTING` branch that now contains `TESTING` commits (e.g. `git merge --ff-only <F>/TESTING`) is reported with the command to undo it; `pre-push` refuses to push it |
| post-checkout | refreshes the repo config and aliases; warns about off-model names |

## Configuration (`.quality-rules.json` -> `branches`)

| Key | Default | Meaning |
| --- | --- | --- |
| `flow` | `squash` | `squash` (5.x) or `merge` (4.x behaviour, for trees started with 4.x; deprecated, removed in 6.0) |
| `model` | `5` | marker of the one-time migration of the rules file; do not change it |
| `enforce` | `block` | `block`, `warn` or `off` |
| `parent_leaf` | `ORIGINAL` | last segment of parent branches |
| `mainline` | `develop` | where versions are merged |
| `protected` | `main`, `master`, `develop` | branches outside the model |
| `levels` | semver (no build metadata), `^[A-Za-z0-9]+$` | regex per segment: version, OT (ASCII letters and digits), ... |
| `segment` | `^[A-Za-z0-9][A-Za-z0-9_-]*$` | regex for deeper segments (ASCII only) |
| `allow` | `[]` | extra branch-name regexes (e.g. `^release/`) |
| `leaf_merge` | `merge` | only with `flow = merge`: final -> ORIGINAL with `merge` (`--no-ff`) or `squash` |
| `require_children_merged` | `true` | a parent goes up only when all its children are in |
| `publish_on_create` | `true` | every branch a suite command creates is pushed to origin with `-u`; `false` (or `QS_PUBLISH=0` for one command) leaves it to `git subir` |
| `tag` / `tag_level` | `{version}` / `1` | release tag (`{version}`, `{ot}`, `{date}`); `tag_level` only with `flow = merge` (`0` = never) |
| `ot_ref` | `refs/ot/{version}/{ot}` | hidden ref on the OT ORIGINAL tip at the OT release (`''` = none); never a tag, so `ot/` names do not clash with the version tags |
| `release_leaf` | `RELEASE` | `<version>/ORIGINAL` becomes `<version>/RELEASE` at `git release` |
| `testing_leaf` | `TESTING` | reserved leaf of the TESTING sandbox; must differ from `parent_leaf` and `release_leaf` |
| `archive_prefix` | `unmerged` | branches never integrated are set aside as `unmerged/<name>` |
| `version_file` | `VERSION` | the version file (`''` = none) |
| `changelog_file` | `CHANGELOG.md` | release notes (`''` = none) |
| `readme_file` | `README.md` | version badge (`''` = none) |
| `pom_version` | `update` | `update`, `snapshot`, `check`, `off` (table above) |
| `tag_url` / `commit_url` | `''` | changelog links: `''` = from origin, `-` = none, or a URL with `{tag}` / `{commit}` |

Top-level key `commit.files`: `block` (default), `warn` or `off`: the `Files:` block in every commit.

The hooks read these values from `.git/quality-suite/policy.env`, written by the engine on
each commit (and regenerated when the rules file is newer).

Repo-local git config applied on install and on checkout: `pull.rebase=true`,
`rebase.autoStash=true`, `branch.autoSetupRebase=always`, `push.default=current`,
`merge.ff=false`, `rerere.enabled=true` (+autoupdate), `fetch.prune=true`, the `qs-version`
merge driver.

## Migrating from 4.x

Rules files are migrated by the engine on the next commit, `git instalar` or
`git actualizar-suite` (see [UPDATING.md](UPDATING.md)):

- a 4.x rules file keeps `branches.flow = merge`: the 4.x behaviour (`git integra` merges, one-level
  release, `git publicar` merges) stays until you switch it by hand;
- a new repository (`git iniciar`, first commit) starts with `flow = squash`.

To switch a repository to the squash flow, first finish or publish the version trees started with
4.x (mixing both flows in one tree is not supported). Then set, in `.quality-rules.json`:

```json
"branches": { "flow": "squash" }
```

Older CHANGELOG lines (with authors, or with `(hash, OT 100, NORM; Author)`) stay valid. The
`merge` flow is deprecated and removed in 6.0.

## Migrating from the 2.0 model (`feature/<HU>.<TR>`)

Old branches are off-model: integrate or rename them (`git branch -m`), or allow them for a
while with `"branches": {"allow": ["^feature/"]}`. Version trees whose name is not semver
(`6.22`) keep working only with the old rule: `"levels": ["^[0-9]+(\\.[0-9]+)*$", "^[0-9]+$"]` (numeric OTs only).
