---
name: agent-orchestration
description: Use whenever the lead (main session) runs work with subagents - the atomic workflow (isolated branches per module, never stop, plan with the strongest model and delegate down to cheaper ones), how many agents run at once, the check before a wave, the brief and report every developer and qa agent uses, push and integration rules, and how to resume agents after a usage-limit stop.
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

## Before a wave

- Only after the human approved the spec (requirements and functionality). Then deploy **one
  developer per feature (final) branch**, respecting the phase dependencies of the spec.
- Each file has exactly one owning final branch per wave. A second branch that needs the file
  waits for the next wave or asks the owner through the spec.
- Check overlap across sibling branches and versions before starting: `git diff --name-only
  <ORIGINAL>...<branch>` for each sibling must show no shared file. A file touched by two
  versions has one owner version; the other rebases after it. Independent version trees run
  concurrently and are joined with `git combinar` (human only).
- Run **a small number of agents at a time**, set by the human according to the usage budget
  (usage runs out fast). Critical path first: the item that blocks others, then the next
  phase, then later versions. Queue the rest, with the agent id, in the shared status file
  (for example `docs/<version>/STATUS.md`) and in the lead's memory.
- Launch all independent developers of a wave in one message, each in its own worktree. QA
  runs in parallel with them.
- The lead creates the branches and pushes them; agents never create, integrate or rename
  branches.

## The brief (task template)

Every developer and qa agent gets a brief with these fields, in this order:

1. **Goal**: one or two sentences, and the spec path and section ("approved with defaults" if so).
2. **Branch**: the existing final branch to `git checkout` in its worktree, and the parent to
   rebase onto.
3. **Owned files (allow-list)**: the only files this agent may change. Prefer new files.
4. **Forbidden files**: siblings' files and shared configuration, named explicitly.
5. **AC ids**: the acceptance criteria to cover.
6. **Paths**: absolute paths of the shared `dev_documents/` and `docs/<ot>/` folders.
7. **Commands**: the gate (`QUALITY_SUITE_IMAGE=<stable image tag>`) and the project's full
   test suite (commands in AGENTS.md), run in a clean temporary directory.
8. **Stop conditions**: "ask instead of guessing"; stop and report on a spec gap, a refused
   push, or a file outside the allow-list.
9. **Report format**: see below.

Rules that apply to every developer:

- Gate with a stable image tag. Never rebuild or retag shared images; use own tags only.
- Atomic Conventional Commits, ASCII, subject <= 50 characters, no AI co-author, no
  `--no-verify`. Commit WIP at each AC (see Resumability).
- Push right after each commit, with a plain `git push origin <branch>`. Never force: if the
  push is refused because the parent moved, stop and report (the lead decides `git subir`).
- Never `git integra`, `git merge`, `git pull` without `--rebase`, or push an ORIGINAL branch.
- Doc comment on every function; English only.
- Finish with `git switch --detach`.

QA brief: probe every acceptance criterion by hand, edge cases, regressions, doc comments,
duplication; the same full test run; read-only on production code (tests only, plain push);
verdict plus findings with severity and file:line. Checks owned by branches not yet
integrated are not findings.

## The report (developer, qa, reviewer)

Keep it under 200 words:

- Branch and tip sha.
- AC table: id, pass or fail, evidence (test name, command output line or file:line).
- Files touched outside the allow-list: must be **none**; list them otherwise.
- Open issues, and what belongs to other branches.
- Commits and tests run.

## Loop

developer -> qa -> (findings: the same developer fixes on the same branch) -> qa again ->
reviewer for docs -> lead integrates. Record every finding in `dev_documents/`.

## Integration (lead)

Integrate from the main checkout only, where the real `.quality-rules.json` is. Check the
`"flow"` setting, run `git integra -m ... -m ...`, check there is one parent
(`git log -1 --format=%P`) and the expected trailers, then push. Before checking a branch
out, free it from the finished agent's worktree (`git -C <worktree> switch --detach`).

## Resumability and usage-limit stop

- Developers commit WIP at each AC and keep `docs/<ot>/<leaf>.md` with progress and the next
  step, so a new agent can resume a stopped one from that file.
- Before stopping the lead: push every fast-forward branch; record per agent: id, branch, tip,
  dirty files, last step, in the shared status file.
- Resume with `SendMessage` to the same agent id ("limit reset, continue from where you
  stopped"), or start a new agent that reads `docs/<ot>/<leaf>.md`; uncommitted work is still in
  its worktree. Resume in priority order, a few at a time.

## Never

- Perform an action an agent was denied (force push, hook bypass) on its behalf: ask the human.
- Let two agents edit the same file in parallel, or share one temporary directory or image tag.
