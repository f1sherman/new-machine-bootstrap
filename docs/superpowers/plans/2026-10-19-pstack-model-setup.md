# Machine-local pstack model setup plan

> Native execution with executing-plans. Self-approved under z-quick-pr. One final fresh-context branch review belongs to the PR gate.

**Spec:** docs/superpowers/specs/2026-10-19-pstack-model-setup-design.md
**Goal:** Confirm and persist host-specific model recommendations, then honor them in native delegates.
**Architecture:** Shared adapter/setup guidance and Ruby profile helper deployed with the existing skill tree. User-owned local state is never provisioned.

## Constraints and review focus

No baked-in model IDs, credentials, model probes before budget confirmation, cross-host profile synchronization, Cursor rules, or hidden fallback from stale choices. Keep existing authority rules. Explicit selection overrides saved mappings. Unconfigured setups still work with inheritance. Thinking support comes from the actual schema/catalog, not names. A single-model panel is not model diversity.

## Task 1: Durable profile boundary

- [x] Add tests/pstack-models.rb executing the real helper with private HOME and synthetic catalogs: save/resolve, aliases, panels, distinct host/harness profiles, invalid/stale selections, unsupported thinking, symlink rejection, and failed-write preservation. Observe failure before implementation.
- [x] Add models.rb beside ADAPTER.md. Commands: roles; show HARNESS; save HARNESS PROFILE CATALOG; resolve HARNESS ROLE CATALOG. Return structured JSON and fixed safe failures. Validate host/schema/harness and catalog, serialize writes, reject unsafe state paths, and replace atomically.
- [x] Run helper tests and Ruby syntax check.

## Task 2: Setup and dispatch

- [x] Add explicit setup-pstack entry/metadata and MODEL-SETUP.md. Route pstack setup requests to local guidance. Update adapter to read local profile, discover fresh native catalogs, resolve roles, and pass configured model overrides. Keep existing safety boundaries.
- [x] Update docs/pstack.md with per-machine setup, budgets/confirmation, profile ownership, stale-model handling, exact native commands, and no promise of a universal best model.
- [x] Run matched old/candidate and leave-one-component-out setup/dispatch diagnostics with frozen inputs/settings and token reporting. Label tool/harness limitations; retain untested safeguards.
- [x] Provision managed skills twice locally and via the established user-level common-role boundary on dev. Verify the new entry, unchanged upstream bytes, preserved local-state sentinel, native CLI setup behavior, and actual saved-role delegate selection on both harnesses. Avoid selecting live user models without confirmation.
- [x] Record evidence, commit, and run fresh branch review. Resolve material findings and recheck the branch.
- [ ] Publish the PR and verify remote head/checks. Keep the existing feedback continuation unchanged.

## Ledger

- Existing model map unconditionally inherited the parent, and setup was disabled by adapter policy. Live discovery already shows that local Pi and dev Pi have different catalogs, so no catalog is stored in source.
- Runtime profiles are intentionally user-owned state, not managed configuration. Provisioning owns helper/guidance only. This is an explicit exception for setup state, not permission to edit other managed home files.
- Helper tests first failed because the helper was absent. An initial test-harness method name collided with Minitest#run; it was corrected before the intended red run. Final macOS and Linux results: 10 tests, 49 assertions, zero failures/errors/skips. Existing linker test and Ansible syntax also passed.
- Thirty inert diagnostic trials completed across initial and final candidates. Final baseline 0/3 vs candidate 3/3; dispatch removal lost saved-role/stale checks. Setup-pointer removal was partly redundant and scored 2/3 in the final run (stale safely abstained but skipped resolution). Reported complete-workflow tokens rose from 48,484 to 98,286. Detailed limits and all condition scores are in evals/pstack-models/README.md. No safeguards were removed. The first harness attempt failed on UTF-8 before any trial and is not a behavioral result.
- Main advanced its pstack pin while implementation was in progress. The first local provision used the older isolated checkout. Fetched/rebased onto current main and provisioned again to restore the current upstream snapshot; no upstream bytes or pin change are in this branch diff.
- Final local and dev managed-skills second applies each reported ok=12 changed=0 failed=0. Local production provisioning preserved a task-owned runtime-state sentinel; only that marker was removed afterward. Dev used the established user-level common-role boundary because normal Linux apt pre-tasks require sudo. The first dev CLI check saw the old installed adapter; checksum verification and a focused reapply corrected that state before accepting any positive result.
- Real /skill:setup-pstack worked in local and dev Pi. A medium-budget local request produced the full table with two entries per initial panel and asked for confirmation, with zero tool errors in the final probe. Real /setup-pstack on dev Claude discovered native aliases, recommended role-specific choices, disclosed missing per-delegate effort controls, and asked for table confirmation. No live profile was saved.
- Real saved-role probes used the production helper plus disposable profiles, redirecting only helper HOME. Pi on both machines launched its native read-only reviewer with an explicit Luna override. Claude launched one Explore delegate with Sonnet while its parent stayed on Opus; usage reported both models. The first Claude test hook redirected HOME too broadly and changed upstream reads; that infrastructure attempt is retained separately. Restricting redirection to the helper invocation preserved normal reads and the actual configured-model probe passed.
- Fresh branch review found that unconfigured/omitted panel roles inherited only one delegate, reducing upstream independent contexts. Added a failing behavioral case, then corrected defaults to two inheritance entries for all panel/pool roles while preserving explicit saved lengths. Final macOS and Linux tests: 11 runs, 67 assertions, zero failures/errors/skips. Reprovisioned both boundaries twice; final second applies remained changed=0. No prompt guidance was pruned.
- CLI-generated temporary setup catalog was moved to private verification evidence before review; it was not committed. All shared profile reads remain unconfigured. No live model choices, credentials, global model defaults, or feedback continuation were changed. Profiles remain unconfigured until Brian confirms setup on each machine/harness.
