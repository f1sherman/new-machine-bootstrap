# Harbor Session Naming Implementation Plan

Execution: Native execution in the current session. Use the existing isolated worktree. One fresh-context final review when available.

Goal: evaluate session naming during real coding and issue-reporting work.
Architecture: Harbor owns Docker, multi-step resume, trajectories, verification, and rewards. A small staging runner exports production guidance variants and runs the native Pi adapter. Hidden verification checks Pi events, persistent session names, real script execution, and sandbox issue records.
Versions: Harbor 0.24.0; Pi 1.0.2; low thinking for the main agent; the same selected model for automatic initial naming.

## Tasks

- [x] Add a hidden trace verifier and behavioral regression tests. Observe the missing-scoring failure before adding scoring; retain incomplete-stream and redundant-rename rejection checks. Verify complete call/result pairing, tool declarations, provider usage, session continuity, and session metadata; name rules must not pass because the agent did no work.
- [x] Package the five-step public-source workflow task. Copy the production scripts and existing restoration harness with pinned provenance. Add a first-window-lookup race reproduction and a branch-picker failure-status test. Confirm both fail against the unmodified scripts. Keep hidden tests out of the agent environment until grading; Harbor removes them before resuming. Provide an actual local issue creation/lookup tool.
- [x] Replace the naming-only runner with Harbor staging and comparison. Keep definition.mjs. Use a registration proxy to change only tool descriptions. Stage Docker contexts under tmp. Run the built-in Pi adapter with native resume and normal tools; pin versions. Export baseline/current and the three section ablations plus the empty-description control. Preserve raw jobs and summarize measured step rewards, calls, names, and workflow tokens.
- [x] Run the live pilot and matched variants. Inspect native session IDs and actual calls, not only scores. Re-run behavioral verifier checks with a redundant naming call and incomplete stream to confirm rejection. Record actual outcomes and limits, including automatic child usage accounting.
- [x] Update README and record a public-safe results summary. Remove obsolete synthetic cases/tool shim/runner logic; retain labeled historical result files. Verify syntax, source hook tests, and diff. Independent review could not start because the host runtime lacks the Pi core Node entry point. Do not substitute another launcher.

Publication: commit, push, and update the existing PR. No managed/deployed files changed, so this source-only eval refactor needs no new deployment.

Evidence: the current-only pilot passed all five task and naming steps. The six-variant comparison completed 30 task steps and passed 26 naming checks (5, 5, 4, 5, 4, 3 by variant). Six trace-grader tests pass. The final verifier regraded all 30 native traces with identical naming scores. Automatic child usage remains unmeasured; broad-name semantics are not an automated reward.

Reviewer evidence: run the documented opt-in command, inspect each Harbor step's agent/pi.txt, agent/pi/sessions/*.jsonl, trajectory.json, verifier/reward.json, and verifier/assessment.json; compare these with the committed measured summary. Native session IDs must remain equal across all five steps. The issue record must exist and the two repaired scripts must pass hidden execution tests.
