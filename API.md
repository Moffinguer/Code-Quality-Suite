# API

<!-- Convention: OpenAPI Specification (https://spec.openapis.org/oas/latest.html) for HTTP APIs; RFC 9110 for HTTP semantics. -->

The interfaces other tools and scripts use. The suite has no HTTP API of its own; the AI gateway
(section 5) is OpenAI-compatible.

## 1. Engine (`engine/qs.py`, entrypoint of the image)

```bash
docker run --rm --network none --read-only -v "$PWD:/workspace" -w /workspace code-quality-suite:<version> <command> ...
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

Every command of the workflow is a git alias. The manual of each one (syntax, what it does, who
runs it) is [docs/GIT-COMMANDS.md](docs/GIT-COMMANDS.md); `git ayuda [command]` prints it in the
terminal. Repository aliases are registered by `install.sh` (`configure_repo`); global aliases by
`setup-global.sh`. The Version column is the release that first registers the alias.

| Alias | Version | Syntax | Purpose | Manual |
| --- | --- | --- | --- | --- |
| `np` / `nueva-padre` | 4.2.1 | `git np <name> [--from <branch>]` | new parent branch (version or OT) | [np](docs/GIT-COMMANDS.md#git-np) |
| `nr` / `nueva-final` | 4.2.1 | `git nr <name> [--from <ORIGINAL>]` | new final branch for one task | [nr](docs/GIT-COMMANDS.md#git-nr) |
| `convertir-padre` | 4.2.1 | `git convertir-padre [--yes]` | final branch becomes a parent | [convertir-padre](docs/GIT-COMMANDS.md#git-convertir-padre) |
| `subir` | 4.2.1 | `git subir` | sync a branch with its parent and push | [subir](docs/GIT-COMMANDS.md#git-subir) |
| `integra` | 4.2.1 | `git integra [-m "<subject>" [-m "<body>"]] [--force]` | integrate into the parent ORIGINAL | [integra](docs/GIT-COMMANDS.md#git-integra) |
| `arbol` | 4.2.1 | `git arbol [prefix]` | show the branch tree and state | [arbol](docs/GIT-COMMANDS.md#git-arbol) |
| `estructura` / `es` | 4.2.1 | `git es [file] [-n] [--push] [--convertir]` | create a branch tree from stdin | [es](docs/GIT-COMMANDS.md#git-estructura--git-es) |
| `changelog` | 4.2.1 | `git changelog [tag] [--version <v>] [-o <file>]` | preview what a release contains | [changelog](docs/GIT-COMMANDS.md#git-changelog) |
| `release` | 4.2.1 | `git release [tag] [--version <v>] [--yes] [--no-push]` | prepare a version release | [release](docs/GIT-COMMANDS.md#git-release) |
| `publicar` | 4.2.1 | `git publicar [tag] [--version <v>] [--yes] [--no-push]` | publish the reviewed release into develop | [publicar](docs/GIT-COMMANDS.md#git-publicar) |
| `combinar` | 4.2.1 | `git combinar [--incluir <v1,v2...>] [--version <v>] [--yes]` | join prepared releases into one | [combinar](docs/GIT-COMMANDS.md#git-combinar) |
| `nueva-version` / `nv` | 4.2.1 | `git nv <version> [--from <branch>] [--arbol-completo] [-n]` | test or pre-release version tree | [nv](docs/GIT-COMMANDS.md#git-nueva-version--git-nv) |
| `repo-files` / `ficheros-repo` | 4.2.1 | `git repo-files [-n] [--force NAME...]` | create missing standard files | [repo-files](docs/GIT-COMMANDS.md#git-repo-files) |
| `encoding` | 4.2.1 | `git encoding [--fix] [file...]` | check or repair the encoding of changes | [encoding](docs/GIT-COMMANDS.md#git-encoding) |
| `clonar` | 4.2.1 | `git clonar <url> [folder]` | clone and set up (global) | [clonar](docs/GIT-COMMANDS.md#git-clonar) |
| `iniciar` | 4.2.1 | `git iniciar [folder] [--sin-ia] [--remoto <url>]` | start a new project (global) | [iniciar](docs/GIT-COMMANDS.md#git-iniciar) |
| `instalar` | 4.2.1 | `git instalar [repo]` | set up a clone already on disk (global) | [instalar](docs/GIT-COMMANDS.md#git-instalar) |
| `ia` | 4.2.1 | `git ia [--actualizar]` | add or refresh the AI agent files (global) | [ia](docs/GIT-COMMANDS.md#git-ia) |
| `ayuda` | 4.2.1 | `git ayuda [command]` | print the manual (global) | [ayuda](docs/GIT-COMMANDS.md#git-ayuda) |
| `actualizar-suite` | 4.2.1 | `git actualizar-suite [--status \| --langs "..." \| --lazy \| --yes]` | update the suite on this machine (global) | [actualizar-suite](docs/GIT-COMMANDS.md#git-actualizar-suite) |
| `testing` | 5.0.0-RC1 | `git testing crear \| estado \| repartir ...` | try several branches together in a sandbox | [testing](docs/GIT-COMMANDS.md#git-testing) |
| `migracion` | 6.0.0 | `git migracion`; also `git np <v> --migracion` | create `<v>/MIGRATION` (human) | [migracion](docs/GIT-COMMANDS.md#git-migracion) |
| `intentos` | 6.0.0 | `git intentos <task> <N>` | ATTEMPT branches with worktrees (lead) | [intentos](docs/GIT-COMMANDS.md#git-intentos--git-elegir) |
| `elegir` | 6.0.0 | `git elegir <task>` | rank attempts; the human confirms (human) | [elegir](docs/GIT-COMMANDS.md#git-intentos--git-elegir) |
| `revision` | 6.0.0 | `git revision <task> [--aplicar [c...]] [--descartar]` | REVIEW branch of a task (reviewer, author) | [revision](docs/GIT-COMMANDS.md#git-revision) |
| `cuarentena` | 6.0.0 | `git cuarentena <task> [--borrar]` | QUARANTINE branch (external-worker; lead or human) | [cuarentena](docs/GIT-COMMANDS.md#git-cuarentena--git-aceptar) |
| `aceptar` | 6.0.0 | `git aceptar <c...> --a <branch>` | cherry-pick a quarantined commit, `Reviewed-by:` (lead or human) | [aceptar](docs/GIT-COMMANDS.md#git-cuarentena--git-aceptar) |
| `checkpoint` | 6.0.0 | `git checkpoint "<msg>" [--lista] [--volver <n>]` | local save points (any agent) | [checkpoint](docs/GIT-COMMANDS.md#git-checkpoint) |
| `spike` | 6.0.0 | `git spike [--llevar <branch> <task>]` | SPIKE branch; `--llevar` takes commits out (anyone) | [spike](docs/GIT-COMMANDS.md#git-spike) |
| `limpiar-unmerged` | 5.0.0-RC1 | `git limpiar-unmerged [-n] [--yes]` | delete archived `unmerged/...` branches already integrated | [limpiar-unmerged](docs/GIT-COMMANDS.md#git-limpiar-unmerged) |
| `amend` | 5.0.0-RC1 | `git amend [git commit --amend options]` | amend a commit through the hooks | none yet in GIT-COMMANDS.md |

Not listed, deferred to a later version: `git refactor`, `git tests`, `git formatear`, `git docs`
and `git changelog --escribir`. Special-branch state is in
[GIT-COMMANDS.md section 5](docs/GIT-COMMANDS.md#5-branches).

Merge driver `qs-version` (`.git/info/attributes`: `/VERSION`, `pom.xml`, `package.json`):
`bash scripts/merge-version.sh %O %A %B %P`.

### 4.1 Usage guide

Five common journeys. Each step names who runs it; details are in the
[manual](docs/GIT-COMMANDS.md). Branch names: `<version>/<ot>/<task>`.

1. **Start a version** (human):

   ```bash
   git checkout develop && git np patch          # 6.22.7/ORIGINAL
   ```

2. **Do a task** (developer, on its own final branch):

   ```bash
   git nr login --from 6.22.7/188858/ORIGINAL    # 6.22.7/188858/login
   # edit, then: git add -A && git commit -m "feat(login): add certificate login"
   git subir                                     # rebase onto the OT ORIGINAL and push
   ```

3. **Bugfix loop** (developer, same final branch):

   ```bash
   git arbol                                     # where am I, what is behind
   git encoding --fix                            # only if a commit stopped with ENCODING
   git commit -m "fix(login): accept expired certificates"
   git subir                                     # after the parent moved
   ```

4. **Close an OT** (lead): every task integrated into the OT ORIGINAL, then the OT moves up:

   ```bash
   git checkout 6.22.7/188858/login && git integra -m "feat(login): add certificate login"
   git checkout 6.22.7/188858/ORIGINAL && git integra -m "feat(login): OT 188858 login" -m "<why>"
   ```

5. **Release and publish a version** (human, after every OT is integrated):

   ```bash
   git changelog                                 # preview: changes, semver advice, checks
   git release                                   # 6.22.7/RELEASE for review
   git publicar                                  # after review: into develop, tagged
   git limpiar-unmerged -n                       # later: preview the archive cleanup
   ```

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
