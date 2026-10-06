# Neutral command evals implementation plan

Execution: native execution in the current session. User approved removing the
redundant reminder, adding neutral cases, retaining stress cases, and updating
future eval-writing guidance. Use a fresh read-only final review after results.

## Goal and scope

Measure command-guidance compliance without task prompts repeating its rules.
Keep operational requirements and expected values explicit. Preserve old cases
and results as stress-test evidence. Keep full versus empty guidance isolated
from deployed agent instructions. No guidance tuning during this experiment.

## Tasks

1. Remove the terminal-section reminder from the two managed base fragments.
   Leave the command section unchanged. Add a shared eval-design skill with a
   short discovery description and a checklist loaded only for eval work.
   Deploy it through the existing canonical common tree to Claude and Codex;
   add one explicit Pi link after its skills directory is created.
2. Verify program-output grading uses real cat and a scratch TMPDIR. Add
   behavioral regressions for a valid cat-to-jq pipeline and heredoc output
   that is functionally correct but violates the separate heredoc policy.
   Keep argument stand-ins for argument-only cases. Confirm file restrictions.
3. Add a neutral set of 18 task-only prompts across the existing feature
   categories. Task data and options are functional requirements; width,
   indentation, wrapping, preservation reminders, and suggested constructions
   are absent. Do not silently inherit the old output case's no-helper-file
   constraint when the neutral user task does not request it.
4. Freeze and hash neutral inputs and full/empty guidance before generation.
   Use openai/gpt-6.1-sol and anthropic/claude-sonnet-4-6 at medium reasoning,
   three calls per case, full and empty guidance only: 216 responses total.
   Use a new output directory per model. Report functional correctness and
   policy compliance separately. Retain raw responses and infrastructure errors.
5. Publish a separate neutral result artifact and label all earlier prompt
   sets as stress tests in README and PR descriptions. State that neutral
   cases are synthetic and long-value-focused, not representative workload
   frequencies or an unseen selection holdout. Add clause ablations only if
   needed after this comparison; do not infer per-clause utility from it.
6. Run the deterministic grader suite and replay the captured final-validation
   comparisons. Provision directly, verify all three deployed skills and both
   base fragments, and check Pi skill discovery without model generation.
   Commit and push the verified changes to the existing PR.

## Reviewer verification

- `ruby tests/command-guidance-eval.rb`: no failures; new regressions exercise
  real program output independently of policy-format failures.
- `--set neutral --variants compact-portable,ablation-none`: 54 responses per
  condition per model. Inspect summary.json for actual scores and infrastructure
  counts, rather than treating runner exit status as compliance success.
- Inspect the published neutral artifact against saved records and hashes.
- Check deployed eval-design links and content after provisioning. The full
  skill body stays outside always-loaded base fragments.

## Recorded outcome

- Removed both pointer lines; added the shared conditional eval-design skill.
- New real-cat regressions failed before the fix and passed after it. Final
  deterministic suite: 24 tests, 156 assertions, no failures, errors, or skips.
- Final review reproduced malformed successful follow-up responses being labelled
  as infrastructure failures with dropped response/usage evidence. The extraction
  path now records a failed/ungradable grade and preserves the full response.
  A transport-fixture regression failed before the fix and passed afterward;
  it executes the production follow-up driver without live model calls.
- All 216 initial response streams completed with no infrastructure errors.
  One jq prompt did not fully specify the input structure. Retain its outputs
  as diagnostics and exclude that same case from all four primary conditions.
  This was a post-inspection exclusion, not a preregistered choice.
- Primary 17-case combined counts: OpenAI full 51/51, empty 12/51; Sonnet full
  48/51, empty 12/51. Functional counts: OpenAI 51/51 in both conditions;
  Sonnet full 51/51, empty 49/51. Report the formatting effect separately.
- A separately frozen schema clarification supplied the actual JSON input.
  All four conditions passed 3/3 (12 new responses). Preserve these separately;
  do not call this unseen validation or replace the original responses.
- Replayed the 72 original final-validation responses: all four comparisons
  remained 18/18. No new calls for that replay.
- Full provisioning passed: ok=312, changed=19, failed=0. All three deployed
  skill copies match their source. Pi discovers and advertises eval-design.
  Both deployed base fragments match and omit the redundant reminder.

## Test policy

No static tests for wording, frozen prompts, or deployment bookkeeping. New
unit tests must execute the production grader and protect meaningful behavior.
