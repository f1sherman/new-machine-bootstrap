# Herdr and tmux Shortcut Alignment Design

## Goal

Add direct Herdr shortcuts that match the existing tmux shortcuts for common
workspace navigation and copy mode. Keep Herdr's default prefix shortcuts.

## Scope

Align these actions:

| Action | Direct shortcut |
|---|---|
| Split pane right | `Alt-\` |
| Split pane down | `Alt--` |
| New tab | `Alt-t` |
| Next tab | `Alt-n` |
| Previous tab | `Alt-p` |
| Goto picker | `Alt-w` |
| Workspace picker | `Alt-8` |
| Previous workspace | `Alt-9` |
| Next workspace | `Alt-0` |
| Focus pane left, down, up, or right | `Ctrl-h/j/k/l` |
| Focus the last pane | `Ctrl-\` |
| Enter copy mode | `Alt-y` |

Each Herdr action will also keep its default prefix binding. Examples include
`Ctrl-b c`, `Ctrl-b n`, and the default copy-mode binding.

Direct `Ctrl-h/j/k/l` bindings intentionally take precedence inside all Herdr
panes. Herdr does not provide tmux's conditional Vim and remote-session
passthrough behavior.

The following tmux shortcuts have no direct Herdr action equivalent and stay
unaligned:

- `Alt-arrow` pane resize. Herdr keeps its default `Ctrl-b r` resize mode.
- `Alt-,` and `Alt-.` window reordering.
- `Alt-=` and `Alt-+` even-pane layouts.

## Configuration

Extend the common Ansible role on the existing Herdr installation branch. Add a
marked block at the start of `~/.config/herdr/config.toml`. The block defines
`[keys]` and only the shared shortcuts.

The managed block must:

- create the Herdr config directory and file when absent;
- preserve all configuration outside the block;
- update idempotently;
- apply on macOS and Linux;
- appear before existing `[[keys.command]]` entries so the TOML table structure
  stays valid;
- retain each relevant Herdr default binding by configuring a list that contains
  the default and direct shortcuts.

A complete managed template is out of scope because it could overwrite
machine-specific settings. Unmanaged local configuration is also out of scope
because it is not reproducible.

## Reload and failure handling

After a change, validate the resulting file with Herdr's built-in
`herdr config check`. Invalid TOML or key syntax must fail provisioning and show
the validation output.

If a Herdr server is running, reload its configuration. An absent server must
not make provisioning fail. A later Herdr launch will read the managed file.

## Verification

1. Run Ansible syntax and check-mode validation for the relevant tasks.
2. Run `bin/provision` from the feature worktree.
3. Run `herdr config check` against the deployed configuration.
4. Open Herdr's shortcut help and confirm that the default and direct bindings
   appear.
5. In a disposable Herdr workspace, verify tab creation and navigation, pane
   splitting and focus, workspace navigation, the Goto picker, and copy mode.
6. Confirm that unrelated custom commands remain in the deployed config.

Do not add a static configuration test. It would duplicate Herdr's parser and
would not verify the user-visible shortcut behavior.
