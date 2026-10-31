# Spec 3.0.0 - ignores, new agent rules, workflow and team skills

Version: 3.0.0 (from 2.6.0)   Data class: internal   Norms: none (AGENTS.md rule 1)

## Goal

Keep agent work files out of project history, add three always-on rules to the agent
instructions (read the requirement files, English code with doc comments, no AI co-author
trailers), and give agents two skills: the full git workflow and the team flow (orchestrator,
developers, QA bugfix loop, bottom-up merge with human approval).

## Context verified

- Agent files are tracked in `ai-template/` and copied by `git ia` = `scripts/ai-init.sh`.
  It writes the `.gitignore` block (`IGNORED=(...)`, lines 51-67) and runs `git rm --cached`
  on any tracked path of that list (lines 69-76).
- The `git-commands` skill is not in `ai-template/`: `scripts/ai-init.sh` (lines 42-48)
  builds it from `docs/GIT-COMMANDS.md`. `scripts/qs-help.sh` (`git ayuda`) reads the same file.
- `--actualizar` never rewrites `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `opencode.json` or
  `knowledge/` (the `yours()` function, line 25). It does rewrite skills, `.claude/agents/*` and
  `.claude/settings.json`.
- OpenCode agents are not tracked. `scripts/ai-sync.sh` generates them from `.claude/agents/*.md`
  (opus -> role-lead, reviewer -> role-review, sonnet -> role-dev, haiku -> role-intern).
- This repo's `docs/` holds 21 tracked product docs (flat files, no subfolders).
  `docs/GIT-COMMANDS.md` is also a runtime input.
- Branch policy (`engine/policy.py` lines 38-42): `levels` = [semver, `^[0-9]+$`], so
  `3.0.0/ignore` is refused. `allow` regexes (full branch name, `scripts/git-flow-lib.sh`
  line 96) skip all checks.
- Claude Code subagents cannot start other subagents. Only the main session can delegate.

## Scope

Part 1 (ignore), Part 2 (new_rules), Part 3 (skills), described in the tasks below.

## Out of scope

- The format of `Requirements.md`, `Functional_Design.md`, `Technical_Design.md` and `Tests.md`
  (a later version).
- Changing the branch model, the aliases or `engine/policy.py` defaults (see OQ1).
- Automatic merge-conflict resolution.
- Changing projects that already exist (`AGENTS.md` is theirs; see R1).

## Acceptance criteria

### Part 1 - ignore

1. After `git ia` runs, the managed block in the project's `.gitignore` contains `/docs/[0-9]*/`
   and still contains every entry it had before.
2. In a project, `docs/123456/spec.md` and `docs/3.0.0/notes.md` are ignored (`git check-ignore`
   exits 0). `docs/GIT-WORKFLOW.md` and `docs/guide/x.md` are not ignored.
3. In this repo, `git ls-files docs` lists the same 21 product docs before and after the change.
   `git check-ignore docs/3.0.0/spec.md` exits 0.
4. Running `git ia` on a project that has a tracked `docs/<n>/` folder takes it out of the index
   and keeps it on disk. The script prints the existing "taken out of the index" message.
5. `tests/hooks/run.sh` has a test for criteria 1-2 and it passes.
6. The analyst/systems-analyst agent text says the work folder `docs/<version-or-ot>/` is
   git-ignored and that a per-branch summary there is optional.

### Part 2 - new_rules

1. `ai-template/AGENTS.md` has a rule that tells agents to read the requirement files if they
   exist, at the start of each task, in the lookup order from OQ2. It also says that a missing
   file is not an error.
2. `ai-template/AGENTS.md` has a rule that requirement files may be written in English or
   Spanish, but code, identifiers and comments are written in English. Every function, method
   or procedure has a doc comment in the language's own style (Javadoc, JSDoc, docstring,
   PL/SQL header, shell header comment) that gives the purpose, the parameters, the return value
   and the errors.
3. `ai-template/AGENTS.md` has a rule against AI attribution: no `Co-Authored-By:` trailer naming
   an AI or model, and no "Generated with ..." line in commits or PRs.
4. `ai-template/.claude/settings.json` turns off Claude Code's co-author and PR attribution
    (`includeCoAuthoredBy: false`, or the current `attribution` key; check which one the
    installed Claude Code version uses).
5. (If OQ3 is accepted) `hooks/commit-msg` rejects a message with a `Co-Authored-By:` line that
    matches `claude|anthropic|openai|gpt|copilot|gemini|codex|noreply@anthropic.com` (case
    insensitive), and the error explains how to fix it. A human co-author trailer is still
    accepted. Policy key `commit.forbid_ai_coauthor` (default true) is defined in
    `engine/policy.py` and documented in `docs/QUALITY-RULES.md`. `tests/hooks/run.sh` covers
    both the rejected case and the accepted case.
6. This repo's local `/AGENTS.md` (untracked) gets the same three rules. Its own rule 1
    ("no Junta norms") stays.

### Part 3 - skills

 1. `ai-template/.agents/skills/branch-workflow/SKILL.md` covers:
    - the tree example;
    - ORIGINAL, final and sibling branches, and `git convertir-padre`;
    - the rebase/merge table (finals rebase, ORIGINALs merge their parent and are never
      rebased);
    - creating a whole tree with `git es`;
    - versions (`git np`, VERSION/pom);
    - the two-step release (`git release`, then the human's `git publicar`);
    - which hook runs when.

    It points to `git-commands` for syntax and does not copy command syntax tables (check with
    grep: no command table duplicated from `docs/GIT-COMMANDS.md`). It stays under about 80 lines.
 2. A new skill `ai-template/.agents/skills/team-flow/SKILL.md` defines, in order:
    - business analyst (main session) reads the requirement files;
    - systems analyst proposes the branch tree (`git es -n` input) and the task per final branch;
    - developers work one per final branch, in their own worktree;
    - each developer runs the quality gate and hooks before asking for review;
    - QA review, then the bugfix loop until QA finds nothing;
    - bottom-up `git integra` with human approval at each level;
    - merge conflicts: the human decides, the systems analyst suggests.

    It keeps the three human checkpoints (spec, plan, merge).
 3. The bugfix rule in `team-flow`:
    - if the requirement branch is final, the lead runs `git convertir-padre` on it first, then
      `git nr bugfix`;
    - if it is already an ORIGINAL, `git nr bugfix` creates a sibling `<req>/bugfix`;
    - QA writes its findings to the work folder (`docs/<version-or-ot>/<req>/bugfix.md`);
    - QA never edits production code.
 4. Shared context between developers is the work folder `docs/<version-or-ot>/`: `spec.md`,
    `plan.md` and an optional `<branch-leaf>.md` summary. It is passed to each developer as an
    absolute path in the main worktree, because git-ignored files do not exist in other worktrees.
 5. Agent files:
    - `ai-template/.claude/agents/analyst.md` is renamed to `systems-analyst.md` (model opus,
      adds Bash limited to `git arbol` / `git es -n`);
    - `business-analyst.md` is added (opus) only if OQ4 picks a subagent;
    - `qa.md` (sonnet) gets the bugfix-loop duties;
    - `developer.md` (sonnet) gets "gate then report, read the work folder";
    - `reviewer.md` (opus) is unchanged except for references.

    The roles table in `ai-template/AGENTS.md` and `ai-template/CLAUDE.md` reflects this.
 6. After `git ia --actualizar` and `scripts/ai-sync.sh`, `.claude/skills/` contains
    `branch-workflow`, `team-flow` and `git-commands`, and `.opencode/agents/` contains
    `systems-analyst.md`. A stale `analyst.md` copy left in a project is listed in
    `docs/UPDATING.md`.
 7. `docs/SKILLS.md`, `docs/AI-SETUP.md` and `docs/AI-DEMO.md` name the new and renamed files.

## Affected components

- Ignore:
  - `scripts/ai-init.sh` (`IGNORED` array; the `git rm --cached` step also applies to the new
    entry);
  - `.gitignore` (this repo's block);
  - `tests/hooks/run.sh`;
  - `ai-template/.claude/agents/analyst.md` (one line);
  - `docs/AI-SETUP.md`.
- New rules:
  - `ai-template/AGENTS.md`, `ai-template/.claude/settings.json`;
  - `hooks/commit-msg`, `engine/policy.py`, `scripts/git-flow-lib.sh` (policy export, if OQ3 is
    accepted);
  - `docs/QUALITY-RULES.md`, `tests/hooks/run.sh`;
  - local `/AGENTS.md` (untracked).
- Skills:
  - `ai-template/.agents/skills/branch-workflow/SKILL.md`;
  - `ai-template/.agents/skills/team-flow/SKILL.md` (new);
  - `ai-template/.claude/agents/{analyst->systems-analyst, qa, developer, reviewer}.md`
    (`business-analyst.md` too, if OQ4 picks a subagent);
  - `ai-template/AGENTS.md` (roles table only), `ai-template/CLAUDE.md`;
  - `docs/SKILLS.md`, `docs/AI-DEMO.md`, `docs/UPDATING.md`;
  - local copies under `/.agents/`, `/.claude/` (refresh them with `scripts/ai-sync.sh`).
- Not touched by hand: `VERSION`, `CHANGELOG.md`, the README badge (`git np` / `git release`
  write them).

## Risks

- R1: `--actualizar` never rewrites `AGENTS.md`, so existing projects do not get Part 2 rules.
  Mitigation: a `docs/UPDATING.md` entry with the text to paste in, plus the rule summary
  repeated in the `team-flow` skill, which is rewritten.
- R2: Adding `/docs/` (the whole folder) to `IGNORED` would make `git ia` untrack this repo's
  product docs and every project's real docs. This is why OQ1 uses a narrow pattern.
- R3: Ignored work folders are not visible from developer worktrees (criterion 16).
- R4: The commit-msg check could reject a legitimate human named e.g. "Gemini". Mitigation: match
  only on the model, vendor and noreply patterns, and keep the policy key so teams can turn it
  off.
- R5: Subagents cannot delegate, so "systems analyst delegates to developers" has to be carried
  out by the main session.
- R6: The `analyst` rename breaks prompts and docs that name it. Mitigation: grep, and an
  UPDATING note.

## Open questions (recommended default in bold)

- OQ1 Branch names `3.0.0/ignore` fail level 2 (`^[0-9]+$`). **Use an OT level:
  `3.0.0/300/ORIGINAL` with finals `3.0.0/300/ignore`, `.../new_rules`, `.../skills` (no code
  change).** Alternative: an `allow` entry `^[0-9]+\.[0-9]+\.[0-9]+/(ignore|new_rules|skills)$`.
  But `.quality-rules.json` is git-ignored and personal, so the entry would not be shared.
- OQ2 Ignore pattern. **Add `/docs/[0-9]*/` (folders whose name starts with a digit: a version
  or an OT) in both the `git ia` block and this repo.** The whole `/docs/` is not ignored. The
  per-branch summary is optional.
- OQ3 Where the requirement files live. **The human creates `requirements/` at the root,
  tracked. Lookup order: `requirements/<version>/<ot>/`, `requirements/<version>/`,
  `requirements/`, repo root. `<version>` and `<ot>` come from the current branch. Read every one
  that exists, from general to specific.** Not under `docs/<n>/`, which is ignored.
- OQ4 Enforce no-AI co-author in `hooks/commit-msg`. **Yes, as a policy key defaulting to on
  (criterion 11).** Note this also makes the change breaking.
- OQ5 Business analyst as a subagent. **No. The main session is the business analyst /
  orchestrator, described in `team-flow`. Rename `analyst` to `systems-analyst`.** A
  `business-analyst.md` subagent could only read and summarise; it could not orchestrate.
- OQ6 Different models for developers. **Claude Code `developer` (sonnet). Other models through
  OpenCode `role-dev` or `external-worker` for non-regulated data only (AGENTS.md rule 6).**
- OQ7 Workflow skill. **Extend `branch-workflow` (hand-written, it links to
  `<SUITE>/docs/GIT-WORKFLOW.md`). No new skill. `git-commands` stays generated.**

## Tasks (parent `3.0.0/300/ORIGINAL`, per OQ1; `git nr <name>` under it)

| # | Branch | Files | Depends on |
| --- | --- | --- | --- |
| 1 | `ignore` | `scripts/ai-init.sh`, `.gitignore`, `tests/hooks/run.sh` (new test block), `ai-template/.claude/agents/analyst.md` (one line), `docs/AI-SETUP.md` | none |
| 2 | `new_rules` | `ai-template/AGENTS.md` (rules section), `ai-template/.claude/settings.json`, `hooks/commit-msg`, `engine/policy.py`, `scripts/git-flow-lib.sh`, `docs/QUALITY-RULES.md`, `tests/hooks/run.sh` (separate block), local `/AGENTS.md` | the rule text in 1 refers to the work folder |
| 3 | `skills` | `branch-workflow` and `team-flow` skills, `ai-template/.claude/agents/*` (rename and edits), `ai-template/AGENTS.md` (roles table), `ai-template/CLAUDE.md`, `docs/SKILLS.md`, `docs/AI-DEMO.md`, `docs/UPDATING.md`; then run `scripts/ai-sync.sh` | 1 (analyst.md), 2 (AGENTS.md) |

Files that more than one task touches, and the order:

- `tests/hooks/run.sh` (tasks 1 and 2);
- `ai-template/AGENTS.md` (tasks 2 and 3);
- `analyst.md` (tasks 1 and 3).

Integrate 1, then 2, then 3. Each later branch runs `git subir` (rebase onto the ORIGINAL)
before `git integra`. Each task changes different sections of the shared files, so conflicts
should be small.

## Semver: 3.0.0, not 2.7.0

Three changes break existing behaviour:

- `git ia` now untracks `docs/<n>/` folders in projects;
- the commit-msg hook can reject messages that passed before;
- the `analyst` subagent is renamed (prompts and references break).

Under Semantic Versioning, an incompatible change to a public interface requires a major bump.
