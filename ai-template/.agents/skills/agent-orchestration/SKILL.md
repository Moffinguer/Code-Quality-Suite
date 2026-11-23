---
name: agent-orchestration
description: >
  Use whenever the lead (main session) runs work with subagents - the atomic workflow (isolated
  branches per module, never stop, plan with the strongest model and delegate down to cheaper
  ones), how many agents run at once, the check before a wave, the brief and report every
  developer and qa agent uses, worktree confinement, push and integration rules, rebases and
  conflicts, helper branches, and how to resume agents after a usage-limit stop. Who may do what
  with branches is in team-flow.
---

# Agent orchestration (lead only)

The roles, the step order and the branch permission matrix are in `team-flow`; the branch
model is `branch-workflow`; alias syntax is `git-commands`. This skill is how the lead runs
many agents at once.

## The workflow (always)

- **Plan first, with the strongest model** (the lead). The hard work is the plan: split the
  spec into atomic tasks over dedicated modules and components, each with where to touch,
  what to change, which test proves it, and the dependencies between tasks.
- **Isolate.** One final branch per feature or module; the more isolated, the fewer conflicts.
  The git aliases (`git es`, `git nr`, `git integra`, `git subir`, `git testing`) exist for
  this: many modules in parallel, and features moved between places. Conflicts that remain are
  unified by a human with the lead's help.
- **Delegate down the price ladder.** Design and planning: strongest model. Branch-sized
  features: mid-tier model (developer). Atomic, well-described tasks (one file or function,
  docs): cheapest model (intern). QA once per batch, not per task.
- **Atomic commits**, pushed at once. The smaller the task, the cheaper the agent and the more
  of them can run at the same time.
- **Never stop.** When an agent finishes, start the next item of the plan; work with what is
  there and integrate continuously towards the integration branch.

## Before a wave

- Only after the human approved the spec (requirements and functionality). Then deploy **one
  developer per feature (final) branch**, respecting the phase dependencies of the spec.
- Each file has exactly one owning final branch per wave. A second branch that needs the file
  waits for the next wave or asks the owner through the spec.
- Check overlap across sibling branches and versions before starting: `git diff --name-only
  <ORIGINAL>...<branch>` for each sibling must show no shared file. A file touched by two
  versions has one owner version; the other rebases after it. Independent version trees run
  concurrently and are joined with `git combinar` (human only).
- Run **at most 3-4 agents at a time by default** (the human may raise it; usage runs out
  fast). Critical path first: the item that blocks
  others, then the next phase, then later versions. Queue the rest, with the agent id, in the
  shared status file (for example `docs/<version-or-ot>/STATUS.md`) and in the lead's memory.
- Launch all independent developers of a wave in one message, each in its own worktree. QA
  runs in parallel with them.
- The lead creates the branches (`git es` / `git nr`) and pushes them; agents never create,
  integrate or rename branches. Every branch follows the naming model of `branch-workflow`,
  even a local-only one; a name outside the model is a defect.

## The brief (task template)

Every developer and qa agent gets a brief with these fields, in this order:

1. **Goal**: one or two sentences, and the spec path and section ("approved with defaults" if
   so).
2. **Branch**: the existing final branch it works on, and the parent to rebase onto.
3. **Owned files (allow-list)**: the only files this agent may change. Prefer new files; say
   which sibling branches run in parallel.
4. **Forbidden files**: siblings' files and shared configuration, named explicitly.
5. **AC ids**: the acceptance criteria to cover.
6. **Paths**: absolute paths of the shared `dev_documents/` and `docs/<ot>/` folders. Ignored
   folders are not in worktrees, so pass them explicitly.
7. **Commands**: the gate with a stable image tag (`QUALITY_SUITE_IMAGE=<stable tag>`) and the
   project's full test suite (commands in AGENTS.md), run in a clean temporary directory.
8. **Stop conditions**: "ask instead of guessing"; stop and report on a spec gap, a refused
   push, or a file outside the allow-list.
9. **Report format**: see "The report" below.

Rules that apply to every developer:

