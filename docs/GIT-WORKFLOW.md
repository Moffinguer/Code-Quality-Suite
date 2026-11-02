# Git workflow - branch model and commands

Client-side workflow layered on the quality gate: hierarchical branches named after the
version and the work order (OT), final branches rebased onto their parent, parents merged
upwards, and a release in two reviewed steps (`git release`, `git publicar`) that writes
`CHANGELOG.md`, the README version badge and the version in `VERSION` / `pom.xml`.
Everything is a plain git alias. Enforcement is client-side (hooks);
`examples/ci/azure-pipelines-quality.yml` repeats the name check on the server.

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
| final (`.../bugfix`) | **rebase** onto its `ORIGINAL` (`git subir`) | `git integra`: rebase, then merge (`--no-ff`, or squash) into its `ORIGINAL` |
| parent (`.../ORIGINAL`) | **merge** of its parent (`git subir`); never rebased: others build on it | `git integra`: merge `--no-ff` into the parent `ORIGINAL`, once all its children are integrated |
| `<version>/ORIGINAL` | merge of `develop` | `git release` -> `<version>/RELEASE` (reviewed) -> `git publicar` into `develop` |

## Commands (git aliases)

The full manual, with syntax, when to use each command and who runs it:
[GIT-COMMANDS.md](GIT-COMMANDS.md) (`git ayuda`, and the `git-commands` skill of the agents).

| Command | Does |
| --- | --- |
| `git np <name>` (`git nueva-padre`) | new parent branch: from `develop` -> `<version>/ORIGINAL` with its version commit (below); from `<F>/ORIGINAL` -> `<F>/<name>/ORIGINAL` |
| `git np patch` / `minor` / `major` | from `develop`: the next version after the highest tag, version tree or `VERSION` (`6.22.6` -> `6.22.7` / `6.23.0` / `7.0.0`) |
| `git nr <name>` (`git nueva-final`) | new final branch: from `<F>/ORIGINAL` -> `<F>/<name>`. `--from <F>/ORIGINAL` (also for `np`) works from any branch, e.g. an agent's worktree |
| `git nueva-version <v> [--from <branch>]` (`git nv`) | a new version tree from any branch, next to the others (below) |
| `git convertir-padre` | `<F>/<x>` -> `<F>/<x>/ORIGINAL` (local rename; on origin: delete + push, after confirmation) |
| `git subir` | final: rebase onto its `ORIGINAL`, push `--force-with-lease`. Parent: merge its remote and its parent if behind, push |
| `git integra` | integrate the current branch into its parent (rules above), with a generated Conventional Commits message; `-m "<subject>" [-m "<body>"]` skips the editor |
| `git arbol [prefix]` | the tree with parents (`+`), finals (`-`), pending commits and the current branch |
| `git estructura [file]` (`git es`) | reads a whole tree from stdin (or files) and creates every missing branch from its parent; existing branches are only checked (below) |
| `git changelog [tag]` | preview of a release: changelog per branch, the `CHANGELOG.md` entry, semver advice, recursive check, plan; changes nothing |
| `git release [tag]` | step 1: `<version>/RELEASE` with the version, `CHANGELOG.md` and README badge commits; the rest of the tree is deleted |
| `git publicar [tag]` | step 2: `<version>/RELEASE` merged into `develop`, tagged, pushed, deleted |
| `git combinar` | several `<v>/RELEASE` joined into one (below) |
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
git integra              # login -> RF001/ORIGINAL (editor opens: fill the subject)
# a final branch that needs children:
git checkout 6.22.6/188858/RF001/bank
git convertir-padre      # -> 6.22.6/188858/RF001/bank/ORIGINAL
git nr bugfix && git nr payments ...
# up the tree, once the children are in:
git integra              # bank/ORIGINAL -> RF001/ORIGINAL
git integra              # RF001/ORIGINAL -> 188858/ORIGINAL -> 6.22.6/ORIGINAL
# the release, in two steps with a review in between:
git changelog            # preview
git release              # 6.22.6/RELEASE + CHANGELOG.md + README badge
git publicar             # into develop, tag 6.22.6, push
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
  between are created (`6.22.6-SNAPSHOT/188858/ORIGINAL` is a copy of the chosen branch). Each
  copy keeps its work and gets a merge of its new parent (made without a work tree); one that
  conflicts is left as it was, with a warning (`git subir` on it).
