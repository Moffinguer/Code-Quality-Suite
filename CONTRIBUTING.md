# Contributing

<!-- Convention: GitHub guidelines for repository contributors (https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/setting-guidelines-for-repository-contributors). -->

Thanks for improving the suite. Read the [code of conduct](CODE_OF_CONDUCT.md) first; the
environment and the tests are in [DEVELOPMENT.md](DEVELOPMENT.md).

## The rules

1. **Everything stays local and offline at check time.** No servers, no proprietary tools; a tool
   that needs the network belongs in the image build, never in a check.
2. **Pin versions.** A new tool comes with its version (and `sha256=` when known) in
   `registry/src`; `python3 tools/gen.py` regenerates the generated files.
3. **The container stays hardened**: `--network none --read-only --cap-drop ALL
   --security-opt no-new-privileges`.
4. **Windows matters.** Every script works in Git Bash: no `jq`, no GNU-only options without a
   fallback, host paths through `qs_hostpath`.
5. **Tests prove it.** A change in behaviour comes with a check in `tests/hooks/run.sh` or
   `tests/unit/test_engine.py`, and every test passes:

   ```bash
   python3 tests/unit/test_engine.py && bash tests/hooks/run.sh && python3 tools/gen.py --check
   ```

6. **English** in code, comments and documentation; minimal comments, `why:` for decisions
   ([docs/CODE_STYLE.md](docs/CODE_STYLE.md)).
7. **UTF-8** files, LF line endings.

## Commits

Conventional Commits, ASCII only, subject up to 50 characters:

```text
feat(engine): detect mojibake in staged files
fix(hooks): keep unstaged edits on a failed commit
docs: group the install guides in INSTALL.md
```

### Accepted types

The default `commit.types` of the engine (`engine/policy.py`); a project may change them in
`.quality-rules.json`. The last column is the group of the changelog entry
(`engine/changelog.py`); "omitted" types never reach the changelog.

| Type | Meaning | Changelog group |
| --- | --- | --- |
| `feat` | a new feature | Added |
| `fix` | a bug fix | Fixed |
| `docs` | documentation only | omitted |
| `style` | formatting, no change in behaviour | omitted |
| `refactor` | code change that neither fixes nor adds | Changed |
| `perf` | performance improvement | Changed |
| `test` | add or fix tests | omitted |
| `build` | build system, dependencies, image | Changed |
| `ci` | CI configuration | omitted |
| `chore` | maintenance, tooling | omitted |
| `revert` | undo an earlier commit | Changed |

### Rules

- ASCII only (write "anadir validacion", not accents or n-tilde) and a subject of at most 50
  characters.
- A `!` after the type or scope (`feat(api)!: drop the old flag`), or a `BREAKING CHANGE:`
  footer, marks a breaking change.
- Trailers: `Files:` lists the files of the commit (the hook adds it), and `Norms: <ids>` lists
  the norms applied, when the project has a norms map.

One logical change per commit. A user-visible change gets a line in [CHANGELOG.md](CHANGELOG.md)
(Common Changelog: imperative, with a reference) in the same change.

## Proposing a change

Describe the problem and the change, attach the test output, and say how you tried it on Windows
when it touches the hooks or the scripts. The owners in [CODEOWNERS](CODEOWNERS) review it.
