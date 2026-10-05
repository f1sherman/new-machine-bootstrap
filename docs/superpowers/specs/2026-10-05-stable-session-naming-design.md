# Stable Session Naming

## Goal

Keep the Pi session name stable while work contributes to the same broad goal. The name is a durable identity, not a task status.

## Approved guidance

Preserve the current name by default. Set a broad name once when the goal becomes clear, including when the initial automatic name is provisional. Rename later only for an explicit rename request or a clear switch to an unrelated broad goal. If the work still contributes to the existing goal, or the distinction is uncertain, preserve the name.

Related implementation, debugging, verification, deployment, and review retain the name. Recording, reporting, or briefly investigating an incidental finding also retains the name, even when the finding is unrelated. Resuming or recovering context does not reset naming. Preserve direct user names throughout related work. Most sessions should retain one agent-selected name for their lifetime.

## Scope

Update only the model-facing description of `set_session_name` in `roles/common/files/pi/extensions/managed-hooks.ts`. Keep initial automatic naming, the explicit rename skill, and the mutation interface unchanged. Keep the existing subject and outcome naming guidance.

## Live evals and prompt size

Add opt-in live tool-call evals under `evals/session-naming/`. Load the production tool definition but replace execution with a harmless recording stub. Give each case its own in-memory Pi invocation, with no other tools, extensions, context files, or persisted sessions. Score observed calls rather than asking the model to classify cases. Require one valid call for initial naming, explicit renames, and clear goal changes; require zero calls for related work and incidental findings. An explicit user name must match exactly.

Cover incidental tickets and reports, brief investigation, uncertainty, resume, user-selected names, provisional initial naming, explicit renames, and genuine goal changes. Run repeated trials against the current description and a selected Git revision. Keep the fixture expectations out of model context. Save model identity, calls, errors, and first-request provider usage to a report. Compare matched first-request input totals, including cache reads and writes; do not label this as a tokenizer count of the description alone.

Shorten the production description toward half its current length without changing the approved threshold or the subject-and-outcome criteria. Use observed decisions and input-token usage to evaluate the trade-off. Evals require credentials and model calls, so keep them out of routine CI. Sample decisions are not a guarantee of future behavior.

## Verification

Run the existing managed-hook checks. Run the live eval suite with repeated trials against both descriptions and leave-one-section-out ablations. Include an empty-description control and keep the name parameter schema unchanged. Score call behavior automatically and review durable-name quality separately. Record regressions and token changes; a negative control is not an ablation. Confirm the suite can detect a deliberately wrong rename policy and fails on provider or parse errors. Apply with `bin/provision` and compare the deployed extension with the source. Keep the eval command, actual results, and limitations visible in the PR.
