# The rules file: `.quality-rules.json`

One editable file at the repository root decides what every tool checks. It is git-ignored
(`.git/info/exclude`), so each clone can tune it; commit it on purpose if the team should
share it (CI then applies exactly the same rules).

## Lifecycle

1. The first commit creates it as a skeleton: level, excludes, repository-wide checks, tests.
2. The first time a language is committed, the suite adds its section with the **base rules
   of the image** (the same rules v1 applied: Checkstyle, PMD, clang-format, perltidy, SQLFluff,
   Prettier, markdownlint, hadolint...). Nothing else is added until a new language appears.
3. You edit it. Your values are never overwritten; only `detected_version` is maintained by
   the suite.
4. On each commit the suite diffs it against the last applied snapshot
   (`.git/quality-suite/rules.applied.json`), logs every change and regenerates the native
   config files (`.git/quality-suite/generated/<lang>/<tool>/…`, for inspection). Those configs
   are what the tools receive, so the change is applied in the same commit.

```text
2026-10-04T21:43:39Z INFO comp=rules file=.quality-rules.json action=change status=SUCCESS msg="modified languages.python.formatting.ruff-format.rules.line-length: 100 -> 120"
2026-10-04T21:43:39Z INFO comp=rules file=.quality-rules.json action=apply status=SUCCESS msg="1 change(s) applied; native configs regenerated in .git/quality-suite/generated"
```

An invalid file (bad JSON, wrong types, unknown level) blocks the commit with the line and
column; unknown languages/tools only warn.

## Layout

```jsonc
{
  "$schema": "file:///…/schema/quality-rules.schema.json",
  "version": 1,
  "level": "standard",
  "data_class": "internal",
  "exclude": ["generated/**", "*.pb.go"],
  "encoding": { "charset": "utf-8", "bom": "forbid", "by_language": {}, "by_glob": {}, "mojibake": "block" },
  "commit":   { "charset": "ascii", "types": ["feat", "fix", "…"], "subject_max": 50 },
  "branches": { "parent_leaf": "ORIGINAL", "levels": ["…version…", "…ot…"], "…": "…" },
  "global": { "<tool>": { "enabled": true, "rules": {} } },
  "languages": {
    "<language>": {
      "enabled": true,
      "level": "inherit",
      "version": "auto",
      "detected_version": "17 (pom.xml)",
      "extensions": [".jspx2"],
      "syntax":     { "<tool>": { … } },
      "formatting": { "<tool>": { … } },
      "analysis":   { "<tool>": { … } }
    }
  },
  "tests": { "commands": [], "autodetect": false }
}
```

