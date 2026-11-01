# Git integration (clone-and-go)

Run once per machine:

```bash
./git-integration/setup-global.sh              # alias + first-commit self-install
./git-integration/setup-global.sh --on-clone   # ... and also offer it right after `git clone`
```

## `git clonar` (clone + bootstrap in one command)

```bash
git clonar https://github.com/owner/repo.git [dest]
```

A global git alias that runs `bootstrap.sh` with the URL: it clones (into `dest`, the
folder you are in, or `CQS_WORKSPACE` from `bootstrap.config`), adds the `.gitattributes`
block, builds the base image, installs the hooks and pre-installs the tools of the
languages already in the repository. It works from Git Bash, cmd and PowerShell (git runs
aliases with its own shell).

## First commit self-install (init.templateDir)

Every new `git clone` / `git init` gets a template hook: the first commit or push installs
the suite and then runs the real hook. Nothing to remember for new repositories.

## Right after `git clone` (`--on-clone`, optional)

Git runs a template `post-checkout` hook at the end of `git clone` (first argument = null
ref). With `--on-clone` that hook asks `Install the code-quality-suite in <repo>? [Y/n]` and
runs the bootstrap. Clones without a terminal (IDEs, CI) are skipped unless
`CQS_AUTO_BOOTSTRAP=1`. Only *your* template runs: hooks inside the cloned repository are
never copied or executed.

## Where the hooks live

One copy per machine in `~/.config/code-quality-suite/hooks/` (Windows:
`%USERPROFILE%\.config\code-quality-suite\hooks`); each repository's `.git/hooks/<name>` is a
symbolic link to it (or a one-line stub where links are not allowed), and its own settings stay in
`.git/hooks/quality-suite.env`. `core.hooksPath` is not used: it would hide the repository's own
settings and clash with tools that manage hooks that way (Husky); `install.sh` refuses to touch
hooks managed through `core.hooksPath` unless `QS_FORCE_HOOKS=1`.

## `git actualizar-suite`

After unzipping a new version of the suite: removes the stopped suite containers and the images
of every other version (running containers are never stopped and their image stays; tags that are
not versions, such as `wt-textot`, are kept with a note), builds the new base and re-points every
installed repository and this global setup. `--keep-old` removes nothing; `--status` shows what
would be removed. See `INSTALL.md` (section 6).
