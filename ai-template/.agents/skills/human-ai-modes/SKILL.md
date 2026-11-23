---
name: human-ai-modes
description: >-
  Use at the start of every new feature or version: ask the human how it will be built -
  full-auto AI or shared with human developers - and plan the branches and hand-offs for
  that mode
---

# Human-AI modes

## The question

For every new feature or version the lead ASKS the human before planning:

- Mode A, full-auto: agents write all code and tests.
- Mode B, shared: the human says which features the AI builds and which features
  human developers build.

Never assume a mode. Wait for the answer and record it in the plan.

## Both modes

- The lead always creates and pushes the whole branch structure first, so humans
  and agents work on the same tree.
- The lead lists, in the plan:
  - pain points: parts of the code that are fragile, slow or often broken;
  - test cases worth testing by humans: manual, exploratory or judgment-based;
  - business situations where the change can break: real cases the tests may miss.

## Mode A steps

1. Lead creates the parent branch and one final branch per feature.
2. Lead pushes every branch to origin at once.
3. Lead gives each developer agent one task on its own final branch.
4. QA agent runs the quality gate and regression tests on each branch.
5. Reviewer agent reviews each diff against the project standards and quality rules.
6. Lead integrates each branch after QA and reviewer agree.
7. Human approves the merge into develop.

## Mode B steps

1. Lead names each human branch in the plan, with its owner and its scope.
2. Lead creates and pushes human branches too, so the tree stays shared.
3. Agents never touch human branches; they only work on AI branches.
4. Humans push their commits to their own branches.
5. QA agent runs the gate and regression tests on AI and human branches alike.
6. Lead integrates both kinds the same way after QA passes.
7. Human approves the merge into develop.

## Report template

| Feature | Owner (AI/human) | Branch | Risks | Human test cases |
| --- | --- | --- | --- | --- |
| <name> | AI or human | <branch> | <business breaks> | <cases> |
