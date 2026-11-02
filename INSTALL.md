# Installation

<!-- Convention: GNU Coding Standards (https://www.gnu.org/prep/standards/), install section. -->

Everything here is copy-paste for Git Bash (Windows) or any bash. The suite folder is called
`/c/dev/code-quality-suite` below; use yours.

## 1. Requirements

| Tool | Version | Check |
| --- | --- | --- |
| Git | 2.38 or newer (Git for Windows on Windows) | `git --version` |
| Docker | Docker Desktop (Windows, macOS) or Docker Engine (Linux), running | `docker info` |
| Disk | about 2 GB for the base image, plus the tools of each language | |

Optional: Developer Mode on Windows (Settings > System > For developers), so the hooks can be
symbolic links; without it each repository gets one-line stubs that work the same.

Nothing is needed in the repositories: no JDK for the linters, no Node, no Python. The network
is used only when a language is installed for the first time.

## 2. Once per machine: the only script you run by hand

```bash
mkdir -p /c/dev && cd /c/dev
unzip ~/Downloads/code-quality-suite.zip            # creates /c/dev/code-quality-suite
bash /c/dev/code-quality-suite/git-integration/setup-global.sh
```

From then on everything is a git command, in any folder:

| Alias | Does |
| --- | --- |
| `git iniciar [folder]` | a new project: `git init` (branch `develop`), hooks, standard files, AI agent files |
| `git clonar <url> [folder]` | clone a project and set it up |
| `git instalar [repo]` | set up a clone you already have |
| `git ia [--actualizar]` | AI agent files, kept out of the repository |
| `git ayuda [command]` | the manual of every git command ([docs/GIT-COMMANDS.md](docs/GIT-COMMANDS.md)) |
| `git actualizar-suite` | clean update after unzipping a new version (section 6) |

It also sets `QS_SUITE` to the suite folder (in `~/.bashrc`, and on Windows for PowerShell and
cmd too: open a new terminal), and a clone template: repositories cloned from now on install the
hooks by themselves on their first commit (`setup-global.sh --on-clone` makes a plain
`git clone` offer it right away). Run it again if you move the suite folder.

## 3. Each repository

| Situation | Command |
| --- | --- |
| a new project (empty folder) | `git iniciar` (`--sin-ia` without the AI files, `--remoto <url>` adds origin) |
| clone a new one | `git clonar https://git.example/team/app.git` |
| a clone you already have | `cd /path/to/repo && git instalar` |
| AI agent files (Claude Code, OpenCode...) | `git ia` |
| hooks only, nothing pre-installed | `bash "$QS_SUITE/install.sh" /path/to/repo` |
| Windows cmd / PowerShell | `bootstrap.bat <git-url\|path> [dest]` / `.\bootstrap.ps1 ...` |

Every one of these ends by building the image of this suite version and then removing the images
and stopped containers of **older** versions (disk space comes back; section 6 has the details).
`QS_KEEP_OLD_IMAGES=1` skips that.

`bootstrap` manages the `.gitattributes` block (LF line endings), installs the hooks and
pre-installs the tools of the languages already in the repository, asking once for versions the
project does not reveal. `install.sh` installs the hooks and leaves the tools to the first commit.
Both are idempotent: run them again at any time.

Both also create the **standard repository files that are missing** (README, CHANGELOG, VERSION,
CONTRIBUTING, ... DEVELOPMENT), filled from the git history and `pom.xml`, and never overwrite
one. Review them and commit them:

```bash
git status --short                      # the new files
git add -A && git commit -m "docs: repository files"
```

`QS_REPO_FILES=0 bash "$QS_SUITE/install.sh" <repo>` skips them; `git repo-files` creates them
later ([docs/REPO-FILES.md](docs/REPO-FILES.md)).

**AI agent files stay out of the repository.** `git ia` (run by `git iniciar`) writes a block in
`.gitignore` for `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `opencode.json`, `.agents/`, `.claude/`,
`.gemini/`, `.opencode/`, `knowledge/` and `.quality-rules.json`: they are personal tooling, and
they hold the path of the suite on your machine. If any of them was committed already, `git ia`
takes it out of the index (it stays on disk); commit that change. Each clone that uses agents runs
`git ia` once; `git actualizar-suite` refreshes them (`git ia --actualizar`).

Check it worked:

```bash
git encoding                            # "encoding OK" (or the files to fix)
git commit --allow-empty -m "chore: check the hooks"   # the hooks run; nothing to analyse
git actualizar-suite --status           # image, languages installed, repositories
```

## 4. What gets installed where

```text
~/.config/code-quality-suite/              (Windows: %USERPROFILE%\.config\code-quality-suite)
├── hooks/        the 7 hooks, ONE copy for the whole machine
├── repos.list    repositories that use them (for updates)
├── image.lock    machine-wide lock while the image changes
└── install.log   the last tools installation

<repo>/.git/hooks/pre-commit  ->  ~/.config/code-quality-suite/hooks/pre-commit   (symbolic link, x7)
<repo>/.git/hooks/quality-suite.env   this repository's settings (suite folder, versions)
<repo>/.git/info/attributes           merge driver for VERSION / pom.xml / package.json
<repo>/.git/quality-suite/            log, generated configs, policy, release notes
<repo>/.quality-rules.json            the rules; created on the first commit, git-ignored
<repo>/AGENTS.md, .claude/, .agents/  AI agent files (git ia), git-ignored

Docker image code-quality-suite:<version>   ONE for every repository; tools added per language
```

The common hooks only find the suite folder and run its hooks, so the logic lives in one place.
`QS_HOOK_LINKS=0` forces the stub form (for example, repositories on a network drive).

## 5. The first commits

Each check runs in a throw-away container (`--rm`, no network, read-only) from the shared image.

| When | What happens |
| --- | --- |
| first commit on the machine (repo A: Java + CSS) | builds the base image, adds a layer with the Java and CSS tools (network, once) |
| first commit in repo B (Python + C) | same image: adds a layer with only Python and C |
| repo A later adds a Python file | nothing to install: Python is already in the image |
| two repositories install at the same time | one waits for the other (machine-wide lock), then installs only what is still missing |

The first commit with a new language takes a few minutes; after that a commit takes seconds.

## 6. Updating the suite

```bash
rm -rf /c/dev/code-quality-suite
unzip ~/Downloads/code-quality-suite.zip -d /c/dev      # the new version, same place
git actualizar-suite                                    # = bash /c/dev/code-quality-suite/scripts/qs-update.sh
```

`git actualizar-suite` asks once, then: removes the stopped suite containers and the images of
**every other** version (with their tools), builds the new base image without cache, and
re-points every repository in `repos.list` and the global git setup to the folder. The first
commit in each repository then reinstalls the tools of its languages, like a first install.

| Option | Does |
| --- | --- |
| `--status` | what is installed, which repositories point where, what a cleanup would remove or keep |
| `--keep-old` | remove no image and no container (same as `QS_KEEP_OLD_IMAGES=1`) |
| `--langs "java css python"` | install those languages now instead of on the next commit |
| `--lazy` | do not build the base now; the first commit builds it |
| `--yes` | no question |

A different folder works too: `bash <new folder>/scripts/qs-update.sh`. If you replaced the folder
and committed without updating, nothing breaks: the new version builds its own image on demand,
and the hooks remind you that old images still take disk space.

Kept by an update: each repository's `.quality-rules.json` (new keys are added, yours are never
overwritten), `quality-suite.env`, branches and aliases (refreshed), `repos.list`. Removed: the
images of the other versions and the tools inside them. Kept: running containers (with their
image, and a warning), tags that are not versions such as `wt-textot` (the output prints the
command to remove them) and every image that is not the suite's. Nothing in the working trees
changes.

`install.sh` (also through `git instalar`, `git clonar` and the bootstrap scripts) removes the
**older** versions too, but only after the image of this version has built, and it keeps a newer
version or one that another registered repository still uses. Hooks never clean. To keep every
old image set `QS_KEEP_OLD_IMAGES=1` for the command.

The same by hand:

```bash
docker ps -aq --filter label=org.opencontainers.image.title=code-quality-suite --filter status=exited | xargs -r docker rm
docker image ls code-quality-suite --format '{{.Repository}}:{{.Tag}}' | xargs -r docker image rm
bash /c/dev/code-quality-suite/install.sh /path/to/repo     # only if the folder changed
```

## 7. Behind a proxy

Tool downloads happen in `docker build`. Set the proxy once in Docker Desktop (Settings >
Resources > Proxies) or in `~/.docker/config.json` (`"proxies"`); Docker passes it to the
builds. Checks never use the network.

## 8. Configuration

| Where | What |
| --- | --- |
| `<repo>/.quality-rules.json` | rules, levels, language versions, encoding, commit and branch policy ([docs/QUALITY-RULES.md](docs/QUALITY-RULES.md)) |
| `<repo>/.git/hooks/quality-suite.env` | `QUALITY_HEAVY_CMD="mvn -B verify"` (push), answers to version questions |
| environment | `QUALITY_LEVEL`, `QUALITY_LOG_LEVEL=DEBUG`, `QS_HOOK_LINKS=0`, `QS_REPO_FILES=0` |

## 9. Removing it

From a repository:

```bash
cd /path/to/repo
for h in pre-commit pre-push prepare-commit-msg commit-msg pre-rebase pre-merge-commit post-checkout; do rm -f .git/hooks/$h; done
rm -f .git/hooks/quality-suite.env
sed -i '/merge=qs-version/d' .git/info/attributes
sed -i "\|^$(pwd)\$|d" ~/.config/code-quality-suite/repos.list
```

From the machine (after every repository): remove the images (section 6, by hand),
`~/.config/code-quality-suite/` and the suite folder, the `QS_SUITE` line of `~/.bashrc`, and the
global aliases:

```bash
for a in clonar iniciar instalar ia ayuda actualizar-suite; do git config --global --unset alias.$a; done
```

## 10. Problems

| Message | Fix |
| --- | --- |
| `the suite is not at '...' (moved or deleted)` | `git actualizar-suite` from the new folder, or `bash <suite>/install.sh <repo>` |
| `Another repository is changing the image; waiting...` | another commit is installing tools; it continues by itself |
| `Images of other suite versions are still on disk` | `git actualizar-suite` frees them (or `bash <suite>/install.sh <repo>` for the older ones) |
| `WARN: kept code-quality-suite:<v>: container <id> is running` | a check is still running; run `git actualizar-suite` again when it ends |
| a tool failed to install | `QS_RETRY_FAILED=1 git commit ...` (built-in checks run meanwhile) |
| `could not be added to the image` | the build failed (network, proxy): `~/.config/code-quality-suite/install.log`; the next commit retries |
| `ENCODING: ... file(s) with encoding problems` | `git encoding --fix <file>`, then commit again ([FAQ.md](FAQ.md)) |

More: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).
