---
name: dev-documents
description: Use when reading or writing dev_documents/Requirements.md, Functional_Design.md, Technical_Design.md or Tests.md, or when a task needs its RF, RNF, CU or CP ids.
---

# Dev documents: format and IDs

The four files form one chain: requirement (RF/RNF) -> use case (CU) -> module (technical
design) -> test case (CP). The templates in `dev_documents/` (headings, labels and an HTML
comment with the format at the top of each file) are the reference: copy their structure.

## Where they live

- `dev_documents/` at the repository root. Git-ignored local files: never committed, no history.
- Repository root as fallback, when the folder is missing. Say which one you used.
- In a worktree the folder is not there (it is ignored, so it is not checked out): use the
  absolute path of the main checkout given in your task. Never write a relative path to it.

## Rules for every file

- UTF-8 without BOM. The level-1 title, the section headings and the field labels are fixed in
  English. Prose (names, descriptions, steps) may be English or Spanish, even mixed.
- IDs are `RF-NNN`, `RNF-NNN`, `CU-NNN`, `CP-NNN`: the prefix, a hyphen and three or more digits,
  zero-padded (`RF-001`). Unique within the file. Never renumber or reuse an ID.
- A dropped item keeps its heading with `(withdrawn)` appended and a one-line reason.
- An item is a `## <ID>: <name>` heading (in Requirements and Functional design the items are
  level 3, under their section). Its fields are a bullet list `- Label: value`; multi-line values
  are nested lists.
- A reference to other items is a comma-separated list of IDs (`CU-001, CU-004`); `-` means none.

## Requirements.md

Sections `## Functional requirements` (items `RF-NNN`) and `## Non-functional requirements`
(items `RNF-NNN`). Each item: a description paragraph (required), then the optional fields
`- Priority: must | should | could` and `- Source: <who or what asked for it>`. RNF items add
`- Category: performance | security | accessibility | usability | availability | maintainability |
other`.

## Functional_Design.md

Section `## Use cases`, one `### CU-NNN: <name>` item each, with the fields `- Actors:`,
`- Preconditions:`, `- Main flow:` (numbered nested steps), `- Alternative flows:` (nested
`<step>a. <condition>: <result>` items, or `-`), `- Postconditions:` and
`- Requirements:` (RF/RNF ids).

Section `## Traceability matrix`: one row per RF and RNF, one column per CU, `X` in each related
cell. The `Requirements:` field of a use case is the source; the matrix is its view. Change both
in the same edit.

## Technical_Design.md

Optional `## Overview` (free text), then one `## Module: <name>` section per module touched.
Module names are unique; modules have no numeric ID. Fields: `- Path:` (folders or files),
`- Use cases:` (the CU ids it touches), `- Changes:` (what changes and why), optional `- Risks:`.

## Tests.md

One `## CP-NNN: <name>` item per test case. Fields: `- Use cases:` and `- Requirements:` (at
least one not `-`), `- Type: unit | integration | system | acceptance | manual`,
`- Preconditions:`, `- Steps:` (numbered nested list), `- Expected result:`, optional
`- Automated: <test file or class>` and `- Status: pending | passed | failed` (last run).

This is version 1 of the Tests format. Test data, environments and a CP x CU coverage matrix
come in later versions: do not add them ad hoc.

## Who writes what

- Analyst: Requirements.md, and the use cases and matrix of Functional_Design.md.
- Systems analyst or developer: the module sections of Technical_Design.md.
- QA: Tests.md (one CP per acceptance criterion or CU flow; update `Status:` after each run).
- Everyone: read the CU ids of your task before coding.

## Commits

Advice, not enforced by the hooks: add a line `Refs: CU-001, RF-002` to the commit body.
