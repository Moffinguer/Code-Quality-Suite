# User manual

This manual shows how to install the code-quality-suite and how to work with its git branch
model day to day. It is the guide: each step says what to run and who runs it. The details
live in the references:

- [GIT-COMMANDS.md](GIT-COMMANDS.md): every command, its syntax and who runs it (`git ayuda <command>`
  prints one of them in the terminal);
- [GIT-WORKFLOW.md](GIT-WORKFLOW.md): the branch model, versions, releases and the hooks;
- [QUALITY-RULES.md](QUALITY-RULES.md): the rules file `.quality-rules.json`;
- [../API.md](../API.md): the interfaces (engine commands, environment variables, aliases);
- [../INSTALL.md](../INSTALL.md): installation details, proxies and removal.

## Conventions

- `<version>` is a Semantic Versioning version without the `v` (`7.1.1`). `<ot>` is a work order
  (letters and digits, `188858`). `<F>` is any final branch. `<name>` is the name you choose.
- Branch names are `<version>/<ot>/<task>`; a branch with children ends in `ORIGINAL`.
- Commit messages are Conventional Commits in ASCII, with a subject of at most 50 characters:
  `feat(login): add certificate login`.
- Every commit and push goes through the quality gate. A finding blocks the commit or the push:
  fix it. Never use `--no-verify`.
- The quality gate runs inside a container image that the suite builds, so Docker must be
  running.

## 1. Clean install

Use this for a new machine (or a new project on a machine that already has the suite).

### 1.1 Machine setup, once per machine

Unzip the suite, then run its global setup from Git Bash:

```bash
bash /c/dev/code-quality-suite/git-integration/setup-global.sh
```