Tool block: `enabled`, `level` (minimum level for this tool), `args` (extra CLI arguments),
`autofix` (linters: apply safe fixes during the commit), `rules` (the tool's settings).

Categories: `syntax` (parsers), `formatting` (identifying mark + the formatter), `analysis`
(linters and deep analysers). Language ids and tool ids are listed in `docs/LANGUAGES.md`;
the JSON Schema gives editors completion and the default rules of each tool.

## Data class (`data_class`)

Top-level key (not a section). The data class of the repository:

| Value | Meaning |
| --- | --- |
| `public` | public data and code: any model or endpoint may see it |
| `internal` | default: the team's own code and data |
| `regulated` | regulated data: `git cuarentena` (QUARANTINE) refuses the repository, and its data never goes to free model tiers or third-party endpoints that train on prompts |

Invalid values block the commit. The hooks read it from the policy environment as
`QS_DATA_CLASS`, like the other keys.

## Encoding (`encoding`)

Every shared text file must use one charset (default **UTF-8 without BOM**). The check runs on
every changed file **before any tool**: when one fails, the commit stops at once, nothing is
formatted or analysed, and the console lists the affected files:

<!-- qs-allow-mojibake-begin: the examples below show damaged text on purpose -->
```text
[quality-suite] ENCODING: 2 file(s) with encoding problems. Nothing was formatted or analysed.
[quality-suite]   src/main/java/es/jda/Login.java
[quality-suite]       line 12, column 20: "CanciÃ³n" should be "Canción" (UTF-8 text read as Windows-1252 and saved again)
[quality-suite]   src/main/resources/messages.properties
[quality-suite]       not valid UTF-8 at line 3, column 9 (byte 0xF1): saved as Windows-1252/ISO-8859-1 (ANSI) instead of UTF-8: 2 character(s); line 3: "año"; line 4: "niño". Repair: git encoding --fix FILE
[quality-suite] Repair: git encoding --fix <file>   (or reopen it in VS Code with the right encoding, then 'Save with Encoding' -> UTF-8)
```

What it finds:

| Problem | Typical cause | Shown as |
| --- | --- | --- |
| not valid UTF-8 | the file was saved as Windows-1252 / ANSI | the line and the word, decoded as Windows-1252 |
| mixed encodings | a UTF-8 file opened as Windows-1252, new text typed and saved in Windows-1252 | the lines in Windows-1252 |
| double encoding (mojibake) | a UTF-8 file opened as Windows-1252 and saved as UTF-8: `ó` -> `Ã³`, `’` -> `â€™` | the damaged word and the right one |
| replacement characters `�` | a Windows-1252 file opened as UTF-8 and saved: the accents are lost | the line (and the original, from the previous version) |
| accents turned into `?` | saved in a charset without those letters | the line and the original |
| BOM, UTF-16 | editor settings | the fix |
<!-- qs-allow-mojibake-end -->

Damage that is **already in the previous version** of the file (`HEAD` for a commit, the remote
branch for a push) on a line you did not touch is only a warning: you are not forced to repair
old files to commit a change next to them.

**Repair.** `git encoding` checks the files you changed (staged, modified or new); `git encoding
--fix [file...]` repairs them in place: Windows-1252 bytes become UTF-8, double-encoded text is
decoded back, and lines whose accents became `?` or `�` take them back from the previous <!-- qs-allow-mojibake -->
version. What it cannot repair is listed. Review with `git diff` before committing.

**VS Code**, so it does not happen again (Settings, JSON):

```json
{ "files.encoding": "utf8", "files.autoGuessEncoding": false }
```

For a file already damaged: the encoding name in the status bar -> *Reopen with Encoding* ->
the one it was really saved in (Windows 1252 for ANSI) -> check the accents -> *Save with
Encoding* -> UTF-8.

| Key | Default | Meaning |
| --- | --- | --- |
| `enabled` | `true` | `false` turns the check off |
| `charset` | `utf-8` | `utf-8`, `ascii`, `iso-8859-1`, `iso-8859-15`, `windows-1252`, `utf-16` ... |
| `bom` | `forbid` | `forbid`, `allow` or `require` (UTF-8 BOM) |
| `by_language` | `{"powershell": {"bom": "allow"}}` | language id -> charset, or `{charset, bom}` |
| `by_glob` | `{}` | path glob -> charset, or `{charset, bom}`; first match wins over `by_language` |
| `mojibake` | `block` | `block`, `warn` or `off`: text damaged by a save in the wrong encoding |
| `mojibake_ignore` | `[]` | path globs never checked for mojibake (fixtures that contain it on purpose) |

A single line that must contain such text on purpose can carry the marker `qs-allow-mojibake`
(in a comment); `qs-allow-mojibake-begin` ... `qs-allow-mojibake-end` exempts the lines between
them.

Legacy example (Java `.properties` that must stay ISO-8859-1):
`"by_glob": {"src/main/resources/**/*.properties": "iso-8859-1"}`. Files declared in a
charset other than UTF-8 that contain non-ASCII bytes are never formatted (formatters assume
UTF-8 and would corrupt them); linters still run, and `{charset}` passes the declared
charset to tools that accept it (PMD `--encoding`).

## Commit messages (`commit`)

| Key | Default | Meaning |
| --- | --- | --- |
| `charset` | `ascii` | `ascii`: no accents, n-tilde, diaeresis or other non-ASCII characters; `utf-8`; `any` |
| `types` | Conventional Commits types | allowed `<type>` values |
| `subject_max` | `50` | maximum subject length |
| `conventional` | `true` | `false` skips the Conventional Commits format check |

A rejected message prints the offending lines and an ASCII suggestion
(`feat: anadir validacion` for `feat: añadir validación`).

## Branches (`branches`)

The branch model and its keys are described in `docs/GIT-WORKFLOW.md` (including the release
keys `release_leaf`, `archive_prefix`, `version_file`, `changelog_file`, `readme_file`,
`pom_version`, `tag_url`, `commit_url`, and `build_cmd`, the full build a MIGRATION push runs)
and `publish_on_create` (default `true`: every branch a suite
command creates is pushed to origin with `-u`; `false`, or `QS_PUBLISH=0` for one command, leaves
it to `git subir`).

### Special branches (`branches.special`)

One table says which reserved branch types exist and what rules each one has. The defaults
(6.0.0) are in `engine/policy.py`; the JSON schema lists every property. A project overrides
one property (`"TESTS": {"paths": ["qa/**"]}`: the other properties keep their defaults) or
disables a whole type (`"FORMAT": false`): a disabled type is not reserved, a branch with that
name is an ordinary branch. TESTING (`branches.testing_leaf`) is not in the table.

| Type | Where (`at`) | Integrates | Order | Notes |
| --- | --- | --- | --- | --- |
| `MIGRATION` | version | squash | first, locks the version | build commits, no `feat`; full build on push |
| `DOCS` | version, no children | squash | last | docs and chore commits, paths `@docs`; the only place for CHANGELOG.md and the badge |
| `REFACTOR` | node | squash | last | refactor commits, gate level `strict` |
| `FORMAT` | node, no children | squash, never rebased | alone | `style` commits |
| `TESTS` | node | squash | any | test and chore commits, paths `@tests` |
| `SPIKE` | node | `apply` (commits are taken out) | any | deleted at the release |
| `ATTEMPT-<n>` | task | `choose` (only the attempt choice) | any | counts in the task changelog |
| `REVIEW-<task>` | task | `apply` | any | deleted at the release |
| `QUARANTINE-<task>` | task | `apply` | any | `Generated-by` trailer, gate level `strict` |
| `CHECKPOINT-<task>` | task, no children | never | any | never pushed, gate level `format` |

Properties of an entry:

| Property | Values | Meaning |
| --- | --- | --- |
| `at` | `version`, `node`, `task` | where the branch may live |
| `children` | bool | may become `<X>/ORIGINAL` with children |
| `suffix` | `none`, `n`, `task` | `ATTEMPT-<n>`, `REVIEW-<task>` |
| `integrates` | `squash`, `never`, `choose`, `apply` | how the integration treats the branch |
| `order` | `any`, `first`, `last`, `alone` | when it integrates among its siblings |
| `rebase` | bool | `false` for FORMAT: regenerated, never rebased |
| `types` | list of Conventional Commits types, `["*"]` = all, `[]` = no own commits | allowed commit types |
| `paths` | list of globs and `@repo-files`, `@docs`, `@tests`; `[]` = any | allowed paths |
| `level` | `off`, `syntax`, `format`, `standard`, `strict` or `null` | gate level for the branch |
| `push` | `normal`, `never` | CHECKPOINT never pushes |
| `push_checks` | `default`, `full` | `full`: full build and tests on push |
| `trailers` | list | trailers every own commit must carry |
| `locks` | bool | while it exists no other branch of the version may be created |
| `on_release` | `required`, `optional`, `delete`, `set_aside` | what the version release does with it |
| `changelog` | `none`, `changed`, `task` | how it appears in the changelog |

Not configurable (the validation refuses another value): `FORMAT.rebase` (`false`),
`ATTEMPT.integrates` (`choose`), `CHECKPOINT.push` (`never`). Also refused: an unknown type
(`HOTFIX`), an unknown property, a bad value and a type named like `parent_leaf`,
`release_leaf` or `testing_leaf` (ignoring case).

`DOCS.on_release` is `required` in new files (DOCS writes the changelog). A file written by
5.x gets `optional` when the suite migrates it (`branches.model` 6), so the 5.x changelog
writer keeps working until the project sets `required` (see `docs/UPDATING.md`). The hooks and
scripts read the table as `QS_SP_NAMES` (enabled types) and `QS_SP_<TYPE>_<PROP>` from
`policy.env` (booleans `1`/`0`, lists joined with `|`).

## Repository files (`qs-repo-files`)

A built-in check of the repository checks (`global`, always on) validates the standard files
when they change: `VERSION` (semver, = the version of the branch, = `pom.xml`), `CHANGELOG.md`
(Common Changelog), the README version badge (= the last release), `CITATION.cff` (required
keys), `CODEOWNERS` (owners), `LICENSE` (template placeholders), and warns while a generated
file still has `qs:fill` markers. Details: `docs/REPO-FILES.md`.

## Large files and generated files (`qs-large-file`)

`qs-large-file` rejects files over `max_kb` (default 512 KB). Generated files are exempt through
a tracked, repo-wide mark: set the git attribute `qs-generated` (or `linguist-generated`) in
`.gitattributes`, for example `schema/quality-rules.schema.json qs-generated`. The check reads
it with `git check-attr`; if git cannot answer (for example inside a container), the root
`.gitattributes` is parsed directly (a pattern without `/` matches the basename at any depth,
a pattern with `/` is anchored to the root, `*` does not cross `/`, `**` does). Macros, quoted
patterns and subdirectory `.gitattributes` files are not supported there and fail closed: the
file is not exempt. An explicit `-qs-generated` wins over `linguist-generated`. Every other
file stays subject to the limit. Do not raise `max_kb` in the personal `.quality-rules.json` for this.

The same mark also skips the marker, format, lint and deep steps for that file, so formatters
never rewrite generator output (which would make `tools/gen.py --check` fail). Syntax checks
and secret scanning (`gitleaks`, `qs-private-key`) still cover generated files.

The mark is a trust decision: it switches off format and lint for that file, so a change
to `.gitattributes` is reviewed like code (`/.gitattributes` has a CODEOWNERS entry).

## Levels

| Level | Runs | Typical use |
| --- | --- | --- |
| `off` | nothing | vendored or generated code |
| `syntax` | parsers only | legacy code you must not touch |
| `format` | + shebang/modeline + formatter | |
| `standard` | + linters (default) | |
| `strict` | + deep: type checkers, security, typos, complexity, editorconfig | new projects |

A language runs at its own `level`, else `QUALITY_LEVEL` from the environment, else the top-level
`level`. A tool's `level` is the minimum level at which that tool runs (for example
`"mypy": {"level": "standard"}` runs a deep tool at `standard`, as v1 did).

