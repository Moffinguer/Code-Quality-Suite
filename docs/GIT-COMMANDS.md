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
| delete archived `unmerged/...` branches already integrated | `git limpiar-unmerged -n`, then without `-n` |
| hand my finished branch to its parent | `git integra` |
| see where everything stands | `git arbol` |
| try several branches together | `git testing crear <branch...>` |
| check / repair the encoding of my changes | `git encoding` / `git encoding --fix` |
| a test copy of a version (SNAPSHOT, rc) | `git nv <version> --from <branch>` |
| see what a release will contain | `git changelog` |
| prepare the release for review | `git release` |
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

- A branch with children ends in `ORIGINAL`; every other branch is final.
- Final branches **rebase** onto their `ORIGINAL`; `ORIGINAL` branches **merge** their parent and
  are never rebased or force-pushed (others build on them).
- Commit messages: Conventional Commits, ASCII only, subject up to 50 characters:
  `feat(login): add certificate login`.

## 4. Global commands (any folder)

### git iniciar

- **Syntax:** `git iniciar [folder] [--sin-ia] [--remoto <url>]`
- **Does:** `git init` with `develop` (if the folder is not a repository yet), the quality hooks
  and repository aliases, the base image, the standard repository files (README, CHANGELOG,
  VERSION...), the AI agent files (`git ia`) and the `.gitignore` block; `--remoto` adds `origin`.
  It does not commit: it prints the next steps.
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
  languages already in it (asks once for versions it cannot detect), the missing standard files.
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
- **Does:** prints this manual, or the section of one command (`git ayuda np`).
- **Who:** anyone.

### git actualizar-suite

- **Syntax:** `git actualizar-suite [--status | --langs "java python" | --lazy | --yes]`
- **Does:** after unzipping a new suite version: removes every suite image, builds the new base,
  re-points every repository (hooks, aliases, AI files), runs the machine setup again. The first
  commit in each repository reinstalls its tools. `--status` only reports.
- **Who:** human.

## 5. Branches

### git np

- **Syntax:** `git np <name> [--from <branch>]` (long: `git nueva-padre`)
- **Does:** a new **parent** branch. From `develop`: `<version>/ORIGINAL`, where `<version>` is a
  semver version or `patch` / `minor` / `major` (the next one after the highest tag, version tree
  or `VERSION`), with a first commit `chore(version): <version>` that writes `VERSION`, the
  `pom.xml` files and `package.json`. From `<F>/ORIGINAL`: `<F>/<name>/ORIGINAL` (an OT is ASCII
  letters and digits: `git np 188858` or `git np ABC123`; `ORIGINAL` and `RELEASE` are reserved).
  Checks the new branch out.
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
  behind their parent, branches set aside (`~ unmerged/...`), and where you are. Special
  branches carry a marker (`[docs]`, `[migration]`, `[refactor]`, `[format]`, `[tests]`,
  `[spike]`, `[attempt]`, `[review]`, `[quarantine]`, `[checkpoint]`, `[testing]`); an open
  MIGRATION is warned about (`MIGRATION open: nothing else can be created`).
- **Use it when:** before integrating or releasing; whenever you are lost.
- **Who:** anyone.

### Special branches (6.0.0)

Reserved names (case-insensitive; exact case in their own place): `DOCS` and `MIGRATION` under
the version, `REFACTOR`, `FORMAT`, `TESTS` and `SPIKE` under a node, `ATTEMPT-<n>` under a task,
`REVIEW-<task>`, `QUARANTINE-<task>` and `CHECKPOINT-<task>` next to the task. `git np`, `git nr`
and `git es` refuse them and name the command below; a type set to `false` in
`branches.special` frees its name. While a version has an open MIGRATION (local or only on
origin) nothing else can be created in it. The commands below are described when each arrives.

### git migracion

- **Syntax:** `git migracion` (stub: not available yet; creates `<version>/MIGRATION`)
- **Who:** human.

### git docs

- **Syntax:** `git docs` (stub: not available yet; creates `<version>/DOCS`)
- **Who:** human.

### git refactor

- **Syntax:** `git refactor` (stub: not available yet; creates `<node>/REFACTOR`)
- **Who:** human.

### git tests

- **Syntax:** `git tests` (stub: not available yet; creates `<node>/TESTS`)
- **Who:** human, qa, lead.

### git formatear

- **Syntax:** `git formatear [paths]` (stub: not available yet; creates `<node>/FORMAT`)
- **Who:** human.

### git spike

- **Syntax:** `git spike` (stub: not available yet; creates `<node>/SPIKE`)
- **Who:** anyone.