- `--arbol-completo` copies every branch of the source version tree instead.
- The original tree is not touched; both live side by side and are released separately.
- `git nv patch|minor|major` takes the next version like `git np`.

## Closing a version: `git changelog`, `git release`, `git publicar`

```bash
git changelog                 # 1. preview: changes nothing
git release                   # 2. <version>/RELEASE with version, CHANGELOG.md, README badge
                              #    ... review CHANGELOG.md on <version>/RELEASE, edit, commit ...
git publicar                  # 3. merge into develop, tag, push, delete RELEASE
```

`--version <v>` can be omitted from any branch of that version tree (or when there is only one).
The tag defaults to `branches.tag` (`{version}`: `6.22.6`); give another as the first argument
(`git release v6.22.6`); `git publicar` reuses the one given to `git release`.

**The check** (preview and step 1) is recursive and follows the names: every branch of
`6.22.6/...` is compared with its own ORIGINAL (siblings with the ORIGINAL of their level, the
children of each sibling with theirs, down to the last level):

| Branch state | What happens |
| --- | --- |
| nothing outside its ORIGINAL (integrated, or identical to it) | deleted with the tree |
| commits that never reached its ORIGINAL | warning; set aside as `unmerged/<its name>` (local and origin), kept out of the release |
| local and origin diverged, or `develop` has commits the version lacks | blocks: fix it first (`git subir`) |

A name for a branch set aside is always free of the file/folder clash of git refs (`a/b` cannot
coexist with `a/b/c`): an existing `unmerged/...` gets `-2`, `-3`... and, if a prefix is taken,
the branch goes under `unmerged-<date>/`.

**The preview** shows what each branch brought (from the history of `<version>/ORIGINAL`: every
`git integra` merge records `Refs: <branch> -> <parent>`, so it works after the branches are
gone), the `CHANGELOG.md` entry that will be written, and a semver warning when the version
does not match the changes since the previous release (a `feat` needs at least a MINOR version,
a breaking change a MAJOR one).

**`git release`** (step 1), in this order:

1. branches never integrated -> `unmerged/<name>` (later, after the push);
2. `<version>/RELEASE` at the tip of `<version>/ORIGINAL`, checked out;
3. `chore(version): <version>` when `VERSION` / `pom.xml` need it (a SNAPSHOT pom becomes the
   release version);
4. `docs(changelog): <version>`: the entry added to `CHANGELOG.md` (created if missing);
5. `docs(readme): version <version>`: the README badge (and `CITATION.cff`);
6. push `<version>/RELEASE`; then the rest of the tree is deleted (local and origin).

The commits go through the hooks like any other. If a step fails, fix it and run the same
`git release` again: it resumes. Once done, review the release on `<version>/RELEASE`:

```bash
git show --stat HEAD~2..HEAD         # the release commits
code CHANGELOG.md                    # wording, order, merge related lines
git commit -am "docs(changelog): review"
```

**`git publicar`** (step 2): `<version>/RELEASE` merged into `develop` (`--no-ff`,
`chore(release): <tag>`), annotated tag `<tag>` on `RELEASE` with its `CHANGELOG.md` entry as the
message, push of `develop` and the tag, and `RELEASE` deleted (local and origin). If the push
fails, `RELEASE` is kept: fix the cause and run it again (it resumes). If `develop` moved since
step 1, it says so: `git checkout <version>/RELEASE && git merge develop`, review, publish.

### The `CHANGELOG.md` entry (Common Changelog)

