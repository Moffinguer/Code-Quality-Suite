# Git commands - the manual

Every command of the code-quality-suite workflow is a git alias. This page is the manual: what
each one does, when to use it, and who runs it. `git ayuda` prints it; `git ayuda <command>`
prints one command. AI agents get it as the `git-commands` skill.

**Who** says who runs a command: *anyone* (people and agents), *lead* (the main agent session or
a person), *human* (a person decides it; agents propose it and stop).

## 1. Once per machine: the only script you run by hand

```bash
bash /c/dev/code-quality-suite/git-integration/setup-global.sh
```

It defines the global aliases below (they work in any folder) and the variable `QS_SUITE` with
the suite folder (in `~/.bashrc` for Git Bash and, on Windows, for PowerShell and cmd too). Run it
again after moving the suite; `git actualizar-suite` runs it for you after an update.

## 2. Which command when

| I want to... | Command |
| --- | --- |
| start a new project in this folder | `git iniciar` |
| clone a project and set it up | `git clonar <url>` |
| set up a clone I already have | `git instalar` |
| add or refresh the AI agent files | `git ia` / `git ia --actualizar` |
| see this manual | `git ayuda [command]` |
| start the next version | `git np patch` (or `minor`, `major`, or `git np 6.22.7`) from `develop` |
| open a work order (OT) under a version | `git np <ot>` from `<version>/ORIGINAL` |
| start my task | `git nr <name>` from the OT's `ORIGINAL` |
| plan a whole tree at once | `git es` (stdin), `git es -n` to preview |
| give a final branch children | `git convertir-padre` |
| bring my branch up to date and push it | `git subir` |
| hand my finished branch to its parent (squash) | `git integra` |
| close an OT | `git release` inside the OT |
| try several branches together | `git testing crear <branch...>` |
| see where everything stands | `git arbol`, `git testing estado` |
| delete archived branches already in develop | `git limpiar-unmerged -n`, then without `-n` |
| check / repair the encoding of my changes | `git encoding` / `git encoding --fix` |
| a test copy of a version (SNAPSHOT, rc) | `git nv <version> --from <branch>` |
| see what a release will contain | `git changelog` |
| close a version (prepare the release for review) | `git release` on `<version>/ORIGINAL` |
| publish the reviewed release into `develop` | `git publicar` |
| join several prepared releases into one | `git combinar` |
| create the missing standard files (README...) | `git repo-files` |
| update the suite on this machine | `git actualizar-suite` |

## 3. Branch model in one minute

```text
develop
└─ 6.22.6/ORIGINAL                   version (Semantic Versioning), always a parent
   └─ 6.22.6/188858/ORIGINAL         work order (OT: letters and digits, e.g. 188858 or ABC123)
      ├─ 6.22.6/188858/login         final branch: one task
      └─ 6.22.6/188858/bank/ORIGINAL a branch with children
         └─ 6.22.6/188858/bank/bugfix
```

- A branch with children ends in `ORIGINAL`; every other branch is final. `ORIGINAL` and `RELEASE`
  (and `TESTING`, under the squash flow) are reserved leaves, refused in any case (`original`).
- Final branches **rebase** onto their `ORIGINAL`; `ORIGINAL` branches **merge** their parent and
  are never rebased or force-pushed (others build on them). The one exception: `git integra`
  rebases a `<F>/ORIGINAL` onto its parent just before squashing it up.
- Commit messages: Conventional Commits, ASCII only, subject up to 50 characters:
  `feat(login): add certificate login`. Every commit lists the files it changes (`Files:`).

## 4. Global commands (any folder)

### git iniciar

- **Syntax:** `git iniciar [folder] [--sin-ia] [--remoto <url>]`
- **Does:** `git init` with `develop` (if the folder is not a repository yet), the quality hooks
  and repository aliases, the base image, the standard repository files (README, CHANGELOG,
  VERSION...), the AI agent files (`git ia`) and the `.gitignore` block; `--remoto` adds `origin`.
  It does not commit: it prints the next steps. A new rules file gets `branches.flow = squash`.
- **Use it when:** you start a project from an empty (or not yet versioned) folder.
- **Who:** human.

```bash
mkdir pokemon_test && cd pokemon_test
git iniciar
git add -A && git commit -m "chore: initial project skeleton"
```

