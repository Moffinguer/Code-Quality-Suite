# Logging (normalized, greppable)

Every tool and hook message goes through one structured format so it can be detected
and filtered later. Implemented in `log-lib.sh` (git hooks, host side) and
`engine/qslog.py` (the analysis engine in the container); both write the same format to
the same file.

## Format

Text (default):

```text
<ts> <LEVEL> comp=<component> [file=<f>] [action=<a>] [status=<SUCCESS|ERROR>] msg="..."
```

JSON (one object per line) with `QUALITY_LOG_FORMAT=json`.

When a step fails, the tool's own output is printed with each line attributed as
`[qs:<language>:<tool>] <line>`; successful steps stay quiet (their result is in the log).

## Settings (env, e.g. in `.git/hooks/quality-suite.env`)

| Var | Default | Meaning |
| ----- | --------- | --------- |
| `QUALITY_LOG_LEVEL` | INFO | DEBUG / INFO / WARN / ERROR |
| `QUALITY_LOG_FORMAT` | text | text or json |
| `QUALITY_LOG_CONSOLE` | WARN | what is also echoed on the terminal |
| `QUALITY_LOG_FILE` | `.git/quality-suite/quality-suite.log` | file to also append to |

## What gets logged

- **Engine run**: `comp=engine` run start/end; for every file and every step a line
  `comp=<language> file=<f> action=<tool> status=SUCCESS|ERROR` (e.g. "format by prettier",
  "lint by checkstyle failed"); `status=SKIP` when a tool is missing or cannot run offline.
- **Rules file**: `comp=rules` when the file is created, a language is added (with the
  version source), each change (`added|modified|removed <path>: old -> new`) and the
  regeneration of native configs.
- **Identifying marks**: `comp=marker action=fix` when a shebang or modeline is added.
- **Installer** (image build output): `[qs-install] INFO|WARN|ERROR …`, including the
  sha256 of every unpinned download.
- **Hooks**: `comp=pre-commit` / `comp=pre-push` — a line per file
  (`msg="staged"/"pushing" file=Y action=fix/check`) and a final run result.
- **Tests**: `comp=tests` — one result line per command.

## Reviewing

```text
grep 'status=ERROR' .git/quality-suite/quality-suite.log     # everything that failed
grep 'comp=python'  .git/quality-suite/quality-suite.log     # one tool/language
grep 'comp=pre-push' .git/quality-suite/quality-suite.log    # push history
grep 'comp=rules'    .git/quality-suite/quality-suite.log    # every change to the rules file
```
