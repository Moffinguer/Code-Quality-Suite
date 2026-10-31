# Code & documentation style

Minimal comments, English only, easy to retrieve with `grep`.

## Principles

- Comment only when the code does NOT explain itself. Names and structure come
  first; comments are the exception, not the rule.
- Explain the WHY (non-obvious decisions), never narrate WHAT the code already says.
- Everything in English: comments, docstrings, log messages, docs.

## Greppable anchors

| Anchor | Meaning | Find with |
| -------- | --------- | ----------- |
| First comment line of a file | one-line purpose of the file | `grep -rn '^# [a-z-]*\.'` |
| `why:` | rationale for a non-obvious decision | `grep -rn 'why:'` |
| Python docstrings | module/function contract | `grep -rn 'def \|"""'` |

## Per language

- **Bash**: file header = one line `# <name> - <purpose>`. A function gets a single
  line above it ONLY if its name is not enough. Non-obvious choices: `# why: ...`.
- **Python**: module docstring + docstrings on non-trivial functions. No inline
  narration.
- **SQL**: a one-line `--` comment above a table only if its purpose is not obvious.
- **Dockerfile/YAML**: one-line section headers; `# why:` for non-obvious steps.
