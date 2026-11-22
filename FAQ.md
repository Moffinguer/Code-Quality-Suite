# FAQ

<!-- Convention: informal; questions grouped by topic. -->

Fixes for error messages: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Using the gate

### What do I need on my machine?

Git and Docker. The formatters and linters live in the image; the projects need nothing.

### Why is the first commit slow?

It installs the tools of the languages in the repository into the shared image (network, a few
minutes, once per machine and language). Later commits take seconds. `git actualizar-suite
--status` shows what is installed.

### Should AGENTS.md, CLAUDE.md or `.claude/` be committed?

No. They are personal tooling with the path of the suite on your machine; `git ia` keeps them in
`.gitignore` and takes them out of the index if they were committed. Each clone that uses agents
runs `git ia` once.

### Which git commands are there?

`git ayuda` prints the manual; `git ayuda <command>` one command
([docs/GIT-COMMANDS.md](docs/GIT-COMMANDS.md)).

### Can I skip the checks once?

`git commit --no-verify` / `git push --no-verify`. CI (`scripts/ci-check.sh`) still checks.

### Where do I see what happened?

`.git/quality-suite/quality-suite.log` in the repository (one line per file and tool);
`QUALITY_LOG_LEVEL=DEBUG git commit ...` prints everything. Tool installs:
`~/.config/code-quality-suite/install.log`.

### How do I change a rule or turn a tool off?

Edit `.quality-rules.json` at the repository root; the next commit applies it and logs the change
([docs/QUALITY-RULES.md](docs/QUALITY-RULES.md)).

## Encoding

### The commit stops with `ENCODING`. What happened?

An editor saved a file in another encoding (Windows-1252 / ANSI), or opened a UTF-8 file as
Windows-1252 and saved it again (accents like `ó` turn into two strange characters). The message
lists every file with the line and the correct text. Repair and commit again:

```bash
git encoding --fix src/main/java/com/example/Login.java     # or: git encoding --fix   (every changed file)
git diff                                               # check the repair
git add -A && git commit
```

### How do I stop VS Code from doing it?

Settings (JSON): `"files.encoding": "utf8"` and `"files.autoGuessEncoding": false`. For a file
already damaged: the encoding in the status bar -> *Reopen with Encoding* -> the real one ->
*Save with Encoding* -> UTF-8.

### A file must stay ISO-8859-1. Can it?

Yes: `"encoding": {"by_glob": {"legacy/**/*.properties": "iso-8859-1"}}`. It is checked against
that charset and never rewritten by formatters.

## Commits and branches

### Why is my commit message rejected?

Conventional Commits, ASCII only, subject up to 50 characters: `fix(login): check expired
certificate`. The hook prints an ASCII version of a message with accents.

### Which version am I working on?

`cat VERSION` on any branch of a version tree. The README badge shows the last release.

### How do I start the next version?

`git checkout develop && git np patch` (or `minor`, `major`): the next semver after the highest
tag, version tree or `VERSION`.

### How do I make a test copy of a version (SNAPSHOT)?

`git nv 6.22.6-SNAPSHOT --from 6.22.6/188858/ORIGINAL`: a new tree next to the original, with
copies of the branches below the chosen one ([docs/GIT-WORKFLOW.md](docs/GIT-WORKFLOW.md)).

### How do I release?

`git changelog` (preview), `git release` (RELEASE branch with CHANGELOG.md and badge; review it),
`git publicar` (into develop). With several RELEASE branches: `git publicar --version <v>`, or
`git combinar` first.

### Why does `git subir` conflict on `VERSION` or `pom.xml`?

The `qs-version` merge driver resolves those lines (the branch keeps its version). If it is
missing, run `git instalar` again in the repository.

## AI agents

### Can AI agents work on regulated code?

Only through local models (`role-local`, Ollama) or paid endpoints that do not train on prompts.
Free tiers are for public or invented code (the demo). See [SECURITY.md](SECURITY.md).

### Do I need Claude Code?

No. The gate checks any author. Claude Code (paid plans), OpenCode (any gateway role), Codex or
Gemini/Antigravity CLI can use the agent files ([docs/AI-SETUP.md](docs/AI-SETUP.md)).

## Updates

### How do I update the suite?

Replace the folder and run `git actualizar-suite` ([INSTALL.md](INSTALL.md), section 6).
