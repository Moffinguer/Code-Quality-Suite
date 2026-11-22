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
