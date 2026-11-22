# Code Quality Suite

<!-- qs:version -->[![version 6.1.0](https://img.shields.io/badge/version-6.1.0-blue)](CHANGELOG.md)<!-- /qs:version -->

Deterministic quality gate for your repositories: on every **commit** and **push** it checks
the encoding, formats and analyses the code, and **blocks** the operation when it does not meet
the rules. It does not matter who writes the code (you, your team or an AI agent): it does not
enter the repository unless it passes. Everything runs in Docker, offline, on Linux, Windows
(Git Bash + Docker Desktop) and macOS. On top of the gate: a branch model with versioned
releases (git aliases), the standard repository files, and an AI-agent layer.

> Work in progress: AI-agent development is only tested and configured with Claude Code.
> OpenCode and other models, the model gateway and the ai-stack database are not functional yet.

## Requirements

- **Git** 2.38 or newer (Git Bash on Windows) and **Docker** running.
- Nothing else in the target repository: every formatter and linter lives in the image.
- Network only the first time a language is installed (image build).

## Quick start

```bash
# once per machine (the only script you run by hand): unzip the suite somewhere stable, then
bash /c/dev/code-quality-suite/git-integration/setup-global.sh     # git aliases + QS_SUITE

# then everything is git
git iniciar                                  # a new project in this folder (develop, hooks, files, AI files)
git clonar https://git.example/team/app.git  # or: clone a project and set it up
git instalar                                 # or: set up a clone you already have
git add -A && git commit -m "chore: initial project skeleton"   # installs the tools (minutes, once)
git ayuda                                    # the manual of every git command
```

Step by step, updates and removal: [INSTALL.md](INSTALL.md). Every command:
[docs/GIT-COMMANDS.md](docs/GIT-COMMANDS.md).

## What happens

```text
git commit
  └─ pre-commit hook
       ├─ encoding of every staged file: UTF-8, no mojibake  ── stops here on a problem
       ├─ detect languages of the staged files (engine, offline)
       ├─ missing tools? → add an image layer (network, once per language)
       └─ docker run --network none --read-only … engine run <files>
            ├─ rules: .quality-rules.json (+ native configs generated from it)
            ├─ per language, in parallel: syntax → mark → format → lint → deep
            ├─ repository checks: secrets, conflict markers, VERSION / CHANGELOG / README badge
            └─ formatted files are re-staged into the same commit; log: .git/quality-suite/
```

`git push` runs the same pipeline in **check** mode on the pushed commits, then the project
tests and an optional heavy command (`QUALITY_HEAVY_CMD="mvn -B verify"`). CI runs
`scripts/ci-check.sh`.

## Day to day

| Command | Does |
| --- | --- |
| `git ayuda [command]` | the manual of every git command (also given to the AI agents as a skill) |
| `git commit` / `git push` | the gate (above); bypass once with `--no-verify`, CI still checks |
| `git encoding [--fix]` | encoding of the changed files; `--fix` repairs a wrong-encoding save |
| `git np patch` | next version tree from develop (`6.22.7/ORIGINAL`, VERSION and pom.xml written) |
| `git np <ot>` / `git nr <name>` | a parent / final branch under the current ORIGINAL |
| `git subir` / `git integra` | bring the parent in / integrate into the parent |
| `git arbol` / `git es` | show the branch tree / create one from stdin |
| `git changelog` → `git release` → `git publicar` | preview, prepare `<version>/RELEASE` (CHANGELOG.md, badge), merge into develop |
| `git nv <version> --from <branch>` / `git combinar` | a version tree from any branch / join several RELEASE |
| `git repo-files` | create the missing standard repository files |
| `git ia [--actualizar]` | AI agent files (AGENTS.md, skills, subagents), kept out of the repository |
| `git actualizar-suite` | update the suite on this machine |

Branch model and release: [docs/GIT-WORKFLOW.md](docs/GIT-WORKFLOW.md). Rules file:
[docs/QUALITY-RULES.md](docs/QUALITY-RULES.md).

## Main languages (excerpt of 184)

| Language | Syntax | Format | Lint (standard) | Deep (strict) |
| --- | --- | --- | --- | --- |
| Java | tree-sitter | google-java-format | Checkstyle, PMD (`--use-version`) | — |
| JSP | built-in `<% %>` | built-in safe | PMD (JSP rules) | — |
| PL/SQL | ZPA | built-in safe | ZPA | — |
| Python | `ast` (target version) | Ruff format (+imports) | Ruff | mypy |
| JS / TS | TypeScript parser | Prettier | ESLint | `tsc --noEmit` |
| HTML / CSS / SCSS | — | Prettier | html-validate, Stylelint | — |
| SQL (dialect knob) | built-in | SQLFluff | SQLFluff | — |
| XML / JRXML | xmllint | xmllint `--format` | XSD (opt-in) | — |
| Shell | `bash -n` and friends | shfmt | ShellCheck | — |
| YAML | parse | yamlfmt | yamllint + subtype tools | — |
| Markdown | — | markdownlint `--fix` | markdownlint | — |

Full matrix and opt-in tools: [docs/LANGUAGES.md](docs/LANGUAGES.md). Pinned versions:
[docs/VERSIONS.md](docs/VERSIONS.md).

## Documentation

| Read | For |
| --- | --- |
| [INSTALL.md](INSTALL.md) | install, update, remove; what lives where |
| [docs/GIT-COMMANDS.md](docs/GIT-COMMANDS.md) | the manual of every git command: syntax, when, who (`git ayuda`) |
| [DEVELOPMENT.md](DEVELOPMENT.md) | working on the suite itself: tests, catalog, image |
| [ARCHITECTURE.md](ARCHITECTURE.md) | components, flows and decisions |
| [API.md](API.md) | engine commands, hook variables, rules schema, gateway roles |
| [FAQ.md](FAQ.md) · [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | questions and fixes |
| [docs/GIT-WORKFLOW.md](docs/GIT-WORKFLOW.md) | branch model, versions, releases |
| [docs/QUALITY-RULES.md](docs/QUALITY-RULES.md) | `.quality-rules.json`, encoding, commit messages |
| [docs/REPO-FILES.md](docs/REPO-FILES.md) | standard repository files and their checks |
| [docs/AI-SETUP.md](docs/AI-SETUP.md) · [docs/AI-DEMO.md](docs/AI-DEMO.md) | AI agents on top of the gate; free demo |
| [docs/SKILLS.md](docs/SKILLS.md) · [docs/KNOWLEDGE-FLYWHEEL.md](docs/KNOWLEDGE-FLYWHEEL.md) | skills and norms map; design of the agent layer |
| [docs/LOGGING.md](docs/LOGGING.md) · [docs/TESTING.md](docs/TESTING.md) · [docs/CODE_STYLE.md](docs/CODE_STYLE.md) | logs, project tests, code style |
| [docs/GATEWAY-TOOLS.md](docs/GATEWAY-TOOLS.md) · [docs/PROVIDERS.md](docs/PROVIDERS.md) · [docs/MODELS.md](docs/MODELS.md) | related tools, model providers |
| [CHANGELOG.md](CHANGELOG.md) · [ROADMAP.md](ROADMAP.md) | what changed, what comes next |
| [CONTRIBUTING.md](CONTRIBUTING.md) · [SECURITY.md](SECURITY.md) · [SUPPORT.md](SUPPORT.md) | contributing, security, support |

## Limitations

- JSP gets PMD's JSP rules and PL/SQL gets ZPA, but no formatter exists for either (the built-in
  safe formatter only fixes whitespace). 17 niche languages keep only the built-in checks.
- Whole-project analysers (Clippy, golangci-lint, tsc, PHPStan, clang-tidy) need the project's
  dependencies inside the container; offline they skip with a warning instead of failing.
- Partial staging works: unstaged edits are set aside during the check and restored; if the
  formatter touches lines right next to them, the commit stops and nothing changes.
- Tool downloads are pinned by version; checksums can be pinned in `registry/src` (`sha256=`).

## License

<!-- qs:fill: the license of the suite (see LICENSE) -->
See [LICENSE](LICENSE).
