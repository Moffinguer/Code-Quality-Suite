# Troubleshooting (real cases solved)

Problems found while setting the project up, and their fixes, so it deploys and
runs without surprises.

## Install / Windows

- **`execvpe(/bin/bash) failed` when launching `bootstrap.bat`** - the PATH has the
  WSL stub (`System32\bash.exe`) with no distro. The launchers now prefer Git Bash
  and ignore that stub. Alternative: open Git Bash and run `./bootstrap.sh`.
- **`svc: not found` or "needs a program to open it"** - on Windows run with
  `bash svc ...` (not `./svc`).
- **`Python was not found` / `python3` missing** - on Windows the binary is
  `python`, not `python3`. `svc` detects whichever exists. If a Microsoft Store
  alias interferes, disable it in Settings -> Apps -> App execution aliases.
- **Aider fails to install on Windows/Python 3.13** (pulls `aider-chat 0.16` and
  fails building `libcst`/Rust) - use the isolated installer:
  `pip install aider-install` then `aider-install`; or
  `uv tool install --python 3.12 aider-chat`.

## Docker / build

- **First commit with a language takes minutes** - expected once: the hook adds an image
  layer with that language's tools (`qs-install`). Later commits reuse it. Pre-install with
  `QUALITY_LANGS="java python" ./install.sh` or `./bootstrap.sh <repo>`.
- **`tool 'X' not installed; skipped`** - the install of that tool failed (see the build
  output: `[qs-install] ERROR X: …`, e.g. a release asset renamed upstream or no build for
  your CPU architecture). The language still gets the built-in checks. Fix the entry in
  `registry/src/`, run `python3 tools/gen.py`, then `QS_REBUILD=1 scripts/build-image.sh`.
- **`skipped: needs dependencies or network that are not available offline`** - project-wide
  analysers (Clippy, golangci-lint, tsc, PHPStan, dart analyze, cue vet) cannot resolve
  dependencies inside the offline container. Run them in the heavy stage/CI with the build.
- **Too many image layers** - after `QS_MAX_LAYERS` (default 40) incremental installs the
  image is rebuilt from the base in a single layer automatically.
- **Suite upgraded** - run `git actualizar-suite` (clean: removes the stopped containers and the
  images of every other version, rebuilds the base, re-points the repositories; tools come back
  on the first commit). `install.sh` also removes the older versions after it builds. Without
  either, the new `VERSION` still builds its own image and the old ones only take disk space
  (`INSTALL.md`, section 6). `QS_KEEP_OLD_IMAGES=1` or `--keep-old` turns the cleanup off.
- **`WARN: kept code-quality-suite:<v>: container <id> is running`** - a check or a manual
  `docker run` still uses that version, so the cleanup never stops it and keeps the image. Wait
  until it ends (`docker ps --filter label=org.opencontainers.image.title=code-quality-suite`)
  and run `git actualizar-suite` again.
- **`kept code-quality-suite:<tag> (not a version tag ...)`** - tags such as `wt-textot` or `dev`
  are never removed automatically; remove the one you no longer need with `docker image rm`.
- **`kept ...: used by <repo>`** - that repository still points to an older suite folder;
  `git actualizar-suite` re-points it and frees the image.
- **`the suite is not at '...' (moved or deleted)`** - the suite folder of that repository is
  gone; `git actualizar-suite` from the new folder, or `bash <suite>/install.sh <repo>`.
- **`the tools for '...' could not be added to the image`** - the image build failed (network,
  proxy, a release renamed upstream). The image keeps what it had, the built-in checks run, and
  the next commit retries; the full build log is `~/.config/code-quality-suite/install.log`.
  Single tools that fail do not discard the others: they are listed as `not installed` and
  retried with `QS_RETRY_FAILED=1 git commit ...`.
- **`Another repository is changing the image; waiting...`** - another commit is installing tools
  into the shared image; it continues by itself. A lock left by a killed commit is taken over.
- **Hooks are stubs instead of symbolic links (Windows)** - links need Developer Mode (Settings >
  System > For developers); stubs behave the same. Re-run `install.sh` after enabling it.
- **Tool downloads fail behind a proxy** - set it in Docker Desktop (Settings > Resources >
  Proxies) or `~/.docker/config.json`; `QS_BUILD_NETWORK=host` only on Linux with the proxy on localhost.
