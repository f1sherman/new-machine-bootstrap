# Test Value Policy and Suite Reduction Design

## Status

Approved in conversation on 2026-08-06.

## Goal

Make automated tests exceptional rather than automatic. Retain tests only when
they protect material, realistic regression risks. Remove low-value tests from
this repository. Update managed agent guidance so future pull requests apply the
same policy before they add tests.

## Non-goals

- Do not optimize CI by weakening provisioning verification.
- Do not retain a test only because it already exists or once found a bug.
- Do not replace removed tests with a new test runner or coverage target.
- Do not require a fixed test count or coverage percentage.
- Do not test static configuration merely to prove that the repository contains
  the requested configuration.

## Baseline

The integration workflow has 65 test-file review units, including the Claude hook
test outside `tests/`. The latest measured successful CI run took approximately
eight minutes. Provisioning took 247 seconds. Tests after provisioning took
approximately 215 seconds.

The initial policy application estimates that approximately 45 of 65 review
units, or 69%, can be removed. The implementation review will record the final
count and percentage. Runtime reduction will be smaller because many removed
configuration tests are fast and some retained behavioral tests are slow.

## Test-value gate

A new or existing automated test must pass all four gates.

1. **Material harm**: A plausible regression can cause data loss, security
   exposure, destructive Git or process behavior, corrupted state, cross-session
   interference, or failure of a critical workflow. Cosmetic differences and
   easy-to-diagnose configuration mistakes do not qualify.
2. **Complex behavior**: The subject contains meaningful branching, parsing,
   concurrency, recovery, state transitions, destructive operations, or
   multi-process interaction. Declarative package entries, Ansible tasks,
   template strings, and file locations do not qualify.
3. **Behavioral verification**: The test executes the production artifact and
   checks observable behavior. Source greps and assertions that restate YAML,
   templates, prose, command strings, or workflow bookkeeping do not qualify.
4. **Unique protection**: Provisioning failure, syntax validation, Ansible
   validation, manual end-to-end verification, or a broader retained test does
   not already catch the same regression.

A retained test must also be deterministic and maintainable. A slow or flaky test
needs proportionally higher value. A past regression is evidence for plausible
recurrence, but it does not override the four gates.

## Automatic removal signals

Remove a test when its main purpose is one or more of these:

- Restate Ansible, template, package, hook, or tool configuration.
- Check that an exact string, file path, workflow entry, or another test exists.
- Preserve a completed one-time migration without a current support window.
- Assert implementation details rather than observable behavior.
- Cover only a trivial happy path whose failure is immediate and easy to diagnose.
- Duplicate broader behavioral coverage.
- Protect a low-impact preference that is easier to verify during provisioning or
  focused manual verification.

Configuration can justify a test only when the test executes a real security or
destructive boundary. Exact configuration presence alone is not sufficient.

## Existing-suite review

Review each test file as one unit first. Review individual cases inside a file
when the file mixes qualifying and non-qualifying coverage.

For each unit, record:

- keep, trim, or remove;
- which gate it passes or fails;
- the material failure it protects, if retained;
- whether another retained test or provisioning already covers the risk.

Likely retained examples include concurrency locking, destructive process
management, Git repository lifecycle behavior, trust boundaries, main-worktree
mutation guards, asynchronous tmux state transitions, interrupted restore
recovery, and demonstrated cross-session interference.

Likely removal examples include CI inventory bookkeeping, tests that inspect
other tests, static package and hook contracts, managed environment declarations,
obsolete-helper absence checks, and completed migration greps.

The workflow will list only retained tests. The CI inventory meta-test will be
removed because it verifies bookkeeping rather than production behavior.

## Guidance and prompt changes

Apply the policy at all relevant instruction layers:

1. Add the four-gate policy to the managed global Pi guidance in
   `roles/common/files/pi/AGENTS.md.d/00-base.md`.
2. Align the existing testing rule in the managed global Claude guidance at
   `roles/common/files/claude/CLAUDE.md.d/00-base.md`.
3. Add the policy to this repository's local `CLAUDE.md`, which also supplies
   `AGENTS.md` through its symlink.
4. Update the shared and Pi quick-PR skills so their specification, planning,
   and execution instructions do not require automatic TDD. They must require
   TDD only when the proposed test passes the test-value gate. They must permit
   manual or end-to-end verification when no valuable automated test exists.

Keep the policy concise and identical in meaning across guidance files. Do not
add an automated policy-enforcement test. Such a test would restate guidance and
violate the policy itself.

## Verification

Verification will use evidence appropriate to the change:

- Run every retained automated test on the implementation worktree where the
  local platform supports it.
- Run `bin/provision` to deploy the updated managed guidance.
- Run `bin/provision --check` to verify idempotence when supported.
- Validate the edited YAML and shell/Ruby syntax.
- Inspect the final workflow to confirm that every referenced test exists and
  every removed test reference is gone.
- Compare the before and after test-file counts, line counts, and measured or
  expected CI runtime.
- Review the final diff to confirm that no production behavior was removed.

The absence of a new automated test for this policy is intentional. The changed
agent guidance and pull-request prompts are the enforcement mechanism.

## Success criteria

- Each retained test has a written material-risk justification.
- Each removed test fails at least one gate or duplicates retained coverage.
- Approximately 65% to 75% of current test-file review units are removed unless
  detailed review finds concrete material risks that justify a smaller reduction.
- The integration workflow passes with the retained suite.
- Managed Pi, Claude, and quick-PR guidance applies the same policy to future
  work.
- Provisioning deploys the guidance without changing unrelated managed state.
