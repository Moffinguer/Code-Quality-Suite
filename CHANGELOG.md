# Changelog

## 4.1.0 - 2026-11-02

### Changed

- Fix lint baseline (38b35cb; Fernando Mateos)
- Fix runner lint baseline (d3a0497; Fernando Mateos)

### Added

- Allow alphanumeric OT (c1ee8c0; Fernando Mateos)
- Allow alphanumeric OT in scripts (3b6f5f0, OT 100; Fernando Mateos)
- Skip style tools on generated files (1494ee0; Fernando Mateos)
- Skip size check for generated (47d76c6; Fernando Mateos)
- Document generated-file exemption (25a116f; Fernando Mateos)

### Fixed

- Restore gen.py output layout (831f838, OT 100; Fernando Mateos)
- Tighten generated-file matching (421994d, OT 100; Fernando Mateos)
- Read generated mark without git (dd50c18; Fernando Mateos)
- Keep gen.py import order (0837be7; Fernando Mateos)

## 4.0.0 - 2026-11-01

### Added

- Add dev-documents skill (58feea0; Fernando Mateos)
- Keep filled dev_documents (f9628bf; Fernando Mateos)
- Add dev_documents templates (c1b5803; Fernando Mateos)

### Fixed

- Mark requirement fields optional (f623dbf, OT 100; Fernando Mateos)
- Cover AC5-AC6 and AC9 (b8582db, OT 100; Fernando Mateos)

## 3.0.0 - 2026-11-01

### Changed

- Rename analyst subagent (458ae0f; Fernando Mateos)

### Added

- Add team-flow skill (c226eb7; Fernando Mateos)
- Add bugfix loop and gate to roles (71e2df8; Fernando Mateos)
- Define the systems-analyst role (210e73b; Fernando Mateos)
- Add requirement docs and rules (5201575, OT 100; Fernando Mateos)
- Ignore agent docs and dev_documents (ce0e9f6; Fernando Mateos)

### Fixed

- Limit convertir-padre, bugfix name (bdcfed1, OT 100; Fernando Mateos)
- Quote ignore globs, narrow disables (e221b21, OT 100; Fernando Mateos)

## 2.6.0 - 2026-10-27

### Changed

- **Breaking:** Keep the AI agent files and `.quality-rules.json` out of the repository: `git ia` writes a `.gitignore` block and takes committed ones out of the index (INSTALL.md)
- Make `setup-global.sh` the only script run by hand; everything else is a git alias (INSTALL.md)

### Added

- Add `git iniciar` to create a project in a folder: `develop`, hooks, standard files and AI files (docs/GIT-COMMANDS.md)
- Add `git instalar` to set up a clone you already have (docs/GIT-COMMANDS.md)
- Add `git ia [--actualizar]` to add or refresh the AI agent files (docs/GIT-COMMANDS.md)
- Add `git ayuda [command]` and the manual of every git command (docs/GIT-COMMANDS.md)
- Give the agents the manual as the `git-commands` skill, regenerated on every update (scripts/ai-init.sh)
- Set `QS_SUITE` to the suite folder for Git Bash and, on Windows, for PowerShell and cmd (git-integration/setup-global.sh)

## 2.5.0 - 2026-10-26

### Changed

- **Breaking:** Require a Semantic Versioning version as the root of a branch tree (`6.22.6`, `6.22.6-SNAPSHOT`); `6.22` is refused unless `branches.levels` says otherwise (docs/GIT-WORKFLOW.md)
- **Breaking:** Split `git release` into two reviewed steps: `git release` prepares `<version>/RELEASE`, `git publicar` merges it into develop, tags and deletes it (docs/GIT-WORKFLOW.md)
- Stop the commit before any tool runs when a file has an encoding problem, and list every affected file (docs/QUALITY-RULES.md)
- Group the installation, update and removal guides in INSTALL.md (INSTALL.md)

### Added

