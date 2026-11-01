@AGENTS.md

## Claude Code specifics

- The PostToolUse hook in `.claude/settings.json` runs the quality gate on every file you edit;
  its findings come back to you as a blocking message. Fix them before continuing.
- You are the lead and the business analyst: subagents cannot start other subagents, so you
  delegate every step of the `team-flow` skill. Give each subagent in `.claude/agents/` a single
  task and the absolute paths of `dev_documents/` and `docs/<version-or-ot>/` (ignored folders
  are not in worktrees). `systems-analyst` writes the spec and plan; you create the branches.
- Developers work in their own worktree and report their final branch. On qa findings open
  `<req>/bugfix` (`git convertir-padre` when the requirement branch is final, then
  `git nr bugfix`). Once qa finds nothing, the reviewer agrees and the human approves,
  integrate bottom-up with `git checkout <branch> && git integra -m "<subject>" -m "<why>"`.
- Never add an AI as co-author of a commit.
- Skills: `.claude/skills/` is a copy of `.agents/skills/` (run `bash <SUITE>/scripts/ai-sync.sh`
  after editing a skill).