Written in [Common Changelog](https://common-changelog.org) format, from the history:

- one change per integrated final branch (the subject of its `git integra` merge) and per direct
  commit on an `ORIGINAL`; Conventional Commits types decide the group: `feat` -> Added, `fix` ->
  Fixed, `perf` / `refactor` / `build` / `revert` -> Changed, a description starting with
  remove / drop / delete -> Removed; `docs`, `test`, `ci`, `chore`, `style` are left out (the
  console lists them);
- `!` or a `BREAKING CHANGE:` footer -> `**Breaking:**`, first in its group;
- references: the commit (a link when origin is GitHub, GitLab, Azure DevOps or Bitbucket, or
  `branches.commit_url`), the OT of the branch, the `Norms:` trailers; then the authors;
- heading `## [6.22.6] - YYYY-MM-DD` with a link definition to the tag (or `## 6.22.6 - ...` when
  no tag URL is known); releases sorted by semver, newest first; no `Unreleased` section.

```md
## [6.22.6] - 2026-10-26

### Added

- Add certificate login ([c7e068d](https://git.example/app/commit/c7e068d...), OT 188858, JDA-SEG-010; Ana Pérez)

### Fixed

- **Breaking:** Drop legacy session cookie ([26c01d3](...); Ana Pérez)
```

The gate validates `CHANGELOG.md` on every commit that touches it (format, semver, dates, order,
groups, link definitions; a change without references is a warning).

### The README badge

`git release` keeps a badge with the last released version under the title of `README.md`:

```md
<!-- qs:version -->[![version 6.22.6](https://img.shields.io/badge/version-6.22.6-blue)](CHANGELOG.md)<!-- /qs:version -->
```

The text between the markers is replaced; the alt text keeps the version readable where images
are blocked. The gate checks that it matches the last release in `CHANGELOG.md`.

## Several version trees: `git combinar` and one release at a time

With several trees at the root (`6.22.6`, `6.22.6-SNAPSHOT`, `6.22.7`...), each one first becomes
its own `RELEASE` (`git release --version <v>`). Then:

- **One at a time.** With two or more `RELEASE` branches, `git publicar` refuses to guess:
  `git publicar --version <v>` merges exactly that one.
- **Joined first.** `git combinar` asks yes/no for each `<v>/RELEASE`, then the version of the
  result, and joins the chosen ones **in creation order** into `<version>/RELEASE`. The order
  uses author dates, which a rebase or a cherry-pick keeps: a tree is dated by its version commit
  (`chore(version): <v>`, made by `git np` or `git nueva-version`), or by its oldest commit not in
  `develop` when it has none; a combined `RELEASE` takes the earliest date of what it squashed
  (each squash commit is written with that date, so the order holds even when an original named
  in `Squashes:` is gone). On the same second, the tree with fewer commits (the source of a copy)
  goes first:

  ```bash
  git combinar                                              # questions
  git combinar --incluir 6.22.6,6.22.6-SNAPSHOT --version 6.22.7 --yes
  ```

  `develop` keeps moving after the trees are prepared, so:

  1. **Up to date with develop.** A `RELEASE` that does not contain `develop` gets a warning, and
     combinar merges `develop` into it as a **temporary commit**: no branch moves. Conflicts in
     the release files (`VERSION`, the pom and `package.json` version, the README badge,
     `CITATION.cff`, `CHANGELOG.md`) are solved for `develop`, because they are written again at
     the end. Any other conflict stops everything with "nothing was changed", the conflicted
     files and the steps: `git checkout <v>/RELEASE && git merge develop`, resolve
     (`CHANGELOG.md` keeps both sides' entries in semver order; `VERSION`, the pom version, the
     badge and `CITATION.cff` keep the `RELEASE` version; other files by hand), commit, run
     combinar again. A merge of `develop` made by hand is used as it is.
  2. **One squash per version.** The result starts at `develop` and gets, oldest tree first, one
     commit `chore(combine): <v> changes` per `RELEASE` with only its own changes: nothing of
     `develop`, none of its version/changelog/readme commits, nothing an earlier tree already
     brought (a tree copied from another with `git nueva-version` squashes only what it added
     after the copy). Its body lists the subjects it squashes and a line
     `Squashes: <v>/RELEASE <sha>` naming the original tip. A squash with nothing new is left
     out. Edits made inside a release commit (other than the version lines) are not kept.
  3. **Release commits.** Then the version, `CHANGELOG.md` and README badge commits of the new
     version. The changelog entry is built from the original histories (the `git integra`
     merges and their `Refs:`), so each change is listed once with its OT, and the squashes
     never appear in it.
  4. **Originals kept.** The joined `RELEASE` branches are renamed to `unmerged/<v>/RELEASE`
     (local and origin), so the changelog refs and the `Squashes:` shas keep resolving; remove
     them by hand when no longer needed. On origin a rename deletes the old name
     (`<v>/RELEASE`) there. Before anything is done, the plan lists every rename, local and on
     origin, and asks for confirmation in the same `[y/N]` question (`--yes` answers it).
  5. **All or nothing.** Every commit (squashes and release commits) is made first in a
     temporary worktree. Only then the local branches move, in one transaction (`git update-ref
     --stdin`): `<version>/RELEASE` on the result, the joined ones renamed, HEAD on the result;
     on any failure (a hook rejects a release commit, the suite image does not run...) branches
     and HEAD stay as they were. Last, origin gets **one atomic push** (`git push --atomic`, with
     `--force-with-lease` on every ref it had): the new branch and the renames, all or none. If
     that push fails, the local result is kept and the exact `git push --atomic ...` to run when
     origin accepts it is printed.

  The output shows, per `RELEASE`, how many own commits were squashed and how many mainline
  merges (merges whose second parent is in `develop`), release commits and commits already
  combined were dropped. A combined `RELEASE` can be combined again with other trees: its
  `Squashes:` lines lead to the originals, for the order, the copy detection and the changelog.
  On a conflict between two `RELEASE` branches nothing changes either: join those by hand on one
  `RELEASE` branch, or combine fewer.

Then `git publicar --version <version>`.

## Hooks

| Hook | Role |
| --- | --- |
| pre-push | branch names follow the model; a final branch contains its `ORIGINAL` (else `git subir`); shared branches (`ORIGINAL`, `develop`, `main`) are never force-pushed; then the quality gate |
| pre-rebase | final branches rebase onto their parent (or tidy their own commits); shared branches only onto their own remote (`git pull`) |
| pre-merge-commit | into an `ORIGINAL`: its children or its parent; into `develop`: a `<version>/ORIGINAL` or `<version>/RELEASE`; never into a final branch |
| post-checkout | refreshes the repo config and aliases; warns about off-model names |
| commit-msg | ASCII-only message (`commit.charset`), Conventional Commits |

## Configuration (`.quality-rules.json` -> `branches`)

| Key | Default | Meaning |
| --- | --- | --- |
| `enforce` | `block` | `block`, `warn` or `off` |
| `parent_leaf` | `ORIGINAL` | last segment of parent branches |
| `mainline` | `develop` | where versions are merged |
| `protected` | `main`, `master`, `develop` | branches outside the model |
| `levels` | semver (no build metadata), `^[A-Za-z0-9]+$` | regex per segment: version, OT (ASCII letters and digits), ... (an OT like `PROJ-123` needs e.g. `^[A-Za-z0-9][A-Za-z0-9_-]*$`) |
| `segment` | `^[A-Za-z0-9][A-Za-z0-9_-]*$` | regex for deeper segments (ASCII only) |
| `allow` | `[]` | extra branch-name regexes (e.g. `^release/`) |
| `leaf_merge` | `merge` | final -> ORIGINAL with `merge` (`--no-ff`) or `squash` |
| `require_children_merged` | `true` | a parent goes up only when all its children are in |
| `tag` / `tag_level` | `{version}` / `1` | release tag (`{version}`, `{ot}`, `{date}`); `tag_level` also tags when a level-N `ORIGINAL` is integrated with `git integra` (`0` = never) |
| `release_leaf` | `RELEASE` | `<version>/ORIGINAL` becomes `<version>/RELEASE` at `git release` |
| `archive_prefix` | `unmerged` | branches never integrated are set aside as `unmerged/<name>` |
| `version_file` | `VERSION` | the version file (`''` = none) |
| `changelog_file` | `CHANGELOG.md` | release notes (`''` = none) |
| `readme_file` | `README.md` | version badge (`''` = none) |
| `pom_version` | `update` | `update`, `snapshot`, `check`, `off` (table above) |
| `tag_url` / `commit_url` | `''` | changelog links: `''` = from origin, `-` = none, or a URL with `{tag}` / `{commit}` |

The hooks read these values from `.git/quality-suite/policy.env`, written by the engine on
each commit (and regenerated when the rules file is newer).

Repo-local git config applied on install and on checkout: `pull.rebase=true`,
`rebase.autoStash=true`, `branch.autoSetupRebase=always`, `push.default=current`,
`merge.ff=false`, `rerere.enabled=true` (+autoupdate), `fetch.prune=true`, the `qs-version`
merge driver.

## Migrating from the 2.0 model (`feature/<HU>.<TR>`)

Old branches are off-model: integrate or rename them (`git branch -m`), or allow them for a
while with `"branches": {"allow": ["^feature/"]}`. Version trees whose name is not semver
(`6.22`) keep working only with the old rule: `"levels": ["^[0-9]+(\\.[0-9]+)*$", "^[0-9]+$"]` (numeric OTs only).
