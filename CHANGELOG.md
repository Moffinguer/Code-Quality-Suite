# Changelog

Two versions were created but never released: **5.0.0** (only its release candidate
5.0.0-RC1 shipped, and 6.0.0 took it in) and **7.0.0** (postponed; 7.1.0 was published first).
Both have a tag for traceability. 5.0.0-RC1 and 6.0.0 were published together as 6.1.0.

## [7.1.1] - 2026-11-25

### Changed

- Share docker lib loader ([365b587](https://github.com/Moffinguer/Code-Quality-Suite/commit/365b587bbd40fddec78b818295611ab151c8e060); cleanup)
- Classify_unmerged ([0add54b](https://github.com/Moffinguer/Code-Quality-Suite/commit/0add54bcc7b718ec35509872dfce2673a07a660e); cleanup)
- One qs_python ([7e9a75e](https://github.com/Moffinguer/Code-Quality-Suite/commit/7e9a75ec3207dec318a96bd5d147200961b622ca); cleanup)
- Installers use qs_python ([0f359d1](https://github.com/Moffinguer/Code-Quality-Suite/commit/0f359d128e47e43bc5564b8f06db4866ecf99fa3); cleanup)
- Ai-ask and ai-keys use qs_python ([ca5256e](https://github.com/Moffinguer/Code-Quality-Suite/commit/ca5256e8d70e4fe6636b4b668751f6239a60fccd); cleanup)
- Files block via qs_files_block ([f57e410](https://github.com/Moffinguer/Code-Quality-Suite/commit/f57e41039c745326848f2e953a2bc0f2b9e5c6fa); cleanup)
- Git-rama.sh split into modules ([53b2540](https://github.com/Moffinguer/Code-Quality-Suite/commit/53b25405dade95bd4b98c0af831f87ab3d0c66ba); cleanup)
- Gitio and textio modules ([16cea5b](https://github.com/Moffinguer/Code-Quality-Suite/commit/16cea5bc60a89953a224bbb4131e1aca10601e90); cleanup)
- Hooks and scripts on shared libs ([d5a0489](https://github.com/Moffinguer/Code-Quality-Suite/commit/d5a0489b709dc542f4e247289521f360826c3b5e); cleanup)
- Shared helpers in flow libs ([0e8f0e5](https://github.com/Moffinguer/Code-Quality-Suite/commit/0e8f0e53d5e59437702b1351eceb4a7e9ec3e771); cleanup)
- Shared hook case fixtures ([1611932](https://github.com/Moffinguer/Code-Quality-Suite/commit/161193274adbb98e115c02d9e267aa9988cd8be6); cleanup)
- Shared enums and defaults ([5d7a585](https://github.com/Moffinguer/Code-Quality-Suite/commit/5d7a5855612d1ff3d47bce6ea37ff67eacc1a2a8); cleanup)

### Added

- Doc gaps ratchet to zero ([523bb70](https://github.com/Moffinguer/Code-Quality-Suite/commit/523bb70b6b8a791368f81e8bb8f4ec459e4805c0); cleanup)
- Enforce code metric thresholds ([89c4e75](https://github.com/Moffinguer/Code-Quality-Suite/commit/89c4e75f0acbc54d75dd122260b6433a8080ddaf); cleanup)
- KNOWN_BUGS.md and git bug-conocido ([aa4e671](https://github.com/Moffinguer/Code-Quality-Suite/commit/aa4e67162054ae8b2226e7c989b1e4ca61948a49); cleanup)
- Commit-flow guards ([54f05f0](https://github.com/Moffinguer/Code-Quality-Suite/commit/54f05f01d4a66d4eb7b826856c0d744a7ab7fad4); cleanup)
- Shared shell and hook libraries ([a0b7ee3](https://github.com/Moffinguer/Code-Quality-Suite/commit/a0b7ee373a030d647768411c23d0e2827ce7cded); cleanup)
- Code metrics with baseline ([d8f9e57](https://github.com/Moffinguer/Code-Quality-Suite/commit/d8f9e57588be4648b18427615a6e8ff48f7d4a11); cleanup)

### Fixed

- Find python, python3 or py ([8638619](https://github.com/Moffinguer/Code-Quality-Suite/commit/8638619f02740e9d7edb108b2e2992d9c6faa21a); cleanup)
- One pass for --limpiar ([44dd9e3](https://github.com/Moffinguer/Code-Quality-Suite/commit/44dd9e3316e69e914d367ed0c533e0fe8481d7a1); cleanup)

## [7.1.0] - 2026-11-22

### Added

- Render the repository files from the git history: write the README version badge as HTML and fill `SUPPORT.md` on one line (1dfca8a)
- Choose the main branch: `git iniciar` starts new repositories on `main`, and the bootstrap warns when only `master` exists (9a908c2)

### Fixed

- Fix the license comment in `README.md` that was glued to the text, and an anchor of the user manual that did not resolve (1ceafb6)

## [7.0.0] - 2026-11-15

_Never released: created for the GitHub project and Actions work, then postponed. 7.1.0
was published first, so it can no longer ship as 7.0.0. Its work continues in 8.0.0. Tagged
for traceability._

## [6.1.0] - 2026-11-22

_Combines 5.0.0-RC1 and 6.0.0 into one release on develop and adds no change of its own: see those two sections._

## [6.0.0] - 2026-11-22

_Also carries every change of 5.0.0-RC1 (listed there). It was combined into 6.1.0 and never published alone._

### Changed

- Write a `refs/ot/<version>/<ot>` ref at the OT release instead of an OT tag, so tags are version numbers only and changelog hashes stay reachable; the key `branches.ot_tag` becomes `branches.ot_ref` (18634ea)

### Added

- Add the special branch types, with one table (`branches.special`) for their placement, order, allowed paths and level: reserved names, a lock on the version of an open MIGRATION, refusals and ordering in `git integra`, and hook checks (d0484e4, 74d10a4, fbbedb4, 6dffb63)
- Add branches for agent work: ATTEMPT (`git intentos`, `git elegir`), REVIEW (`git revision`), QUARANTINE (`git cuarentena`, `git aceptar`) and CHECKPOINT (`git checkpoint`) (05abc05)
- Add `git spike`, a SPIKE branch that never goes up; `--llevar` replays its commits on a new task branch (a15340e)
- Add `git migracion` and `git np --migracion`: a MIGRATION branch that locks its version and is squashed into ORIGINAL with its own changelog line (fe66154)
- Give each agent role a Branches section and the list of human-only commands (3d644f8)
- Give Claude Code and OpenCode allow/ask/deny rows per role; `git ia --actualizar` merges `settings.json` and keeps your rows (7ff43ea)
- Upgrade each repository's `.quality-rules.json` when the suite is updated, and clean old images (06ebcd3)
- Push every branch created by the suite's commands to origin (0f89e4b)

### Fixed

- Skip a RELEASE that a later one already holds when combining (`git combinar --contenida`), and list each commit once in the union changelog (671f71c)
- Delete SPIKE, ATTEMPT, REVIEW, QUARANTINE and CHECKPOINT leftovers at the OT release (7616a31)
- Print the restore hint of `git integra` only after it really deleted a REVIEW, QUARANTINE or CHECKPOINT branch (8039f9c)

## [5.0.0] - 2026-11-21

_Never released as a final version: its release candidate 5.0.0-RC1 is its last state (the
tag is on the same commit). 6.0.0 took it in. Tagged for traceability._

## [5.0.0-RC1] - 2026-11-21

_Release candidate. It was combined into 6.1.0 and never published alone._

### Added

- Add `git testing`, a TESTING sandbox per level that refuses merges and copies of TESTING commits (7ab4d17)
- Add the OT release, the version release and the mainline release; `git publicar` puts a version on develop as one commit (69232d5)
- Make `git arbol` understand squash integrations; `--limpiar` deletes a branch only when every copy is integrated (29b0e81)
- Make `git integra` squash per level, listing the files of the change (b2cfb8c)
- Add a Files block to every commit message, set with `commit.files` (block, warn or off) (d93e657)
- Write one changelog line per change with its hash and OT, without authors; merge hashes and warn about lines in the old 4.x format (87dcf7d, 4cb7db3)
- Add `git limpiar-unmerged` to delete archived branches that are integrated or superseded (bee98bf)
- Add the keys `flow`, `ot_tag`, `files` and `testing` to the rules file, and migrate old rules files to model 5 (47e4a5c, df5f884)

### Fixed

- Land one squash per OT in the version release instead of rebasing each OT RELEASE, which conflicted (24c80b9)
- Let the format check read the real file, and use the same isort source in check and fix (11413d7, 5aef7f7)
- Make `git limpiar-unmerged` judge only its own version and origin, and accept stamped archive branches (75cffba)
- Detect `git commit --amend` on Windows and check the Files block (2815c0a)
- Stop the test runner from running cases twice and run it in a safe sandbox (7f69a67)
- Set the flow after the first commit, and keep `flow: merge` when migrating a rules file (f096534, e67c003)

## [4.2.1] - 2026-11-02

_Combines 4.0.1, 4.0.2, 4.0.3, 4.1.0, 4.1.1 and 4.2.0 into one release on develop and adds no change of its own: see those sections. Their tags exist, but only 4.2.1 was published by `git release`._

## [4.2.0] - 2026-11-02

### Added

- Clean old suite images and containers on install, with `qs_clean_old_images` (ff00729, b90ede6)

### Fixed

- Match the suite image repository name exactly when cleaning, so images of other repositories are left alone (0f29e54)

## [4.1.1] - 2026-11-02

_Near empty: it adds no change of its own. It carries the changes of 4.0.3 (listed there) on top of 4.1.0._

## [4.1.0] - 2026-11-02

_Near empty: it adds no change of its own. It carries the changes of 4.0.2 (listed there), joined by `git combinar`._

## [4.0.3] - 2026-11-02

_Also carries every change of 4.0.2 (listed there). It was combined into 4.2.1 and never published alone._

### Added

- Make `git combinar` land one commit per version on develop (c88c0bf)

### Fixed

- Refuse an invalid OT everywhere, not only in some commands (4fea1e5)
- Make `git combinar` all or nothing, with one atomic push to origin (4acc3ea)
- Read the OT of a squash from its Refs line (609533e)

## [4.0.2] - 2026-11-01

_Also carries the changes of 4.0.1 (listed there). It was combined into 4.2.1 and never published alone._

### Added

- Allow an OT with letters as well as digits in branch names, in the engine and in the scripts (c1ee8c0, 3b6f5f0)
- Skip the style tools and the size check on generated files, and document the exemption (1494ee0, 47d76c6, 25a116f)

### Fixed

- Restore the output layout of `tools/gen.py` and keep its import order (831f838, 0837be7)
- Tighten the matching of generated files, and read the generated mark without git (421994d, dd50c18)

## [4.0.1] - 2026-11-01

_Near empty: it repeats two changes already listed under 3.0.0. It was combined into 4.2.1 and never published alone._

### Added

- Make `git ia` ignore the agent docs and `dev_documents` (ce0e9f6)

### Fixed

- Quote the ignore globs and narrow the disables (e473287)

## [4.0.0] - 2026-11-01

### Added

- Add the `dev_documents` templates `Requirements.md`, `Functional_Design.md`, `Technical_Design.md` and `Tests.md` (c1b5803)
- Add the `dev-documents` skill: the format and ID rules of those files and who writes each (58feea0)
- Keep a filled `dev_documents` folder when `git ia` updates the AI files (f9628bf)

### Fixed

- Mark the requirement fields as optional in the skill and templates (f623dbf)

## [3.0.0] - 2026-11-01

### Changed

- Rename the `analyst` subagent to `systems-analyst` (458ae0f)

### Added

- Add the `team-flow` skill, the flow the agents follow (c226eb7)
- Define the systems-analyst role: it writes the spec and the plan and proposes the branch tree (210e73b)
- Add the bugfix loop to the roles: `qa` writes findings to `bugfix.md`, and `developer` runs the gate and hooks before review (71e2df8)
- Add the requirement documents and their rules to `AGENTS.md` and the agent settings (5201575)
- Make `git ia` ignore the agent docs and `dev_documents` (ce0e9f6)

### Fixed

- Limit the `git convertir-padre` advice and the bugfix branch name in the skills (bdcfed1)
- Quote the ignore globs of `git ia` and narrow its disables (e221b21)

## [2.6.0] - 2026-10-31

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

_No tag: predates the repository history._

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

_No tag: predates the repository history._

### Added

- Add a free demo of the AI layer: `LITELLM_CONFIG=demo.yaml` puts every role on free tiers (docs/AI-DEMO.md)
- Add `scripts/ai-keys.sh` to tell which provider keys work and which model answers each role (scripts/ai-keys.sh)
- Add OpenCode support: `opencode.json` and the same subagents as Claude Code, on gateway roles (scripts/ai-sync.sh)
- Add `scripts/ai-skills.sh list|add|installed` for community skills pinned to a commit (scripts/ai-skills.sh)

## 2.3.0 - 2026-10-22

_No tag: predates the repository history._

### Added

- Add `git changelog`: preview of a release with a changelog per branch and a recursive check of the tree (docs/GIT-WORKFLOW.md)
- Add `git release`: branches never integrated are set aside as `unmerged/<name>`, the version is tagged and merged (docs/GIT-WORKFLOW.md)

### Fixed

- Allow plain `git merge` again: `pre-merge-commit` runs before git writes `MERGE_HEAD` (hooks/pre-merge-commit)

## 2.2.0 - 2026-10-13

_No tag: predates the repository history._

### Changed

- Share one Docker image per suite version between every repository; a machine-wide lock serialises installs (INSTALL.md)
- Install the hooks once per machine and link them from each repository (one-line stubs where links are not allowed) (INSTALL.md)

### Added

- Add `git actualizar-suite`: remove every suite image, rebuild the base and re-point every repository (scripts/qs-update.sh)
- Add `git estructura` (`git es`) to create a whole branch tree from stdin (docs/GIT-WORKFLOW.md)

### Fixed

- Keep the other tools of an install when one runtime fails to download, and report the failure with its log (install/qs-install)

## 2.1.0 - 2026-10-13

_No tag: predates the repository history._

### Added

- Add the branch model as git aliases: `git np`, `git nr`, `git convertir-padre`, `git subir`, `git integra`, `git arbol` (docs/GIT-WORKFLOW.md)
- Add the encoding gate: every shared file in the configured charset, with per-language and per-glob overrides (docs/QUALITY-RULES.md)
- Reject non-ASCII commit messages with an ASCII suggestion (hooks/commit-msg)
- Add tools for 184 languages, 323 in total, all local and offline at check time; noisy ones opt-in (docs/LANGUAGES.md)
- Pin every tool and runtime, with apt from a dated Ubuntu snapshot and `tools/check-versions.py` (docs/VERSIONS.md)
- Add the AI layer: `scripts/ai-init.sh` and the LiteLLM gateway with roles, FreeLLMAPI and Ollama (docs/AI-SETUP.md)

## 2.0.0 - 2026-10-04

_First release recorded in this changelog. No tag: predates the repository history._

### Changed

- **Breaking:** Replace the per-language settings with one editable rules file, `.quality-rules.json` (docs/QUALITY-RULES.md)
- Install the tools of a language on demand, on the first commit that contains it (Dockerfile)
- Replace black, isort, autopep8, pylint and flake8 with Ruff; vet and staticcheck with golangci-lint (docs/LANGUAGES.md)

### Added

- Add quality levels that never clash: off, syntax, format, standard, strict (docs/QUALITY-RULES.md)
- Add identifying marks: shebangs for scripts and modelines for ambiguous files (engine/runner.py)

[7.1.0]: https://github.com/Moffinguer/Code-Quality-Suite/releases/tag/7.1.0
[6.1.0]: https://github.com/Moffinguer/Code-Quality-Suite/releases/tag/6.1.0
[6.0.0]: https://github.com/Moffinguer/Code-Quality-Suite/releases/tag/6.0.0
[5.0.0-RC1]: https://github.com/Moffinguer/Code-Quality-Suite/releases/tag/5.0.0-RC1
[4.2.1]: https://github.com/Moffinguer/Code-Quality-Suite/releases/tag/4.2.1
[4.2.0]: https://github.com/Moffinguer/Code-Quality-Suite/releases/tag/4.2.0
[4.1.1]: https://github.com/Moffinguer/Code-Quality-Suite/releases/tag/4.1.1
[4.1.0]: https://github.com/Moffinguer/Code-Quality-Suite/releases/tag/4.1.0
[4.0.3]: https://github.com/Moffinguer/Code-Quality-Suite/releases/tag/4.0.3
[4.0.2]: https://github.com/Moffinguer/Code-Quality-Suite/releases/tag/4.0.2
[4.0.1]: https://github.com/Moffinguer/Code-Quality-Suite/releases/tag/4.0.1
[4.0.0]: https://github.com/Moffinguer/Code-Quality-Suite/releases/tag/4.0.0
[3.0.0]: https://github.com/Moffinguer/Code-Quality-Suite/releases/tag/3.0.0
[2.6.0]: https://github.com/Moffinguer/Code-Quality-Suite/releases/tag/2.6.0
[5.0.0]: https://github.com/Moffinguer/Code-Quality-Suite/releases/tag/5.0.0
[7.0.0]: https://github.com/Moffinguer/Code-Quality-Suite/releases/tag/7.0.0
[7.1.1]: https://github.com/Moffinguer/Code-Quality-Suite/releases/tag/7.1.1
