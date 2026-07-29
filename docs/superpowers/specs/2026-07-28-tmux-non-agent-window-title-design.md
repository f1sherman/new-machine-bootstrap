---
date: 2026-07-28
topic: Restore program and project titles outside coding-agent sessions
status: approved
---

# Design: Non-agent tmux window titles

## Goal

When a tmux pane is not running a coding-agent TUI, its window header must show the foreground program and top-level directory as `<program> | <directory>`. Inside Git, `<directory>` is the worktree root basename. Outside Git, it is the current directory basename.

Managed coding-agent task, goal, and branch titles remain authoritative while the corresponding coding-agent TUI is running.

## Root cause

Coding-agent task state is intentionally durable in pane-local tmux options. `tmux-window-label` treats that state as authoritative without checking whether the pane still runs an agent. After the agent exits and another program such as Neovim starts, focus and session hooks refresh the old managed label instead of replacing it. Automatic tmux renaming is disabled deliberately to prevent programs from clobbering structured agent and remote titles, so tmux cannot repair the stale name itself.

## Design

### Window-label authority

Extend the existing window-label renderer to distinguish a live coding-agent TUI from stale coding-agent metadata.

A managed task label remains authoritative only when the effective foreground command is a coding-agent process consistent with the pane's managed agent kind. Otherwise, the renderer ignores cached task and worktree title state for the visible window name and produces a non-agent fallback.

The non-agent fallback is:

```text
<program> | <directory>
```

The directory resolver uses the Git worktree root basename when `git rev-parse --show-toplevel` succeeds for the pane path. It uses the current directory basename otherwise. Root paths retain a useful `/` fallback.

The renderer also removes coding-agent activity and PR indicators from a non-agent window. Durable pane options may remain available for later agent lifecycle cleanup or resume; stale metadata must not control the visible non-agent title.

### Immediate shell transitions

Extend the managed zsh lifecycle hooks:

- `preexec` invokes the window-label renderer with the command about to run, allowing an immediate title such as `nvim | blog` before tmux observes the child process.
- `precmd` invokes the renderer with `zsh`, restoring `zsh | blog` when the command exits.
- the existing `chpwd` path refreshes the label after directory changes.

The renderer accepts an optional effective-command override for these pre-execution transitions. Without an override, existing tmux focus and client-session hooks use `pane_current_command` and repair missed or externally initiated transitions.

The existing remote-title publication path runs only after a successful corrected label update so nested tmux clients do not republish a stale coding-agent subject.

Ordered transition state is scoped by a POSIX `cksum` of the full tmux socket path plus pane ID. Its directory lock publishes PID and request identity together through a temporary file and atomic rename. A waiter validates that identity against the live process argv before preserving the lock, so an unrelated process that reused the PID does not strand the queue.

Each zsh clamps its request timestamp to the greatest timestamp it has already emitted. PID and serial fields retain uniqueness, and later requests from that shell remain lexically newer if wall clock moves backward.

### Agent transitions

Known agent launches may briefly use the non-agent fallback before their normal startup hooks establish `@agent_kind` and task state. Once established, the existing agent refresh path restores the managed task title. Agent exit returns to the shell fallback through `precmd`.

No automatic rename or raw pane-title propagation is enabled.

## Error handling

All title updates remain best effort:

- no tmux pane: no-op;
- missing or empty command: use the pane's current command, then a shell fallback;
- Git lookup failure or non-Git directory: use the current directory basename;
- missing path: retain the existing title rather than emitting a malformed label;
- tmux/helper failure: do not block shell command execution or prompt rendering.

## Known minor limitations

Cross-shell ordering still uses wall clock because synchronous shared coordination would block prompt transitions. If a replacement shell starts after a backward clock adjustment, its requests can sort behind the prior shell's high-water mark until wall clock catches up. The exposure is bounded by the size of the rollback; same-shell requests are clamped and remain ordered.

Request files normally disappear through the transition helper's exit trap. An untrappable termination can leave a file in the private per-user state directory. Age-based garbage collection remains deferred: unsafe deletion could discard a genuinely pending request, while the residual risk is limited disk growth from small files.

## Testing

Add regression coverage proving:

1. stale provisional, active, or completed agent metadata does not control a window running Neovim;
2. a non-agent Git pane renders `nvim | <worktree-root>` from a nested directory;
3. a non-Git pane uses its current directory basename;
4. live Claude, Codex, and Pi commands preserve managed titles;
5. non-agent rendering clears visible agent/PR indicators;
6. zsh `preexec` requests the launched program label before remote publication;
7. zsh `precmd` restores the shell label;
8. existing remote, structured-title, branch, and task-label contracts remain green.

After automated tests, run `bin/provision` and verify an actual tmux pane transitions from an agent subject to `nvim | <repo>`, then back to `zsh | <repo>` after Neovim exits.

## Non-goals

- Do not clear or migrate durable coding-agent state merely because another program is running.
- Do not enable `automatic-rename`, `allow-rename`, Linux `set-titles`, or terminal passthrough.
- Do not poll panes periodically.
- Do not change Ghostty's session-title policy.
- Do not change managed title formatting while an agent is live.

## Files

Expected implementation surface:

- Modify: `roles/common/files/bin/tmux-window-label`
- Modify: `roles/common/templates/dotfiles/zshrc.d/10-common-shell.zsh`
- Modify: `tests/tmux-label-contract.sh`
- Modify focused shell-hook contract tests if separation improves clarity