### git intentos / git elegir

- **Syntax:** `git intentos <task> <N>`, `git elegir <task>` (stub: not available yet)
- **Who:** lead; the human confirms.

### git revision

- **Syntax:** `git revision <task>` (stub: not available yet; creates `<node>/REVIEW-<task>`)
- **Who:** reviewer, author.

### git cuarentena / git aceptar

- **Syntax:** `git cuarentena <task>`, `git aceptar <c...> --a <branch>` (stub: not available yet)
- **Who:** external-worker; lead or human.

### git checkpoint

- **Syntax:** `git checkpoint "<msg>"` (stub: not available yet; local save points)
- **Who:** any agent.

## 6. Sync and integrate

### git subir

- **Syntax:** `git subir`
- **Does:** final branch: rebase onto its `ORIGINAL` and push `--force-with-lease`. `ORIGINAL`:
  merge its remote and its parent when behind, push. Never rebases a shared branch.
- **Use it when:** before integrating, after someone else integrated into your parent, or when a
  push says `behind its parent`. Use it instead of `git pull` after a rebase.
- **Who:** anyone (on their own branch).

### git integra

- **Syntax:** `git integra [-m "<subject>" [-m "<body>"]] [--force]`
- **Does:** final branch -> its `ORIGINAL` (rebase, then merge `--no-ff` or squash);
  `ORIGINAL` -> parent `ORIGINAL` once all its children are integrated (`--force` skips that
  check). The message is generated (`Refs`, commits, files); fill the subject: it becomes a line
  of `CHANGELOG.md`, so write it for the reader. Agents pass `-m`.
- **Use it when:** a task (or a whole OT) is finished, reviewed and passes the gate.
- **Who:** lead (into an `ORIGINAL`). A version is not integrated into `develop` with it: use
  the release commands.

```bash
git checkout 6.22.7/188858/login && git integra -m "feat(login): add certificate login"
```

### git testing

- **Syntax:** `git testing crear <branch...> [--nivel <F>] [--recrear [--force]]`,
  `git testing estado [<F>]`,
  `git testing repartir [<F>] [--map <commit>=<branch>]... [--on-applied skip|apply]`
- **Does:** `crear` builds the sandbox `<F>/TESTING` from `<F>/ORIGINAL` with the branches you
  name (any branches) merged in; a marker commit records them (`Sources:`). You commit on
  TESTING. `estado` lists the sources and the commits made on TESTING. `repartir` goes commit by
  commit (numbered menu: the sources first, `o` other branch, `s` skip, `q` quit; `--map` answers
  without questions) and `cherry-pick -x`s each one onto the branch you choose. A change already
  in the target is skipped after asking; a failed pick leaves the target untouched. Nothing is
  pushed. To pick up changes of the sources, `crear --recrear` (refused while commits are not
  distributed, unless `--force`). TESTING can never be merged, rebased or integrated, in either
  direction (`git integra`, `git subir`, `git merge`, `git rebase` and a push to an `ORIGINAL` or
  `RELEASE` are refused). At release it is deleted, or set aside as `unmerged/...` when commits
  are still undistributed.
- **Use it when:** you want to try branches together before integrating any of them.
- **Who:** anyone.

```bash
git testing crear 6.22.7/188858/login 6.22.7/188858/menu
git testing repartir --map 3f2a1c9=6.22.7/188858/login
```

## 7. Releases

### git limpiar-unmerged

- **Syntax:** `git limpiar-unmerged [-n] [--yes]`
- **Does:** lists the archived branches (`unmerged/...`, `unmerged-<stamp>/...`, local or only on
  origin) with a state. `integrated`: a simulated merge with `develop` changes nothing but
  release files (`VERSION`, `CHANGELOG.md`, `CITATION.cff`, the README badge, pom/package.json
  version lines), so squashes count. `superseded by <ref>`: proved an ancestor of, or with the
  same content as, an integrated archived branch or a release tag. `pending`: anything else
  (lists its `M <file>` changes, a conflict or no merge base); never deleted. Deletes the
  integrated and superseded ones on origin (one atomic push with leases) and locally, printing
  `deleted <branch> (was <sha>)`; `git branch <branch> <sha>` restores one. A branch checked
  out in a worktree keeps its local copy.
- **Use it when:** after `git release` / `git publicar`, to tidy the archive.
- **Who:** lead. `-n` previews without fetching or changing anything; `--yes` skips the question.

### git changelog

