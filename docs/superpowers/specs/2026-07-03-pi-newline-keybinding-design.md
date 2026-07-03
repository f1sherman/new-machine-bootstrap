# Design: pi Ctrl+N newline keybinding

## Goal

Manage pi's interactive editor newline fallback from Ansible so `Ctrl+N` inserts a newline on hosts where `Shift+Enter` is not distinguishable and `Ctrl+J` is reserved by tmux pane navigation.

## Scope

- Add managed pi keybindings under the existing common role pi configuration area.
- Manage `~/.pi/agent/keybindings.json` with `tui.input.newLine` bound to `shift+enter` and `ctrl+n`.
- Do not bind `ctrl+j` because tmux uses it for pane navigation in this environment.
- Do not change tmux extended key settings.

## Design

The common role already creates `~/.pi/agent/extensions` and installs managed pi hooks. Add a nearby common-role task that writes `~/.pi/agent/keybindings.json` before or alongside the extension installation. The parent directory already exists because creating `~/.pi/agent/extensions` also creates the `.pi/agent` parent, but the task should not depend on pi runtime state.

The file is fully managed with Ansible `copy` content:

```json
{
  "tui.input.newLine": ["shift+enter", "ctrl+n"]
}
```

Full-file management is acceptable because there is no existing managed keybindings file and the desired behavior is a small explicit quality-of-life setting.

## Verification

- Parse the managed JSON content with `jq`.
- Run Ansible syntax/check or local provisioning for the common role path when available.
- Avoid adding a CI test that only greps for this literal; that would be tautological and lower-value than manual/provision verification.
