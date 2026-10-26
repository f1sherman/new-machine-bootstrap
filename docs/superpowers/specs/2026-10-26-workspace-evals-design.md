# Repeatable workspace guidance evals

Status: self-approved. Execution: Native.

## Goal

Replace one-off diagnostic evidence with committed, repeatable behavioral evals. Do not change the guidance while measuring it.

## Scope and approach

Use three small decisions: create an isolated handoff, retire unpublished work after a direct removal was blocked, and update owned generated state without source changes. The first two are sanitized reductions of observed sessions; the third is a synthetic destructive-boundary control. Keep provenance and limitations with each fixture. Retain untested safeguards.

Run provider-library calls directly, without starting native Pi or registering automatic repair. Each trial gets a fresh, network-disabled Docker container containing disposable repositories and read-only production lifecycle scripts. Tools execute inside that container, never on the host. No credentials enter the container. A root-owned system-call trace records actual helper execution, so echoed command names cannot count as success. Use the existing shell guard before Bash calls and inspect actual repository state afterward. This tests shared shell behavior, not full native Pi integration or hostile sandbox escape resistance.

The runner stages a frozen manifest before paid calls. Compare current guidance with the previous long rules, each component removed, and both removed. Use two repetitions per case and condition. Hold tasks, tools, model, reasoning, skill input, runtime image, and grader constant. Keep all results, including failures. Timeouts, malformed responses, missing evidence, and invalid judge output are incomplete runs, not scored behavioral failures.

Score observable state and actual helper calls first. For unpublished cleanup, use a separate hidden semantic judge only to check that the terminal reply accurately explains preservation and does not promise a bypass. Calibrate that judge with accurate, false, negated, and unsafe-promising replies. Never tell the candidate the rubric.

## Alternatives

- Commit the old substring-based simulator: rejected. It previously confused command discovery with execution.
- Use the existing native-session Harbor suite: not selected because this task prohibits starting native Pi.
- Execute generated commands on host scratch: rejected because changing the current directory is not a security boundary.

## Verification and safety

Run offline grader tests before live calls. Exercise the production helpers in the container with correct, wrong, misleading, and destructive traces. Validate tool input and reject unsupported tool names without execution. Keep the image and source hashes in each manifest. Every container is labelled and recorded before use; the foreground runner owns removal on success, failure, or interruption. Check for leftovers after the run.

A passing small matrix supports only these bounded decisions. Record fixed input cost and total trial tokens separately. No live deployment, real branch deletion, or infrastructure repair is in scope.
