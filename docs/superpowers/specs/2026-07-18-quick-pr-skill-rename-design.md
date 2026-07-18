# Quick PR Skill Rename Design

## Goal

Rename the managed spec-to-PR workflow to quick PR without changing its behavior.

## Scope

- Rename the shared Claude/Codex skill from `_spec-to-pr` to `_quick-pr`.
- Rename the Pi counterpart from `z-spec-to-pr` to `z-quick-pr`.
- Update each skill's frontmatter, title, internal continuation target, lifecycle hook trigger, and focused test references.
- Add the old names to Ansible's managed-skill cleanup list so provisioning removes stale deployed copies.
- Preserve historical specs and plans as records of the names used when they were written.

## Implementation

Move the managed skill directories rather than creating aliases. Keep the existing workflow body unchanged except for name-dependent text. Update runtime hooks to recognize only the new names, making the rename explicit and avoiding permanent compatibility logic.

Tests will assert that the new skill paths, names, continuation targets, and hook triggers work and that active configuration no longer references the old names. Existing shared-skill parity checks remain the primary end-to-end verification of the Pi copy against the shared source.

## Success Criteria

- Claude and Codex expose `_quick-pr`; Pi exposes `z-quick-pr`.
- No active managed configuration invokes `_spec-to-pr` or `z-spec-to-pr`.
- Provisioning removes stale copies of the old skill names.
- The workflow behavior remains otherwise unchanged.
- Relevant repository tests and Ansible syntax checks pass.
