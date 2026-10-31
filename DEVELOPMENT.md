# Development

<!-- Convention: contributing.md guides (https://contributing.md/). -->

How to work on the suite itself. Using the suite in a project: [INSTALL.md](INSTALL.md).

## 1. Environment

- bash, git 2.38+, Python 3.12+ (the engine is plain Python 3, standard library + PyYAML).
- Docker, only to build and try the real image; the tests use a fake `docker`.
- VS Code settings for this repository (UTF-8, LF):

```json
{ "files.encoding": "utf8", "files.autoGuessEncoding": false, "files.eol": "\n" }
```

## 2. Layout

```text
code-quality-suite/
├── VERSION · CHANGELOG.md · Dockerfile (base: engine + installer)
├── bootstrap.sh/.bat/.ps1/.command · install.sh
├── engine/      qs.py (CLI) · policy (encoding, mojibake, commit/branch policy) · registry · runner
│                rules · writers · builtin checks · semver · maven (versions in pom.xml)
│                changelog (Common Changelog) · repofiles (standard files: checks + generator)
├── registry/    src/*.py (catalog: languages, tools, installs) -> registry.json (generated)
├── schema/      quality-rules.schema.json (generated)
├── install/     qs-install (apt / pip / npm / releases / scripts, at image build time)
├── config/      base rules per tool (checkstyle, pmd, clang, sql, web, ...)
├── hooks/       pre-commit · pre-push · commit-msg · prepare-commit-msg · branch guards
├── scripts/     git-rama (branch, version and release aliases) · git-flow-lib · merge-version
│                qs-docker-lib · ensure-langs · build-image · qs-update · qs-run · ci-check · ai-*
├── git-integration/  setup-global (git clonar, git actualizar-suite, clone template)
├── ai-template/ AGENTS.md · skills · Claude Code / OpenCode agents · knowledge/
├── ai-stack/    docker compose: LiteLLM + Postgres, FreeLLMAPI, Ollama
├── tools/       gen.py (registry, schema, LANGUAGES.md) · check-versions.py
├── tests/       unit/ · hooks/ (end to end, fake docker) · noclash/ (fix and check agree)
└── docs/        reference guides (see README.md)
```

## 3. Tests

```bash
python3 tests/unit/test_engine.py           # engine: policy, encoding, mojibake, rules, writers (seconds)
bash tests/hooks/run.sh                     # install + every hook and git alias, fake docker (~5 min)
python3 tools/gen.py --check                # the generated files match the catalog
python3 tests/noclash/run.py                # formatters and linters agree (needs the tools: real image)
QS_TEST_DEBUG=1 bash tests/hooks/run.sh     # the same with set -x
```

`tests/hooks/fake-docker` implements the docker commands the suite uses and runs the engine on the
host with the container paths mapped back (`/workspace`, `/qs-state`, `/qs-git`). The hook tests
need `ruff`, `sqlfluff`, `shellcheck` and `shfmt` on the host:

```bash
pip install ruff sqlfluff shellcheck-py shfmt-py
```

Every change keeps all of them green; a new behaviour gets its check in `tests/hooks/run.sh` (the
`ok`/`fail` lines) or `tests/unit/test_engine.py`.

## 4. The real image

```bash
bash scripts/build-image.sh "$PWD" code-quality-suite:dev            # base only
bash scripts/build-image.sh "$PWD" code-quality-suite:dev java xml   # + a layer of languages
QS_REBUILD=1 bash scripts/build-image.sh "$PWD" code-quality-suite:dev   # after editing the engine or Dockerfile
QUALITY_SUITE_IMAGE=code-quality-suite:dev git commit ...            # use it in a repository
```

## 5. Adding a language or a tool

1. Describe it in `registry/src/*.py` (`lang(...)`, `tool(...)`, install source pinned to a
   version, `sha256=` when known).
2. `python3 tools/gen.py` regenerates `registry/registry.json`, the schema and
   `docs/LANGUAGES.md`, and validates the cross references.
3. Add an `ok` and a `bad` fixture under `tests/noclash/` and run it with the real image.
4. `python3 tools/check-versions.py` compares every pinned version with the latest stable one.

## 6. Conventions

- Code and documentation in English; minimal comments, `why:` for non-obvious decisions
  ([docs/CODE_STYLE.md](docs/CODE_STYLE.md)).
- Shell: `set -euo pipefail`, quote everything, Git Bash compatible (no GNU-only flags without a
  fallback), paths through `qs_hostpath` before docker.
- The analysis container stays `--network none --read-only --cap-drop ALL
  --security-opt no-new-privileges`; anything that needs the network happens at image build.
- Commit messages: Conventional Commits, ASCII, subject up to 50 characters.

## 7. Releasing the suite

```bash
echo 2.6.0 > VERSION
$EDITOR CHANGELOG.md            # new entry on top (Common Changelog), and the README badge
python3 tests/unit/test_engine.py && bash tests/hooks/run.sh && python3 tools/gen.py --check
cd .. && zip -qr code-quality-suite.zip code-quality-suite -x '*/__pycache__/*'
```

Users update with `git actualizar-suite` ([INSTALL.md](INSTALL.md), section 6).
