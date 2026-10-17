---
name: pstack
description: Use poteto's pstack workflows with an explicit task or skill name.
disable-model-invocation: true
---

# pstack

Use this entry only when the user explicitly invokes `pstack`. It does not replace the default workflow.

1. Read [ADAPTER.md](ADAPTER.md) in full before upstream instructions.
2. Resolve `$HOME/.local/share/new-machine-bootstrap/pstack` as the upstream root. If it is missing, report that provisioning is required. Do not install a replacement.
3. If the first argument exactly names a directory under `skills/`, read that directory's `SKILL.md` and use the remaining text as its task. Otherwise read `skills/poteto-mode/SKILL.md` and use the whole request as the task. With no task, read `skills/poteto-help/SKILL.md`.
4. Apply the adapter throughout this invocation, including routed skills and authorized delegates. Read upstream sibling references from the upstream root, not from the installed entry directory.