- **Syntax:** `git changelog [tag] [--version <v>] [-o <file>]`
- **Does:** preview, changes nothing: what each branch brought, the `CHANGELOG.md` entry (Common
  Changelog), semver advice (a `feat` needs MINOR, a breaking change MAJOR), the recursive check
  of the tree (branches never integrated) and the plan.
- **Use it when:** before `git release`, and any time to see how a version stands.
- **Who:** anyone.

### git release

- **Syntax:** `git release [tag] [--version <v>] [--yes] [--no-push]`
- **Does:** step 1: branches never integrated are set aside as `unmerged/<name>`;
  `<version>/ORIGINAL` becomes `<version>/RELEASE` with commits for the version (`VERSION`,
  `pom.xml`), the `CHANGELOG.md` entry and the README badge; it is pushed and the rest of the tree
  deleted. Resumes if interrupted.
  With `branches.flow = squash` and `--version <v>`, every OT of the version must have its
  `<v>/<ot>/RELEASE`; `<v>/RELEASE` gets each OT rebased in, oldest first.
  A release given up by deleting `<v>/RELEASE` by hand leaves no state behind: the next
  `git release` says so (`stale release state ... is cleared`) and takes every OT that exists then.
- **Use it when:** every OT of the version is integrated into `<version>/ORIGINAL`.
- **Who:** human. Then review `CHANGELOG.md` on `<version>/RELEASE` (edit and commit there).

### git release --reset

- **Syntax:** `git release --reset --version <v> [--yes]`
- **Does:** forgets the resume state of a version release given up: `qs.release.<v>.plan`,
  `.ots`, `.current` and `.tag` (git config only). Asks first; `--yes` skips the question.
  Refused, nothing changed, while `<version>/RELEASE` exists (it is the release in progress or
  prepared, and `git publicar` needs the tag name it keeps) or a rebase is stopped. The local tag
  itself is not deleted (`git tag -d <tag>` does that). Says "nothing to reset" when no state is
  left.
- **Use it when:** a cancelled release must not be resumed: delete `<version>/RELEASE` by hand
  first, then reset. Usually not needed: the next `git release` clears a stale state by itself.
- **Who:** human.

### git publicar

- **Syntax:** `git publicar [tag] [--version <v>] [--yes] [--no-push]`
- **Does:** step 2: `<version>/RELEASE` merged into `develop`, tagged (annotated with its
  `CHANGELOG.md` entry), pushed, and deleted. With two or more `RELEASE` branches `--version` is
  required: one release at a time. Resumes if the push fails.
- **Use it when:** the release was reviewed.
- **Who:** human.

### git combinar

- **Syntax:** `git combinar [--incluir <v1,v2...>] [--version <v>] [--yes]`
- **Does:** asks yes/no for each `<v>/RELEASE` and the version of the result. A `RELEASE`
  without `develop` gets a warning and a temporary merge of `develop` (no branch moves; conflicts
  in the release files are solved for `develop`, any other conflict stops with "nothing was
  changed" and the `git merge develop` steps). The result starts at `develop` and gets, oldest
  tree first, one `chore(combine): <v> changes` squash per `RELEASE` with only its own changes
  (no `develop` content, no release commits, nothing an earlier or copied-from tree brought; the
  body lists the subjects and a `Squashes: <v>/RELEASE <sha>` line), then the version,
  `CHANGELOG.md` and README badge commits of the new version. The changelog entry comes from the
  original histories, each change once. Prints per `RELEASE` the commits squashed and the
  mainline merges, release commits and already combined commits dropped. The joined branches
  are kept as `unmerged/<v>/RELEASE` (local and origin; on origin the old name is deleted). The
  plan lists every local and origin rename before the confirmation (`--yes` answers it). A
  combined `RELEASE` can be combined again. Order: author date of each tree's version commit; a
  combined `RELEASE` takes the earliest date of what it squashed. All or nothing: every commit
  is made in a temporary worktree first, then the local branches move in one transaction, then
  one `git push --atomic` to origin. On any conflict or failure nothing changes; if only the
  push fails, the local result is kept and the push to run is printed.
- **Use it when:** several prepared versions must reach `develop` as one.
- **Who:** human.

## 8. Quality and repository files

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
  `--force-with-lease` on final branches only); `git merge` into a final branch; `git rebase` of an
  `ORIGINAL`; a branch named only `<version>`; editing `VERSION`, the `pom.xml` version or the
  README badge by hand (the commands write them); `--no-verify` to get around the gate.

Details: [GIT-WORKFLOW.md](GIT-WORKFLOW.md) (model, versions, releases),
[QUALITY-RULES.md](QUALITY-RULES.md) (rules, encoding), [REPO-FILES.md](REPO-FILES.md).
