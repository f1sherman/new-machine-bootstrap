# Harbor Eval Integration Implementation Plan

> **Execution:** Native execution in the current session. Keep completed plans out of the final PR; preserve runnable regression material instead.

**Goal:** Use one Harbor orchestration path for command-guidance and session-naming regression evals without changing guidance or macOS grading behavior.

**Architecture:** Keep suite-specific staging and grading behind one local driver. Harbor's supported custom agent and verifier interfaces provide prompt-only Pi generation in Docker and sandboxed command grading on macOS. Naming tasks retain the normal Pi adapter and native continuation.

**Tech stack:** Node.js driver, Harbor 0.24.0, Pi 1.0.2, Python 3.12+, Ruby, Docker, macOS sandbox-exec.

## Constraints

- No production guidance changes, Harbor fork, external publication, or private fixtures.
- Preserve all 18 command prompts, selected guidance, empty control, grading observations, Bash/Zsh runtimes, and timeout/sandbox behavior.
- Preserve both naming workflows, positive rename controls, and exact-name retention checks.
- The command agent has no tools, extensions, skills, context, templates, themes, approval hooks, or saved session. Preserve its full system/user prompts and medium thinking.
- Naming uses low thinking, normal tools, and continued native sessions.
- Forward only the selected provider credential; do not copy host auth/config or mount a host checkout into the agent.
- Keep functional/policy failures, ungradable responses, and infrastructure failures separate. Regression mode fails on required primary-condition failures; comparison mode still fails on infrastructure failures.
- Live calls are explicit, bounded by the selected cases/conditions/trials, and outside routine CI. Keep raw evidence under ignored tmp/.
- Add tests only for behavioral protection with material, complex, unique regression value.

## Task 1: Preserve and expose the command grader

**Files:** `evals/command-guidance/grader.rb`, existing `run.rb`, existing `tests/command-guidance-eval.rb`.

**Interfaces:** Preserve `CommandGuidanceEval.grade(command, test_case)`, `capture`, `command_from`, and `InfrastructureError`. The old runner requires the extracted module until cutover.

- [x] Extract the existing grading module without semantic changes.
- [x] Run all existing 23 grader/runner tests after extraction.
- [x] Add a JSON request-file/stdout entry point around the same production grader. Parse native events and retain response/usage when code-block extraction fails.
- [x] Exercise correct commands, bad arguments, invalid output format, and incomplete streams; retain existing missing-sandbox coverage. The suite now has 29 tests and 233 assertions.
- [x] Replay 216 prompt-matched saved responses, preserving originals. Per-shell calls/stdout/status, failure categories, response, and usage all match exactly. Actual report: ignored `tmp/grader-parity/report.json`.

**Reviewer verification:** `ruby tests/command-guidance-eval.rb` plus an ignored parity report containing the actual number of matched records and any mismatches. No model calls.

## Task 2: Integrate supported Harbor agent/verifier interfaces

**Files:** `evals/harbor/prompt_agent.py`, `evals/harbor/command_verifier.py`, behavioral integration tests.

**Interfaces:** `PromptOnlyPi` extends Harbor's Pi adapter, reusing installation/usage handling but preserving the exact isolated CLI invocation. `MacOSCommandVerifier(BaseVerifier).verify()` reads completed Pi events and a hidden staged case, invokes the Ruby JSON entry point, writes assessment/rewards, and returns native `VerifierResult`.

- [ ] Write failing behavioral tests that invoke the actual adapter transport with a fake CLI and the actual verifier through Harbor's factory.
- [ ] Verify full prompt/settings forwarding and disabled tools/context/session flags; reject unsupported resume or extra prompt-mutating features.
- [ ] Keep stdout events and stderr separate. Propagate command failures instead of hiding them behind a logging pipeline.
- [ ] Grade on the host through the unchanged macOS sandbox. Return combined, functional, and format-policy rewards; retain ungradable outputs and usage.
- [ ] Fail closed on invalid streams, missing artifacts, unsupported host sandbox, or grader transport errors.

**Reviewer verification:** Captured adapter argv/environment and native Harbor verifier results from offline fixtures. Verify the API using Harbor 0.24.0, not a substitute interface.

## Task 3: Share orchestration and cut over

**Files:** `evals/harbor/run.mjs`, suite staging/collection modules, both suite READMEs; remove obsolete orchestration only after parity passes.

**Interfaces:** Each suite prepares task directories, primary/control conditions, native agent/verifier settings, and expected cases/steps. The driver owns version checks, isolated host state, credentials, Docker configuration, subprocesses, artifacts, replay, summary, and exit status.

- [ ] Stage command tasks with the unchanged user requests and hidden case data. Use the custom prompt-only agent and native host verifier.
- [ ] Move existing naming staging/collection into its suite module, preserving the overlay and native trace checks.
- [ ] Implement one explicit suite/case/condition/trial selection contract. Record the resolved matrix and input hashes before execution; display paid user-turn counts with naming-child usage excluded.
- [ ] Support fresh output directories, explicit live runs, stage-only preparation, and replay of Harbor artifacts without credentials or model calls.
- [ ] Make regression mode gate only required primary conditions. Control failures remain evidence, not current-policy failures.
- [ ] Run offline parity/integration checks and stage both naming cases plus the command suite.
- [ ] Run a small frozen live command matrix: two cases, guidance/empty conditions, one trial each. Inspect isolation, rewards, artifacts, and usage. Do not claim statistical reliability.
- [ ] Remove the old Ruby experiment loop and naming-specific executor, retaining graders/fixtures/tests. Update runnable documentation and remove this completed plan from the final diff.
- [ ] Run final verification, inspect the full branch diff, commit, push, and create a draft PR. Keep the prior independent-review launcher failure disclosed; do not switch launchers without approval.

**Reviewer verification:** Offline replay/parity report, native Harbor trial config/results and raw events from the four-call live check, both naming task staging manifests, complete test output, and a draft PR with bounded claims.