- **CRLF in shell scripts** - `.sh`/hooks saved on Windows with CRLF break inside the Linux
  container. `.gitattributes` forces LF; keep LF when editing by hand.
- **"The formatter changes overlap your unstaged edits; nothing was changed"** - you staged part
  of a file and the formatter needs to touch lines next to the unstaged part. Stage the whole
  file or `git stash --keep-index`, commit, then `git stash pop`. A copy of the unstaged edits is
  kept in `.git/quality-suite/unstaged.backup.patch` while a commit runs.
- **Hooks not running** - if `core.hooksPath` is set (Husky, corporate tooling) `install.sh`
  stops; install with `QS_FORCE_HOOKS=1` or call `.git/hooks/pre-commit` from that tool. Hooks
  that were not ours are kept as `<hook>.pre-cqs`.
- **`[ci] base 'origin/main' not found`** - the CI clone is shallow: use `fetch-depth: 0`
  (GitHub) or `GIT_DEPTH: "0"` (GitLab), or fetch the base branch first.
- **`.quality-rules.json` is invalid** - the commit is blocked with line and column; fix the
  JSON (or delete the file: it is recreated with the base rules on the next commit).
- **A formatter and a linter disagree** - report it: the no-clash harness
  (`tests/noclash/run.py`) must pass for every language; meanwhile disable the linter rule in
  the rules file.

## Encoding, commit messages, branches and releases

- **`ENCODING: N file(s) with encoding problems. Nothing was formatted or analysed.`** - the
  commit stopped before any tool ran; the lines below list each file. `git encoding --fix
  <file>` repairs Windows-1252 bytes, double-encoded accents and accents turned into `?` or
  U+FFFD (from the previous version); then `git diff` and commit again. Prevent it in VS Code:
  `"files.encoding": "utf8"`, `"files.autoGuessEncoding": false`.
- **`not valid UTF-8 at line L, column C ... saved as Windows-1252`** / **`mixed encodings`** -
  the file was saved in another charset (or partly). `git encoding --fix <file>`; if the file
  must stay legacy, declare it in `.quality-rules.json` -> `encoding.by_glob` (it is then checked
  against that charset and never rewritten by formatters).
- **`WARN encoding <file>: ... [already in HEAD]`** - old damage on a line you did not touch: the
  commit goes on; repair it when convenient (`git encoding --fix <file>`).
- **`starts with a UTF-8 BOM ... forbidden here`** - save without BOM (`encoding.bom`; PowerShell scripts allow it
  by default).
- **Commit message rejected (non-ASCII)** - accents, n-tilde, diaeresis and typographic quotes
  are rejected; the hook prints an ASCII version to copy. Change it with `commit.charset`.
- **`does not follow <version>/<ot>/.../ORIGINAL`** - create branches with `git np` / `git nr`.
  `fatal: cannot lock ref ... exists` means a branch `a/b` blocks `a/b/c` (git stores refs as
  files): that is why parents are `<folder>/ORIGINAL`; use `git convertir-padre`.
- **`'x' is behind its parent`** on push - `git subir` (rebases a final branch onto its ORIGINAL).
- **`git integra`: children not integrated yet** - integrate the listed branches first, or
  `--force` if they are abandoned (then delete them).
- **`branch '6.22.6/...' belongs to version 6.22.6 but this file says ...`** - `VERSION` must
  hold the version of its tree; `git np` writes it when the tree is created. Fix the file, or
  `printf '6.22.6\n' > VERSION`.
- **`<version>X</version> does not match VERSION`** - `mvn versions:set -DnewVersion=<VERSION>
  -DgenerateBackupPoms=false` (or `branches.pom_version: "check"` / `"off"`).
- **`the version badge says X but the last release in CHANGELOG.md is Y`** - the README badge is
  written by `git release`; edit the text between `<!-- qs:version -->` markers by hand if needed.
- **CHANGELOG.md errors (`release heading must be ...`, `group ... is not allowed`)** - the file
  follows Common Changelog ([docs/GIT-WORKFLOW.md](GIT-WORKFLOW.md)); `## [x.y.z] - YYYY-MM-DD`,
  groups Changed / Added / Removed / Fixed, no `Unreleased`.
- **`there are N RELEASE branches ...; publish one at a time`** - `git publicar --version <v>`, or
  join them first with `git combinar`.
- **`git combinar`: `... conflicts with the ones before it`** - nothing changed; merge those two by
  hand on one RELEASE branch (`git checkout a/RELEASE && git merge b/RELEASE`), or combine fewer.
