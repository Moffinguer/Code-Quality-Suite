# Architecture

<!-- Convention: arc42 (https://arc42.org/), shortened; C4 model (https://c4model.com/) levels in the diagrams. -->

## 1. Goals and context

A local, deterministic quality gate for every repository on a developer's machine, whoever
writes the code (a person or an AI agent), plus the workflow around it: branch model, versions,
releases, standard repository files, and an AI-agent layer that must pass the same gate.

**Status of this document.** It describes the system as of **6.1.0 + 7.0.0**. Not everything is
built yet; each section says which part it describes:

| Mark | Meaning | Source |
| --- | --- | --- |
| built | in the tree of this document (suite 4.2.1 on `develop`) | the code |
| 6.1.0 | squash flow, `Files:` block, OT and version release, TESTING sandbox (5.0.0-RC1); special branches, publish on create, rules upgrade, agent flow (6.0.0). Developed on their own branch trees, combined into 6.1.0, **not on `develop` yet** | `docs/5.0.0-RC1/spec.md`, `docs/6.0.0/spec.md` |
| 7.0.0 | GitHub settings as code, GitHub Actions that repeat the local checks, shared check library. **Specified, not built** | `docs/7.0.0/spec.md` |

```text
 developer / AI agent ──git commit / push──> git hooks (host) ──docker run──> engine (container)
         │                                        │                               │
         └──git aliases (np, release...)──> git-rama.sh (host) ──docker run──> engine tools
                                                  │                         (pom.xml, CHANGELOG)
 CI pipeline ──scripts/ci-check.sh──> same engine, same rules
 AI agents ──LiteLLM gateway (ai-stack)──> model providers / local Ollama
```

## 2. Constraints

| Constraint | Consequence |
| --- | --- |
| Code of the `regulated` data class: never sent to services that train on prompts | the gate runs offline; AI roles for real code use paid no-training endpoints or local models only |
| Windows 11 + Git Bash + Docker Desktop as the main platform | bash only (no jq, no GNU-only flags), host paths through `cygpath`, stubs when symbolic links are not allowed |
| No local runtimes in the projects | every tool lives in the image; the host needs git and docker |
| Reproducible | tools pinned by version, apt from a dated snapshot, base image digest lock |
| Tools offline at check time | network only during `docker build` (new language) |
| Secrets never in images or repositories | `ai-stack/.env` is local; the gate blocks private keys and known secret formats |

## 3. Building blocks

| Block | Where | Responsibility |
| --- | --- | --- |
| Hooks | `hooks/` (one copy per machine, linked per repository) | collect the files, stage/restore partial edits, call the engine, block |
| Engine | `engine/qs.py` + modules | classify files, encoding and mojibake gate, rules file, native configs, pipelines per language, repository checks, version/changelog/repo-file tools |
| Catalog | `registry/src/*.py` -> `registry.json` | languages, subtypes, tools, roles, installs, levels |
| Installer | `install/qs-install`, `scripts/ensure-langs.sh`, `scripts/build-image.sh` | add an image layer with the tools of new languages, under a machine-wide lock |
| Branch workflow | `scripts/git-rama.sh`, `git-flow-lib.sh`, `merge-version.sh` | git aliases: tree, integration, versions, release, combine; merge driver for version files |
| Repository files | `engine/repofiles.py`, `changelog.py`, `maven.py`, `semver.py` | generate and validate README, CHANGELOG, VERSION ...; versions in pom.xml |
| Machine setup | `install.sh`, `bootstrap.*`, `git-integration/`, `scripts/qs-update.sh` | install, clone, update, re-point repositories |
| AI layer | `ai-template/`, `scripts/ai-*.sh`, `ai-stack/` | agent files and skills per repository; model gateway with roles and fallbacks |

### 3.1 Layers (overview)

The blocks are delivered in four layers; each adds value on its own. Recommended order:
1, CI, 2, 3, 4.

| Layer | Blocks | What it gives |
| --- | --- | --- |
| 1 Quality gate | Engine, Catalog, Installer | 184 languages: a syntax check, a formatter and linters per language, at the level set in `.quality-rules.json` |
| 2 Local Git hooks | Hooks, Branch workflow, Repository files | `pre-commit` formats and blocks, `pre-push` re-checks in check mode, `commit-msg` enforces Conventional Commits, `prepare-commit-msg` preloads the message |
| 3 CI/CD | `scripts/ci-check.sh`, `examples/ci/` | the same engine on the changed files of a PR; local hooks can be skipped with `--no-verify`, CI cannot. 7.0.0 adds GitHub Actions (section 7) |
| 4 AI-assisted development | AI layer | any AI-generated code passes the same gate before entering the repository (section 3.2) |

### 3.2 Agent skeleton

*Roles table copied from `ai-template/AGENTS.md`; steps from skill `team-flow`.* **Status: built
(4.2.1).** The 6.1.0 rights are marked as such. Claude Code
subagents cannot start other subagents, so only the main session (the lead, also the business
analyst) delegates. The roles live in `.claude/agents/`; OpenCode gets the same ones in
`.opencode/agents/`.

| Role | Model | Does | May run | Never |
| --- | --- | --- | --- | --- |
| main session (lead, business analyst) | strongest available | reads `dev_documents/`, delegates, creates and integrates branches, escalates to the human | `git np`, `nr`, `es`, `convertir-padre`, `integra` | writes large code itself |
| systems-analyst | opus | spec, plan, branch tree for `git es -n`, one task per final branch, merge-conflict suggestions | read-only git; 6.1.0: runs `git es`, `np`, `nr`, `integra` | edits source code |
| developer | sonnet | implements one task on its own final branch; gate and hooks before review | commits, `git subir`, the gate; 6.1.0: may create CHECKPOINT branches | merges into an ORIGINAL |
| reviewer | opus | reviews diffs against norms and quality rules | read-only git; 6.1.0: commits on REVIEW branches | edits code |
| qa | sonnet | tests, gate runs, regression checks; findings open the `<final-branch>/bugfix` loop | the gate, tests; 6.1.0: runs `git tests` and `git revision` | changes production code |
| docs-writer | haiku | documentation from recipes | commits on its branch | invents requirements |
| intern | haiku | boilerplate, renames, small mechanical edits | commits on its branch | touches security code |
| external-worker | haiku | hands cheap, non-regulated tasks to other models through the gateway | gateway roles | sends regulated data |

The "May run" column summarises `team-flow` and `branch-workflow`. The per-agent permission rows
come from `oc_bash_rules` in `scripts/ai-sync.sh` (and `ai-template/.claude/settings.json`), not
from per-agent settings.

*Flow of skill `team-flow`.*

```text
human ── requirements ──> lead (business analyst) ── requirements, processes ──> systems-analyst
                                                                                     │ spec.md, plan.md
                          human approves the spec, then the plan <───────────────────┘
lead: git es -n, then git es  (creates the branch tree)
  ├─> developer (one worktree per final branch): code, gate, git subir
  │     ├─> qa: findings in docs/<v>/<req>/bugfix.md
  │     │     └─> lead: git convertir-padre + git nr bugfix; developer fixes; qa again, until clean
  │     └─> reviewer: verdict
  └─> lead: git integra, bottom-up; the human approves each merge
human: git release (6.1.0: the OT release still writes the CHANGELOG), git publicar
```

Human checkpoints: approve the spec, approve the plan, approve each merge (bottom-up) and the
merge into `develop`. The shared context (`dev_documents/`, `docs/<v>/`) is git-ignored and
exists only in the main worktree: the lead passes absolute paths. Models other than Claude work
as developers through OpenCode `role-dev` or `external-worker`, for non-regulated data only. The
gateway (`ai-stack/`, LiteLLM) maps roles to providers and fallbacks; it is not functional yet
for agents other than Claude Code (work in progress, see [docs/AI-SETUP.md](docs/AI-SETUP.md)).

### 3.3 Commands and branches

*Branch tree copied from [docs/GIT-WORKFLOW.md](docs/GIT-WORKFLOW.md) ("Branch model").*

```text
develop
├─ 6.22.6/ORIGINAL                         version (always a parent; Semantic Versioning)
│  └─ 6.22.6/188858/ORIGINAL               OT 188858
│     └─ 6.22.6/188858/RF001/ORIGINAL      requirement RF001
│        ├─ 6.22.6/188858/RF001/login      final branch
│        └─ 6.22.6/188858/RF001/bank/ORIGINAL
│           ├─ 6.22.6/188858/RF001/bank/bugfix
│           └─ 6.22.6/188858/RF001/bank/payments
└─ 6.22.6-SNAPSHOT/ORIGINAL                another version tree next to it (git nueva-version)
   └─ 6.22.6-SNAPSHOT/188858/ORIGINAL ...
```

*Commit pipeline copied from [README.md](README.md) ("What happens").*

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

Who runs which command, at which level of the tree:

| Level | Command | Who | Effect |
| --- | --- | --- | --- |
| develop -> version | `git np <version>` (or `patch`, `minor`, `major`) | lead | creates `<v>/ORIGINAL` and its version commit |
| version, OT, requirement | `git np <name>`, `git es` | lead | parent branches (`<folder>/ORIGINAL`); `git es` creates a whole tree |
| final branch | `git nr <name>` | lead | (built) creates the final branch; developers never create branches; in 6.1.0 they may create CHECKPOINT branches |
| final branch | commits, `git subir` | developer (qa fixes on `bugfix` the same way) | hooks run; `git subir` rebases the final branch onto its ORIGINAL |
| final -> ORIGINAL | `git integra -m ... -m ...` | lead, after qa and reviewer; the human approves | built: merge. 6.1.0: ONE squash commit with `Commits:`, `Files:`, `Refs:` per level, bottom-up |
| OT end | `git release` in the OT | human | 6.1.0: OT RELEASE `<v>/<ot>/RELEASE` with its CHANGELOG lines (the OT release still writes the CHANGELOG), tag `ot/<v>/<ot>`, subtree deleted |
| version end | `git release` (6.1.0: `--version <v>`) | human | built: `<v>/RELEASE` with VERSION, CHANGELOG.md, badge. 6.1.0: refused until every OT has its RELEASE; tag |
| into develop | `git publicar`, `git combinar` | human | built: merge into develop and tag. 6.1.0: rebase onto develop, ONE commit |

**6.1.0 additions (specified, not on `develop` yet).** `Files:` lists every file in every
commit; the changelog line is `- <Subject> (<short hash>; <OT>)`. **TESTING**
(`<level>/TESTING`) is a throw-away branch that merges several branches to try them together
and is never integrated (`git testing crear`, `estado`, `repartir`).

**Special branches (6.1.0).** Reserved UPPERCASE names with their own rules, all read from
`branches.special` in `.quality-rules.json`: MIGRATION and DOCS at version level (in 6.1.0 the OT
release still writes the CHANGELOG; the DOCS-writes-changelog mode, `git changelog --escribir`,
is DEFERRED to a later version and is not built); REFACTOR, FORMAT, TESTS and SPIKE as
controls for people; ATTEMPT-n, REVIEW-`<task>`, QUARANTINE-`<task>` and CHECKPOINT-`<task>` as
controls for agents; TESTING as above. Hooks, `git arbol`, `git ayuda` and the agent
permissions read the same table. Every branch a suite command creates is published right after
(`publish_on_create`; CHECKPOINT never).

## 4. Runtime view

**Commit.** `pre-commit` lists the staged files, sets unstaged edits aside, installs missing
languages (`ensure-langs`), then `docker run --network none --read-only` the engine with the
repository at `/workspace` and the object store read-only at `/qs-git`. The engine checks the
encoding first (stops on a problem, listing the files), syncs the rules file, runs the pipelines
per language in parallel (syntax -> mark -> format -> lint -> deep) and the repository checks; the
hook re-stages the formatted files and restores the unstaged edits.

**Push.** `pre-push` checks the branch model, exports the pushed tree (`git archive`), runs the
engine in check mode against the remote base, then the project tests and the heavy command.

**Version tree.** `git np 6.22.6` creates `6.22.6/ORIGINAL` and, without a checkout, a commit
that writes the version: the files are extracted (`git archive`), edited by the engine in the
container (`version-set`), and committed with `git commit-tree`.

**Release (built).** `git release` analyses the tree, creates `<version>/RELEASE`, commits the
version, the CHANGELOG.md entry (from the integration merges, `release-notes`) and the README
badge, pushes it and deletes the rest of the tree. `git publicar` merges it into develop, tags
and deletes it. `git combinar` rebases several RELEASE branches in a temporary worktree.

**Release (6.1.0, not on `develop` yet).** Two reviewed steps. An OT is closed by an OT release
(`<v>/<ot>/RELEASE`: its CHANGELOG lines, tag `ot/<v>/<ot>`, subtree deleted). In 6.1.0 the OT
release still writes the CHANGELOG; the DOCS-writes-changelog mode (`git changelog --escribir`) is
DEFERRED to a later version and is not built. The version
release is refused until every OT has its RELEASE; it rebases the OT RELEASEs into
`<v>/RELEASE`, checks the badge and, once the DOCS mode lands, that DOCS holds `CHANGELOG.md`; then tags. `git publicar`
rebases `<v>/RELEASE` onto develop and lands it as ONE commit. 5.0.0-RC1 and 6.0.0 are not
published alone: `git combinar` joins them and they ship as 6.1.0.

## 5. Deployment

```text
suite folder (VERSION <version>) ──> image code-quality-suite:<version> = base + one layer per language batch
~/.config/code-quality-suite/hooks/*  <── symbolic links (or stubs) from every <repo>/.git/hooks/
<repo>/.git/hooks/quality-suite.env   points at the suite folder
```

One image per suite version, shared by every repository; labels `qs.langs` and `qs.layers`
record what it holds. An update removes every suite image and rebuilds the base.

## 6. Decisions

| Decision | Why |
| --- | --- |
| Docker image with tools, not host tools | the same versions for everyone; nothing to install in projects |
| One shared image per version, layers per language | install once per machine, not per repository |
| `ORIGINAL` as the parent leaf | git refs are files and folders: `a/b` and `a/b/c` cannot coexist |
| Final branches rebased, parents merged | linear work per branch; shared branches never rewritten |
| Release in two steps with a RELEASE branch | the changelog is reviewed before it reaches develop |
| Semantic Versioning for version roots | ordering, next-version and changelog checks need comparable versions |
| Version commit without checkout (`commit-tree`) | creating trees never touches the working tree |
| Merge driver for version files | every tree writes its own version in the same lines |
| Encoding gate before any tool | formatters would rewrite damaged text and hide the cause |
| Previous version from a read-only object store mount | tell new damage from old in worktrees and pushed trees too |
| Common Changelog generated from integration merges | `git integra` subjects are curated; raw `git log` is noise |
| LiteLLM gateway with roles | agents name a role; providers and fallbacks change in one file |
| Squash per level (6.1.0) | a short, OT-scoped history; every integration is one single-parent commit |
| Special branches from one table (6.1.0) | hooks, commands, `git arbol` and agent permissions cannot disagree |
| Actions report, rulesets refuse (7.0.0) | github.com has no pre-receive hooks |

## 7. GitHub (7.0.0, specified, not built)

*Source: `docs/7.0.0/spec.md`.* github.com has no pre-receive hooks, so GitHub Actions run after
a push is accepted: they mark it red, never refuse it. Only rulesets refuse pushes.

| Piece | Where | Role |
| --- | --- | --- |
| Settings as code | `.github/repo-settings.json`, `scripts/gh-settings.sh` | desired repository options, Actions policy and rulesets; the human applies them (`--diff`, then `--apply`) with their own `gh auth login`; agents are denied |
| Rulesets | applied from the JSON | refuse deletion and non-fast-forward of `main` and `develop`, non-fast-forward of `**/ORIGINAL`, creation of `CHECKPOINT-*`, update and deletion of release and `ot/**` tags |
| Workflows | `.github/workflows/quality.yml`, `flow.yml`, `selftest.yml` | gate on the changed files (diff-only until the baseline cleanup), branch model, messages, `Files:` block, TESTING leak guards, release and special-branch rules, the suite's own tests |
| Shared check library | `scripts/flow-check-lib.sh`, `scripts/ci-flow-check.sh` | the new rules (develop moves only through `git publicar`, tags, no AI co-author line) written once, used by the hooks and the Actions |

```text
 push / PR ──> GitHub ruleset (refuses ref-level violations)
                  └─> Actions: quality, flow, selftest ──> same engine, same rules, red check
 local:  hooks (pre-commit, commit-msg, pre-push) ──> same shared library
```

## 8. Risks and technical debt

- Node-based tools and some downloads are verified only in a connected environment.
- `git combinar` with trees copied from each other relies on `--rebase-merges`; conflicts stop it.
- Download checksums are pinned only where known (`sha256=` in the catalog).
- Baseline debt: the repository has pre-existing gate findings; the 7.0.0 Actions are diff-only
  until a cleanup (planned for 6.1.x) lands.

## 9. Glossary

| Term | Meaning |
| --- | --- |
| OT | work order (orden de trabajo), the second level of a branch name |
| ORIGINAL | the parent branch of a folder of branches |
| RELEASE | a version tree ready to reach develop, under review |
| special branch | a branch with a reserved UPPERCASE name and its own rules (6.1.0) |
| TESTING | throw-away branch that merges several branches to test them together (6.1.0) |
| gate | the checks that block a commit or a push |
| role | a model alias of the gateway (`role-lead`, `role-dev`, `role-local`...) |
