# Changelog

## [5.0.0-RC1] - 2026-11-21

### Added

- Squash-aware tree and cleanup ([29b0e81](https://github.com/Moffinguer/Code-Quality-Suite/commit/29b0e815abce8bf3265b166ae9a4a758c0533ad8); git)
- OT, version and mainline release ([69232d5](https://github.com/Moffinguer/Code-Quality-Suite/commit/69232d5491ec3f97d301be73a4006eac5d67a94e); git)
- TESTING sandbox per level ([7ab4d17](https://github.com/Moffinguer/Code-Quality-Suite/commit/7ab4d171080ad25f7a8fb1ff452d64d9984271c2); git)
- Merged hashes, old-format warning ([4cb7db3](https://github.com/Moffinguer/Code-Quality-Suite/commit/4cb7db352a8f67d586dbd9184b08d404ec9c303e); git)
- Hash and OT lines, no authors ([87dcf7d](https://github.com/Moffinguer/Code-Quality-Suite/commit/87dcf7d1537338b0b9beabd10121b2d8f0fd1ec4); git)
- Add limpiar-unmerged ([bee98bf](https://github.com/Moffinguer/Code-Quality-Suite/commit/bee98bf01488c76a92394d99a9e6240e5e669b62); git)
- Squash per level with files ([b2cfb8c](https://github.com/Moffinguer/Code-Quality-Suite/commit/b2cfb8cf73f7c57317f95649b09ed2be06a6a96e); git)
- Add Files block to commit messages ([d93e657](https://github.com/Moffinguer/Code-Quality-Suite/commit/d93e65752381b4cfd545d8b9413a30f109254e79); git)
- Migrate rules file to model 5 ([df5f884](https://github.com/Moffinguer/Code-Quality-Suite/commit/df5f8840900cc19d99c75375f4b05c7c1df1bdc3); git)
- Add flow, ot_tag, files, testing ([47e4a5c](https://github.com/Moffinguer/Code-Quality-Suite/commit/47e4a5ccdf995cdfde26c75ec19221b0ab4239fb); git)

### Fixed

- One squash per OT in version release ([24c80b9](https://github.com/Moffinguer/Code-Quality-Suite/commit/24c80b9434b6c95738f1208aa5d523a85c23b59a); git)
- Format check pipes real file ([11413d7](https://github.com/Moffinguer/Code-Quality-Suite/commit/11413d74e05afac84ae3a5627751cbab1070ba29); git)
- Same isort src in format check and fix ([5aef7f7](https://github.com/Moffinguer/Code-Quality-Suite/commit/5aef7f71fb0f2afdf1a854ba30d6d64cbc619fdf); git)
- Own versions, origin, hooks ([75cffba](https://github.com/Moffinguer/Code-Quality-Suite/commit/75cffba0ff2a9391cd36b33ac47bb21b08c54c59); git)
- Detect amend on Windows, check files ([2815c0a](https://github.com/Moffinguer/Code-Quality-Suite/commit/2815c0a986ba7b0f6b926f6fc24f2e6a47b51b67); git)
- No double run, safe sandbox ([7f69a67](https://github.com/Moffinguer/Code-Quality-Suite/commit/7f69a674b014402fef770f3e43c9cd55e2f47391); git)
- Set flow after the first commit ([f096534](https://github.com/Moffinguer/Code-Quality-Suite/commit/f096534a7f6b40db9ada5609c50b95e7b36014d7); git)
- Safe migration, flow merge kept ([e67c003](https://github.com/Moffinguer/Code-Quality-Suite/commit/e67c00362a932e8fb1a7e1c43d70606b08c39b9c); git)

## 4.2.1 - 2026-11-02

### Changed

- Fix lint baseline (38b35cb; Fernando Mateos)
- Fix runner lint baseline (d3a0497; Fernando Mateos)

### Added

- Clean old images on install (ff00729; Fernando Mateos)
- Add qs_clean_old_images (b90ede6; Fernando Mateos)
- One squash per version on develop (c88c0bf; Fernando Mateos)
- Allow alphanumeric OT (c1ee8c0; Fernando Mateos)
- Allow alphanumeric OT in scripts (3b6f5f0, OT 100; Fernando Mateos)
- Skip style tools on generated files (1494ee0; Fernando Mateos)
- Skip size check for generated (47d76c6; Fernando Mateos)
- Document generated-file exemption (25a116f; Fernando Mateos)

### Fixed

- Match the suite repo exactly (0f29e54, OT 100; Fernando Mateos)
- Refuse invalid OT everywhere (4fea1e5, OT 100; Fernando Mateos)
- All or nothing, atomic origin push (4acc3ea, OT 100; Fernando Mateos)
- OT from the Refs line in squashes (609533e; Fernando Mateos)
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

[5.0.0-RC1]: https://github.com/Moffinguer/Code-Quality-Suite/releases/tag/5.0.0-RC1
