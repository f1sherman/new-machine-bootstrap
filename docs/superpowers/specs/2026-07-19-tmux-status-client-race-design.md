# Tmux Status Client Race Design

## Goal

Keep tmux window tabs visible for direct terminal clients while avoiding duplicate bars for sessions viewed only through nested multiplexers. Client attach, detach, and session changes must converge on the correct session status without leaving stale state.

## Problem

The macOS and Linux tmux configs currently inspect the client that triggered `client-attached` or `client-session-changed` and immediately run `set status on` or `set status off`.

Nesting is a client property: a direct Ghostty client typically reports `xterm-256color`, while a nested tmux or screen client reports `tmux*` or `screen*`. The `status` option is session-scoped, however. One nested or control-mode client can therefore hide the shared bar from an already-attached direct client. The configs also do not reconcile on detach, so the session can remain hidden after that client exits.

This was observed when an orphaned `tmux -C attach-session -t hnp` process with `TERM=tmux-256color` attached to `hnp`. It changed only that session to local `status off`, hiding tabs from its direct Ghostty client. Killing the orphan did not restore the bar.

## Shared policy

The desired session value is derived from the complete set of clients currently attached to it:

- If any direct client is attached, set `status on`.
- If one or more clients are attached and every client terminal is `tmux*` or `screen*`, set `status off`.
- If no clients are attached, set `status on` as the safe default.

Direct clients win in mixed-client sessions because hiding the bar removes their only tmux window navigation. Nested clients may see a duplicate inner bar in that mixed case, which is preferable to breaking direct clients. A nested-only session still hides the duplicate bar.

## Implementation

Add a shared executable helper, `roles/common/files/bin/tmux-reconcile-status-bars`. It will:

1. Exit without changes when global `@managed-bars` is `off`.
2. Enumerate every tmux session.
3. Enumerate the clients currently attached to each session and inspect `client_termname`.
4. Apply the shared policy with a session-targeted `set-option`.
5. Tolerate sessions or clients disappearing during reconciliation.

Reconciling all sessions is intentional. A `client-session-changed` event changes both the destination session and the session the client left, while its hook context does not provide a reliable old-session target. A full pass is small and makes both sides converge.

Install the helper through the common Ansible role. Keep the existing cleanup for the removed `tmux-sync-status-visibility` implementation; the new helper has a distinct name and different all-client semantics.

In both:

- `roles/macos/templates/dotfiles/tmux.conf`
- `roles/linux/files/dotfiles/tmux.conf`

remove the current per-client TERM toggles and invoke the reconciler asynchronously from:

- `client-attached`
- `client-detached`
- `client-session-changed`
- config load

The config-load pass repairs existing local `status off` values immediately after provisioning or sourcing the config. Hook array appends preserve unrelated existing hook commands.

## Failure behavior

The reconciler is best-effort and idempotent. A session disappearing between listing and update is skipped rather than making a tmux hook fail. If client enumeration for an existing session fails, the helper does not infer a nested-only state. `@managed-bars=off` remains a complete opt-out so external configuration can own status visibility.

## Testing

Extend the managed-bars behavioral contract around an isolated tmux server and real pseudo-terminal clients. Cover:

1. direct-only session shows status;
2. nested-only session hides status;
3. nested attach cannot hide status from an existing direct client;
4. direct detach from a mixed session leaves nested-only status hidden;
5. nested detach from a mixed session leaves direct status visible;
6. last client detach restores status on;
7. client session changes reconcile both source and destination sessions;
8. `@managed-bars=off` prevents changes;
9. macOS and Linux configs register attach, detach, session-change, and load reconciliation.

Run the repository contract tests, tmux config parsing checks, Ansible syntax validation, and local provisioning/check workflows available on macOS. End-to-end proof must use isolated sockets so it cannot mutate the developer's live tmux sessions.

## Scope

This PR contains only the status reconciliation helper, its installation/config wiring, tests, and this design/plan documentation. It must not include PR #341's stale-window-label work or any other tmux label changes.
