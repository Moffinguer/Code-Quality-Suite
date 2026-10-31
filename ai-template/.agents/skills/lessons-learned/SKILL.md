---
name: lessons-learned
description: Use at the end of a task, or whenever an approach failed, a hidden rule surfaced or the human corrected you. Records the lesson in knowledge/lessons so future agents avoid it.
---

# Record a lesson

Create `knowledge/lessons/<yyyy-mm-dd>-<slug>.md` from `_template.md`:
- context (task, files, tool), what happened, why, what to do instead (one imperative line);
- `applies_to` (languages, layers, tools) so other agents can find it;
- if it is enforceable, propose the rule (gate rule, AGENTS.md line, skill change).

Then add one line to `knowledge/lessons/INDEX.md`. Do not record secrets, personal data or
project data of a regulated class. Prefer updating an existing lesson to adding a duplicate.
