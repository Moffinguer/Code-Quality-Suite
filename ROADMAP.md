# Roadmap

<!-- Convention: informal; GitLab direction pages (https://about.gitlab.com/direction/) as a model. -->

Last release: 4.2.1. What changed: [CHANGELOG.md](CHANGELOG.md).

## Now

- **5.0.0-RC1**: squash flow (`branches.flow = squash`), one OT release per OT
  (`<v>/<ot>/RELEASE`, tag `ot/<v>/<ot>`), one version release (`<v>/RELEASE`) that is refused while
  an OT is open, `git publicar` as one commit on `develop`, `Files:` in every commit, the TESTING
  sandbox (`git testing`) and `git limpiar-unmerged`. See [docs/GIT-WORKFLOW.md](docs/GIT-WORKFLOW.md)
  and [docs/UPDATING.md](docs/UPDATING.md).
- Install on Windows 11 following [INSTALL.md](INSTALL.md): check whether the hooks become
  symbolic links (Developer Mode) or stubs, and report what breaks.
- Try the release flow on a real Maven repository: `git np patch`, `git release`, `git publicar`,
  the `pom.xml` version and the merge driver after a second release.
- Pin the `sha256` of every download once the first real build prints them.

## Next

- **6.0.0: special branches.** New final branches under `<v>/special` (spec in
  `docs/6.0.0/spec.md`), with auto-publish of new branches, the rules upgrade and the agent flow
  as separate parts, and the `merge` flow is removed (as [docs/UPDATING.md](docs/UPDATING.md) and
  [docs/GIT-WORKFLOW.md](docs/GIT-WORKFLOW.md) say). The final scope is defined in the approved
  6.0.0 spec.
- **6.1.0 = 5.0.0-RC1 + 6.0.0**, combined with `git combinar` and published to `develop`:
  - auto-publish of new branches;
  - the rules upgrade on suite update (`git actualizar-suite` applies the rules-file changes);
  - the branch flow in each agent's context (the `branch-workflow` and `team-flow` skills and
    `AGENTS.md`).
- **6.1.1: more Conventional Commits types** accepted by the subject check and the changelog
  groups.
- **7.0.0: GitHub project and Actions.** Repository settings and rulesets for `main`, `develop`,
  `ORIGINAL` and `RELEASE` branches; GitHub Actions that re-run the gate and the branch-model
  checks on every push. The hooks are still missing.
- **7.1.0: documentation sweep and parallel agents.** Unified root docs; parallel agents and
  prompt engineering; new repositories start on `main` instead of `master`.
- AI layer ([docs/AI-SETUP.md](docs/AI-SETUP.md)): first Junta notifications into
  `knowledge/jda/inbox/`, then the skills that read them.
- Build order step 4 of [docs/KNOWLEDGE-FLYWHEEL.md](docs/KNOWLEDGE-FLYWHEEL.md): LangGraph triage
  -> worker -> gate -> lessons learned.
- A model catalog in a database (defined, deleted and reordered without editing YAML).

## Later

- **HOTFIX, REPRO and BACKPORT branches.** They need a decision first on how `main` moves when a
  fix leaves `develop` for a live release (which branch carries it, and how it returns to
  `develop`).
- **Baseline cleanup of the pre-existing gate findings.** The first push of `main` found 328
  findings in 268 files (shfmt, markdownlint, ruff, prettier, yamlfmt, xmllint, ...), including the
  deliberately broken `tests/noclash/bad/*` fixtures. Plan: exclude the test fixtures through a
  tracked mechanism (like `qs-generated`), then format and fix the rest, logged in the quality log.
- Agent hierarchy by change risk (orchestrator, analysts, QA, developers, interns) with paid
  models only at the top levels.
- Server-side checks of the branch model and repository files in Azure DevOps pipelines.
- Formatters for JSP and PL/SQL when a reliable one exists.
