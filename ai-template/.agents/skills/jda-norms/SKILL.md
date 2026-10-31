---
name: jda-norms
description: Use before designing, coding or reviewing anything in a Junta de Andalucia project. Finds the Junta development norms that apply to the task in knowledge/jda and lists what they require.
---

# Apply the Junta norms

1. Read `knowledge/jda/INDEX.md`. It maps topics (architecture, security, accessibility,
   documentation, databases, front end, naming, delivery) to norm notes.
2. Pick every note whose `applies_to` matches the task (file types, layers, deliverables).
   Read those notes in full; read the `sources` excerpt only if a rule is ambiguous.
3. Write down, before working, a checklist: `NORM-ID: what it requires here`.
4. Do the work. For every item, either comply or stop and ask the human (never silently skip).
5. Machine-checkable norms (`check:` field in the note) are enforced by the quality gate. If a
   note says `check: missing`, mention it in your report: it is a candidate rule for
   `.quality-rules.json`.
6. In the commit body add `Norms: <ids>`; in a review, quote the ids you checked.

Precedence when notes disagree: the newer `date` wins unless the older one is marked
`status: mandatory` and the newer one `status: recommendation`. Report the conflict.
