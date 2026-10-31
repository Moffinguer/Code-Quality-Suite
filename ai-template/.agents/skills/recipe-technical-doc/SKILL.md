---
name: recipe-technical-doc
description: Use when asked to write or update the technical documentation of a Junta de Andalucia project or work order (OT) - design document, installation manual or release notes - in the team's Markdown format.
---

# Recipe: technical document (example recipe, adapt it)

Output: `docs/<ot>/<kind>.md` in Markdown (the team's pipeline converts it to the Junta Word/PDF
template).

1. Front matter block: `title`, `ot`, `version` (from the branch: `<version>/<ot>/...`), `date`,
   `author`, `status: draft`.
2. Sections, in this order: Purpose; Scope; Affected components (table: component, change,
   files); Design (diagrams as Mermaid or PlantUML code blocks); Data changes (DDL/DML scripts
   listed with their order); Configuration; Deployment steps (numbered, copy-pasteable);
   Rollback; Tests performed; Applicable norms (ids from `jda-norms`).
3. Language: Spanish for the content (it goes to the client), ASCII-safe file names.
4. Checks: the quality gate on the file (markdownlint); every component in the table exists in
   the diff; every DDL script listed exists.
