# Repository files - convention, generation and checks

Every repository installed with the suite gets the standard files below. `git repo-files`
creates the ones that are missing, filled with what the repository already knows; it never
overwrites a file you have. The installer runs it once (`QS_REPO_FILES=0` skips it). The quality
gate validates the files that have a format when they change.

```bash
git repo-files -n                       # what would be created
git repo-files                          # create the missing ones (review and commit them)
git repo-files --force CONTRIBUTORS.md  # regenerate one from the current history
git add -A && git commit -m "docs: repository files"
```

Parts only the team can write are marked `<!-- qs:fill: what to write -->` (`# qs:fill` in
`CODEOWNERS` and `AUTHORS`). The gate warns, without blocking, while a marker stays in a
committed file. A file found in `docs/` or `.github/` (or with another case, `readme.md`)
counts as present.

## The files

| File | Convention | Generated from | Checked by the gate |
| --- | --- | --- | --- |
| `README.md` | [Google README style guide](https://google.github.io/styleguide/docguide/READMEs.html), [GitHub READMEs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes) | `pom.xml` (name, description, Java, modules, packaging, license), origin, build commands | version badge = last release in `CHANGELOG.md` (error); no badge (warning) |
| `CHANGELOG.md` | [Common Changelog](https://common-changelog.org/) | the last 10 release tags (`v1.2.3` or `1.2.3`) and the history between them | title, `## [x.y.z] - YYYY-MM-DD`, semver, real dates, newest first, no duplicates, no `Unreleased`, groups Changed/Added/Removed/Fixed in order, one-line list items, link definitions (errors); changes without references, text before the first release (warnings) |
| `VERSION` | [Semantic Versioning 2.0.0](https://semver.org/) (the meaning; the file is one line) | `pom.xml` version (without `-SNAPSHOT`), `package.json`, the last tag, else `0.1.0` | one line, semver, = the version of the branch, = `pom.xml` (or `-SNAPSHOT`), not older than the last release (errors) |
| `CONTRIBUTING.md` | [GitHub: contributor guidelines](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/setting-guidelines-for-repository-contributors) | the branch model, commit rules and encoding rules of the suite | `qs:fill` markers |
| `CODE_OF_CONDUCT.md` | [Contributor Covenant](https://www.contributor-covenant.org/) 2.1, adopted by reference | - | `qs:fill` markers (the contact) |
| `LICENSE` | [SPDX License List](https://spdx.org/licenses/), [REUSE](https://reuse.software/spec/) | `pom.xml` `<licenses>`; otherwise a note (Spanish public administrations usually publish under EUPL-1.2) | empty (error); `[year]`, `[fullname]` placeholders (warning) |
| `AUTHORS` | [GNU Coding Standards](https://www.gnu.org/prep/standards/) | `git log`: `Name <e-mail>`, most commits first (bots left out) | - |
| `CONTRIBUTORS.md` | informal | `git log`: name, commits, years | - |
| `CITATION.cff` | [Citation File Format 1.2.0](https://citation-file-format.github.io/) | name, description, authors, last release and its date, repository URL, SPDX license | YAML, `cff-version`, `message`, `title`, `authors` (each with `family-names` or `name`), `date-released` format (errors); version = last release (warning) |
| `SECURITY.md` | [GitHub: security policy](https://docs.github.com/en/code-security/getting-started/adding-a-security-policy-to-your-repository) | the supported `MAJOR.MINOR.x` from the last release | `qs:fill` markers (contact, response time) |
| `SUPPORT.md` | [GitHub: support resources](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-file-for-support-resources) | - | `qs:fill` markers |
| `CODEOWNERS` | [GitHub](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners) / GitLab code owners (root, `.github/`, `docs/` or `.gitlab/`) | the two most active committers per top folder in the last two years (e-mails) | owners are `@user`, `@org/team` or e-mails (error); a path without owner (warning) |
| `MAINTAINERS.md` | informal; [CHAOSS](https://chaoss.community/) governance as a model | the most active committers of the last year | `qs:fill` markers |
| `ROADMAP.md` | informal; [GitLab direction](https://about.gitlab.com/direction/) as a model | last release, version under development, version trees in progress, branches set aside (`unmerged/`) | `qs:fill` markers |
| `FAQ.md` | informal, questions by topic | build, encoding, commit messages, version, branch tree | `qs:fill` markers |
| `INSTALL.md` | [GNU Coding Standards](https://www.gnu.org/prep/standards/) | requirements (JDK, Maven / wrapper), build and test commands, artifacts per module | `qs:fill` markers |
| `ARCHITECTURE.md` | [arc42](https://arc42.org/) (shortened), [C4 model](https://c4model.com/) for diagrams | modules (artifact, packaging, description), frameworks seen in `pom.xml` | `qs:fill` markers |
| `API.md` | [OpenAPI](https://spec.openapis.org/oas/latest.html), [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110) | OpenAPI files (`openapi*.yaml/json`, `swagger*`) and endpoints of `@GetMapping`... (Spring) and `@Path` (JAX-RS) | `qs:fill` markers |
| `DEVELOPMENT.md` | [contributing.md](https://contributing.md/) guides | requirements, VS Code UTF-8 settings, hooks, build, daily flow, release commands | `qs:fill` markers |

Each generated Markdown file starts with a comment naming its convention, so the next person
knows where the structure comes from.

## Internal convention (what each file must have)

| File | Required | Mandatory sections |
| --- | --- | --- |
| `README.md` | always | title, version badge, what it is, requirements, quick start (copy-paste), documentation links, license |
| `CHANGELOG.md` | always | one entry per release (written by `git release`) |
| `VERSION` | always | the version under development |
| `CONTRIBUTING.md` | always | branches, commits, review |
| `CODE_OF_CONDUCT.md` | always | adoption, reporting contact |
| `LICENSE` | always | the full license text |
| `SECURITY.md` | always | supported versions, how to report, response time |
| `CODEOWNERS` | when reviews are required on the platform | an owner for `*` |
| `INSTALL.md`, `DEVELOPMENT.md` | when the README quick start is not enough | requirements, build, deploy / daily flow |
| `ARCHITECTURE.md` | applications with more than one module or external systems | goals, constraints, building blocks, decisions |
| `API.md` | when other systems call it | where the contract is (OpenAPI), conventions |
| `AUTHORS`, `CONTRIBUTORS.md`, `MAINTAINERS.md`, `CITATION.cff`, `ROADMAP.md`, `FAQ.md`, `SUPPORT.md` | recommended | as generated |

## Versions in these files

`git release` keeps them in step with the version tree: `VERSION` and `pom.xml` (version
commit), `CHANGELOG.md` (entry), the README badge and `CITATION.cff` (`version`,
`date-released`). See `docs/GIT-WORKFLOW.md`.