### git clonar

- **Syntax:** `git clonar <url> [folder]`
- **Does:** clone + everything `git instalar` does.
- **Use it when:** you start working on an existing remote project.
- **Who:** human.

### git instalar

- **Syntax:** `git instalar [repo]`
- **Does:** in a clone you already have: hooks, aliases, `.gitattributes` block, the tools of the
  languages already in it (asks once for versions it cannot detect), the missing standard files,
  and the one-time migration of an existing `.quality-rules.json` (see [UPDATING.md](UPDATING.md)).
  Idempotent.
- **Use it when:** a clone without the hooks, or after `git actualizar-suite` reported a
  repository it could not re-point.
- **Who:** human.

### git ia

- **Syntax:** `git ia [--actualizar]`
- **Does:** adds the AI agent files: `AGENTS.md` (+ `CLAUDE.md`, `GEMINI.md`), skills in
  `.agents/skills` (copied to `.claude/skills`), Claude Code and OpenCode subagents, the hook that
  runs the gate after every agent edit, `knowledge/`. Writes the `.gitignore` block that keeps all
  of them **out of the repository** (also `.quality-rules.json`), and takes out of the index any
  of them already committed (they stay on disk; then commit). Existing files are kept;
  `--actualizar` rewrites the suite's own files (skills, subagents, settings, this manual) and
  never `AGENTS.md`, `CLAUDE.md`, `opencode.json`, `knowledge/` or `dev_documents/`. It also adds
  the four `dev_documents/` templates (Requirements, Functional_Design, Technical_Design, Tests)
  when missing; filled documents are never overwritten, not even by `--actualizar`.
- **Use it when:** after `git iniciar`/`git clonar` on a machine with agents, after a suite
  update (`git actualizar-suite` runs `--actualizar` itself), or when agent files were committed.
- **Who:** human.

### git ayuda

- **Syntax:** `git ayuda [command]`
- **Does:** prints this manual, or the section of one command (`git ayuda limpiar-unmerged`).
- **Who:** anyone.

### git actualizar-suite

- **Syntax:** `git actualizar-suite [--status | --langs "java python" | --lazy | --yes]`
- **Does:** after unzipping a new suite version: removes every suite image, builds the new base,
  re-points every repository (hooks, aliases, AI files), runs the machine setup again, and applies
  the rules-file migration to each registered repository. The first commit in each repository
  reinstalls its tools. `--status` only reports.
- **Who:** human.

## 5. Branches

### git np

- **Syntax:** `git np <name> [--from <branch>]` (long: `git nueva-padre`)
- **Does:** a new **parent** branch. From `develop`: `<version>/ORIGINAL`, where `<version>` is a
  semver version or `patch` / `minor` / `major` (the next one after the highest tag, version tree
  or `VERSION`), with a first commit `chore(version): <version>` that writes `VERSION`, the
  `pom.xml` files and `package.json`. From `<F>/ORIGINAL`: `<F>/<name>/ORIGINAL` (an OT is ASCII
  letters and digits: `git np 188858` or `git np ABC123`). Reserved names are refused in any case:
  `ORIGINAL`, `RELEASE`, `TESTING`. Checks the new branch out.
- **Use it when:** starting a version (from `develop`), an OT, or a group of tasks that will have
  several final branches.
- **Who:** lead (a version: human).

```bash
git checkout develop && git np patch      # 6.22.7/ORIGINAL
git np 188858                             # 6.22.7/188858/ORIGINAL
```

### git nr

- **Syntax:** `git nr <name> [--from <ORIGINAL>]` (long: `git nueva-final`)
- **Does:** a new **final** branch `<F>/<name>` from the current `ORIGINAL` (or `--from`).
- **Use it when:** starting one task. In an agent worktree (the `ORIGINAL` is checked out
  elsewhere) always pass `--from`.
- **Who:** anyone.

```bash
git nr login --from 6.22.7/188858/ORIGINAL
```

### git convertir-padre

- **Syntax:** `git convertir-padre [--yes]`
- **Does:** the current final branch `<F>/<x>` becomes `<F>/<x>/ORIGINAL` (on origin too: delete
  and push, after confirmation).
- **Use it when:** a task turns out to need sub-tasks.
- **Who:** human (it renames a shared branch).

