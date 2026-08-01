# Tmux Agent Title Ownership Design

## Problem

A scheduled Codex Desktop automation inherited `TMUX` and `TMUX_PANE` from an unrelated Ghostty shell. The automation followed the managed task-label instruction and ran:

```sh
tmux-agent-subject set "Taiwan NZ award monitor"
```

The helper trusted the inherited pane identifier. It wrote an `agent/provisional` task to the unrelated pane. The automation then ended without clearing that state. Because tmux automatic renaming is disabled and provisional task state is durable, the unrelated window kept the false title.

Two behaviors are incorrect:

1. A process that does not run under a tmux pane can mutate that pane by inheriting its environment.
2. An interactive agent's provisional title remains after the agent exits and control returns to the shell.

## Goals

- Accept user-facing task-title mutations only from a process that runs under the target tmux pane.
- Clear an `agent/provisional` task when control returns to `zsh`.
- Restore the normal non-agent window title after the clear.
- Preserve active branch, goal, and manual task identities.
- Preserve internal remote-title adoption and detached tmux hook behavior.

## Non-goals

- Do not change Codex Desktop or depend on its automation lifecycle.
- Do not enable tmux automatic renaming or terminal title passthrough.
- Do not clear completed, branch, goal, or manual task identities when a shell prompt appears.
- Do not add compatibility heuristics for specific desktop applications.

## Design

### User-facing pane ownership gate

`tmux-agent-subject` is the user-facing entry point for agent-generated provisional task titles. Before `set` or `clear`, it will confirm that the current process belongs to `$TMUX_PANE`.

The check will:

1. Require `TMUX` and `TMUX_PANE`.
2. Ask tmux for the target pane's root process identifier (`#{pane_pid}`).
3. Walk the caller's parent-process chain.
4. Accept the operation only if the pane process appears in that chain.
5. Exit successfully without mutation when the pane is missing, the process chain cannot be verified, or the caller is unrelated.

The gate belongs in `tmux-agent-subject`, not in `tmux-agent-state`. Internal helpers call `tmux-agent-state` from detached tmux hooks and must remain able to target an explicit pane. This keeps the security boundary at the interface used by interactive agents and managed agent instructions.

This rule is application-independent. Codex Desktop, another GUI application, or any unrelated process cannot mutate a Ghostty pane merely because it inherited stale tmux variables.

### Provisional cleanup on shell return

The existing zsh `precmd` hook dispatches an ordered `tmux-title-transition` request with the effective command `zsh`. The transition helper will clear stale session-scoped state before it renders the shell title.

A new narrow `tmux-agent-state` operation will clear task state only when both conditions are true:

- `@task_source` is `agent`.
- `@task_state` is `provisional`.

For all other task sources and states, it is a no-op.

When `tmux-title-transition` processes a `zsh` transition, it will invoke this narrow operation before `tmux-window-label`. The existing renderer will then produce the normal non-agent title, such as `zsh | home-network-provisioning`. The transition's existing ordering and stale-request checks remain authoritative, so an older shell transition cannot overwrite a newer agent transition.

### State and lifecycle

The resulting lifecycle is:

1. An interactive agent starts under a tmux pane.
2. `tmux-agent-subject set` verifies process ownership and writes `agent/provisional` state.
3. The pane renders `~ <subject>` while the agent process owns the shell foreground.
4. The agent exits.
5. zsh runs `precmd` and submits a `zsh` title transition.
6. The transition clears only `agent/provisional` state.
7. The transition renders and publishes the normal shell title.

A background automation outside the pane fails at step 2 and creates no state that needs later cleanup.

## Error handling

Ownership verification fails closed. Missing tmux state, an invalid pane, an unavailable pane PID, or an unverifiable process chain causes a silent successful no-op. This matches the current helper behavior outside tmux and prevents task-label support from blocking agent work.

The narrow cleanup operation is idempotent. It succeeds when there is no provisional task to clear. Existing renderer and remote-title publication failures keep their current best-effort behavior.

## Testing

Automated tests will prove:

- A process descended from the target pane process can use `tmux-agent-subject set`.
- An unrelated process with copied `TMUX` and `TMUX_PANE` cannot change task state.
- Missing or invalid pane ownership fails closed.
- The narrow cleanup removes `agent/provisional` label, source, state, and context.
- The narrow cleanup preserves active branch, goal, and manual identities and completed task state.
- A `zsh` title transition clears provisional state before rendering the window label.
- Non-shell transitions do not clear provisional state.
- Existing remote provisional adoption remains functional because it uses the internal state interface.

End-to-end verification will start an agent in a disposable tmux pane, set a provisional title, exit to zsh, and confirm that the window returns to its normal shell label. A separate process with copied pane variables will be unable to set the title.
