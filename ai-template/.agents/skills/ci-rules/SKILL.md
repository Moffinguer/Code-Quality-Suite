---
name: ci-rules
description: Use when a project needs the tracked CI rules file for its forge (GitHub now, others later) - creates it from the template or adapts it to the project's root rules file, never weakening a default without a why key, and validates it with the policy validation the hooks use.
---

# CI rules file

The root `.quality-rules.json` is personal and git-ignored; CI (a clean clone) needs a tracked
file. Set `QS_RULES_FILE` to it in the pipeline. The file lives at the forge path below.

## Forges

| Forge | Tracked rules file | State |
| --- | --- | --- |
| GitHub | `.github/quality-rules.json` | supported (`templates/github.quality-rules.json`) |
| GitLab | `.gitlab/quality-rules.json` | later, no file created |
| Azure DevOps | `.azuredevops/quality-rules.json` | later, no file created |

## Steps

1. Copy the forge template to its path; if the file exists, edit it in place.
2. Read the root `.quality-rules.json` and carry over only the project-wide keys:
   `branches.flow`, `branches.model`, `branches.levels`, `branches.mainline`,
   `branches.protected`, `branches.special`, `commit.charset`, `commit.types`,
   `commit.subject_max`, `commit.files`. Never copy personal values (paths, user names,
   tool commands, `QUALITY_*` settings, anything that holds for one machine only).
3. Add the forge keys the template shows: `branches.allow` lists regexes of bot branches
   (GitHub: `^dependabot/`) that skip the branch-name rules.
4. Never weaken a default (lower a level, set a check to `off` or `warn`, widen a list) unless a
   sibling `why` key in the same object gives the reason.
5. Validate with the same code the hooks use (`policy.validate` in `engine/policy.py`; it
   returns a list of messages, empty when valid) and fix every message.
6. Commit it alone: `ci(rules): add <forge> rules file`, ASCII, body says why each key differs
   from the defaults.

## Rules

- Keep the file small: only keys that differ from `policy.DEFAULTS` belong in it.
- Do not edit the template for one project: copy it, then adapt the copy.
- A forge marked "later" gets no file until its template exists.
