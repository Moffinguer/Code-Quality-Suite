# Pinned versions

Every tool, runtime and package the image installs is pinned, so two machines (or the same
machine a month later) analyse code with exactly the same tools.

| What | Where it is pinned | How |
| --- | --- | --- |
| Tools (npm, pip, GitHub/URL releases, jars, phars) | `registry/src/*.py` | exact versions: `name@1.2.3`, `name==1.2.3`, release tag |
| Runtimes (Node, Go, Rust, Dart, Julia, PowerShell) | `registry/src/base.py` (`NODE_V`, `GO_V`...) | exact version; downloads checked against the vendor's SHA-256 where published |
| apt packages (Ubuntu 24.04) | `Dockerfile` `ARG QS_APT_SNAPSHOT` | the Ubuntu archive as it was on that date (snapshot.ubuntu.com); `QS_APT_SNAPSHOT=off` uses the live archive |
| Base image | `base-image.lock` (optional) | Ubuntu digest; create it with `scripts/build-image.sh --pin <suite-dir>` |

Rule used when choosing versions: the latest stable release published by the project
(no alpha/beta/rc/dev/nightly), on the LTS line where the community has one (Node 24 LTS,
OpenJDK 21, .NET 10), unless a dependency forbids it (see "Held" below).

If the snapshot server is unreachable (corporate proxy), the build warns and falls back to the
live archive; the installed versions are then the current Ubuntu updates.

## Checking for updates

```bash
python3 tools/check-versions.py                  # report: ok | update | held
python3 tools/check-versions.py --verify-assets  # also check every release asset still downloads
python3 tools/check-versions.py --only npm,pip --json
```

It reads npm and PyPI and lists GitHub tags with `git ls-remote` (no token, no API rate
limit). For each `update` it also checks that the new release really ships the assets we
download. To bump: edit the version in `registry/src/`, run `python3 tools/gen.py`, the tests
(`python3 -m unittest discover -s tests/unit`, `python3 tests/noclash/run.py`,
`bash tests/hooks/run.sh`), then rebuild with `QS_REBUILD=1`.

## Held back on purpose

| Package | Pinned | Newer | Why |
| --- | --- | --- | --- |
| typescript | 6.0.x | 7.x | typescript-eslint 8 supports `<6.1`; 7.x is the native (Go) port without the JS API |
| graphql | 16.x | 17.x | graphql-schema-linter and @graphql-eslint require `^16` |
| regal | v0.43.0 | v2.2.x tags | those tags publish no release binaries |
| OpenJDK | 21 | 25 | runs every JVM tool here; some (detekt) are not yet certified on 25 |

## Changes in 2.1

- dotenv-linter 4: `check` subcommand, `--ignore-checks` (the old `--skip` in a rules file still
  works), update check disabled (`DOTENV_LINTER_SKIP_UPDATES=1`).
- eslint-plugin-astro / astro-eslint-parser 3.x, .NET SDK 10, Node 24.21.0, Go 1.27.2,
  Rust 1.99.0, Dart 3.13.5, Julia 1.13.1, and patch updates (see `git log`).
