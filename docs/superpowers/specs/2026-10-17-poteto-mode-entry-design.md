# Direct poteto-mode entry

Status: self-approved under z-quick-pr.

## Goal and scope

Expose `/skill:poteto-mode <task>` in native Pi and `/poteto-mode <task>` in Claude Code. Preserve the existing pstack command and every adapter safeguard. Do not add a Pi extension for a bare slash alias, expose all 54 skills, or modify upstream content.

## Decision

Add a second explicit-only wrapper under `roles/common/files/config/skills/pstack/poteto-mode/`. The existing tree synchronization and linker discover its directory automatically. The wrapper reads the shared sibling pstack adapter first, checks the same deployed upstream root, then reads upstream poteto-mode. It passes the whole task unchanged instead of treating its first word as a leaf-skill selector. Empty invocation opens upstream help. It reports missing upstream content as a provisioning requirement.

Alternatives: renaming pstack would break the installed command; directly linking upstream poteto-mode would bypass local policy and model mapping. A small second wrapper preserves both interfaces with one shared adapter.

## Verification and rollout

Baseline: neither host has a direct poteto-mode entry. Check production Pi discovery before/after, then execute real direct invocations in local Pi and remote Pi/Claude Code. Confirm the adapter is read, native delegates inherit the parent model, the original pstack command still works, and source files remain unchanged by smoke runs. Provision twice and require idempotence. Use existing linker tests; static prose tests would add no unique protection. Update the guide and link task label. Keep the existing feedback continuation unchanged.
