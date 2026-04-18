# Codex push-to-main hook

**Status:** Approved
**Date:** 2026-04-15

## Goal

Prevent Codex from pushing directly to the `main` branch in bootstrap-managed
environments.

After this change:

- Codex denies explicit pushes targeting remote `main`
- Codex also denies bare or non-explicit `git push` commands when the current
  local branch is `main`
- the deny message is short and directive: `Do not push to main directly. Open
  a PR.`
- the policy is managed entirely in `new-machine-bootstrap`

## Non-goals

- No changes to Claude hook behavior
- No attempt to block pushes to branches other than `main`
- No repo-local `.codex/hooks.json` files in application repositories
- No instruction-text changes in managed `CLAUDE.md` or `AGENTS.md`
- No automatic rewrite from a blocked push into a PR command
- No enforcement outside Codex's Bash tool path

## Current State

This repository already manages Codex hook infrastructure:

- `roles/common/tasks/main.yml` enables `codex_hooks = true` in
  `~/.codex/config.toml`
- the same task file merges a managed `PreToolUse` Bash hook into
  `~/.codex/hooks.json`
- the current managed Codex hook command is
  `~/.local/bin/codex-block-worktree-commands`
- regression coverage already exists for both the hook helper script and the
  Ansible hook-registration task

This means the missing piece is not general Codex hook support. The missing
piece is a second managed hook with narrower policy: deny pushes to `main`.

## Design

### Summary

Add a dedicated Codex `PreToolUse` Bash hook command for push-to-`main`
protection.

Keep it separate from the existing worktree hook so each helper has one clear
responsibility:

- `codex-block-worktree-commands` handles raw `git worktree` misuse
- `codex-block-git-push-main` handles direct pushes to `main`

Both hooks are registered in the managed user-level `~/.codex/hooks.json`
through `roles/common/tasks/main.yml`.

### Hook helper

Add a new installed helper script under:

- `roles/common/files/bin/codex-block-git-push-main`

Provisioning installs it into:

- `~/.local/bin/codex-block-git-push-main`

The script reads the Codex hook payload from stdin and extracts
`.tool_input.command`. If the payload is missing a command, the script exits
successfully without output.

### Matching rules

The script only evaluates real `git push` Bash invocations. It should ignore:

- non-Bash tools
- non-`git push` commands
- plain text mentions such as `echo git push origin main`

The matching should be conservative, following the same style as the existing
worktree blocker so it still catches common shell forms such as:

- plain invocations
- `git -C repo push ...`
- assignment-prefixed invocations
- `command git push ...`
- chained shell commands where one segment is a real `git push`

### Deny cases

The hook denies two categories of pushes.

1. Explicit destination to remote `main`

Examples:

- `git push origin main`
- `git push origin main:main`
- `git push upstream HEAD:main`
- `git push origin HEAD:refs/heads/main`
- `git push origin refs/heads/main`
- `git push origin :main`

This category is denied regardless of the current local branch.
For this design, "explicit destination to remote `main`" means any refspec
whose destination is `main` or `refs/heads/main`, including deletion refspecs.

2. Bare or non-explicit push while the current local branch is `main`

Examples:

- `git push`
- `git push origin`
- `git push -u origin`

This category is denied only when `git branch --show-current` resolves to
`main`.

This preserves the requested behavior:

- block explicit pushes to remote `main`
- also block pushes that would implicitly push local `main`
- allow normal pushes from feature branches

### Allow cases

The hook allows:

- pushes from non-`main` local branches when the command does not explicitly
  target remote `main`
- non-push git commands
- shell commands that only mention `main` as plain text
- PR-oriented commands that do not directly execute `git push` to `main`

### Deny response

When the hook blocks a command, it emits a standard Codex hook deny payload
with:

- `hookEventName`: `PreToolUse`
- `permissionDecision`: `deny`
- `permissionDecisionReason`: `Do not push to main directly. Open a PR.`

## Provisioning Changes

Update `roles/common/tasks/main.yml` to merge a second managed `PreToolUse`
`Bash` hook entry into `~/.codex/hooks.json` for
`~/.local/bin/codex-block-git-push-main`.

Requirements:

- preserve unrelated top-level content in `hooks.json`
- preserve unrelated hook groups and unrelated `PreToolUse` entries
- avoid duplicate managed entries on repeated runs
- continue enforcing `0600` on `~/.codex/hooks.json`

No changes are required to the existing `codex_hooks = true` config behavior.

## Testing Strategy

Add two regression layers, matching the existing Codex hook pattern.

### Script tests

Add a shell test alongside the helper under `roles/common/files/bin/` covering:

- explicit `git push origin main`
- explicit `git push upstream HEAD:main`
- explicit `git push origin refs/heads/main`
- bare `git push` while on local `main`
- `git push origin` while on local `main`
- allowed `git push` from a feature branch
- allowed non-push commands
- allowed plain-text mention of `git push origin main`
- missing or empty command payload

These tests should build temporary git repositories where needed so branch
resolution is empirical rather than mocked.

### Provisioning tests

Add a new regression under `tests/`, modeled after
`tests/codex-worktree-hook-provisioning.sh`, covering:

- the new Ansible task name and expected env wiring
- merge behavior into an existing `hooks.json`
- installation of the managed command exactly once
- preservation of unrelated hook groups
- idempotence on rerun
- restoration of `0600` mode after drift

## Risks

- If push detection is too loose, harmless text commands could be blocked.
- If push detection is too narrow, variant `git push` forms could slip through.
- If the hook merge logic duplicates entries, repeated provisioning would grow
  `hooks.json`.
- If script tests do not exercise real git branch state, the implicit-push
  behavior could regress unnoticed.

## Implementation Notes

- Keep this as a dedicated helper instead of extending
  `codex-block-worktree-commands`.
- Reuse the existing jq-based hook payload pattern used by the current Codex
  blocker.
- Prefer empirical git checks inside tests over string-only fixtures for the
  local-branch-dependent deny cases.
