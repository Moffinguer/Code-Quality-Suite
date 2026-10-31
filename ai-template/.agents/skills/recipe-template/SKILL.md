---
name: recipe-template
description: Template for the team's recipe book. Copy this folder to create a new recipe (a repeatable procedure such as "create this document with this format", "run these validations", "check these norms").
disable-model-invocation: true
---

# Recipe: <name>

When to use: <one sentence: the trigger>.
Inputs: <what the agent needs>.
Output: <file(s), format, location>.

Steps:
1. <step, with the exact command or template to use>
2. ...

Checks before finishing:
- [ ] <validation 1> (command)
- [ ] norms: <ids>
- [ ] quality gate clean on the produced files

Copy this folder to `.agents/skills/recipe-<name>/`, rename `name:` and write a precise
`description:` (agents choose skills by it), remove `disable-model-invocation`, then run
`bash <SUITE>/scripts/ai-sync.sh`.
