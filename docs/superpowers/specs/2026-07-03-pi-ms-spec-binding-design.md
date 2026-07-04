# Pi `M-s` spec pane shortcut design

## Goal

Make `M-s` (`alt+s`) in Pi open the current Superpowers spec pane, matching the existing tmux-based spec viewer workflow without taking over Pi's default `alt+f` word-right editor shortcut.

## Design

Add a managed Pi extension that registers an `alt+s` shortcut. When invoked, the shortcut runs `~/.local/bin/tmux-spec-open` from inside Pi. The helper already owns spec discovery and pane management, so the extension should only bridge Pi's keyboard shortcut system to that existing command.

The shortcut should be safe outside tmux: if Pi is not running with `TMUX` and `TMUX_PANE`, it should show a small notification instead of failing noisily. If the helper exits non-zero, Pi should notify the user with stderr/stdout details.

## Installation

Install the new extension to `~/.pi/agent/extensions/` through the existing common Ansible role, alongside `managed-hooks.ts` and `pi-attention-bell.ts`.

## Out of scope

- Do not change the existing `M-f` tmux binding.
- Do not remove Pi's default `alt+f` word-right behavior.
- Do not add compatibility heuristics or alternate fallback keys.

## Verification

- Confirm the extension file is installed by the Ansible task list.
- Confirm `alt+s` appears in the extension source as the registered shortcut.
- Run a syntax/check pass over the modified Ansible tasks.
