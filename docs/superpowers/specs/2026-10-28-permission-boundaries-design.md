# Permission boundaries

Status: self-reviewed and approved for native execution.

## Goal
Reduce unnecessary requests for Brian's attention. Continue authorized work until a result or a real blocker. Preserve safety gates and explicit review checkpoints.

## Observed problem
An agent investigating an unsuccessful repair asked whether it could design the next workflow. Design was a safe, in-scope next step. Skill stage approvals competed with the existing bias toward action.

## Approach
Replace the vague action-default bullet in the managed Pi and Claude base fragments with one permission section. Codex receives the Claude guidance through its existing symlink. Explicitly replace Claude's unconditional spec-approval bullet. Keep all existing external-contribution, publication, workspace, credential, and automation safeguards.

Three components define the boundary:
1. Task authority covers necessary in-scope process steps, including revised designs after failed experiments. Skill ceremony and complexity do not create approval gates. User-requested checkpoints and narrower deliverables still bind.
2. Ask when authority is missing for a consequential action, or when an undiscoverable fact or incompatible user goals prevent a correct result. Use conservative assumptions for reversible implementation choices.
3. Before asking, inspect direct evidence and complete independent safe work. Ask one specific question with the decision, consequence, recommendation, and exact approval scope. Report progress without turning it into a request to continue.

Alternatives: keep only the vague default (already insufficient); modify third-party skills (unnecessary ownership and maintenance cost). Prefer a local instruction override that explicitly outranks skill gates.

## Verification
Freeze a small task-only decision matrix before generation. Compare the previous Pi base, candidate, empty-policy control, and each leave-one-component-out condition with identical loaded skill text and model settings. Capture responses and tokens. Assess next-action decisions manually against frozen criteria; this is a provider-library decision probe, not an actual tool-executing agent or proof of universal compliance. Retain untested safeguards. Do not add static prose tests.

Run provisioning and compare deployed base fragments with repository sources. Existing sessions may need reload; new instructions do not retroactively prove the original repair succeeded.

## Non-goals
No new blanket merge, deployment, credential, deletion, spending, third-party publication, or persistent-automation authority. No changes to third-party skill repositories or other live threads.
