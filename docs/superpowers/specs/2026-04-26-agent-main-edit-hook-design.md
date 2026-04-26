# Claude/Codex Main-Branch Edit Hook

**Status:** Approved
**Date:** 2026-04-26

## Goal

Prevent Claude Code and Codex from editing repository files on the `main`
branch in bootstrap-managed environments, while still allowing edits in safer
contexts.

After this change:

- Claude denies native file-edit tool calls on `main` when the target file is
  tracked by git
- Claude also denies native file-edit tool calls on `main` when the target file
  is untracked and not gitignored
- Codex enforces the same policy for its native edit path
- ignored scratch files remain editable on `main`
- the deny message is short and generic: move to a non-`main`
  branch/worktree per repo instructions, then retry
- the policy is managed entirely in `new-machine-bootstrap`

## Non-goals

- No repo-specific parsing of `CLAUDE.md` or `AGENTS.md` to decide whether the
  remediation should say "branch" or "worktree"
- No attempt to rewrite the blocked edit into a new branch or worktree command
- No enforcement for Bash-based write paths in this feature
- No enforcement for branches other than the literal local branch name `main`
- No blocking for files outside git repositories
- No changes to repo-local hook files in downstream application repositories

## Current State

This repository already manages hook infrastructure for both runtimes.

Claude:

- `roles/common/tasks/main.yml` creates `~/.claude/hooks/`
- the same task file installs managed Claude hook scripts from
  `roles/common/files/claude/hooks/`
- the same task file registers multiple Claude `PreToolUse` Bash hooks in
  `~/.claude/settings.json`

Codex:

- `roles/common/tasks/main.yml` enables `codex_hooks = true` in
  `~/.codex/config.toml`
- the same task file merges managed `PreToolUse` Bash hooks into
  `~/.codex/hooks.json`
- dedicated helper scripts already exist under `roles/common/files/bin/`

This means the missing piece is not hook plumbing. The missing piece is a new
policy layer for native file edits on `main`.

Current official hook capabilities support this design:

- Claude `PreToolUse` supports tool matchers such as `Edit`, `MultiEdit`, and
  `Write`
- Codex `PreToolUse` supports Bash plus file edits through `apply_patch`, with
  `Edit` and `Write` matcher aliases

That makes edit-time enforcement possible without depending on shell-command
heuristics.

## Design

### Summary

Add one dedicated native-edit blocker for Claude and one for Codex.

Keep the new hooks separate from existing worktree and push blockers so each
helper has one clear responsibility:

- existing hooks keep handling Bash policy
- new hooks handle native file edits on `main`

The policy is intentionally simple:

1. allow edits outside git repositories
2. allow edits when the current branch is not exactly `main`
3. on `main`, allow edits only when every target path is gitignored
4. on `main`, deny edits when any target path is tracked or untracked-but-not-ignored

When denied, the hook tells the agent to move to a non-`main`
branch/worktree per repo instructions, then retry.

### Claude hook

Add a new managed hook script under:

- `roles/common/files/claude/hooks/`

Register it in `~/.claude/settings.json` as a `PreToolUse` hook with matcher:

- `Edit|MultiEdit|Write`

The helper should use the same general pattern as the existing Claude hook
scripts:

- read JSON from stdin with `jq`
- exit success when required fields are missing
- emit a standard `PreToolUse` deny result when the policy blocks the edit

### Codex hook

Add a new managed helper under:

- `roles/common/files/bin/`

Register it in `~/.codex/hooks.json` as a `PreToolUse` hook for the native
edit path, using a matcher that covers:

- `apply_patch`
- `Edit`
- `Write`

This keeps the implementation aligned with current Codex hook behavior while
remaining explicit about the intended edit tools.

### Path extraction by runtime

The two runtimes expose edit targets differently, so path extraction should be
explicit instead of generic.

Claude:

- `Write` and `Edit` should read the target from `tool_input.file_path`
- `MultiEdit` should use the same target path field if present
- if Claude emits an unexpected payload shape with no usable path, allow

Codex:

- the native edit path is still represented as `apply_patch`
- candidate paths should be parsed from patch headers inside
  `tool_input.command`
