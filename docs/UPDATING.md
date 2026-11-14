# Shared image and updates

## Migrating to 5.0.0: the git flow

5.0.0 changes the integration and release flow (see [GIT-WORKFLOW.md](GIT-WORKFLOW.md)). The
rules file is migrated once, by the engine, on the next run (commit, `git instalar`,
`git actualizar-suite`). Nothing else is needed to keep working.

- **Existing repositories stay on the 4.x flow.** The migration writes `branches.flow = merge`
  (the 4.x behaviour: `git integra` merges, one-level release, `git publicar` merges) and
  `branches.model = 5`. A notice is logged once: "existing rules file: `branches.flow` set to `merge`
  to keep the 4.x behaviour ...". In-flight 4.x version trees are safe.
- **Existing `levels[1]` is updated.** The OT rule `^[0-9]+$` (the 4.0.0 default) becomes
  `^[A-Za-z0-9]+$`, so text OTs work. A custom value is kept. Logged as
  `migrated branches.levels[1]: ...`. Repeating the run changes nothing.
- **New repositories start on the 5.x flow.** A rules file created by `git iniciar`, `git instalar`
  or the first commit gets `flow = squash` and `model = 5`, with no notice.
- **Old CHANGELOG lines stay.** Entries with authors or with the 4.x reference format are not
  rewritten.
- The `merge` flow is deprecated and removed in 6.0.

### How to switch a repository to the squash flow

1. Finish or publish the version trees started with 4.x: the two flows must not be mixed inside
   one tree.
2. Edit `.quality-rules.json` (git-ignored, personal) and set the key under `branches`:

   ```json
   "branches": { "flow": "squash" }
   ```

3. Run any commit or `git instalar`; check with `git arbol` and `git es -n` on a test branch.

With `flow = squash`, `git integra` squashes and then asks to delete the integrated branch (`--yes`
answers yes); `git release` and `git publicar` follow the two-release process of 5.x.

## How the pieces are shared

```text
                      ~/.config/code-quality-suite/hooks/*   (one copy per machine)
                          ^            ^            ^
       repo A .git/hooks -+   repo B --+   repo C --+          symbolic links (or one-line stubs)
                          |
                          v
          suite folder (hooks, scripts, engine)  -- VERSION 2.2.0
                          |
                          v
   docker image code-quality-suite:2.2.0   (one per suite version, shared by every repository)
     = base-2.2.0 (engine + installer) + a layer per batch of languages installed so far
                          |
                          v
   docker run --rm --network none --read-only ...   (a throw-away container per check)
```

- The image name follows the `VERSION` of the suite folder at run time; repositories do not store
  it. Updating the suite folder moves every repository to the new image.
- Labels on the image record what it has: `qs.langs` (installed languages and tools) and
  `qs.layers` (after 40 layers it is rebuilt in one).
- A machine-wide lock (`~/.config/code-quality-suite/image.lock`) serialises image changes. A
  waiting repository re-reads the labels after the wait and installs only what is still missing. A lock left by a killed process is taken over.

## Update procedure

From the new suite folder:

```bash
git actualizar-suite                 # = bash <suite>/scripts/qs-update.sh
```

It asks once, then:

1. removes the stopped suite containers (normally none: checks use `--rm`). A container that is
   still running is never stopped or removed, and the image it uses stays;
2. removes the images of **every other** suite version, with their tools and old layers (the
   current pair is removed too and rebuilt from scratch). Tags that are not versions, such as
   `code-quality-suite:wt-textot`, are kept and the output tells you the command to remove them;
3. builds the base image of this version without cache (needs network; `--lazy` leaves it to the
   first commit);
4. re-points every repository in `repos.list` and the global git setup (`git clonar`, the clone
   template, `git actualizar-suite`) to this folder;
