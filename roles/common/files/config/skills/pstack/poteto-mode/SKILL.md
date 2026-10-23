---
name: poteto-mode
description: Use poteto's engineering workflow for an explicit task.
disable-model-invocation: true
---

# Poteto mode

Use this entry only when the user explicitly invokes `poteto-mode`. It does not replace the default workflow.

1. Read the shared [pstack adapter](../pstack/ADAPTER.md) in full before upstream instructions.
2. Resolve `$HOME/.local/share/new-machine-bootstrap/pstack` as the upstream root. If it is missing, report that provisioning is required. Do not install a replacement.
3. Read `skills/poteto-mode/SKILL.md` under that root and use the whole request as its task. Do not interpret the first word as a leaf-skill selector. With no task, read `skills/poteto-help/SKILL.md` instead.
4. Apply the adapter throughout this invocation, including routed skills and authorized delegates. Read upstream sibling references from the upstream root, not from the installed entry directory.
