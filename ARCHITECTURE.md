# Architecture

<!-- Convention: arc42 (https://arc42.org/), shortened; C4 model (https://c4model.com/) levels in the diagrams. -->

## 1. Goals and context

A local, deterministic quality gate for every repository on a developer's machine, whoever
writes the code (a person or an AI agent), plus the workflow around it: branch model, versions,
releases, standard repository files, and an AI-agent layer that must pass the same gate.

```text
 developer / AI agent ──git commit / push──> git hooks (host) ──docker run──> engine (container)
         │                                        │                               │
         └──git aliases (np, release...)──> git-rama.sh (host) ──docker run──> engine tools
                                                  │                         (pom.xml, CHANGELOG)
 CI pipeline ──scripts/ci-check.sh──> same engine, same rules
 AI agents ──LiteLLM gateway (ai-stack)──> model providers / local Ollama
```

## 2. Constraints

| Constraint | Consequence |
| --- | --- |
| Regulated code (public-sector work): never sent to services that train on prompts | the gate runs offline; AI roles for real code use paid no-training endpoints or local models only |
| Windows 11 + Git Bash + Docker Desktop as the main platform | bash only (no jq, no GNU-only flags), host paths through `cygpath`, stubs when symbolic links are not allowed |
| No local runtimes in the projects | every tool lives in the image; the host needs git and docker |
| Reproducible | tools pinned by version, apt from a dated snapshot, base image digest lock |
| Tools offline at check time | network only during `docker build` (new language) |
| Secrets never in images or repositories | `ai-stack/.env` is local; the gate blocks private keys and known secret formats |

## 3. Building blocks

| Block | Where | Responsibility |
| --- | --- | --- |
| Hooks | `hooks/` (one copy per machine, linked per repository) | collect the files, stage/restore partial edits, call the engine, block |
| Engine | `engine/qs.py` + modules | classify files, encoding and mojibake gate, rules file, native configs, pipelines per language, repository checks, version/changelog/repo-file tools |
| Catalog | `registry/src/*.py` -> `registry.json` | languages, subtypes, tools, roles, installs, levels |
| Installer | `install/qs-install`, `scripts/ensure-langs.sh`, `scripts/build-image.sh` | add an image layer with the tools of new languages, under a machine-wide lock |
| Branch workflow | `scripts/git-rama.sh`, `git-flow-lib.sh`, `merge-version.sh` | git aliases: tree, integration, versions, release, combine; merge driver for version files |
| Repository files | `engine/repofiles.py`, `changelog.py`, `maven.py`, `semver.py` | generate and validate README, CHANGELOG, VERSION ...; versions in pom.xml |
| Machine setup | `install.sh`, `bootstrap.*`, `git-integration/`, `scripts/qs-update.sh` | install, clone, update, re-point repositories |
| AI layer | `ai-template/`, `scripts/ai-*.sh`, `ai-stack/` | agent files and skills per repository; model gateway with roles and fallbacks |

## 4. Runtime view

**Commit.** `pre-commit` lists the staged files, sets unstaged edits aside, installs missing
languages (`ensure-langs`), then `docker run --network none --read-only` the engine with the
repository at `/workspace` and the object store read-only at `/qs-git`. The engine checks the
encoding first (stops on a problem, listing the files), syncs the rules file, runs the pipelines
per language in parallel (syntax -> mark -> format -> lint -> deep) and the repository checks; the
hook re-stages the formatted files and restores the unstaged edits.

**Push.** `pre-push` checks the branch model, exports the pushed tree (`git archive`), runs the
engine in check mode against the remote base, then the project tests and the heavy command.

**Version tree.** `git np 6.22.6` creates `6.22.6/ORIGINAL` and, without a checkout, a commit
that writes the version: the files are extracted (`git archive`), edited by the engine in the
container (`version-set`), and committed with `git commit-tree`.

**Release.** `git release` analyses the tree, creates `<version>/RELEASE`, commits the version,
the CHANGELOG.md entry (from the integration merges, `release-notes`) and the README badge, pushes
it and deletes the rest of the tree. `git publicar` merges it into develop, tags and deletes it.
`git combinar` rebases several RELEASE branches in a temporary worktree.

## 5. Deployment

```text
suite folder (VERSION 2.5.0) ──> image code-quality-suite:2.5.0 = base + one layer per language batch
~/.config/code-quality-suite/hooks/*  <── symbolic links (or stubs) from every <repo>/.git/hooks/
<repo>/.git/hooks/quality-suite.env   points at the suite folder
```

One image per suite version, shared by every repository; labels `qs.langs` and `qs.layers`
record what it holds. An update removes every suite image and rebuilds the base.

## 6. Decisions

| Decision | Why |
| --- | --- |
| Docker image with tools, not host tools | the same versions for everyone; nothing to install in projects |
| One shared image per version, layers per language | install once per machine, not per repository |
| `ORIGINAL` as the parent leaf | git refs are files and folders: `a/b` and `a/b/c` cannot coexist |
| Final branches rebased, parents merged | linear work per branch; shared branches never rewritten |
| Release in two steps with a RELEASE branch | the changelog is reviewed before it reaches develop |
| Semantic Versioning for version roots | ordering, next-version and changelog checks need comparable versions |
| Version commit without checkout (`commit-tree`) | creating trees never touches the working tree |
| Merge driver for version files | every tree writes its own version in the same lines |
| Encoding gate before any tool | formatters would rewrite damaged text and hide the cause |
| Previous version from a read-only object store mount | tell new damage from old in worktrees and pushed trees too |
| Common Changelog generated from integration merges | `git integra` subjects are curated; raw `git log` is noise |
| LiteLLM gateway with roles | agents name a role; providers and fallbacks change in one file |

## 7. Risks and technical debt

- Node-based tools and some downloads are verified only in a connected environment.
- `git combinar` with trees copied from each other relies on `--rebase-merges`; conflicts stop it.
- Download checksums are pinned only where known (`sha256=` in the catalog).

## 8. Glossary

| Term | Meaning |
| --- | --- |
| OT | work order (orden de trabajo), the second level of a branch name |
| ORIGINAL | the parent branch of a folder of branches |
| RELEASE | a version tree ready to reach develop, under review |
| gate | the checks that block a commit or a push |
| role | a model alias of the gateway (`role-lead`, `role-dev`, `role-local`...) |