- recognize:
  - `*** Add File: <path>`
  - `*** Update File: <path>`
  - `*** Delete File: <path>`
- if no recognized file headers are present, allow

### Policy evaluation

After extracting candidate paths, each helper should evaluate the edit request
in this order.

1. Identify the candidate target path or paths from the hook payload.
2. Resolve repository context with `git rev-parse --show-toplevel`.
3. Resolve the current local branch with `git branch --show-current`.
4. If not in a git repo, allow.
5. If the branch is not exactly `main`, allow.
6. For each target path:
   - if `git ls-files --error-unmatch -- <path>` succeeds, mark it as blocked
   - otherwise, if `git check-ignore -q -- <path>` succeeds, mark it as allowed
   - otherwise, mark it as blocked
7. Deny the tool call if any target path is blocked.

This produces the approved behavior:

- tracked file on `main` => deny
- untracked, non-ignored file on `main` => deny
- untracked, ignored file on `main` => allow
- feature branch => allow
- detached HEAD or unknown branch => allow, because the branch is not the
  literal string `main`

### Deny response

When a hook blocks an edit, it should return a short directive.

Reason text:

- `File edit blocked on main. Move to a non-main branch/worktree per repo instructions, then retry.`

The response should use each runtime's standard `PreToolUse` deny shape already
used elsewhere in this repository.

### Payload handling

The helpers should be conservative and fail open on malformed or incomplete
payloads.

Rules:

- if the payload does not contain any usable file path information, allow
- if the path cannot be evaluated cleanly, allow rather than risk blocking a
  non-editing tool invocation incorrectly
- if multiple paths are present, deny when any one path is blocked

Path handling should be robust enough for:

- absolute paths
- relative paths
- edits invoked from subdirectories inside the repository

No attempt should be made to canonicalize every filesystem edge case beyond
what is needed for reliable `git ls-files` / `git check-ignore` evaluation.

## Provisioning Changes

Update `roles/common/tasks/main.yml` in four places.

1. Install the new Claude hook script into `~/.claude/hooks/`.
2. Register a new Claude `PreToolUse` entry for `Edit|MultiEdit|Write`.
3. Install the new Codex helper into `~/.local/bin/`.
4. Merge a new Codex `PreToolUse` entry into `~/.codex/hooks.json` for the
   native edit matcher.

Requirements:

- preserve unrelated top-level JSON content
- preserve unrelated hook groups and existing managed hooks
- avoid duplicate managed entries on repeated runs
- continue enforcing `0600` on managed settings files

No changes are required to managed repo instructions in `~/.claude/CLAUDE.md`
or `~/.codex/AGENTS.md`.

## Testing Strategy

Add two regression layers per runtime.

### Hook helper tests

Add shell tests alongside each new helper covering:

- tracked file on `main` => deny
- untracked, non-ignored file on `main` => deny
- ignored file on `main` => allow
- tracked file on a feature branch => allow
- edit outside a git repo => allow
- Codex patch text with no recognizable file headers => allow
- multi-path edit with one blocked path => deny
- missing or malformed payload => allow

These tests should build temporary git repositories so tracked, ignored, and
branch-state behavior is empirical rather than mocked.

### Provisioning tests

Add provisioning regressions covering:

- installation of the new Claude and Codex helper scripts
- registration of the new Claude matcher exactly once
- merge of the new Codex hook entry exactly once
- preservation of unrelated hook groups and entries
- idempotence on rerun
- restoration of `0600` mode after drift where applicable

## Risks

- If path extraction is too narrow, some edit payload shapes may slip through
  unblocked.
- If path extraction is too loose, a hook could block an edit based on the
  wrong path field.
- If the settings merge logic duplicates entries, repeated provisioning would
  grow hook config files.
- If tests do not exercise real git ignore behavior, the ignored-file allow
  rule could regress unnoticed.

## Implementation Notes

- Keep these as dedicated helpers instead of extending the existing worktree or
  push blockers.
- Do not parse `CLAUDE.md` or `AGENTS.md` for remediation text in this feature.
- Prefer short, deterministic shell plus `jq` over abstraction-heavy shared
  libraries for the first pass.
- Match only the literal local branch name `main`, per approved scope.
