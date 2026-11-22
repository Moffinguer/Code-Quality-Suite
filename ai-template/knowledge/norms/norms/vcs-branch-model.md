---
id: VCS-001
title: Branch model per version and work order (example note)
status: mandatory
applies_to: [git]
source: "Team agreement 2026-10 (example; replace with the real source document)"
date: 2026-10-12
supersedes: []
check: "branches: <version>/<ot>/.../ORIGINAL (hooks pre-push, pre-rebase, pre-merge-commit)"
---

> Las ramas se nombran <version>/<orden de trabajo>/<detalle>; la rama de la OT recibe el tag de
> la version y se integra en develop.

Summary: one branch tree per version and OT; parents end in ORIGINAL; the version is tagged
when it reaches develop.
