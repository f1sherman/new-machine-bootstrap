# BB Pi naming implementation plan

Execution: superpowers:executing-plans in the current session.
Status: self-reviewed and approved.
Goal: skip automatic native naming and omit its tool when BB_THREAD_ID is set.
Architecture: one initialization-time Boolean gates two presentation entry points.
Tech stack: JavaScript-compatible TypeScript, shell, Node.
Spec: ../specs/2026-10-15-bb-pi-naming-design.md

## Constraints and review focus

Keep ASR, completion, names, and all safety checks. Do not infer root ownership.
Cover empty/whitespace values, inherited markers, TUI/RPC contexts, and standalone
naming. Existing prompt text and unrelated hooks must not change.

## Task: gate the two naming entry points

File: roles/common/files/pi/extensions/managed-hooks.ts.

- [x] Run existing standalone baseline checks with BB_THREAD_ID unset.
- [x] Run a temporary production-handler probe against the baseline. Record the
  redundant naming child and exposed tool with BB_THREAD_ID present.
- [x] Capture `Boolean(process.env.BB_THREAD_ID?.trim())` inside the extension
  factory. Skip the initial naming evaluator and omit only the rename tool
  when true. Keep all other registrations and hooks.
- [x] Run the same temporary probe against the candidate for absent, empty,
  whitespace, and present markers in RPC and TUI; require correct naming calls,
  tool registration, retained done_session, and ASR registration.
- [x] Run both existing managed-hook shell checks with BB_THREAD_ID unset.
- [ ] Commit, obtain a fresh whole-branch review, and open a GitHub PR. Do not
  merge or claim deployment. Record author-initiated boundary evidence.

No new retained automated test: this small display gate fails material-harm
criteria. Temporary verification executes the production extension instead.

## Results

The matched baseline and candidate probes each completed eight scenarios. With
a present marker, baseline registered the rename tool and executed one naming
child in both RPC and TUI. Candidate registered no rename tool and executed no
naming child in both modes. Absent, empty, and whitespace markers retained one
naming child and the rename tool. Every case retained completion and ASR
registration. Both existing standalone managed-hook checks passed before and
after the change. The first probe lacked a theme stub; that fixture omission
was corrected before collecting the matched baseline/candidate results.
No inference was run: child execution used an inert sink. No deployed-session
or model token-savings measurement is claimed.
