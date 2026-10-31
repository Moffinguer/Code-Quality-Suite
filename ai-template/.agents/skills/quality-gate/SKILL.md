---
name: quality-gate
description: Use after editing files, before committing, or when a commit or push was rejected by the code-quality-suite. Runs the gate on the files and explains how to fix each finding.
---

# Run and read the quality gate

- Run: `bash <SUITE>/scripts/qs-run.sh <file>...` (fix mode: formats in place, then reports).
  `--check` reports without changing anything.
- Output lines look like `[qs:<language>:<tool>] file:line: message`. The tool id tells you
  which rule set applies; the rules are in `.quality-rules.json` under
  `languages.<language>.<syntax|formatting|analysis>.<tool>.rules`.
- Fix the code, not the rule. Change a rule only when the human asks, and say why.
- Encoding errors: the file is not in the declared charset. Do not reconvert files you did not
  create; ask the human.
- Commit rejected for non-ASCII characters: rewrite the message without accents.
- Push rejected because the branch is behind its parent: `git subir`.
- Full log: `.git/quality-suite/quality-suite.log`.
