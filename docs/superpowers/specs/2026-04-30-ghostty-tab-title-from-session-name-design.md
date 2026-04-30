---
date: 2026-04-30
topic: Pin Ghostty tab title to the local tmux session name
status: approved
---

# Design: Ghostty tab title from tmux session name

## Goal

Every Ghostty tab attached to a tmux client always shows the local tmux
session name (`#S`). Programs running inside tmux panes — Claude Code, Codex,
vim, ssh, anything — must not be able to override the tab title.

This holds for both purely local tmux sessions and for tmux sessions that
contain SSH/DevPod/Codespaces panes. Even when the focused pane is remote, the
Ghostty tab keeps showing the local session name as the user set it.

## Non-goals

- No change to the local-window-rename pipeline that mirrors a remote
  worktree label into the local tmux window name (the
  `pane-title-changed` → `tmux-sync-remote-title` chain stays exactly as it is
  today).
- No change to per-pane border content from `tmux-pane-label`.
- No change to the on-screen status bar (`status-left` / `status-right`).
- No change to the remote helper `tmux-remote-title` itself; it continues to
  publish stable labels via plain OSC 2 for the remote→local pane_title
  transport.
- No new scripts, no new launchd jobs, no new tmux hooks, no periodic refresh.
- No session auto-rename triggered by the remote title contract.
  `tmux-sync-remote-title` already only renames the window today; this spec
  locks that in.

## Background

Today the Ghostty tab title is fought over by three actors:

1. tmux's own title emitter. The macOS config has `set-titles on` and
   `set-titles-string '#S'` (`roles/macos/templates/dotfiles/tmux.conf:118-119`).
   tmux re-evaluates this on focus / session events and emits OSC 2 to each
   client's tty when the result changes. Since `#S` rarely changes, this
   emits seldom — typically once on attach.

2. Programs running inside tmux panes. Tools like Claude Code emit
   `\ePtmux;\e\e]2;<title>\e\\` — a tmux DCS-passthrough sequence wrapping an
   inner OSC 2. With `set -g allow-passthrough all`
   (`roles/macos/templates/dotfiles/tmux.conf:169`) the inner escape is
   forwarded verbatim to Ghostty, which interprets it as a tab title set.
   tmux does not re-emit its own title afterwards, so the override sticks
   until the next event triggers `set-titles` to fire.