## Versions

`"version": "auto"` detects it on every commit from the project (pom.xml, build.gradle,
pyproject.toml, composer.json, go.mod, Cargo.toml, .ruby-version, CMakeLists.txt,
Package.swift, pubspec.yaml…) and records it in `detected_version`. A fixed value pins it.
Precedence: `version` in this file > legacy variable in `.git/hooks/quality-suite.env`
(`PMD_JAVA_VERSION`, `SQL_DIALECT`, `LUA_VERSION`, `RUST_EDITION`, `PHP_VERSION`,
`GO_VERSION`, `PYTHON_VERSION`, `QS_*_VERSION`) > detection > default. A legacy variable is
copied into `version` the first time the language is added.

What the version drives: PMD `--use-version`, Ruff `target-version` and the Python parser,
mypy `python_version`, PHPStan `phpVersion`, RuboCop `TargetRubyVersion`, rustfmt `--edition`,
golangci-lint `run.go`, StyLua `syntax` and luacheck `--std`, scalafmt dialect, SwiftFormat
`--swiftversion`, `dart format --language-version`, cppcheck `--std`, GHDL `--std`, the SQL
dialect of SQLFluff. A value you set in `rules` always wins over the version-derived one.

## How `rules` become native configuration

| Tool config | Strategy | Notes |
| --- | --- | --- |
| JSON/JSONC, YAML, TOML, INI, perltidy flags | base file **merged** with your rules | dicts merge, lists replace |
| Checkstyle | `{"Module": {"prop": "v"}}`, `false` removes, `true` adds | Checker-level modules handled |
| PMD | `{"category/java/x.xml": bool, "category/java/x.xml/Rule": false or {props}}` | |
| ESLint (`eslint.config.mjs`) | rules are an overlay on the image base | `$config` for extra config keys |
| PHP CS Fixer | `{"@PSR12": true, "rule": {...}}` merged into the base config | |
| flag-driven tools (shfmt, ShellCheck, cppcheck, gersemi…) | rules become CLI flags | `"-i": 2`, `"--severity": "warning"` |
| shared configs (Ruff, RuboCop, SQLFluff, djLint, markdownlint, vsg, groovy, dotenv) | the linter **inherits** the formatter's rules | set line length once |

