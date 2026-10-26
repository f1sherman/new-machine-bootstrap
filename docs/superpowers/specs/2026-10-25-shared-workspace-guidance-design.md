# Shared workspace guidance

Status: self-approved. Execution: Native.

## Goal

Tell agents which shared tools own branch creation and cleanup before a guard rejects an ordinary Git command.

## Evidence and scope

A weekly review found blocked setup commands in several independent sessions. One session repeated the mistake. An approved cleanup of unpublished work stopped after a guard rejection. These are symptoms in shared tooling, not a repository-specific rule.

The shared Pi base lacks a lifecycle instruction. The Claude base already names `repo-start`, but does not clearly distinguish cleanup cases. Codex uses the assembled Claude instructions.

## Approach

Update the Pi and Claude base fragments. Require `repo-start <branch>` for source work that needs a new branch or worktree. Reuse existing isolation. Keep repository worktree preferences and generated-state exceptions intact. Read `--help` when a helper fails; do not bypass the guard or edit the main checkout as a fallback.

Use `repo-end` for integrated work and `repo-end --closed` only for a fully published branch with a closed, unmerged pull request. Unpublished work with changes absent from main has no discard mode. Preserve it and report the precise limitation. Do not publish abandoned work merely to enable deletion. Environment-owned worktrees remain under their owner's cleanup rules.

## Alternatives

- Add rules in each repository: rejected because the guard is shared and rules would drift.
- Add a destructive discard mode: deferred. It needs separate authorization and safety design. Clear guidance can correct the present confusion without expanding deletion authority.
- Change the upstream generic worktree skill: rejected because the command requirement belongs to this environment.

## Verification

Run bounded model comparisons with current guidance, proposed guidance, and each new component removed. Use sanitized historical setup and cleanup decisions. Include generated-state and environment-owned safety cases. Keep tasks, tools, model, settings, and scoring fixed. Record tool choices and token usage. Do not start native Pi or modify retained sessions.

Exercise the actual lifecycle scripts in temporary Git repositories with a local remote. Confirm integrated cleanup succeeds and unpublished unique work survives rejection. No real abandoned workspace is deleted. Do not add tests that assert prose strings.

## Rollout

Open one pull request containing the instructions, plan, and sanitized results. Keep private evidence outside the public diff. No guard, deletion policy, or live infrastructure changes are in scope. Deployment remains separate from evidence that agents follow the instructions.