3. The remote title pipeline. `tmux-remote-title` writes plain OSC 2 to the
   remote tmux's client tty for SSH/DevPod/Codespaces panes. That OSC 2 is
   intercepted by local tmux (it updates the SSH pane's `pane_title`) and is
   not forwarded to Ghostty. So this actor is not a direct contributor to the
   visible mess; it remains correctly scoped to driving the local
   window-rename hook.

The visible symptom is "the Ghostty tab title keeps changing": tmux puts up
`#S`, then the inner program overrides via DCS passthrough, then a navigation
event causes tmux to re-emit, and so on. The user observes a mix of session
names, branch names, and free-form strings emitted by inner tools.

## Approach

Disable DCS passthrough at the tmux layer. With
`set -g allow-passthrough off`, programs inside tmux can no longer use the
`\ePtmux;...\e\\` escape to bypass tmux. The DCS-wrapped OSC 2 is dropped by
tmux instead of being forwarded to Ghostty. tmux's existing
`set-titles-string '#S'` becomes the sole authority for the outer terminal
title.

This is one tmux option in two config files. No new scripts, no new hooks, no
new processes.

### Why this works

- Ghostty only ever sees OSC 2 sequences that tmux itself emits (via
  `set-titles`).
- tmux's `set-titles` format is `'#S'`, which is the local session name.
- tmux re-emits the title on attach and on every event where the format result
  may have changed (session rename, focus changes that switch sessions, etc.).
- Inner programs lose their bypass channel entirely. Their OSC 2 emissions
  (DCS-wrapped or otherwise) update tmux's own `pane_title`, which is used
  internally for the pane border and the remote→local window-rename pipeline,
  but never reach Ghostty as a tab title set.
- The remote→local window-rename pipeline keeps working: `tmux-remote-title`
  writes plain OSC 2 (not DCS-wrapped); plain OSC 2 from inside a tmux pane
  is always intercepted by tmux into `pane_title`, regardless of
  `allow-passthrough`. The local `pane-title-changed` →
  `tmux-sync-remote-title` chain reads `pane_title` and renames the local
  window. None of that flow goes through DCS passthrough.

### Why this is acceptable

`allow-passthrough` only controls one specific feature: the
`\ePtmux;<inner-escape>\e\\` DCS sequence. Disabling it does **not** affect:

- Normal terminal output (text, colors, true color, cursor, mouse).
- Tmux internals (sessions, windows, panes, commands, keybindings).
- OSC 52 clipboard (controlled by `set-clipboard on`).
- OSC 8 hyperlinks (controlled by `terminal-features "*:hyperlinks"`).
- OSC 7 current-directory tracking.
- Tmux's own `set-titles` emission to the client.

It does block, from inside tmux:

- Inner programs setting the outer terminal's tab title (the desired effect).
- Sixel images emitted from inside a pane (image-preview tools, plot tools).
- Kitty graphics protocol from inside a pane.
- Terminal progress bars (OSC 9;4) and notifications wrapped in DCS
  passthrough from inside a pane.

The user has confirmed they do not currently use any image preview, sixel,
kitty graphics, or DCS-wrapped notification flow inside tmux on this machine.
Reverting is one line if a future need arises.

## Approaches considered and rejected

### 1. Active publish + periodic refresh via launchd

A new helper script writes OSC 2 with `#S` to each client's tty. Driven by
tmux hooks for navigation events plus a launchd timer every N seconds to
beat any inner-program override.

Rejected because it is strictly more machinery than required. It tolerates
the override and recovers within an interval, instead of preventing the
override at the layer where it actually happens.

### 2. Active publish + periodic refresh embedded in `status-right`

Same as above, but the periodic refresh is implemented as a `#(...)`
side-effecting shell call inside the `status-right` format. tmux re-evaluates
the format every `status-interval`, so the script fires every 5s.

Rejected because it abuses the status format for a side effect unrelated to
status rendering, and because it solves the same problem as launchd with
worse separation of concerns.

### 3. Event-only hooks, no periodic refresh

Hook on every navigation event (`pane-focus-in`, `session-window-changed`,
`window-pane-changed`, `client-session-changed`, `client-attached`,
`session-renamed`) and republish the title from each. Skip periodic refresh.

Rejected because the title remains wrong for the entire time the user stays
in a single pane after an inner program overrode. Does not satisfy the
"always" requirement.

## Changes

### `roles/macos/templates/dotfiles/tmux.conf`

The current passthrough block reads:

```tmux
# Allow escape sequences (notifications, progress bars) to pass through to the outer terminal
set -g allow-passthrough all
```

Replace with:

```tmux
# Block inner programs from bypassing tmux to talk directly to the outer
# terminal. Keeps the Ghostty tab title pinned to '#S' instead of letting
# Claude Code, vim, ssh, etc. override it via DCS-wrapped OSC 2.
set -g allow-passthrough off
```

No other lines in this file change.

### `roles/linux/files/dotfiles/tmux.conf`

Make the identical change (same comment, same option value) for parity.

### `roles/common/files/bin/tmux-window-bar-config.test`

Extend `assert_tmux_file` so that for both managed tmux configs:

- `set -g allow-passthrough off` is present.
- Neither `allow-passthrough all` nor `allow-passthrough on` appears.

The first assertion uses `assert_contains`. The second uses `assert_not_contains`
(or `grep -Fq` plus `!`) for both forbidden values.

## What stays unchanged

- `set -g set-titles on` — primary title-emission mechanism.
- `set -g set-titles-string '#S'` (macOS) — the format whose result becomes
  the Ghostty tab title.
- `set -g set-titles-string '#S: #W'` (Linux) — kept as-is. Linux tmux only
  emits to its own client tty (which is local tmux's SSH pane pty when SSH'd
  in from Mac). Local tmux intercepts that OSC 2 into `pane_title` and never
  forwards it to Ghostty, so Linux's `set-titles-string` value does not
  affect any Ghostty tab title.
- `tmux-remote-title` — unchanged. Continues to write plain OSC 2 to its
  client tty, which the local tmux interprets as `pane_title` for the SSH
  pane, which feeds the local window-rename hook.
- `tmux-sync-remote-title` — unchanged. Still only renames the window, not
  the session.
- All hooks (`pane-focus-in`, `client-session-changed`, `pane-title-changed`,
  pipe-pane hooks, restore hooks).
- `status-left`, `status-right`, `pane-border-format`, `window-status-*`,
  `pane-border-style`, `pane-active-border-style`.
- `set-clipboard`, `terminal-features`, `default-terminal`,
  `terminal-overrides`, key bindings.

## Tests

### Static / parity test

Extend `roles/common/files/bin/tmux-window-bar-config.test` so its
`assert_tmux_file` helper enforces, for both `tmux.conf` files:

1. `set -g allow-passthrough off` is present.
2. `allow-passthrough all` is absent.
3. `allow-passthrough on` is absent.

Run: `bash roles/common/files/bin/tmux-window-bar-config.test`. Expect
`passed=N failed=0`.

### Unit / shell-harness tests

None. No new scripts; the change is configuration only.

### Manual verification

After `bin/provision` reloads tmux on the Mac:

1. Attach to a local tmux session named `foo` from a Ghostty tab. Confirm
   the tab shows `foo`.
2. Inside a pane, run `claude --version` or any short-lived run that
   normally emits a title via DCS passthrough. Confirm the tab title stays
   `foo` (no flicker, no temporary other-title).
3. Open `nvim` in a pane. Confirm the tab title stays `foo` regardless of
   buffer changes.
4. Run `tmux rename-session bar`. Confirm the tab updates to `bar`.
5. SSH from the Mac into a dev host inside the same tmux session. Run
   `worktree-start <branch>` on the dev host. Confirm:
   - the local tmux **window** name updates to the remote worktree label
     (existing behavior);
   - the Ghostty tab title still shows the local session name `bar`,
     never the remote worktree label.
6. Detach the client and re-attach. Confirm the tab shows `bar` from the
   first redraw.
7. Open a second Ghostty tab attached to a different tmux session named
   `baz`. Confirm each tab shows its own session name and they do not
   interfere.

### Acceptance

- All extended parity-test assertions pass.
- Every manual step above behaves as described.
- No regressions in the existing test suite for `tmux-remote-title`,
  `tmux-sync-remote-title`, `tmux-window-bar-config`, or other affected
  helpers.

## Risks

- **Loss of DCS passthrough features.** Image previews, sixel, kitty
  graphics, and DCS-wrapped progress/notification escapes from inside tmux
  stop reaching Ghostty. The user has confirmed none are in active use.
  Mitigation: revert the single line if a future workflow needs it.
- **Surprise from third-party tools.** A future tool that relies on DCS
  passthrough will silently lose its escape forwarding. Mitigation: the
  tmux.conf comment explicitly explains why passthrough is off, so the next
  reader (human or agent) sees the trade-off in context.

## Files

- Modify: `roles/macos/templates/dotfiles/tmux.conf` (one line + comment).
- Modify: `roles/linux/files/dotfiles/tmux.conf` (one line + comment).
- Modify: `roles/common/files/bin/tmux-window-bar-config.test` (assertions
  inside `assert_tmux_file`).
