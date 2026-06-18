# Test Quality Guidance Design

## Problem

The repository has accumulated tests that mostly mirror implementation text:
string-presence checks over docs, workflows, install loops, and generated
guidance. These tests create false confidence, make harmless refactors harder,
and teach future agents to add more ceremonial coverage.

Tautological tests are worse than no tests. The durable fix is to change agent
guidance and review policy so new tests must prove behavior that can break.
The actual cleanup of existing tests is being handled in another session and is
out of scope for this implementation.

## Goals

- Make `new-machine-bootstrap` guidance reject tautological tests.
- Update deployed Claude/Codex/shared skill guidance so future agents use a
  higher bar for test creation across Brian's projects.
- Update `home-network-provisioning` Codex PR reviewer guidance so reviewers
  flag newly added tautological tests.
- Preserve Red/Green TDD as a tool for behavior changes, but require the red
  test to be meaningful.
- Avoid adding tests that only assert the new guidance text exists.

## Non-Goals

- Do not delete or refactor the current `new-machine-bootstrap` test suite in
  this change. Another active session owns that cleanup.
- Do not perform broad `home-network-provisioning` test cleanup.
- Do not add a brittle lint rule that tries to classify tests by keyword.

## Test Quality Standard

A useful automated test must satisfy all of these:

1. It would fail for a plausible regression.
2. It would still pass after a harmless implementation refactor.
3. It asserts behavior, generated structure, or an external contract rather
   than restating internal text.
4. It gives maintainers confidence that is not already provided by a narrower
   existing test or end-to-end verification.

Avoid tests whose only assertion is that exact prose, YAML snippets, install
loop entries, README wording, skill text, or command strings exist. These are
acceptable only when the literal string is itself a user-facing compatibility
contract.

When no useful automated test exists, agents should say so and use focused
manual or end-to-end verification instead.

## `new-machine-bootstrap` Changes

Update durable repo guidance:

- `README.md`: replace the current "CI is source of truth" testing note with a
  short test-quality policy. Keep the CI wiring rule, but add the behavior-test
  standard and the explicit "no test is better than a tautological test" rule.
- `roles/common/files/claude/CLAUDE.md.d/00-base.md`: expand the testing line
  from generic Red/Green TDD to meaningful behavior-test guidance.
- Shared skill guidance under `roles/common/files/config/skills/common/`:
  adjust planning and validation skills that currently nudge agents toward
  adding or checking tests without asking whether the tests are useful.
- Codex/Claude-specific managed skill guidance, only where it repeats the same
  testing expectations.

Guidance should stay concise and operational. It should tell agents what to do
instead of creating a long essay on testing philosophy.

## `home-network-provisioning` Reviewer Change

Update
`/Users/brian/projects/home-network-provisioning/tools/codex-pr-review/upstream_review_prompt.md`.

The reviewer should:

- Treat newly added tautological tests as actionable maintainability bugs when
  they create false confidence or lock implementation text.
- Flag tests that only assert exact strings, config snippets, prose, or install
  list membership when behavior could be verified by running or structurally
  parsing the system.
- Not demand tests for every change. If a change is better verified manually or
  by existing end-to-end checks, accept that.
- Prefer findings that ask the author to delete unhelpful tests, replace them
  with behavior tests, or document manual verification.
- Avoid nitpicking pre-existing bad tests unless the PR adds to them or relies
  on them as proof.

This is reviewer prompt guidance only; no broad `hnp` test cleanup belongs in
this change.

## Implementation Boundary

This implementation updates guidance and review policy only. It must not race
the parallel session that is deleting or refactoring existing `nmb` tests.

If the parallel cleanup lands first, this guidance should still apply cleanly.
If this guidance lands first, the cleanup can proceed against the new standard.

## Verification

Use direct, empirical verification:

- Read the final guidance in each touched file and confirm it includes the
  approved standard without contradictions.
- Run markdown or syntax checks if the repository already has them for touched
  files.
- Run narrow existing tests only if they execute guidance generation or reviewer
  prompt behavior.
- Do not add new tests that merely assert the guidance contains exact strings.

For `hnp`, verify the prompt text directly and run the narrow Ruby test lane
only if an existing reviewer prompt test must be updated as a result.

## Risks

- Agents may under-test changes if guidance is read as "avoid tests" rather
  than "avoid bad tests." Mitigation: explicitly require behavior tests when
  they would catch plausible regressions.
- The Codex reviewer may over-flag useful contract tests. Mitigation: make the
  exception explicit for user-facing compatibility strings and external
  contracts.
- Cross-repo changes may conflict with another active session. Mitigation: keep
  this work to guidance and reviewer policy.
