---
name: agent-orchestration
description: Use whenever the lead (main session) runs work with subagents - the atomic workflow (isolated branches per module, never stop, plan with the strongest model and delegate down to cheaper ones), how many agents run at once, the brief every developer and qa agent gets, push and integration rules, and how to resume agents after a usage-limit stop.
---

# Agent orchestration (lead only)

## The workflow (always)

- **Plan first, with the strongest model** (the lead). The hard work is the plan: split the
  spec into atomic tasks over dedicated modules and components, each with where to touch,
  what to change, which test proves it, and the dependencies between tasks.
- **Isolate.** One final branch per feature or module; the more isolated, the fewer conflicts.
  Many modules run in parallel. Conflicts that remain are unified by a human with the lead's help.
- **Delegate down the price ladder.** Design and planning: strongest model. Branch-sized
  features: mid-tier model (developer). Atomic, well-described tasks (one file or function,
  docs): cheapest model. QA once per batch, not per task.
- **Atomic commits**, pushed at once. The smaller the task, the cheaper the agent and the more
  of them can run at the same time.
- **Never stop.** When an agent finishes, start the next item of the plan; work with what is
  there and integrate continuously.

## When agents start

- Only after the human approved the spec (requirements and functionality). Then deploy **one
  developer per feature (final) branch**, respecting the phase dependencies of the spec.
- Run **a small number of agents at a time**, set by the human according to the usage budget
  (usage runs out fast). Critical path first: the item that blocks others, then the next
  phase, then later versions. Queue the rest, with the agent id, in the shared status file
  (for example `docs/<version>/STATUS.md`) and in the lead's memory.
- The lead creates the branches and pushes them; agents never create, integrate or rename
  branches.

## The brief (keep shared rules in one file and point to it)

Developer brief, every time:

1. The spec path and section, and "approved with defaults" if so.
2. The existing branch to `git checkout` in its worktree; the parent to rebase onto.
3. Only the files the spec gives to that branch; prefer new files; say which siblings run in
   parallel.
4. Gate with a stable image tag (`QUALITY_SUITE_IMAGE=<stable image tag>`). Never rebuild or
   retag shared images; use own tags only.
5. Atomic Conventional Commits, ASCII, subject <= 50 characters, no AI co-author, no
   `--no-verify`.
6. Push right after each commit, with a plain `git push origin <branch>`. Never force: if the
   push is refused because the parent moved, stop and report (the lead decides `git subir`).
7. Never `git integra`, `git merge`, `git pull` without `--rebase`, or push an ORIGINAL branch.
8. Doc comment on every function; English only.
9. Run the project's full test suite in a clean temporary directory (the commands are in
   AGENTS.md); read the results in full.
10. Finish with `git switch --detach` and a short report: acceptance criteria covered or not,
    commits, tests, what belongs to other branches.

QA brief: probe every acceptance criterion by hand, edge cases, regressions, doc comments,
duplication; the same full test run; read-only on production code (tests only, plain push);
verdict plus findings with severity and file:line. Checks owned by branches not yet
integrated are not findings.

## Loop

developer -> qa -> (findings: the same developer fixes on the same branch) -> qa again ->
reviewer for docs -> lead integrates. Record every finding in `dev_documents/`.

## Integration (lead)

Integrate from the main checkout only, where the real `.quality-rules.json` is. Check the
`"flow"` setting, run `git integra -m ... -m ...`, check there is one parent
(`git log -1 --format=%P`) and the expected trailers, then push. Before checking a branch
out, free it from the finished agent's worktree (`git -C <worktree> switch --detach`).

## Usage-limit stop and resume

- Before stopping: push every fast-forward branch; record per agent: id, branch, tip, dirty
  files, last step, in the shared status file.
- Resume with `SendMessage` to the same agent id ("limit reset, continue from where you
  stopped"); uncommitted work is still in its worktree. Resume in priority order, a few at a
  time.

## Never

- Perform an action an agent was denied (force push, hook bypass) on its behalf: ask the human.
- Let two agents edit the same file in parallel, or share one temporary directory or image tag.
