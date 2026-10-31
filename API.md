# API

<!-- Convention: OpenAPI Specification (https://spec.openapis.org/oas/latest.html) for HTTP APIs; RFC 9110 for HTTP semantics. -->

The interfaces other tools and scripts use. The suite has no HTTP API of its own; the AI gateway
(section 5) is OpenAI-compatible.

## 1. Engine (`engine/qs.py`, entrypoint of the image)

```bash
docker run --rm --network none --read-only -v "$PWD:/workspace" -w /workspace code-quality-suite:2.5.0 <command> ...
```

| Command | Does | Exit |
| --- | --- | --- |
| `run <files...>` | encoding gate, rules sync, pipelines (`QUALITY_MODE=fix\|check`) | 0 ok, 1 findings, 2 bad rules |
| `explain <files...>` | classification and planned tools | 0 |
| `langs <files...>` | language ids (and `lang/subtype`, `tool:<id>`) to install | 0 |
| `sync <files...>` | create / populate the rules file only | 0 |
| `ask <files...>` | versions to ask for new languages (TSV) | 0 |
| `policy` | commit and branch policy as `KEY='value'` lines | 0 |
| `encoding [--fix] <files...>` | encoding and mojibake report; `--fix` repairs in place | 0 clean, 1 problems |
| `version-set <v> [--pom update\|snapshot\|check\|off] [--version-file F]` | write the version to VERSION, pom.xml, package.json; prints changed files | 0 |
| `version-get` | versions declared (JSON) | 0 |
| `version-align WINNER FILE...` | give the files the version of WINNER (merge driver) | 0 |
| `release-notes --version V --tip REV --base REV [--date D] [--tag T] [--previous V] [--write]` | Common Changelog entry (stdout); semver advice (stderr); `--write` merges it into CHANGELOG.md | 0 |
| `release-docs --version V [--date D]` | README badge and CITATION.cff; prints changed files | 0 |
| `repo-files [--force] [-n] [NAME...]` | create the missing standard files | 0 |

Files can also come from a NUL-separated list: `QS_FILES_FROM=/qs-state/files.lst`.

## 2. Environment variables

| Variable | Read by | Meaning |
| --- | --- | --- |
| `QUALITY_MODE` | engine | `fix` (commit) or `check` (push, CI) |
| `QUALITY_LEVEL` | engine | overrides the rules file level |
| `QUALITY_LOG_LEVEL` / `_FORMAT` / `_FILE` / `_CONSOLE` | engine, hooks | logging ([docs/LOGGING.md](docs/LOGGING.md)) |
| `QS_ROOT`, `QS_RULES`, `QS_STATE` | engine | repository root, rules file, state folder |
| `QS_BASE_REV` | engine | revision of the previous version (encoding: old damage only warns) |
| `QS_GIT_DIR` | engine | read-only object store (the hooks mount it at `/qs-git`) |
| `QS_BRANCH` | engine | branch being committed or pushed (VERSION check) |
| `QS_REPO_NAME` | engine | folder name of the clone (repo-files) |
| `QUALITY_HEAVY_CMD` | pre-push | heavy stage, e.g. `mvn -B verify` |
| `QS_HOOK_LINKS=0`, `QS_REPO_FILES=0`, `QS_SKIP_IMAGE=1` | install.sh | stubs, no repository files, hooks only |
| `QS_RETRY_FAILED=1` | ensure-langs | retry tools that failed to install |
| `QUALITY_ALLOW_REBASE=1` | pre-rebase | bypass the rebase guard once |

## 3. Rules file

`.quality-rules.json` at the repository root, validated by `schema/quality-rules.schema.json`
(editors complete it). Sections: `level`, `exclude`, `encoding`, `commit`, `branches`, `global`,
`languages`, `tests`. Reference: [docs/QUALITY-RULES.md](docs/QUALITY-RULES.md) and
[docs/GIT-WORKFLOW.md](docs/GIT-WORKFLOW.md) (`branches`).

## 4. Git aliases

Installed per repository by `install.sh` (`configure_repo`): `np`, `nr`, `nueva-padre`,
`nueva-final`, `convertir-padre`, `subir`, `integra`, `arbol`, `estructura`/`es`, `changelog`,
`release`, `publicar`, `nueva-version`/`nv`, `combinar`, `repo-files`, `encoding`. Global, by
`setup-global.sh`: `clonar`, `actualizar-suite`. Help: `bash scripts/git-rama.sh` (no arguments).

Merge driver `qs-version` (`.git/info/attributes`: `/VERSION`, `pom.xml`, `package.json`):
`bash scripts/merge-version.sh %O %A %B %P`.

## 5. AI gateway (`ai-stack/`)

LiteLLM proxy at `http://localhost:4000/v1`, OpenAI-compatible (`POST /v1/chat/completions`,
`GET /v1/models`), key `LITELLM_MASTER_KEY` (or a virtual key) as `Authorization: Bearer`.

| Model name | Use |
| --- | --- |
| `role-lead`, `role-review` | planning, review (paid, no free fallback) |
| `role-dev` | code changes |
| `role-intern` | cheap tasks (free chain) |
| `role-long` | long context |
| `role-local` | local Ollama model: regulated code |

`LITELLM_CONFIG=demo.yaml` puts every role on free tiers (public or invented code only).
Details: [docs/AI-SETUP.md](docs/AI-SETUP.md), [docs/AI-DEMO.md](docs/AI-DEMO.md).

```bash
curl -s http://localhost:4000/v1/chat/completions -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"model": "role-dev", "messages": [{"role": "user", "content": "hello"}]}'
```
