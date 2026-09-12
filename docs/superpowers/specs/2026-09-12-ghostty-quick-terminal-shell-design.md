# Ghostty Quick Terminal Shell Design

**Status:** Self-approved

## Goal

Make Ghostty's quick terminal open a plain login shell. Preserve the existing
behavior where the first regular Ghostty surface starts Herdr and later regular
surfaces attach to tmux.

## Non-goals

- Do not change the quick-terminal shortcut.
- Do not change normal Ghostty tab, window, tmux restore, or Herdr lifecycle
  behavior.
- Do not add a separate terminal application or shortcut manager.

## Assumptions

- "Plain terminal" means the user's configured shell without Herdr or tmux.
- The installed Ghostty version sets `GHOSTTY_QUICK_TERMINAL=1` before it starts
  the configured command. This is confirmed by the installed Ghostty binary and
  upstream implementation.
- The shell is available through `SHELL`; `/bin/zsh` is a safe macOS fallback.

## Root Cause

Ghostty applies its `command` setting to every new terminal surface. The managed
command is `ghostty-tab-launch`. That helper assigns Herdr to the first surface
in each Ghostty process. Ghostty's quick terminal is also a surface, so it can
claim the Herdr slot.

Ghostty marks quick-terminal processes with `GHOSTTY_QUICK_TERMINAL=1`, but the
helper does not use that marker.

## Recommended Approach

At the start of `ghostty-tab-launch`, after PATH setup and before state or lock
work, detect `GHOSTTY_QUICK_TERMINAL=1`. Replace the helper process with the
configured shell in login mode. Use `/bin/zsh` only when `SHELL` is unset.

This keeps the quick-terminal decision at the existing command-routing boundary.
It also ensures that a quick terminal does not create or consume a Herdr marker.

### Alternatives Considered

1. **Use Ghostty `initial-command` for Herdr.** This is simpler, but Ghostty can
   apply the initial command to the quick terminal. It also cannot restart Herdr
   in the next regular tab after the Herdr tab exits.
2. **Route the quick terminal to `tmux-attach-or-new`.** This avoids Herdr, but it
   does not provide the requested plain shell and can attach the quick terminal
   to durable work.
3. **Add a second Ghostty configuration or launcher.** This adds unnecessary
   shortcut and process-management complexity when Ghostty already exports an
   explicit surface marker.

## Interfaces and Error Handling

- Input: `GHOSTTY_QUICK_TERMINAL=1` and optional `SHELL`.
- Quick-terminal output: an interactive login shell replaces the helper.
- Regular-surface output: unchanged Herdr-or-tmux routing.
- If the selected shell cannot execute, the existing shell error is visible and
  the surface exits. No Herdr state has been changed.

## Verification

Use an isolated temporary home and a fake shell to execute the production helper
with `GHOSTTY_QUICK_TERMINAL=1`. Confirm that the fake shell receives `-l` and
that no Ghostty launcher state directory is created. Run `bash -n` and
`shellcheck` on the helper. Run Ansible syntax validation. Provision the macOS
role, reload or restart Ghostty as required, and confirm the effective managed
command remains the helper. The next newly created quick-terminal process will
then use the new branch.

No retained automated test is warranted. This is a low-impact routing rule, and
focused provisioning plus end-to-end verification catches a failure directly.
