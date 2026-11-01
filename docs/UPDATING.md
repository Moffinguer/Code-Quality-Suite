# Shared image and updates

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

1. removes leftover suite containers (normally none: checks use `--rm`);
2. removes **every** suite image: all versions, with their tools and old layers;
3. builds the base image of this version without cache (needs network; `--lazy` leaves it to the
   first commit);
4. re-points every repository in `repos.list` and the global git setup (`git clonar`, the clone
   template, `git actualizar-suite`) to this folder.

Then the first commit in each repository installs the tools of its languages again, exactly like a
first install. To have them ready before committing: `qs-update.sh --langs "java css python c"`.

Options: `--yes` (no question), `--lazy`, `--langs "..."`, `--status` (what is installed, which
repositories point where, images of old versions still on disk).

If you only replaced the folder and committed without running the update, nothing breaks: the
new version builds its own image and installs tools on demand, and the hooks print a reminder that
images of old versions are still taking disk space.

## The same, by hand

```bash
# 1. containers and images of the suite (all versions)
docker ps -aq --filter label=org.opencontainers.image.title=code-quality-suite | xargs -r docker rm -f
docker image ls -aq --filter label=org.opencontainers.image.title=code-quality-suite | xargs -r docker image rm -f
# 2. only if the suite folder changed: re-point each repository
bash /c/dev/code-quality-suite/install.sh /path/to/repo
# 3. commit: the base image and the tools are rebuilt on demand
```

## What an update keeps

| Kept | Where |
| --- | --- |
| each repository's rules and pinned versions | `<repo>/.quality-rules.json` (new rule keys of the new version are added, yours are never overwritten) |
| answers to version questions, `QUALITY_HEAVY_CMD` | `<repo>/.git/hooks/quality-suite.env` |
| branch aliases and branches | repository config (refreshed) |
| list of repositories | `~/.config/code-quality-suite/repos.list` |

Removed: the images and the tools inside them. Nothing in the working trees changes.

## New skill in 4.0.0

The `dev-documents` skill (format and IDs of the `dev_documents/` files) reaches a repository with
`git ia --actualizar` (it adds the new skill folder), then `bash <suite>/scripts/ai-sync.sh`
(copies it into `.claude/skills/` for Claude Code).

## Behind a proxy

Tool downloads happen in `docker build`. Set the proxy once in Docker Desktop (Settings >
Resources > Proxies) or in `~/.docker/config.json` (`"proxies"`), and Docker passes it to the
builds. Checks never use the network.

## Troubleshooting

| Message | Fix |
| --- | --- |
| `the suite is not at '...' (moved or deleted)` | `git actualizar-suite` from the new folder, or `bash <suite>/install.sh <repo>` |
| `Another repository is changing the image; waiting...` | another commit is installing tools; it continues by itself |
| `Images of other suite versions are still on disk` | `git actualizar-suite` frees them |
| a tool failed to install | `QS_RETRY_FAILED=1 git commit ...` (built-in checks run meanwhile; the other tools of the batch are kept) |
| `could not be added to the image` | the whole build failed (network, proxy); log in `~/.config/code-quality-suite/install.log`; the next commit retries |
