# Other quality-gate tools

What else exists to guarantee quality before code lands, how it relates to this suite, and
what is deliberately left out. Rule of thumb: **the commit hook stays fast, local and
offline; anything that needs a database download, a server or the whole project build
belongs to the push heavy stage or to CI.**

## Recommended next steps (for a Java/JSP/Maven context)

1. **CI as the non-skippable gate**: `scripts/ci-check.sh` on every pull request, with the
   rules file committed (hooks can be bypassed with `--no-verify`, CI cannot).
2. **Dependency vulnerabilities in CI**: OSV-Scanner or Trivy (`trivy fs`, SBOM + CVEs).
   Both need a vulnerability database (downloaded daily), so they do not fit an offline hook.
3. **Coverage on changed lines**: JaCoCo in `mvn verify` (heavy stage) + `diff-cover` to fail
   only when new code is untested.
4. **Architecture rules as tests**: ArchUnit (layers, cycles, naming) runs with `mvn test`.
5. **Security patterns**: Semgrep CE with rules vendored in the repository (no registry
   download), at `strict` or in CI.
6. **Duplicates**: PMD CPD or jscpd in CI (they need the whole code base to be useful).
7. **PR feedback**: reviewdog posts any linter output as review comments.

## Hook frameworks

| Tool | What | Relation to this suite |
| --- | --- | --- |
| pre-commit | Python framework, per-repo `.pre-commit-config.yaml`, tool envs per hook | alternative runner; this suite already provides isolation (Docker) and the single rules file |
| lefthook | fast Go runner, parallel jobs, monorepo friendly | can call the suite's hooks as one job |
| husky + lint-staged | Node ecosystem staple | only JS-centric repos; can call the suite |

## Aggregators (many linters in one)

| Tool | Notes |
| --- | --- |
| MegaLinter | Docker, 100+ linters, CI-oriented; huge images. Its descriptors informed this registry |
| super-linter | GitHub's aggregator; CI only |
| Trunk Check | hermetic local runner with caching; free CLI, cloud features optional |
| qlty | open-source CLI (successor of Code Climate's engine), local plugins |
| treefmt | one command for many formatters (Nix-centric) |

This suite differs by: per-language on-demand install, one rules file with base rules,
no-clash levels, identifying marks, and offline execution.

## Static analysis beyond per-language linters

| Tool | Local/offline | Status here |
| --- | --- | --- |
| Semgrep CE | yes with local rules | candidate for `strict` (rules must be vendored) |
| ast-grep | yes | candidate for custom structural rules |
| PMD CPD, jscpd | yes | candidates (CI) |
| Lizard | yes | **included** (strict) |
| SonarQube / SonarCloud, Codacy, DeepSource, Qodana | server/cloud | excluded for now |
| CodeQL | CLI local, licence limits use on closed-source code | excluded |
| Snyk | cloud | excluded |

## Secrets and supply chain

| Tool | Notes |
| --- | --- |
| Gitleaks | **included** (standard), rules built in |
| TruffleHog, detect-secrets | alternatives; TruffleHog's verification calls the network |
| OSV-Scanner, Trivy, Grype | vulnerability DB downloads: CI |
| Syft | SBOM generation: CI/release |
| OWASP Dependency-Check | NVD API key + DB: CI |
| REUSE (`reuse lint`) | licence headers / SPDX compliance: candidate |

## Commit and review hygiene

| Tool | Notes |
| --- | --- |
| commit-msg hook (this suite) | Conventional Commits, subject length |
| commitlint, gitlint | alternatives with richer rule sets |
| reviewdog | linter output as PR comments (any CI) |
| Danger | PR rules (size, changelog, labels) |
| diff-cover | coverage/quality on the diff only |
