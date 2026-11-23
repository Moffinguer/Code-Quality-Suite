---
name: session-checkpoint
description: Use on shutdown, deadline, usage limit or low budget; save state, then resume in steps
---

# session-checkpoint

## When to use

- The human announces a shutdown, a deadline or a usage limit.
- Usage runs low (tokens, time or agent budget) before the work is done.
- Use it before starting any long job, not only when the stop is already near.

## Steps

1. Write a RESUME block at once in the lead's memory and pending work: branch,
   current step, any half-done rebase or worktree, and the next exact command.
2. Refresh the RESUME block after every integration or push.
3. Prefer steps that end committed and pushed. Never leave a rebase open.
4. Skip long test suites unless they fit before the deadline.
5. Before the deadline:
   - every worktree is detached and clean (no uncommitted changes);
   - running agents are told to commit and push, or to stop;
   - their id and last step are recorded in the RESUME block.

## Resume

1. Read the last RESUME block in the lead's memory and pending work.
2. Check the git status of each worktree listed in it.
3. Continue from the next command in the block.

## Never

- Start a long job right before the deadline.
- Leave a conflict half resolved in the main checkout.