### git estructura / git es

- **Syntax:** `git es [file] [-n] [--push] [--convertir]` (tree on stdin)
- **Does:** creates every missing branch of a tree, each from its parent's tip; existing branches
  are only checked (`=`, with `N behind` when they need `git subir`); a new version gets its
  version commit. Validates everything before creating anything. `-n` shows the plan only.
- **Use it when:** planning an OT with several tasks at once, or copying a structure.
- **Who:** `-n` anyone; creating: lead.

```bash
printf '6.22.7\n  188858\n    login\n    bank/\n      bugfix\n' | git es -n
```

### git nueva-version / git nv

- **Syntax:** `git nv <version> [--from <branch>] [--arbol-completo] [-n]`
- **Does:** a new version tree next to the others, starting at any branch, with its version
  commit; the branches below that branch are copied under the new version (same path below the
  version, their work kept, merged with their new parent). `--arbol-completo` copies the whole
  source tree.
- **Use it when:** a test or pre-release copy (`6.22.7-SNAPSHOT`, `6.22.7-rc.1`) that must live
  apart from the main tree.
- **Who:** human.

### git arbol

- **Syntax:** `git arbol [prefix]`
- **Does:** the tree with parents (`+`), finals (`-`), commits pending to integrate, branches
  behind their parent, branches set aside (`~ unmerged/...`), and where you are.
- **Use it when:** before integrating or releasing; whenever you are lost.
- **Who:** anyone.

## 6. Sync and integrate

### git subir

- **Syntax:** `git subir`
- **Does:** final branch: rebase onto its `ORIGINAL` and push `--force-with-lease`. `ORIGINAL`:
  merge its remote and its parent when behind, push. Never rebases a shared branch. On a
  `<v>/RELEASE`: rebase onto `develop` and push `--force-with-lease`. Refused on a TESTING branch.
- **Use it when:** before integrating, after someone else integrated into your parent, or when a
  push says `behind its parent`. Use it instead of `git pull` after a rebase.
- **Who:** anyone (on their own branch).

### git integra

- **Syntax:** `git integra [-m "<subject>" [-m "<body>"]] [--force] [--yes]`
- **Does:** (flow squash) final branch -> its `ORIGINAL`: rebased onto it, then **one squash
  commit**; the branch is then deleted locally and on origin (confirmation, `--yes` skips it).
  `<F>/ORIGINAL` -> its parent `ORIGINAL` once all its children are in (`--force` skips that
  check): rebased onto the parent, then squashed into it. Refused for an OT `ORIGINAL` and a
  `<v>/ORIGINAL`: use `git release`. Refused for a `<F>/ORIGINAL` checked out in another worktree.
  The message is generated (subject, body, `Commits:`, `Files:`, `Norms:`, `Refs:`, `Squashed:`);
  the subject becomes a line of `CHANGELOG.md`, so write it for the reader. Agents pass `-m`.
  (flow merge: the 4.x behaviour, `--no-ff` merge.)
- **Use it when:** a task (or a whole OT) is finished, reviewed and passes the gate.
- **Who:** lead (into an `ORIGINAL`).

```bash
git checkout 6.22.7/188858/login && git integra -m "feat(login): add certificate login"
```

### git amend

- **Syntax:** `git amend [--no-edit] [-m "<subject>"]`
- **Does:** `git commit --amend` with `QS_AMEND=1`, so the hooks know it is an amend. The `Files:`
  block of the amended commit is recomputed against `HEAD^`. After it, the `post-commit` hook
  warns if the block does not match the files of the commit; it never rewrites anything.
- **Use it when:** you change the last commit. Fix a warning with `git amend --no-edit`.
- **Who:** anyone.

### git testing

- **Syntax:**
  - `git testing crear <branch...> [--nivel <F>] [--recrear [--force]]`
  - `git testing estado [<F>]`
  - `git testing repartir [<F>] [--map <commit>=<branch>]... [--on-applied skip|apply]`
