---
date: 2026-07-22
topic: Synchronize Pi conversation identity with the tmux window header
status: approved
---

# Design: Pi conversation-aware tmux window headers

## Goal

When a tmux pane switches to or resumes a different Pi conversation, its tmux window header must stop showing the provisional task from the previous conversation. The header should adopt the active Pi session name immediately and keep following later Pi session renames.

Active branch labels remain authoritative after `repo-start`; conversation names must not replace them.

## Root cause

NMB intentionally separates two title channels on Linux development hosts:

- Pi and remote-pi update the inner tmux `pane_title` through `ctx.ui.setTitle()`.
- `tmux-agent-state` owns the durable `@task_label` used for the tmux window header and publishes that structured label to an outer tmux client through `tmux-remote-title`.

Linux tmux has `set-titles off` so arbitrary inner pane titles cannot overwrite the structured outer label. This is deliberate and prevents title clobbering.

The stale-header bug occurs because provisional agent task state is pane-local and survives Pi conversation replacement. `managed-hooks.ts` refreshes that existing task on `session_start`, and `before_agent_start` skips subject generation whenever a provisional task already exists. The new Pi conversation therefore updates `pane_title`, while the old `@task_label` remains the structured source for the tmux window header.

## Design

Extend the managed Pi extension so Pi session identity refreshes provisional tmux task identity.

### Session start

During `session_start`:

1. Read the session file already bound to `@persist_pi_session_file`.
2. Read the active Pi session file and display name.
3. If the bound file identifies a different conversation and the active Pi session has a non-empty display name, call `tmux-agent-subject set <session-name>` before the normal label refresh.
4. Continue setting `@agent_kind`, binding the new session file, and synchronizing the managed Pi session name as today.

The existing `tmux-agent-state set-provisional` behavior supplies the authority rule:

- a provisional agent task is replaced;
- a completed task can be replaced;
- an active branch task is preserved.

A first startup with no previous pane binding is not treated as a conversation switch. Existing repo/worktree identity remains untouched, and the ordinary first-prompt subject flow still applies.

### Pi session rename

Handle Pi's `session_info_changed` event. For a non-empty name, call `tmux-agent-subject set <name>`. This updates the same provisional task state and triggers the existing window-label and remote-title refresh path. Empty names are ignored rather than erasing useful task identity.

This covers `/name`, RPC-driven renames, and remote-pi's Pi-session-name synchronization without coupling NMB to remote-pi internals. A broker collision suffix such as `#2` remains mesh-specific display detail; the tmux header uses the Pi conversation name.

### Tmux client attach

Add `tmux-remote-title publish` to the existing `client-attached` hook path so attaching a client to an already-running remote tmux session republishes the current structured task label. This repairs an outer header even when no Pi or pane lifecycle event occurs after attach.

The publisher remains the sole remote-to-outer title owner. `set-titles` stays off on Linux, and raw `pane_title` propagation remains disabled.

## Error handling

All synchronization remains best effort:

- no tmux context: no-op;
- missing session file or display name: no-op;
- missing previous pane binding: preserve current task state;
- failed tmux/helper command: warn through the existing `exec()` wrapper and continue Pi startup;
- active branch task: helper refuses replacement.

No title synchronization failure may block session startup, resume, rename, or client attach.

## Testing

### Managed Pi hook contract

Extend `tests/pi-managed-hooks.sh` to prove:

1. resuming a different bound session replaces a stale provisional subject with the active Pi session name before label refresh;
2. restarting the same bound session does not rewrite the subject;
3. first startup with no prior binding does not rewrite the subject;
4. `session_info_changed` updates a non-empty session name;
5. an empty session name does not clear task identity;
6. the active session file is rebound after synchronization;
7. existing session naming, subject generation, main-branch guards, and spec tracking still pass.

### Tmux configuration contract

Extend `tests/tmux-managed-bars-contract.sh` or a focused hook contract to prove both managed tmux configurations retain one base `client-attached` hook and that the hook invokes `tmux-remote-title publish` in addition to existing attach maintenance.

### Regression and end-to-end verification

Run:

```bash
bash tests/pi-managed-hooks.sh
bash tests/tmux-agent-state.sh
ruby tests/tmux-pane-title-changed.rb
bash tests/tmux-managed-bars-contract.sh
bin/provision
```

After provisioning, verify in a nested remote tmux workflow:

1. resume conversation A and confirm the outer tmux window header uses A;
2. switch the same pane to conversation B and confirm the header changes to B;
3. rename B and confirm the header follows;
4. detach and reattach the remote tmux client and confirm B is republished;
5. activate a feature branch and confirm its branch label remains authoritative across conversation changes.

## Non-goals

- Do not change the Ghostty terminal tab title policy (`#S`).
- Do not enable Linux `set-titles` or raw pane-title propagation.
- Do not parse remote-pi footer strings or mesh notifications.
- Do not make collision suffixes part of durable task identity.
- Do not rename tmux sessions.
- Do not change branch/worktree label precedence.

## Files

- Modify: `roles/common/files/pi/extensions/managed-hooks.ts`
- Modify: `tests/pi-managed-hooks.sh`
- Modify: `roles/macos/templates/dotfiles/tmux.conf`
- Modify: `roles/linux/files/dotfiles/tmux.conf`
- Modify: `tests/tmux-managed-bars-contract.sh`
