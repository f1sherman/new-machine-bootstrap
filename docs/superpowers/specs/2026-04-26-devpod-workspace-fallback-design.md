---
date: 2026-04-26
topic: Improve DevPod tmux label fallback when workspace parsing fails
status: approved
---

# Design: DevPod workspace fallback for tmux labels

## Goal

Improve the tmux naming path for DevPod sessions so the UI shows a useful
workspace-oriented label more often, instead of degrading to bare `devpod`
when process-list parsing misses the workspace name.

The desired best-effort behavior is:

- if `devpod ssh <workspace>` is visible, use `<workspace>`
- if argv parsing misses but `DEVPOD_WORKSPACE_ID` exists, use that
- if neither workspace source exists but an SSH host is known, use the host
- only fall back to literal `devpod` as the last resort

This should make the pane border, remote title path, and session-name path
agree on DevPod identity without broad tmux refactoring.

## Non-goals

- No attempt to guarantee a workspace label when neither argv nor environment
  exposes one.
- No changes to tmux hooks, Ghostty integration, or `worktree-start`.
- No broader cleanup of SSH/Codespaces labeling beyond the narrow DevPod path.
- No change to the existing precedence where Codespaces naming wins over
  DevPod when both are set.
- No requirement to live-verify on a DevPod machine during this design phase.

## Background

Current behavior is split across multiple helpers:

- `tmux-remote-title` already reads `DEVPOD_WORKSPACE_ID`
- `tmux-host-tag` already reads `DEVPOD_WORKSPACE_ID`
- `tmux-pane-label` does not read `DEVPOD_WORKSPACE_ID`; it only parses
  `devpod ssh <workspace>` from the process list
- `tmux-session-name` has its own remote-session logic and treats DevPod as a
  special case, but it does not share one DevPod resolver with the other paths

This creates an avoidable degraded case:

1. the pane is in a DevPod remote context
2. `ps` still proves it is DevPod-related
3. the workspace name is not recoverable from argv in the exact format the
   helper expects
4. `tmux-pane-label` falls back to literal `devpod`
5. another helper may still know the workspace name from
   `DEVPOD_WORKSPACE_ID`

So the likely problem is not that `DEVPOD_WORKSPACE_ID` is universally broken.
It is that the most visible label path does not currently consult it.

## Approaches considered

### 1. Minimal `tmux-pane-label` patch

Teach only `tmux-pane-label` to fall back from failed DevPod argv parsing to
`DEVPOD_WORKSPACE_ID`.

Pros:

- smallest code diff
- directly addresses the most visible degraded label

Cons:

- keeps DevPod naming logic split across scripts
- leaves room for window/session drift

### 2. Recommended: shared DevPod fallback

Create one small shared DevPod resolver and use it from the existing tmux
helpers that already participate in remote naming.

Pros:

- fixes the likely failure mode
- keeps pane, title, and session behavior aligned
- still narrow in scope

Cons:

- touches a few scripts instead of one

### 3. Full remote-label consolidation

Refactor SSH, Codespaces, and DevPod naming onto one broader remote-label
subsystem.

Rejected because it is more scope than needed for a best-effort DevPod fix.

## Design summary

Add one small shared helper under `roles/common/files/bin/` that resolves the
best available DevPod identity from the current environment and, when needed,
from a parsed `devpod ssh` command line.

DevPod precedence should be:

1. parsed `devpod ssh <workspace>`
2. `DEVPOD_WORKSPACE_ID`
3. SSH host, when available to the caller
4. literal `devpod`

This helper should be consumed by:

- `tmux-pane-label`
- `tmux-remote-title`
- `tmux-session-name`, but only within its existing remote-handling path

The change is deliberately narrow: it fixes how DevPod identity is chosen, not
how tmux hooks fire or how remote labels are generally structured.

## Shared helper contract

The helper should answer one question:

> "Given the current DevPod-related command/environment context, what is the
> best name to show for this remote?"

Inputs may include:

- a full args line such as `devpod ssh workspace-beta`
- `DEVPOD_WORKSPACE_ID`
- an SSH host value if one has already been derived

Output rules:

- return `<workspace>` when argv parsing succeeds
- otherwise return `DEVPOD_WORKSPACE_ID` when set
- otherwise return the SSH host when it is available to the caller
- otherwise return `devpod`

The helper must stay silent on internal failure and always degrade to a plain
string result. No script should print errors into tmux UI paths.

## Consumer behavior

### `tmux-pane-label`

File: `roles/common/files/bin/tmux-pane-label`

Replace the current inline DevPod fallback with the shared helper.

Required behavior:

- if `ps` shows a `devpod ssh` line with a parseable workspace, keep today's
  workspace label behavior
- if `ps` proves DevPod but the workspace token cannot be parsed, consult
  `DEVPOD_WORKSPACE_ID`
- if the env var is also absent and a host hint is available, prefer that
  host over literal `devpod`
- only emit bare `devpod` as the last resort

This is the main user-visible fix because the pane/window labeling path most
often flows through this helper.

### `tmux-remote-title`

File: `roles/common/files/bin/tmux-remote-title`

Keep the current host precedence shape, but have the DevPod branch use the same
shared resolver contract so remote-title publishing does not drift from
`tmux-pane-label`.

This should preserve today's behavior when `DEVPOD_WORKSPACE_ID` is already
present while aligning fallback behavior with the pane-label path.

### `tmux-session-name`

File: `roles/common/files/bin/tmux-session-name`

Apply only a narrow DevPod fallback patch within the existing remote-session
handling path. Do not broaden session-renaming behavior.

The goal here is not to redesign session naming. It is only to avoid obvious
mismatch where session naming knows less about DevPod identity than the shared
resolver does.

## Testing strategy

Extend existing shell-script tests instead of adding a new framework.

Required coverage:

- parseable `devpod ssh workspace-beta` still yields `workspace-beta`
- unparseable DevPod argv plus `DEVPOD_WORKSPACE_ID=workspace-beta` yields the
  workspace name
- unparseable DevPod argv plus no env var falls back to SSH host when present
- final fallback remains literal `devpod`

Likely touched tests:

- `roles/common/files/bin/tmux-pane-label.test`
- `roles/common/files/bin/tmux-remote-title.test`
- `tmux-session-name` test coverage if a matching test already exists or is
  easy to extend

The design only requires repo-level verification for the precedence chain. A
live DevPod-machine check can happen later during implementation or manual
validation.

## Risks and constraints

- `DEVPOD_WORKSPACE_ID` may not exist in every entry path, so the helper must
  remain best-effort.
- Some DevPod invocation shapes may still be unparseable from argv, which is
  why env and host fallback remain necessary.
- Session naming is intentionally kept narrow to avoid reintroducing unrelated
  tmux churn.
