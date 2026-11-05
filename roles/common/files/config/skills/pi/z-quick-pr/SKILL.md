---
name: z-quick-pr
description: >
  Use when a user wants a change taken through implementation, verification,
  and pull request without clarifying questions or approval loops.
---

# Quick PR

Take the request to a verified pull request using poteto-mode and its adapter.
Use the matched playbook rather than a separate spec-and-plan workflow.

## Process

1. Read `~/.pi/agent/skills/poteto-mode/SKILL.md` and follow its adapter.
2. Inspect repository instructions, relevant files, and existing behavior. Reuse
   isolation or create the workspace required by repository policy.
3. Resolve observable questions from evidence. Ask one blocking question only
   for a missing fact you cannot discover, incompatible product choices, or a
   security, privacy, credential, destructive, legal, billing, or publication
   decision that needs authorization. Otherwise make a conservative assumption.
4. Follow the matched poteto-mode playbook. Create a spec or plan document when
   the user requests one or that playbook requires it. Preserve repository
   document paths and ignore rules when creating such a document.
5. Implement in the current session. Delegate implementation only when the user
   requests it. Respect repository test policy and verify the affected behavior
   before claiming success.
6. Commit completed work and invoke `z-pull-request` from the implementation
   worktree. Require passing verification and a clean worktree before
   publication. The PR workflow owns the final fresh-context branch review;
   do not dispatch a duplicate review. If independent review is unavailable or
   unauthorized, disclose that limit.

Continue to the pull request without an execution-mode or intermediate approval
prompt unless a blocking decision requires the user. Keep merge and other
publication authority separate from this workflow.
