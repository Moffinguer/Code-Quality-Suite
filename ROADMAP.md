# Roadmap

<!-- Convention: informal; GitLab direction pages (https://about.gitlab.com/direction/) as a model. -->

Last release: 2.6.0. What changed: [CHANGELOG.md](CHANGELOG.md).

## Now

- Install on Windows 11 following [INSTALL.md](INSTALL.md): check whether the hooks become
  symbolic links (Developer Mode) or stubs, and report what breaks.
- Try the release flow on a real Maven repository: `git np patch`, `git release`, `git publicar`,
  the `pom.xml` version and the merge driver after a second release.
- Pin the `sha256` of every download once the first real build prints them.

## Next

- AI layer ([docs/AI-SETUP.md](docs/AI-SETUP.md)): first Junta notifications into
  `knowledge/jda/inbox/`, then the skills that read them.
- Build order step 4 of [docs/KNOWLEDGE-FLYWHEEL.md](docs/KNOWLEDGE-FLYWHEEL.md): LangGraph triage
  -> worker -> gate -> lessons learned.
- A model catalog in a database (defined, deleted and reordered without editing YAML).

## Later

- Agent hierarchy by change risk (orchestrator, analysts, QA, developers, interns) with paid
  models only at the top levels.
- Server-side checks of the branch model and repository files in Azure DevOps pipelines.
- Formatters for JSP and PL/SQL when a reliable one exists.
