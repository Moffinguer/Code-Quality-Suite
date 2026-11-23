# Roadmap

<!-- Convention: informal; GitLab direction pages (https://about.gitlab.com/direction/) as a model. -->

Last release: 6.1.0. What changed: [CHANGELOG.md](CHANGELOG.md).

Items are not promises. Built items leave this page and stay in the changelog only.

## 7.0.0

- GitHub project as code, and GitHub Actions that re-run the quality gate and the branch rules
  (the repository settings branch is already built).
- Rulesets and remote hook checks on the server side.

## 7.1.0 (not shipped yet)

- Parallel agents and prompt engineering.
- Agent development is work in progress: only Claude Code is tested. OpenCode, other models,
  the gateway and the AI-stack database are not working yet.
- AI layer ([docs/AI-SETUP.md](docs/AI-SETUP.md)): feed client notifications into the knowledge
  inbox first, then add the skills that read them.
- Install on Windows 11 following [INSTALL.md](INSTALL.md): check whether the hooks become
  symbolic links (Developer Mode) or stubs, and report what breaks.
- Try the release flow on a real Maven repository: `git np patch`, `git release`, `git publicar`,
  the `pom.xml` version and the merge driver after a second release.
- Pin the `sha256` of every download once the first real build prints them.

## 7.1.1

- General refactor of all files: remove duplication and dead code.
- Commit-flow guards: `git integra` refuses a flow mismatch or a default rules file; the
  pre-push hook refuses merge commits on an ORIGINAL branch.
- `KNOWN_BUGS.md` at the root, with the rule to cherry-pick bug fixes first.
- One agent per feature.

## 7.2.0

- Forge integration MVP, GitHub first. A provider module per forge, chosen by the repository
  host; unknown hosts stay off.
- Per OT, a project view per version. An issue per feature ORIGINAL branch. A milestone per
  version with an estimated end date.
- First, research the GitHub API limits.

## 7.2.1 and 7.2.1-RC1

- FEAT_and BUG_ branches outside the version trees (bugs start from main), gathered into a
  version on demand.
- Pilot 7.2.1-RC1: one FEAT_branch per language that rewrites the linter and formatter
  configs from common community configs; BUG_ branches for open known bugs. Maybe an RC2.
- Discuss new branch types: snapshot, beta, experimental.
- Deferred 6.0.0 work lands here too: `refactor_tests`, `format_branch`, the changelog writer
  chain (DOCS writes the changelog) and the full manual.
- Engine: `detect_language` skips files whose language is already detected (7.2.1-RC1).
- Temporary branches (fix, sync and QA branches the lead makes and integrates): `git integra`
  deletes the integrated final at once, local and origin, or offers to. Before an OT or version
  release, `git release` audits every branch of the tree: content already in the ORIGINAL
  (`Squashed:` trailer or patch-equivalent) is deleted; content missing is asked about, then
  kept or renamed `unmerged/`; a stale pre-rebase copy on origin is reconciled, not refused.

## Later (no version yet)

- Test battery wired into the hooks (`.quality-tests`): a fast set on pre-push, the full run in
  Actions and before a release.
- Micro-task orchestration: the lead plans atomic tasks (file or function, change, test) for
  cheap agents, with one integration test run per batch.
- Agent hierarchy by change risk (orchestrator, analysts, QA, developers, interns), with paid
  models only at the top levels.
- HOTFIX, REPRO and BACKPORT branches (decide the main-branch policy first).
- 6.1.1: extra Conventional Commit types.
- Baseline cleanup of the findings the gate already reports on old code.
- Other temp-copy tools in check mode.
- Image cleanup that keeps the images still in use: no leftover versions on update, and
  `rules_upgrade` runs it.
- LangGraph flywheel step 4 ([docs/KNOWLEDGE-FLYWHEEL.md](docs/KNOWLEDGE-FLYWHEEL.md)): triage,
  worker, gate, lessons learned.
- A model catalog in a database, so models can be defined, deleted and reordered without
  editing YAML.
- Server-side checks of the branch model and repository files in Azure DevOps pipelines.
- Formatters for JSP and PL/SQL when a reliable one exists.
- Overlap detector `git solape`, if it is not built yet.
- Retrospective: novelty, gaps, more quality levels, own tools and parsers.
