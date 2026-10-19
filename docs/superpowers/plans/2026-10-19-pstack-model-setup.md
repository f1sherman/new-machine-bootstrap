# Machine-local pstack model setup plan

> Native execution with executing-plans. Self-approved under z-quick-pr. One final fresh-context branch review belongs to the PR gate.

**Spec:** docs/superpowers/specs/2026-10-19-pstack-model-setup-design.md
**Goal:** Confirm and persist host-specific model recommendations, then honor them in native delegates.
**Architecture:** Shared adapter/setup guidance and Ruby profile helper deployed with the existing skill tree. User-owned local state is never provisioned.

## Constraints and review focus

No baked-in model IDs, credentials, model probes before budget confirmation, cross-host profile synchronization, Cursor rules, or hidden fallback from stale choices. Keep existing authority rules. Explicit selection overrides saved mappings. Unconfigured setups still work with inheritance. Thinking support comes from the actual schema/catalog, not names. A single-model panel is not model diversity.

## Task 1: Durable profile boundary

- [ ] Add tests/pstack-models.rb executing the real helper with private HOME and synthetic catalogs: save/resolve, aliases, panels, distinct host/harness profiles, invalid/stale selections, unsupported thinking, symlink rejection, and failed-write preservation. Observe failure before implementation.
- [ ] Add models.rb beside ADAPTER.md. Commands: roles; show HARNESS; save HARNESS PROFILE CATALOG; resolve HARNESS ROLE CATALOG. Return structured JSON and fixed safe failures. Validate host/schema/harness and catalog, serialize writes, reject unsafe state paths, and replace atomically.
- [ ] Run helper tests and Ruby syntax check.

## Task 2: Setup and dispatch

- [ ] Add explicit setup-pstack entry/metadata and MODEL-SETUP.md. Route pstack setup requests to local guidance. Update adapter to read local profile, discover fresh native catalogs, resolve roles, and pass configured model overrides. Keep existing safety boundaries.
- [ ] Update docs/pstack.md with per-machine setup, budgets/confirmation, profile ownership, stale-model handling, exact native commands, and no promise of a universal best model.
- [ ] Run matched old/candidate and leave-one-component-out setup/dispatch diagnostics with frozen inputs/settings and token reporting. Label tool/harness limitations; retain untested safeguards.
- [ ] Provision managed skills twice locally and via the established user-level common-role boundary on dev. Verify the new entry, unchanged upstream bytes, preserved local-state sentinel, native CLI setup behavior, and actual saved-role delegate selection on both harnesses. Avoid selecting live user models without confirmation.
- [ ] Record evidence, commit, run one fresh branch review, publish the PR, and verify remote head/checks. Keep the existing feedback continuation unchanged.

## Ledger

- Existing model map unconditionally inherited the parent, and setup was disabled by adapter policy. Live discovery already shows that local Pi and dev Pi have different catalogs, so no catalog is stored in source.
- Runtime profiles are intentionally user-owned state, not managed configuration. Provisioning owns helper/guidance only. This is an explicit exception for setup state, not permission to edit other managed home files.
