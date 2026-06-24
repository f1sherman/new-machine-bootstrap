# Nested tmux Top Status Bar Hiding — Design

**Goal:** Remove the broken, unwanted `tmux-sync-status-visibility` helper script and replace it with a working, script-free mechanism that hides a tmux server's top status bar when it is viewed through an outer multiplexer (nested tmux — e.g. SSH'd into a remote tmux from the local one). When nested, the outer (local) bar stays; the inner (remote) bar hides. A direct, non-nested attach shows the bar normally.

## Background: why the current approach fails

`roles/common/files/bin/tmux-sync-status-visibility` gates on `SSH_CONNECTION`:

```bash
if [ -n "${SSH_CONNECTION:-}" ]; then
  case "${client_termname:-}" in
    tmux*) status="off" ;;
  esac
fi
```

The script runs from tmux `run-shell` hooks. `run-shell` commands execute in tmux's **global** environment. `SSH_CONNECTION` is delivered to tmux's **session** environment via `update-environment`, not the global environment, so it is empty in the hook's shell. The `status="off"` branch therefore never runs and the bar never hides.

The `client_termname` check would have worked on its own. Nesting detection does not require SSH: a client whose `TERM` is `tmux*`/`screen*` is, by definition, running inside another multiplexer. That terminal name is the reliable nesting signal, and reading it via a tmux format avoids the environment problem entirely.

## Approach

Detect nesting purely from the client terminal name using a tmux format conditional (`if-shell -F`), matching the repo's existing zero-fork detection idiom (`is_vim`, `is_ssh`). Toggle `set -g status` on the `client-attached` and `client-session-changed` hooks — the events at which nesting can actually change. No helper script, no shell env dependency.

Rejected alternatives:
- **Unconditional `status off` on Linux only** — simplest, but wrong on a direct attach and does not cover local tmux-in-tmux.
- **Rewrite the helper script with fixed detection** — explicitly unwanted; the script is being removed.

## Changes

### Remove

1. **Delete** `roles/common/files/bin/tmux-sync-status-visibility`.
2. **Remove** the `tmux-sync-status-visibility` entry from the install loop in `roles/common/tasks/main.yml` (the `Install tmux label helpers` `copy` task's `loop`).
3. **Add a cleanup task** in `roles/common/tasks/main.yml` that removes the already-deployed `~/.local/bin/tmux-sync-status-visibility` via `file: state=absent`. This is known-unwanted managed state, so per repo policy the cleanup is included rather than left inert on existing machines. The task is idempotent (no-op once the file is gone).
4. **Remove** the `run-shell -b "TMUX_HOOK_PANE_ID=#{pane_id} $HOME/.local/bin/tmux-hook-run tmux-sync-status-visibility #{pane_id}";` segment from both the `pane-focus-in` and `client-session-changed` hook chains, in **both**:
   - `roles/macos/templates/dotfiles/tmux.conf`
   - `roles/linux/files/dotfiles/tmux.conf`

   The other segments in those chains (`tmux-remote-title publish`, `tmux-window-label`, `tmux-sync-pane-border-status`, `tmux-update-pane-label`) stay unchanged.

### Add

In **both** tmux.conf files, near the existing hook block:

```tmux
# Hide this server's top status bar when viewed through an outer multiplexer
# (nested tmux, e.g. SSH'd into a remote tmux from the local one). A client
# TERM of tmux*/screen* is the nesting signal — no SSH env needed.
set-hook -ag client-attached        'if-shell -F "#{m:tmux*,#{client_termname}}" "set -g status off" "set -g status on"'
set-hook -ag client-session-changed 'if-shell -F "#{m:tmux*,#{client_termname}}" "set -g status off" "set -g status on"'
```

The existing `set -g status on` default (macOS line ~93, Linux equivalent) is retained, so a direct non-nested attach restores the bar via the `else` branch and as the startup default.

`set-hook -ag` **appends** to the hook arrays rather than replacing them — required because `client-attached` already carries `tmux-client-attached`, and the macOS config appends debug instrumentation to `client-attached` later in the file. Appending matches the established pattern in this repo.

## Design decisions / scope

- **Toggle scope.** `set -g status` flips the bar for the whole server. On the remote dev host that is correct: it is always reached through a single nested client. The negligible edge case — two clients on one server with different `TERM`s, where last-attach wins — is out of scope.
- **Hook triggers.** Status logic is driven by `client-attached` and `client-session-changed`, the events at which nesting can change. It is intentionally **not** driven by `pane-focus-in`: focus changes within an already-attached client never change nesting, so the old script's use of that hook was wasteful.
- **`screen*` match.** Included alongside `tmux*` for robustness even though this repo's `default-terminal` is `tmux-256color`; the cost is nil.

## Testing

No automated test is added. Per repo testing policy, asserting exact tmux.conf hook strings would be a tautological test (the literal config line is not itself a user-facing behavior contract, and such a test would not survive a harmless reword). The behavior is verified end-to-end:

1. `bin/provision` applies cleanly (macOS) and the deployed `~/.tmux.conf` reflects the changes.
2. `~/.local/bin/tmux-sync-status-visibility` no longer exists after provisioning (removed by the `file: state=absent` cleanup task).
3. Local (non-nested) tmux: top status bar visible.
4. SSH from local tmux into the remote dev host's tmux: the remote bar is hidden, the local bar remains.
5. Direct attach to the remote tmux from a non-tmux terminal (`TERM=xterm-256color`): the remote bar is visible.
