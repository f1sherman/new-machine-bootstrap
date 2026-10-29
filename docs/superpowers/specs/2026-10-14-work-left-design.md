# Work-left session decision

Status: self-reviewed and approved.

## Goal and boundary

Make `z-work-left` explicitly cover remaining work in the current thread or
any child threads, and whether the session should end. This saves Brian a
follow-up question. Keep the skill read-only; do not end the session or resume
work. Only the managed Pi skill changes.

## Approach and assumptions

Extend the existing short description and body. Keep model discovery because
users may ask either about remaining work or about ending the session.
The response should recommend whether to end, with a brief reason. Missing
thread information must be reported rather than treated as completed work.

Alternatives: change only the description (does not direct the response), or
add a detailed thread-inspection workflow (unnecessary coupling and context).
No change leaves the end-session question unanswered.

## Verification and rollout

Use matched synthetic thread snapshots: completed parent with unfinished child,
all work complete, and unavailable child status. Compare the original skill,
empty policy, candidate, and each added instruction removed in turn. Record
responses and token usage; do not claim statistical reliability. Preserve the
read-only safeguard regardless of this small sample. No permanent static-text
test is warranted under repository test policy.

Apply through `bin/provision --tags managed-skills`. Confirm the deployed skill
matches the managed source. No migration or new tooling is needed.