The script defines the global aliases (they work in any folder) and the variable `QS_SUITE`.
Run it again after moving the suite folder. Details: [GIT-COMMANDS.md section 1](GIT-COMMANDS.md#1-once-per-machine-the-only-script-you-run-by-hand).

### 1.2 Start the project

```bash
mkdir pokemon_test && cd pokemon_test
git iniciar
```

`git iniciar` runs `git init`, creates the branches `main` and `develop`, installs the quality
hooks and the repository aliases, creates the standard repository files (README, CHANGELOG,
VERSION...), adds the AI agent files (`git ia`) and writes the `.gitignore` block. Options:
`--sin-ia` skips the AI files, `--remoto <url>` adds `origin`. It does not commit.

The repository starts on `main`.

### 1.3 First commit

```bash
git add -A && git commit -m "chore: initial project skeleton"
```

The first commit completes `.quality-rules.json` with the defaults of the suite and installs the
tools of the languages it finds. If a language version cannot be detected, `git instalar` asks
once for it. The rules are described in [QUALITY-RULES.md](QUALITY-RULES.md#how-to-configure).

### 1.4 Share it (optional)

If you used `--remoto`, publish the two main branches:

```bash
git push -u origin main
git push -u origin develop
```

### 1.5 First version

Versions start from `develop`, so bring it up to `main` first (a fast-forward, because the
repository is new) and create the version tree:

```bash
git checkout develop
git merge --ff-only main
git np patch            # or: git np minor, git np major, or an explicit version such as git np 1.0.0
git arbol               # shows 1.0.0/ORIGINAL (or the version you chose) and where you are
```

The creation of a version writes its first commit `chore(version): <version>`, which sets
`VERSION` and `pom.xml` (see [GIT-WORKFLOW.md](GIT-WORKFLOW.md#the-version-version-pomxml-packagejson)).
Section 3 covers the branch flows.

## 2. Existing install (update)

Use this when the project, the clone or the suite was installed before.

### 2.1 A clone you do not have yet

```bash
git clonar <url> [folder]
```

It clones and does everything `git instalar` does (hooks, aliases, the tools of the languages
in the project, the missing standard files).

### 2.2 A clone that is already on disk

```bash
cd <repo>
git instalar
```

`git instalar` is idempotent: run it again whenever in doubt. Use it when a clone has no hooks
or no aliases, or when `git actualizar-suite` could not re-point it.

### 2.3 Update the suite on this machine

Unzip the new suite version, then:

```bash
git actualizar-suite --status     # only reports what would change
git actualizar-suite              # rebuilds the images, re-points every repository, runs the setup again
```

`git actualizar-suite` also accepts `--langs "java python"`, `--lazy` and `--yes`. The first commit
in each repository reinstalls its tools. It runs `git ia --actualizar` for you: the suite's own
files (skills, subagents, this manual) are rewritten, and your `AGENTS.md`, `CLAUDE.md`,
`knowledge/` and `dev_documents/` are never touched. Details: [GIT-COMMANDS.md section 4](GIT-COMMANDS.md#4-global-commands-any-folder).

### 2.4 After an update

```bash
git repo-files -n                 # lists the standard files that are missing (writes nothing)
git arbol                         # the branch tree and what is behind
```

A repository created before the 7.x model may still start on `master`. The suite treats `master`,
`main` and `develop` as protected names, outside the model, and does not rename anything. Keep
the name, or decide the rename with the human who owns the repository.

Branches of the old 2.0 model (`feature/<HU>.<TR>`) are off-model: see the migration section of
[GIT-WORKFLOW.md](GIT-WORKFLOW.md#migrating-from-the-20-model-featurehutr).

## 3. Branch flows

Every flow below is a sequence of git aliases. Each step names who runs it: anyone, the lead
(the main agent session or a person) or the human.

### 3.1 The tree

```text
develop
└─ 7.1.1/ORIGINAL                    version (always a parent)
   └─ 7.1.1/188858/ORIGINAL          work order (OT)
      ├─ 7.1.1/188858/login          final branch: one task
      └─ 7.1.1/188858/bank/ORIGINAL  a branch with children
         └─ 7.1.1/188858/bank/bugfix
```

A branch with children ends in `ORIGINAL`; every other branch is final. Final branches rebase
onto their `ORIGINAL`; `ORIGINAL` branches merge their parent and are never rebased, because
others build on them. The model is in [GIT-WORKFLOW.md](GIT-WORKFLOW.md#branch-model).

### 3.2 Version tree (human)

A new version is created from `develop` with its version number, or with `patch`, `minor` or
`major` (the next one after the highest tag, version tree or `VERSION`):

```bash
git checkout develop
git np 7.1.1            # 7.1.1/ORIGINAL, with the commit chore(version): 7.1.1
```

### 3.3 Work order (lead)

An OT is created from its version `ORIGINAL`. Its name is letters and digits only:

```bash
git checkout 7.1.1/ORIGINAL
git np 188858           # 7.1.1/188858/ORIGINAL
```

A requirement under an OT is one more parent level, created the same way:

```bash
git checkout 7.1.1/188858/ORIGINAL
git np RF001            # 7.1.1/188858/RF001/ORIGINAL
```

To plan a whole tree at once, describe it on stdin. Indentation means "child of the line
above". `-n` shows the plan only, and nothing is created:

```bash
printf '7.1.1\n  188858\n    login\n    bank/\n      bugfix\n' | git es -n
printf '7.1.1\n  188858\n    login\n    bank/\n      bugfix\n' | git es
```

Existing branches are only checked, never recreated. Full syntax: [GIT-COMMANDS.md section 5](GIT-COMMANDS.md#git-estructura--git-es).

### 3.4 Final branch: one task (developer)

The developer works on its own final branch, created from the `ORIGINAL` of its OT or
requirement. In an agent worktree the `ORIGINAL` is checked out elsewhere, so `--from` is needed:

```bash
git nr login --from 7.1.1/188858/RF001/ORIGINAL   # 7.1.1/188858/RF001/login
# edit, then:
git add -A && git commit -m "feat(login): add certificate login"
git subir                                         # rebase onto the ORIGINAL and push
```

`git subir` rebases a final branch onto its `ORIGINAL` and pushes it with
`--force-with-lease`. Use it instead of `git pull`, and whenever a push says the branch is
behind its parent. Commit rules: [GIT-WORKFLOW.md](GIT-WORKFLOW.md#commands-git-aliases).

### 3.5 Bugfix loop (developer)

Work continues on the same final branch until the reviewer and the gate accept it:

```bash
git arbol                        # where am I, and what is behind
git encoding --fix               # only when a commit stopped with ENCODING; then check git diff
git commit -m "fix(login): accept expired certificates"
git subir                        # after the parent moved
```

When a task turns out to need sub-tasks, the final branch becomes a parent first. Its own
commits are kept, and the sub-tasks are created under the new `ORIGINAL`:

```bash
git checkout 7.1.1/188858/RF001/bank
git convertir-padre              # 7.1.1/188858/RF001/bank/ORIGINAL
git nr bugfix                    # 7.1.1/188858/RF001/bank/bugfix
git nr payments
```

`git convertir-padre` renames a shared branch, so on origin it deletes and pushes; it asks first.
It is the human's decision: see [GIT-COMMANDS.md](GIT-COMMANDS.md#git-convertir-padre).

### 3.6 Integrate (lead)

`git integra` moves a finished branch one level up. A final branch goes into its `ORIGINAL`; an
`ORIGINAL` goes into its parent once all its children are in:

```bash
git checkout 7.1.1/188858/RF001/login
git subir
git integra -m "feat(login): add certificate login" -m "Why: certificate login for the OT."
git checkout 7.1.1/188858/RF001/ORIGINAL   # the requirement goes up when its children are in
git integra -m "feat(login): requirement RF001 login" -m "Why: all tasks of RF001 are in."
```

Before integrating, check the flow of the checkout against the target: the line `"flow"` in
`.quality-rules.json` must equal the flow of the target `ORIGINAL`. After integrating, under the
`squash` flow, the commit must have one parent and the body must show `Commits:`, `Files:` and
`Refs:`:

```bash
grep '"flow"' .quality-rules.json
git log -1 --format='%P' 7.1.1/188858/RF001/ORIGINAL     # one hash
git log -1 --format=%B 7.1.1/188858/RF001/ORIGINAL       # Commits:, Files:, Refs:
```

If a check fails, do not push: report it to the human. The subject becomes a line of
`CHANGELOG.md`, so write it for the reader. `--force` skips the children check and is for the
human only. Full rules: [GIT-COMMANDS.md section 6](GIT-COMMANDS.md#6-sync-and-integrate) and
the `branch-workflow` skill.

### 3.7 Test copy of a version (lead)

To test a copy of a version (a SNAPSHOT or a release candidate) that lives apart from the main
tree, use `git nv`. Preview first with `-n`:

```bash
git nv 7.1.1-SNAPSHOT --from 7.1.1/188858/ORIGINAL -n
git nv 7.1.1-SNAPSHOT --from 7.1.1/188858/ORIGINAL
```

The new tree keeps the branches below the chosen one, under the new version. The original tree is
not touched, and each tree is released on its own. Details: [GIT-COMMANDS.md section 5](GIT-COMMANDS.md#git-nueva-version--git-nv).
