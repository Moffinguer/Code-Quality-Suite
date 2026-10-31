# Quick start: the quality hooks

What you need on the machine: **Git** (Git Bash on Windows) and **Docker** running. Nothing else:
every formatter and linter lives in a Docker image. Commands are for Git Bash / any bash.

## 1. Once per machine (2 minutes)

```bash
cd /c/dev                                        # any folder; keep the suite there
unzip code-quality-suite.zip
bash code-quality-suite/git-integration/setup-global.sh
```

You get `git clonar <url>` (clone + hooks), `git actualizar-suite` (updates, section 5) and a
clone template: repositories cloned from now on install the hooks by themselves on their first
commit.

## 2. Each repository (one command)

| Situation | Command |
|---|---|
| clone a new one | `git clonar https://.../repo.git` |
| a clone you already have | `bash /c/dev/code-quality-suite/bootstrap.sh /path/to/repo` |
| hooks only, nothing pre-installed | `bash /c/dev/code-quality-suite/install.sh /path/to/repo` |

`bootstrap` also manages the `.gitattributes` block (LF line endings) and pre-installs the tools of
the languages already in the repository; `install.sh` leaves that to the first commit.

## 3. What gets installed

```
~/.config/code-quality-suite/              (Windows: %USERPROFILE%\.config\code-quality-suite)
├── hooks/        the 7 hooks, ONE copy for the whole machine
└── repos.list    repositories that use them (for updates)

<repo>/.git/hooks/pre-commit  ->  ~/.config/code-quality-suite/hooks/pre-commit   (symbolic link, x7)
<repo>/.git/hooks/quality-suite.env   this repository's settings (suite folder, versions)
<repo>/.quality-rules.json            the rules; created on the first commit, git-ignored

Docker image code-quality-suite:<version>   ONE for every repository; tools are added per language
```

The common hooks only find the suite folder and run its hooks, so the logic lives in one place.
On Windows, symbolic links need Developer Mode (Settings > System > For developers). Without it,
each repository hook is a one-line file that calls the common one: same behaviour, nothing to
maintain. `QS_HOOK_LINKS=0` forces that form (for example, repositories on a network drive).

## 4. The first commits

Each check runs in a throw-away container (`--rm`, no network, read-only) created from the shared
image. The tools live in the image, not in the container, so every repository uses the same ones
and there is nothing to clean between commits.

| When | What happens |
|---|---|
| first commit on the machine (repo A: Java + CSS) | builds the base image, adds a layer with the Java and CSS tools (network, once) |
| first commit in repo B (Python + C) | same image: adds a layer with only Python and C |
| repo A later adds a Python file | nothing to install: Python is already in the image |
| two repositories install at the same time | one waits for the other (machine-wide lock), then installs only what is still missing |

The first commit with a new language takes a few minutes; after that a commit takes seconds.
See what is installed: `git actualizar-suite --status`.

## 5. Updating the suite

1. Replace the suite folder with the new version (delete it and unzip the new one at the same
   path; a different folder also works).
2. `git actualizar-suite` (or `bash <new folder>/scripts/qs-update.sh` when the folder changed).
3. Commit as usual: the first commit in each repository reinstalls the tools of its languages,
   like a first install.

Details, and the same steps by hand with docker commands: `docs/UPDATING.md`.

## 6. Day to day

| Command | Does |
|---|---|
| `git commit` | formats and checks the staged files; blocks on errors (log: `.git/quality-suite/quality-suite.log`) |
| `git push` | the same checks in read-only mode on what you push, then the project tests |
| `git np / nr / es / subir / integra / arbol` | branch model (`docs/GIT-WORKFLOW.md`) |
| edit `.quality-rules.json` | change rules, levels, versions (`docs/QUALITY-RULES.md`) |

Bypass once (CI will still check): `git commit --no-verify`.

## Remove from a repository

Delete the 7 hooks and `quality-suite.env` from `.git/hooks/`, and the repository's line from
`~/.config/code-quality-suite/repos.list`. The image stays for the other repositories.