Removing a key falls back to the image default; to switch a rule off, set it explicitly
(`false`, `null`, `"off"`, `"disable"`, whatever the tool uses).

## Identifying marks

`formatting.qs-marker.rules` holds the shebang (`"shebang": "#!/usr/bin/env bash"`,
`"always": true` for shell) or the modeline used for ambiguous extensions
(`"modeline": "% -*- mode: matlab -*-"`). Scripts get the shebang when they are executable
in git or have no extension; shell scripts always. The change is staged into the commit.

## Examples

```jsonc
// Python: 120 columns for formatter AND linter (the linter inherits it)
"python": { "formatting": { "ruff-format": { "rules": { "line-length": 120 } } } }

// Java: pin the language level and relax one Checkstyle limit
"java": { "version": "17", "analysis": { "checkstyle": { "rules": { "MethodLength": { "max": "120" } } } } }

// SQL: PostgreSQL instead of Oracle
"sql": { "version": "postgres" }

// XML: validate against a schema of the repository (v1 XML_SCHEMA)
"xml": { "analysis": { "xmllint-schema": { "rules": { "schema": "schemas/app.xsd" } } } }

// Dockerfile: try the opt-in formatter
"dockerfile": { "formatting": { "dockerfmt": { "enabled": true } } }

// Legacy module: syntax only
"perl": { "level": "syntax" }

// Map an extra extension to a language
"jsp": { "extensions": [".jspx2"] }

// Tests on push (precedence over .quality-tests)
"tests": { "commands": ["mvn -B -q test"], "autodetect": false }
```

## Where things are

| Path | What |
| --- | --- |
| `.quality-rules.json` | the rules (you edit this) |
| `.git/quality-suite/rules.applied.json` | snapshot of the last applied rules |
| `.git/quality-suite/generated/` | native configs generated from the rules |
| `.git/quality-suite/quality-suite.log` | per-file, per-tool SUCCESS/ERROR + rule changes |
| `.git/quality-suite/tests.txt` | test commands exported for the push hook |
| `schema/quality-rules.schema.json` | JSON Schema (completion, validation, defaults) |
