# Incidental monitor report eval implementation plan

**Execution:** Native execution in the current session. No delegated implementation.

**Goal:** Add the approved three-turn workflow that exposes incidental-task naming changes without primary-goal reminders.

**Architecture:** Keep the original five-step task. Add a small task overlay with the frozen report/continuation prompts and a shared-verifier entry point. Stage the shared public environment once per variant, then apply the selected overlay. Add an explicit task selector and derive the expected step count from the selected task. Do not change naming guidance.

## Constraints

- Public fixtures and generic wording only. No private transcripts or internal services.
- Local issue records only. No real PR-monitor or deployment access.
- The initial name must remain unchanged through reporting and continuation, with zero naming calls on those turns.
- Keep explicit-rename and genuine goal-change checks in the existing task.
- Harbor 0.24.0, Pi 1.0.2, and the existing credential/resource isolation remain unchanged.
- Live checks are opt-in and paid. Preserve all discovery results, including the passing prior-guidance pilot.

## Tasks

- [x] Add `verify(index, report_kind="branch-picker")` support for the explicit `pr-monitor` report kind. That kind requires one local monitor issue describing the checks and an actual successful `create_issue` call; it retains primary restoration checks and unchanged-name grading.
- [x] Add `tasks/incidental-monitor-report/` with a three-step task file, the two frozen prompts, and a small verifier wrapper that calls the shared verifier with `report_kind="pr-monitor"`.
- [x] Add `--task incidental-monitor-report` to `run.mjs`; default to the existing task. Copy the base fixture, preserve its verifier as `base_verify.py`, apply the overlay, and expect three rather than five steps. Keep current-policy failure exits unchanged.
- [x] Run the offline verifier checks, stage both task choices and all guidance variants, and run the committed entry point against the selected task.
- [x] Record public-safe confirmation evidence: three current-policy passes versus three context-section-removal failures; all task steps complete. Distinguish discovery from confirmation and do not claim universal reliability.
- [ ] Update README and PR description, commit the source changes, and push the existing PR branch.

## Reviewer verification

Run the focused task through the normal runner with `--task incidental-monitor-report --trials 3`. Expected current-policy result: three workflows at 3/3 naming and 3/3 task steps. The captured ablation confirmation has three workflows at 1/3 naming and 3/3 task steps, with a rename on the report turn and another on continuation. Inspect native session JSONL and executed naming calls, not only aggregate rewards. Source-entry-point live smoke verification must also pass before publication.
