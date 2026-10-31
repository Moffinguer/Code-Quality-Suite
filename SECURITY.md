# Security policy

<!-- Convention: GitHub security policy (https://docs.github.com/en/code-security/getting-started/adding-a-security-policy-to-your-repository). -->

## Supported versions

| Version | Supported |
| --- | --- |
| 2.6.x | yes |
| older | no: update with `git actualizar-suite` ([INSTALL.md](INSTALL.md)) |

## Reporting a vulnerability

Do not open a public issue or publish details. Write to the maintainer listed in
[MAINTAINERS.md](MAINTAINERS.md) with the suite version (`cat VERSION`), the steps to reproduce,
and the impact you expect. You get an answer within <!-- qs:fill: response time, e.g. 5 working days -->,
and we agree the date of the fix and of the disclosure.

## How the suite protects your code

| Area | Measure |
| --- | --- |
| Analysis container | `--network none --read-only --cap-drop ALL --security-opt no-new-privileges --tmpfs /tmp`, a throw-away container per check (`--rm`), the host user on Linux |
| Repository access | the work tree read-write only during a commit (formatting); the object store read-only; a push checks an exported copy |
| Network | only at image build, when a language is installed for the first time; checks are offline |
| Supply chain | every tool and runtime pinned to a version, apt from a dated Ubuntu snapshot, base image digest lock, `sha256=` pins where known; `tools/check-versions.py` reviews updates |
| Secrets | the gate blocks private keys (built-in) and known secret formats (Gitleaks); no secret goes into an image or a Dockerfile |
| AI gateway | keys only in `ai-stack/.env` (never committed); LiteLLM pinned to a reviewed tag (PyPI 1.82.7 and 1.82.8 were compromised) |

## Rules for regulated code (Junta de Andalucía)

- Regulated code never goes to free tiers or any service that trains on prompts: only local
  models (`role-local`, Ollama) or paid endpoints that do not train on them.
- A Claude subscription is used only inside the official Claude Code client.
- Free tiers and the AI demo (`LITELLM_CONFIG=demo.yaml`) are for public or invented code only.
- Never use leaked or public API keys.