- Stay inside the own worktree; never touch the main checkout. Base the worktree on
  `origin/<final>` (`git fetch origin` first) and commit there.
- Gate with a stable image tag. Never rebuild or retag shared images; use own tags only.
- Atomic Conventional Commits, ASCII, subject <= 50 characters, no AI co-author, no
  `--no-verify`. Commit WIP at each AC (see Resumability).
- Push right after each commit, with a plain `git push origin HEAD:<final>`. Never force: if
  the push is refused because the parent moved, stop and report (the lead decides `git subir`).
- Never `git integra`, `git merge`, `git pull` without `--rebase`, or push an ORIGINAL branch.
- Doc comment on every function; English only.
- Full run when the project has shell or hook code: copy `git archive` output into a unique
  temporary directory, use a clean container image, install the tools, `chmod +x` the files
  with a shebang, run the unit tests, the generator checks and the hook tests (commands in
  AGENTS.md), and read the results in full.
- Finish with `git switch --detach` and the report.

QA brief: probe every acceptance criterion by hand, edge cases, regressions, doc comments,
duplication; the same full run; read-only on production code (tests only, plain push);
verdict plus findings with severity and file:line. Checks owned by branches not yet
integrated are not findings.

## The report (developer, qa, reviewer)

Keep it under 200 words:

- Branch and tip sha.
- AC table: id, pass or fail, evidence (test name, command output line or file:line).
- Files touched outside the allow-list: must be **none**; list them otherwise.
- Open issues, and what belongs to other branches.
- Commits and tests run; ACs covered or not.

## Loop

developer -> qa -> (findings: the same developer fixes on the same branch) -> qa again ->
reviewer for docs -> lead integrates. Record every finding in the project's known-bugs log (KNOWN_BUGS.md).
(`team-flow` opens a `<final>/bugfix` branch for qa findings; follow it where it applies.)

## Rebases and conflicts (lead)

- Every worktree's hooks and aliases run the scripts of the main checkout. Never rebase or
  resolve conflicts there: a half-resolved file breaks every agent's commit. Rebase and resolve
  in a separate worktree (`git worktree add --detach <path>`), and push from there with
  `git subir`.
- Keep the main checkout on the latest integrated ORIGINAL (stable scripts), clean.

## Integration (lead)

Integrate from the main checkout only, where the real `.quality-rules.json` is (a worktree may
hold a generated default with another flow). Check the `"flow"` setting, run
`git integra -m "<subject>" -m "<why>"`, check there is one parent (`git log -1 --format=%P`)
and the trailers (`Commits:`, `Files:`, `Refs:`, `Squashed:`), then push. Before checking a
branch out, free it from the finished agent's worktree (`git -C <worktree> switch --detach`).

## Helper branches (lead)

- Fix, sync and QA branches made by the lead (for example `qafix`, `syncfix`) are deleted,
  local and origin, right after their `git integra` is pushed. Integra rebases the local final
  branch, so the origin copy goes stale and later blocks the release ("local and origin
  diverged").
- Before any release, audit every branch of the tree: content already in the ORIGINAL
  (`Squashed:` trailer, or `git cherry` shows only `-`) -> delete it; content missing -> ask
  the human whether it is needed, then integrate it or set it aside as unmerged. Local and
  origin must agree on every branch left.

## Resumability and usage-limit stop

- Developers commit WIP at each AC and keep `docs/<ot>/<leaf>.md` with progress and the next
  step, so a new agent can resume a stopped one from that file.
- Before stopping, the lead pushes every fast-forward branch and records per agent: id, branch,
  tip, dirty files, last step, in the shared status file.
- Resume with `SendMessage` to the same agent id ("limit reset, continue from where you
  stopped"), or start a new agent that reads `docs/<ot>/<leaf>.md`; uncommitted work is still
  in its worktree. Resume in priority order, 3-4 at a time.

## Never

- Perform an action an agent was denied (force push, hook bypass) on its behalf: ask the human.
- Let two agents edit the same file in parallel, or share one temporary directory or image tag.
