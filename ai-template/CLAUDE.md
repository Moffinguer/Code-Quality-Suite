@AGENTS.md

## Claude Code specifics

- The PostToolUse hook in `.claude/settings.json` runs the quality gate on every file you edit;
  its findings come back to you as a blocking message. Fix them before continuing.
- Delegate to the subagents in `.claude/agents/` by role; give each one a single task. Developers
  work in their own worktree and report their final branch; integrate it into its ORIGINAL with
  `git checkout <branch> && git integra -m "<subject>" -m "<why>"` once qa and reviewer agree.
- Skills: `.claude/skills/` is a copy of `.agents/skills/` (run `bash <SUITE>/scripts/ai-sync.sh`
  after editing a skill).
