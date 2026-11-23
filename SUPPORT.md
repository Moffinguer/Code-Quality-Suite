# Support

<!-- Convention: GitHub support resources (https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-file-for-support-resources). -->

## Help yourself first

| Problem | Look at |
| --- | --- |
| a message of a hook | [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md), [FAQ.md](FAQ.md) |
| install, update | [INSTALL.md](INSTALL.md), section 10 |
| rules, encoding, commit messages | [docs/QUALITY-RULES.md](docs/QUALITY-RULES.md) |
| branches, versions, releases | [docs/GIT-WORKFLOW.md](docs/GIT-WORKFLOW.md) |
| AI agents and the gateway | [docs/AI-SETUP.md](docs/AI-SETUP.md), [docs/AI-DEMO.md](docs/AI-DEMO.md) |

## What to collect before asking

```bash
suite="$(sed -n 's/^QUALITY_SUITE_DIR="\(.*\)"/\1/p' "$(git rev-parse --git-path hooks)/quality-suite.env")"
cat "$suite/VERSION"                                   # suite version
git actualizar-suite --status                          # image, languages, repositories
tail -n 50 .git/quality-suite/quality-suite.log        # what the gate did
tail -n 50 ~/.config/code-quality-suite/install.log    # the last tools install
QUALITY_LOG_LEVEL=DEBUG git commit                     # the failing commit, with every detail
```

Remove passwords, keys and personal data from logs before sending them.

## Where to ask

Write to the maintainer listed in [MAINTAINERS.md](MAINTAINERS.md), or open an issue in the [GitHub Issues](https://github.com/Moffinguer/Code-Quality-Suite/issues) of the repository. Security problems: [SECURITY.md](SECURITY.md) only.