5. applies the rules-file migration of [5.0.0](#migrating-to-500-the-git-flow) to each registered
   repository.

Then the first commit in each repository installs the tools of its languages again, exactly like a
first install. To have them ready before committing: `qs-update.sh --langs "java css python c"`.

Options: `--yes` (no question), `--lazy`, `--langs "..."`, `--keep-old` (remove no image and no
container; the current image is not rebuilt either), `--status` (what is installed, which
repositories point where, and what a cleanup would remove or keep, without removing anything).

## Old images on install

`install.sh`, `git instalar`, `git clonar` and the bootstrap scripts also clean up, after the image
of this version has built successfully (never before, so you are not left without one):

- they remove the images and stopped containers of **older** versions only. A newer version, and
  an older one that another registered repository still uses (the output names the repository),
  are kept with a note; `git actualizar-suite` removes both;
- a version whose container is running is kept with `WARN: kept ...: container <id> is running`.
  Run the cleanup again once it ends (`git actualizar-suite`);
- the hooks never clean: a commit that builds a new version lazily only prints the note about the
  other versions on disk.

To keep everything (for example suite developers who switch between branches of different
versions), set `QS_KEEP_OLD_IMAGES=1` in the environment of the command.

If you only replaced the folder and committed without running the update, nothing breaks: the
new version builds its own image and installs tools on demand, and the hooks print a reminder that
images of old versions are still taking disk space.

## The same, by hand

```bash
# 1. stopped containers and images of the suite (no -f: Docker refuses what is still in use)
docker ps -aq --filter label=org.opencontainers.image.title=code-quality-suite --filter status=exited | xargs -r docker rm
docker image ls code-quality-suite --format '{{.Repository}}:{{.Tag}}' | xargs -r docker image rm
docker image prune -f --filter label=org.opencontainers.image.title=code-quality-suite
# 2. only if the suite folder changed: re-point each repository
bash /c/dev/code-quality-suite/install.sh /path/to/repo
# 3. commit: the base image and the tools are rebuilt on demand
```

## Alphanumeric OT (4.0.1)

The default of `branches.levels[1]` (the OT, segment 2 of `<version>/<ot>/...`) changed from
`^[0-9]+$` to `^[A-Za-z0-9]+$`, so `ABC123` is an OT as well as `188858`. The suite never rewrites
an existing `.quality-rules.json` beyond the 5.0.0 migration above, and a file created before 4.0.1
stores the old value. To accept text OTs in a repository, set the second item of `branches.levels`
by hand:

```json
"branches": { "levels": ["<keep the first item, the semver regex>", "^[A-Za-z0-9]+$"] }
```

Numeric OTs keep working. `ABC1` and `abc1` are different branches (case is not checked).
`RELEASE`, `ORIGINAL` and (under the squash flow) `TESTING` cannot be used as an OT name.

## What an update keeps

| Kept | Where |
| --- | --- |
| each repository's rules and pinned versions | `<repo>/.quality-rules.json` (new rule keys of the new version are added, yours are never overwritten; 5.0.0 also migrates `branches.flow`/`model` and `levels[1]`, see above) |
| answers to version questions, `QUALITY_HEAVY_CMD` | `<repo>/.git/hooks/quality-suite.env` |
| branch aliases and branches | repository config (refreshed) |
| list of repositories | `~/.config/code-quality-suite/repos.list` |

Removed: the images of the other versions and the tools inside them, and stopped suite containers.
Kept: running containers and their image, tags that are not versions (`wt-textot`), images that
are not the suite's. Nothing in the working trees changes.

## New skill in 4.0.0

The `dev-documents` skill (format and IDs of the `dev_documents/` files) reaches a repository with
`git ia --actualizar` (it adds the new skill folder), then `bash <suite>/scripts/ai-sync.sh`
(copies it into `.claude/skills/` for Claude Code).

## Updating the AI files to 3.0.0

`git ia --actualizar` rewrites the suite's own AI files (skills, `.claude/agents/*`,
`.claude/settings.json`) and adds the new ones (the `team-flow` skill). It never deletes a file
and never rewrites `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `opencode.json` or `knowledge/`.

- **`analyst` is now `systems-analyst`.** Delete the stale copy, then regenerate the OpenCode
  agents (it removes `.opencode/agents/analyst.md`):

  ```bash
  git ia --actualizar
  rm -f .claude/agents/analyst.md
  bash <suite>/scripts/ai-sync.sh
  ```

  Replace `analyst` with `systems-analyst` in your own prompts and notes.
- **`AGENTS.md` is yours.** Update its roles table by hand: `analyst` -> `systems-analyst`, the
  main session is also the business analyst, and the flow is the `team-flow` skill (compare with
  `<suite>/ai-template/AGENTS.md`). The same for the delegation lines of `CLAUDE.md`. For 5.0.0,
  rule 5 of `AGENTS.md` gains the exception for `git integra` on a `<F>/ORIGINAL` (squash flow).

## Behind a proxy

Tool downloads happen in `docker build`. Set the proxy once in Docker Desktop (Settings >
Resources > Proxies) or in `~/.docker/config.json` (`"proxies"`), and Docker passes it to the
builds. Checks never use the network.

## Troubleshooting

| Message | Fix |
| --- | --- |
| `the suite is not at '...' (moved or deleted)` | `git actualizar-suite` from the new folder, or `bash <suite>/install.sh <repo>` |
| `Another repository is changing the image; waiting...` | another commit is installing tools; it continues by itself |
| `Images of other suite versions are still on disk` | `git actualizar-suite` frees them (or `bash <suite>/install.sh <repo>` for the older ones) |
| `WARN: kept code-quality-suite:<v>: container <id> is running` | a check is still running; run `git actualizar-suite` again when it ends |
| `kept code-quality-suite:<tag> (not a version tag ...)` | not removed on purpose; `docker image rm code-quality-suite:<tag>` if you no longer need it |
| `used by <repo>` | that repository still points to an older suite folder; `git actualizar-suite` re-points it and frees the image |
| a tool failed to install | `QS_RETRY_FAILED=1 git commit ...` (built-in checks run meanwhile; the other tools of the batch are kept) |
| `could not be added to the image` | the whole build failed (network, proxy); log in `~/.config/code-quality-suite/install.log`; the next commit retries |
| `existing rules file: branches.flow set to merge` | informational: see [Migrating to 5.0.0](#migrating-to-500-the-git-flow) |
| `TESTING is a sandbox: it cannot be merged, rebased or integrated` | move the commits with `git testing repartir`; see [GIT-WORKFLOW.md](GIT-WORKFLOW.md) |
