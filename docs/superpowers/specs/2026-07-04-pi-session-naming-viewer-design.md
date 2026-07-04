# Pi Session Naming and Session Viewer Design

## Problem

Pi sessions created under Superpowers often start with similar context and are hard to distinguish in `/resume`. The tmux pane/window labels already track the current agent kind, subject, repo, branch, and worktree state for Claude and Codex. Pi only partially participates in that system: its managed extension marks the pane as `pi`, but does not refresh tmux labels or name the Pi session from those labels.

## Goals

- Make Pi session names match the tmux window label so Pi's session picker and third-party session viewers show meaningful names.
- Give Pi the same session-start tmux label refresh behavior that Claude and Codex already have.
- Keep tmux as the source of truth for label formatting instead of duplicating repo/branch/host formatting in TypeScript.
- Install the `pi-session-manager` package so `/sessions`, `/sessions all`, and `/sall` are available on provisioned machines.

## Non-goals

- Do not rename Claude or Codex sessions.
- Do not redesign tmux label formatting.
- Do not overwrite manually named Pi sessions unless the name was previously set by the managed Pi hook.
- Do not add permanent backwards-compatibility heuristics for old Pi sessions.

## Existing Behavior

Claude's `SessionStart` hook runs `tmux-claude-session-start`, which stores the Claude session id, marks the pane kind as `claude`, refreshes the cached pane label, and renames the tmux window.

Codex's `SessionStart` hook runs `codex-bind-tmux-pane`, which stores the Codex session id/cwd/transcript, marks the pane kind as `codex`, refreshes the cached pane label, and renames the tmux window.

Pi's managed extension currently runs `tmux-agent-state set-kind pi` on `session_start`. That marks the pane kind and indirectly refreshes tmux agent state, but the extension does not explicitly mirror the Claude/Codex label refresh steps and does not call `pi.setSessionName()`.

Later worktree changes also update tmux labels. `repo-start` calls `_worktree_publish_tmux_state`, which calls `tmux-agent-worktree set <path>`. That command writes `@agent_worktree_path`, updates `@pane-label`, publishes any cached PR link, and refreshes `tmux-agent-state`, which renders `@window-label`.

## Design

Extend `roles/common/files/pi/extensions/managed-hooks.ts` with a small session-name synchronization path.

On Pi `session_start`, when running inside tmux:

1. Run `tmux-agent-state set-kind pi` as today.
2. Run `tmux-update-pane-label $TMUX_PANE` to match Claude/Codex session-start behavior.
3. Run `tmux-window-label $TMUX_PANE` to apply the rendered window label.
4. Read the pane's `@window-label` tmux option.
5. Set the Pi session name to that window label using `pi.setSessionName()`.
6. Record that value in extension-local state so future automatic updates can distinguish managed names from user-supplied names.

After bash tool results, synchronize again. This catches `repo-start`, `tmux-agent-worktree set`, `tmux-agent-subject set`, and shell wrappers that update tmux state after the Pi session has already started. The hook should read the current `@window-label` and call `pi.setSessionName()` only when:

- the label is non-empty,
- it differs from the current Pi session name, and
- the current Pi session name is empty or equals the last name set by this managed hook.

This preserves manual `/name` values while allowing managed names to follow tmux label changes during normal repo/worktree lifecycle events.

## Session Viewer Installation

Update the managed Pi package install section in `roles/common/tasks/main.yml` to install `npm:pi-session-manager` alongside `npm:pi-subdir-context` on macOS and Linux. Provisioning should remain idempotent by treating `already installed` output as unchanged.

## Error Handling

All tmux synchronization is best-effort. If tmux is unavailable, `TMUX_PANE` is absent, a helper command is missing, or reading `@window-label` fails, the extension should skip naming without blocking Pi startup or agent work. Failures should use the existing managed hook warning path.

## Testing

- Extend `tests/pi-managed-hooks.sh` to verify the Pi `session_start` hook registers and runs the tmux refresh commands.
- Verify `pi.setSessionName()` is called with the rendered `@window-label`.
- Verify managed auto-renaming follows a later bash result when the tmux window label changes.
- Verify a user-supplied/manual session name is not overwritten by a later managed sync.
- Add or update Ansible/task contract coverage so both `pi-subdir-context` and `pi-session-manager` are installed for macOS and Linux.

## Open Questions Resolved

Pi session names should follow the tmux window label rather than a shorter custom label. That keeps one naming system across tmux and Pi session browsing.