- **Does:** TESTING is a throw-away branch `<F>/TESTING`, one per level, that tries several
  branches together. `crear` starts it at `<F>/ORIGINAL` and merges each source (any branch, in the
  given order), then makes the marker commit `chore(testing): create` with `Sources:` and
  `Testing-Create:`. The level is the one of the current branch unless `--nivel`. A conflict
  aborts and changes nothing. `--recrear` re-creates it from the current sources; it is refused
  while commits are not yet distributed, unless `--force`. `estado` lists the sources (and how
  many new commits each has since the creation) and the commits made on TESTING, each marked
  `applied in <branch>` when its change is already in a source. `repartir` moves each TESTING
  commit, oldest first, to a branch you pick from a numbered menu (the sources first; `o` another
  existing branch; `s` skip; `q` quit), by `cherry-pick -x` in a temporary worktree. Before
  applying it checks whether the change is already in the target (skipped by default). With
  `--map` there are no questions: unmapped commits are skipped. Nothing is pushed.
- **Guards.** TESTING is never merged, rebased or integrated: `git merge` into or from it,
  `git rebase` of it or onto it, `git integra` and `git subir` on it, and pushes of its commits to
  an `ORIGINAL` or `RELEASE` ref are refused with "TESTING is a sandbox: it cannot be merged,
  rebased or integrated. Move its new commits to their source branches with `git testing
  repartir`." Pushing it to its own name is allowed. The reserved leaf is `TESTING` under the
  squash flow only; under `flow = merge` the command refuses to run.
- **Use it when:** you want to build or test several branches together without merging them.
- **Who:** anyone (the lead for shared levels).

## 7. Releases

### git changelog

- **Syntax:** `git changelog [tag] [--version <v>] [-o <file>]`
- **Does:** preview, changes nothing. On an OT branch it previews the OT release; on a version
  branch, `develop` or with `--version`, the version release. It shows what each branch brought,
  the `CHANGELOG.md` entry (Common Changelog), semver advice (a `feat` needs MINOR, a breaking
  change MAJOR), the recursive check of the tree and the plan.
- **Use it when:** before `git release`, and any time to see how a version stands.
- **Who:** anyone.

### git release

- **Syntax:** `git release [tag] [--version <v>] [--ot <v>/<ot>] [--yes] [--no-push]`
  and `git release --reset --version <v> [--yes]`
- **Does:**
  - **Inside `<v>/<ot>/...` (or `--ot`): the OT release.** Checks that every branch of the OT is
    integrated (others are set aside as `unmerged/<name>`). Creates `<v>/<ot>/RELEASE` at the OT
    ORIGINAL tip with one `docs(changelog)` commit (one line per change, `(<hash>; <ot>)`), tags the
    OT ORIGINAL tip `ot/<v>/<ot>`, pushes RELEASE and the tag, deletes the OT subtree. Resumable.
  - **On `<v>/ORIGINAL`, on `develop`, or with `--version <v>`: the version release.** Refused,
    listing them, while an OT has no RELEASE or still has other branches. Otherwise `<v>/RELEASE` =
    `<v>/ORIGINAL` + every OT RELEASE rebased in, oldest first (their `docs(changelog)` commits
    dropped), then the version, `CHANGELOG.md` (the union of the OT sections) and README badge
    commits. An annotated tag is made locally. One push; the OT RELEASEs and `<v>/ORIGINAL` are
    deleted. A conflict stops with the steps: `git rebase --continue`, then `git release` resumes
    with the next OT.
  - `--reset --version <v>`: forgets the resume state of a version release that was given up.
    Refused while `<v>/RELEASE` exists.
- **Use it when:** the OT's branches are all integrated (OT release), or the OT RELEASEs are all
  done (version release).
- **Who:** human. Review `CHANGELOG.md` on `<v>/RELEASE` before `git publicar` (edit and commit
  there).

### git publicar

- **Syntax:** `git publicar [tag] [--version <v>] [--yes] [--no-push]`
  and `git publicar --reset --version <v> [--yes]`
- **Does:** `<version>/RELEASE` is rebased onto `develop` (if `develop` moved) and lands on it as
  **one commit** `chore(release): <tag>`, with `Commits:`, `Files:`, `Refs:` and `Squashed:` (and
  `Squashes:` for a combined version). The tag is annotated with its `CHANGELOG.md` entry and moved
  onto the new commit when needed. One atomic push of `develop` and the tag; RELEASE is deleted.
  With two or more `RELEASE` branches `--version` is required: one release at a time. Conflicts on
  release-owned lines (version, README badge, CHANGELOG entries) are solved; any other conflict
  stops with the steps, and running it again after `git rebase --continue` resumes.
  `--reset --version <v>` forgets the publish state kept during the rebase; refused while a rebase
  is stopped.