- **Agent worktrees (`worktree-...` branches)** - Claude Code creates them for subagents; they are
  never pushed. Inside one, create the real branch with `git nr <name> --from <ORIGINAL>`.

## Free providers (relevant with Goose too)

- **Gemini `no longer available to new users`** - use a current flash alias from your
  `/v1beta/models`.
- **429 / rate limit** - free-tier limit (per minute or per day, per model, and for
  Gemini per project not per key). Groq caps around 12k tokens/min, which agentic
  work exceeds. No real ceiling: local Ollama, or the `ai-stack` gateway (role fallbacks and the
  FreeLLMAPI pool rotate across providers).
- **`:free` slug returns 404** (e.g. `qwen/qwen3-coder:free`) - free catalogs rotate;
  verify the id on the provider site.

## Costs

- **Am I spending money?** With free-tier keys (Groq, Gemini, OpenRouter, Cerebras)
  and DeepSeek **with no payment method**, charges are impossible: free tiers 429
  when exhausted (no charge) and DeepSeek with no balance simply stops responding.
  You only spend if you add balance/card to a paid provider and a request lands on
  its model.

## Git: re-resolving the same conflicts on every rebase

Normal git behavior: a rebase replays your commits and re-shows conflicts each time.
Fixes (both applied by this suite): `rerere` remembers a resolution and reapplies it
automatically; and after a rebase use `git subir` (force-push), never `git pull`
(which would rebase again). If a push is rejected as non-fast-forward after a rebase,
that is expected - force-push with lease via `git subir`, do not pull.

## Cross-cutting lesson (code-editing agents)

When an agent (Aider/Cline) rewrites files: always review the diff. In this project
an agent removed comments and security notes, bumped the version without asking, and
added fragile dependencies that broke the build. Ask for minimal changes ("do not
reformat or remove comments") and let the pre-push/CI `docker build` catch these
before they land.

## Git: wrong Files: block after `git commit --amend -m` (fixed in 5.0.0-RC1)

Symptom: after `git commit --amend -m "..."` the `Files:` block lists only the newly staged
files (index vs HEAD) instead of everything the amended commit changes (HEAD~1 vs index).
Happened on Windows / Git Bash; `--amend` with the editor and `--amend --no-edit` were fine.

Cause: for `--amend -m` git calls prepare-commit-msg with `message` and no sha, exactly like a
normal commit. The suite guessed the amend from `/proc/$PPID/cmdline`, which does not exist in
Git Bash (PPID is 1), so the amend went undetected.

Fix: `git amend` (alias, set by install) runs `git commit --amend` with `QS_AMEND=1`, which the
hook trusts: use `git amend -m "..."`. The new post-commit hook also compares the block with the
real files of HEAD and prints a WARNING with the fix when they differ; it never rewrites
anything and respects `commit.files` (off = silent).

Commits written before: run `git commit --amend --no-edit` (or `git amend --no-edit`) on the
last one to rebuild its block. Older commits keep the wrong block; `git rebase -r --exec
"git commit --amend --no-edit"` rewrites them only if they are unpushed.

## Format check reports a file the commit leaves alone (known limitation)

Symptom: `qs-run.sh --check` (or the pre-push check) says `not formatted (a commit formats
it)`, but a commit does not change the file.

Cause: formatters without a reliable check mode are checked by formatting a copy of the file
in a temp folder and comparing (`"check": "diff"`). A tool that finds its config, or the
project layout, by walking up from the file or from the working directory finds nothing there,
so the copy can be formatted with other settings than the real file. ruff-format had this
bug (imports of the repository's own packages sorted as third-party); since 5.0.0-RC1 it is
checked by piping the real file through stdin with its real path (`"check": {"pipe": ...}`).

Still affected, planned for a later version:

- configs found by walking up directories: `.editorconfig`, `.rubocop.yml`, `.sqlfluff`;
- ktlint, rubocop-layout, perltidy, sqlfluff-format, markdownlint-fix, html-beautify-*,
  vsg-fix and npm-groovy-lint-format;
- tools the suite runs without `--config`: fprettify, nimpretty, dockerfmt, cue-fmt and
  puppet-lint-fix.

Workaround: run the fix (`qs-run.sh <file>`, or commit) and trust its result. For a tool the
suite passes a generated config, put the setting in `.quality-rules.json`: that config is the
same in both modes.
