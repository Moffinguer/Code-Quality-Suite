---
name: norms-ingest
description: Use when a new norm document arrives (a regulation, guideline, standard or notification, dropped in knowledge/norms/inbox). Turns it into norm notes, updates the knowledge map and proposes quality-gate rules.
---

# Ingest a document into the norms map

Input: a file in `knowledge/norms/inbox/` (PDF, DOCX, e-mail export, Markdown).

1. Read it completely. Identify: issuing body, title, date, version, scope (which projects,
   layers, file types), and whether it replaces an earlier document.
2. Split it into atomic rules. One rule = one obligation that can be checked. For each rule
   create or update `knowledge/norms/norms/<area>-<short-name>.md` from `_template.md`:
   id (`<AREA>-<NNN>`, never reuse ids), statement in the original wording (quoted) plus a
   one-line plain summary, `status` (mandatory | recommendation), `applies_to`, `source`
   (document + section/page), `date`, `supersedes`, `check`.
3. `check`: name the gate tool and rule that enforces it (e.g. `checkstyle: LineLength max=120`,
   `encoding: utf-8`, `branches.levels`), or `manual: <how a reviewer verifies it>`, or `missing`.
4. Update `knowledge/norms/INDEX.md` (topic table and the changelog at the bottom). Mark replaced
   notes `status: superseded` with a link to the new one; do not delete them.
5. For every `check: missing` that a tool could enforce, write a proposal in
   `knowledge/norms/proposals/<date>-<doc>.md` with the exact `.quality-rules.json` change. Do not
   edit `.quality-rules.json` yourself: a human approves it.
6. Move the original to `knowledge/norms/sources/` and summarise to the human: new rules, changed
   rules, conflicts, proposals.

Never invent obligations that are not in the document; quote it.