- **Use it when:** the release was reviewed.
- **Who:** human.

### git combinar

- **Syntax:** `git combinar [--incluir <v1,v2...>] [--version <v>] [--yes]`
- **Does:** asks yes/no for each `<v>/RELEASE` and the version of the result. A `RELEASE` without
  `develop` gets a temporary merge of `develop` (no branch moves; release-file conflicts are solved
  for `develop`, any other conflict stops with "nothing was changed"). The result starts at
  `develop` and gets one `chore(combine): <v> changes` squash per RELEASE with only its own
  changes, then the version, `CHANGELOG.md` (the **union** of the combined sections) and README
  badge commits. The joined branches are kept as `unmerged/<v>/RELEASE` (local and origin). The plan
  lists every rename before the confirmation (`--yes` answers it). All or nothing: commits are made
  in a temporary worktree, the local branches move in one transaction, then one `git push
  --atomic` to origin. Then `git publicar --version <v>` lands the result as one commit.
- **Use it when:** several prepared versions must reach `develop` as one.
- **Who:** human.

## 8. Archived branches, quality and repository files

### git limpiar-unmerged

- **Syntax:** `git limpiar-unmerged [-n] [--yes]`
- **Does:** lists every branch under `unmerged/` and `unmerged-<date>/` (local, and on origin after
  `git fetch --prune`) as **integrated** (its changes are in `develop`: a simulated merge differs
  only in release files), **superseded by <ref>** (an ancestor of, or the same content as, an
  integrated archived branch or release tag), or **pending** (anything else). Deletes the integrated
  and superseded ones only: local with `git branch -D`, origin in one atomic push with leases. Each
  deletion prints `deleted <branch> (was <sha>)`, so `git branch <branch> <sha>` restores it.
  `-n` shows the states and the plan and changes nothing. A branch checked out in a worktree keeps
  its local copy (with a note).
- **Use it when:** after the releases, to tidy the archive. Run `-n` first; the local deletion is
  the lead's call, the deletion on origin the human's.
- **Who:** lead (local); human (origin).

### git encoding

- **Syntax:** `git encoding [--fix] [file...]`
- **Does:** checks that the changed files (staged, modified, new) are UTF-8 and free of text
  damaged by a wrong-encoding save; `--fix` repairs them (Windows-1252 bytes, double-encoded
  accents, accents turned into `?` or `�` taken back from the previous version). <!-- qs-allow-mojibake -->
- **Use it when:** a commit stops with `ENCODING`, or after editing with a tool you do not trust.
- **Who:** anyone. Check `git diff` after `--fix`.

### git repo-files

- **Syntax:** `git repo-files [-n] [--force NAME...]`
- **Does:** creates the missing standard files (README, CHANGELOG, VERSION, CONTRIBUTING ...
  DEVELOPMENT) from the git history and `pom.xml`; never overwrites; `--force NAME` regenerates one.
- **Use it when:** a repository without them; to refresh `CONTRIBUTORS.md` or `API.md`.
- **Who:** `-n` anyone; writing: lead.

## 9. Plain git that is fine, and what never to do

- Fine: `git status`, `git diff`, `git log`, `git add`, `git commit`, `git switch`,
  `git stash`, `git push` of your own branch.
- Never: `git push --force` on an `ORIGINAL`, `develop` or `main` (`git subir` uses
  `--force-with-lease` on final branches and on `<v>/RELEASE` only); `git merge` into a final
  branch; `git rebase` of an `ORIGINAL` by hand (`git integra` does it, squash flow only); a branch
  named only `<version>`; a branch whose segment is `original` or `release` in any case, or `testing` under the squash flow;
  merging a TESTING branch; editing `VERSION`, the `pom.xml` version or the README badge by hand
  (the commands write them); `--no-verify` to get around the gate.

Details: [GIT-WORKFLOW.md](GIT-WORKFLOW.md) (model, versions, releases),
[QUALITY-RULES.md](QUALITY-RULES.md) (rules, encoding), [REPO-FILES.md](REPO-FILES.md).
