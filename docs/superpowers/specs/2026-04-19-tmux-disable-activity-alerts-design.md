---
date: 2026-04-19
topic: Disable tmux activity alerts and activity markers in the window bar
status: approved
---

# Design: disable tmux activity alerts

## Goal

Stop tmux from showing noisy `activity in window *` messages and stop showing
the matching `+` activity markers in the top window bar when those indicators
do not reflect meaningful user-visible change.

The desired steady state is:

- no `activity in window *` pop-up messages
- no `+` activity markers in window labels
- existing `!` bell markers stay intact
- the always-on top bar otherwise keeps its current layout and colors
- both managed tmux configs stay aligned between macOS and Linux

## Non-goals

- No change to session naming, pane labels, or window-label helper scripts.
- No change to bell handling or `!` bell markers.
- No attempt to make tmux native activity detection "smarter."
- No new helper script, hook, cache, or custom activity implementation.
- No change to deployed dotfiles outside this repository.

## Background

The current tmux window-bar config in both managed tmux files does two things:

1. enables native activity tracking with `monitor-activity on`
2. enables native activity pop-up messages with `visual-activity on`

The top bar also renders the native activity flag:

```tmux
#{?window_activity_flag,+,}
```

In practice, this setup is noisy and misleading in this environment. The repo
already documents that modern agent-style CLIs can emit frequent pane title or
redraw churn. Even when those specific hooks are avoided, tmux native activity
tracking still treats background pane output as "activity," which makes the top
bar and pop-up message path feel broken.

The user requirement is not to keep a degraded version of this feature. The
user wants the false-positive activity path gone.

## Design Summary

Remove native tmux activity tracking from both managed tmux configs.

Concretely:

- remove `#{?window_activity_flag,+,}` from `window-status-format`
- remove `#{?window_activity_flag,+,}` from `window-status-current-format`
- change `monitor-activity` from `on` to `off`
- change `visual-activity` from `on` to `off`

Keep bell behavior unchanged:

- keep `#{?window_bell_flag,!,}` in both window-status format strings
- do not change any bell-related tmux options in this work

This is the simplest fix that matches observed behavior and the user request:

- hiding only the message would leave a broken `+` marker behind
- keeping activity tracking while trying to special-case certain programs adds
  complexity and still depends on tmux activity semantics that are already not
  trustworthy here

## Managed Files

1. `roles/macos/templates/dotfiles/tmux.conf`
2. `roles/linux/files/dotfiles/tmux.conf`
3. `roles/common/files/bin/tmux-window-bar-config.test`

## Config Changes

Both tmux configs should render the top bar as:

```tmux
set -g window-status-format ' #{window_name}#{?window_bell_flag,!,} '
set -g window-status-current-format ' #{window_name}#{?window_bell_flag,!,} '
setw -g monitor-activity off
set -g visual-activity off
```

Everything else in the current window-bar layout stays unchanged.

## Test Strategy

Update the existing text-level tmux config regression harness so it asserts:

- both tmux configs still keep the top bar enabled
- both tmux configs no longer contain `window_activity_flag`
- both tmux configs still contain `window_bell_flag`
- both tmux configs set `monitor-activity off`
- both tmux configs set `visual-activity off`

Then verify with repo-local tests plus a real tmux config load in a disposable
server to confirm the managed config parses cleanly.

## Risks

The only functional trade-off is that genuine tmux activity notifications will
also disappear. That is intentional. Given the current false-positive behavior,
removing the feature is lower risk than continuing to surface misleading
signals in the main tmux chrome.
