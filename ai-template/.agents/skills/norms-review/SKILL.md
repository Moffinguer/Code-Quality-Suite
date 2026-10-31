---
name: norms-review
description: Use when reviewing a diff, a pull request or a finished task in a Junta de Andalucia project. Checks it against the norms map, the quality gate and the recipe that produced it.
---

# Review against the norms

1. Get the diff (`git diff <parent>...HEAD`) and the task/spec it implements.
2. Run the `jda-norms` skill for the touched areas; build the checklist.
3. Run the gate in check mode on the changed files: `bash <SUITE>/scripts/qs-run.sh --check <files>`.
4. Review: correctness against the spec, each norm in the checklist, security (input validation,
   output encoding in JSP, SQL binds in PL/SQL and JDBC), error handling, tests, documentation.
5. Report as a table: finding, file:line, norm id or rule, severity (blocker | major | minor),
   suggested fix. No praise padding; say "no findings" when there are none.
6. Blockers go back to the developer; anything you could not verify goes to the human.