- Detect text damaged by a save in the wrong encoding: double-encoded accents, U+FFFD, accents turned into `?`, mixed UTF-8 and Windows-1252 (engine/policy.py)
- Add `git encoding [--fix]` to check and repair the encoding of the changed files (scripts/qs-run.sh)
- Commit the version to `VERSION`, every `pom.xml` and `package.json` when a version tree is created (scripts/git-rama.sh)
- Add `git np patch|minor|major` to take the next version after the highest tag, tree or `VERSION` (scripts/git-rama.sh)
- Write `CHANGELOG.md` in Common Changelog format and the README version badge at `git release` (engine/changelog.py)
- Add `git nueva-version` to create a version tree from any branch next to the others (scripts/git-rama.sh)
- Add `git combinar` to join several RELEASE branches in creation order (scripts/git-rama.sh)
- Add a merge driver that keeps the branch version in `VERSION`, `pom.xml` and `package.json` (scripts/merge-version.sh)
- Add `git repo-files` to create the missing standard repository files from the git history and `pom.xml` (engine/repofiles.py)
- Validate `VERSION`, `CHANGELOG.md`, the README badge, `CITATION.cff` and `CODEOWNERS` in the gate (engine/repofiles.py)
- Add the standard repository files of the suite itself (README.md)

### Fixed

- Read the previous version of a file from a worktree or a pushed tree through a read-only mount of the object store (scripts/qs-docker-lib.sh)

## 2.4.0 - 2026-10-22

### Added

- Add a free demo of the AI layer: `LITELLM_CONFIG=demo.yaml` puts every role on free tiers (docs/AI-DEMO.md)
- Add `scripts/ai-keys.sh` to tell which provider keys work and which model answers each role (scripts/ai-keys.sh)
- Add OpenCode support: `opencode.json` and the same subagents as Claude Code, on gateway roles (scripts/ai-sync.sh)
- Add `scripts/ai-skills.sh list|add|installed` for community skills pinned to a commit (scripts/ai-skills.sh)

## 2.3.0 - 2026-10-22

### Added

- Add `git changelog`: preview of a release with a changelog per branch and a recursive check of the tree (docs/GIT-WORKFLOW.md)
- Add `git release`: branches never integrated are set aside as `unmerged/<name>`, the version is tagged and merged (docs/GIT-WORKFLOW.md)

### Fixed

- Allow plain `git merge` again: `pre-merge-commit` runs before git writes `MERGE_HEAD` (hooks/pre-merge-commit)

## 2.2.0 - 2026-10-13

### Changed

- Share one Docker image per suite version between every repository; a machine-wide lock serialises installs (INSTALL.md)
- Install the hooks once per machine and link them from each repository (one-line stubs where links are not allowed) (INSTALL.md)

### Added

- Add `git actualizar-suite`: remove every suite image, rebuild the base and re-point every repository (scripts/qs-update.sh)
- Add `git estructura` (`git es`) to create a whole branch tree from stdin (docs/GIT-WORKFLOW.md)

### Fixed

- Keep the other tools of an install when one runtime fails to download, and report the failure with its log (install/qs-install)

## 2.1.0 - 2026-10-13

### Added

- Add the branch model as git aliases: `git np`, `git nr`, `git convertir-padre`, `git subir`, `git integra`, `git arbol` (docs/GIT-WORKFLOW.md)
- Add the encoding gate: every shared file in the configured charset, with per-language and per-glob overrides (docs/QUALITY-RULES.md)
- Reject non-ASCII commit messages with an ASCII suggestion (hooks/commit-msg)
- Add tools for 184 languages, 323 in total, all local and offline at check time; noisy ones opt-in (docs/LANGUAGES.md)
- Pin every tool and runtime, with apt from a dated Ubuntu snapshot and `tools/check-versions.py` (docs/VERSIONS.md)
- Add the AI layer: `scripts/ai-init.sh` and the LiteLLM gateway with roles, FreeLLMAPI and Ollama (docs/AI-SETUP.md)

## 2.0.0 - 2026-10-04

_First release recorded in this changelog._

### Changed

- **Breaking:** Replace the per-language settings with one editable rules file, `.quality-rules.json` (docs/QUALITY-RULES.md)
- Install the tools of a language on demand, on the first commit that contains it (Dockerfile)
- Replace black, isort, autopep8, pylint and flake8 with Ruff; vet and staticcheck with golangci-lint (docs/LANGUAGES.md)

### Added

- Add quality levels that never clash: off, syntax, format, standard, strict (docs/QUALITY-RULES.md)
- Add identifying marks: shebangs for scripts and modelines for ambiguous files (engine/runner.py)
