# Ghostty quick-terminal shortcut design

## Goal

Pressing `Ctrl+Space` anywhere in macOS toggles Ghostty's native quick terminal.

## Design

Manage the shortcut through the existing macOS Ghostty configuration tasks in `roles/macos/tasks/main.yml`. Add one idempotent Ansible `lineinfile` task that replaces any existing `global:ctrl+space` Ghostty binding with:

```ini
keybind = global:ctrl+space=toggle_quick_terminal
```

Use Ghostty's native global keybinding and quick-terminal action rather than Hammerspoon or macOS automation. This keeps the behavior within Ghostty and avoids additional scripts or dependencies.

## Error handling

Ghostty may require macOS Accessibility permission for global keybindings. macOS input-source switching or another application may also claim `Ctrl+Space`; provisioning cannot resolve those user-level conflicts.

## Verification

- Run `ansible-playbook playbook.yml --syntax-check`.
- Confirm the managed task contains the exact global keybind and is idempotent by construction.
- Run `bin/provision` to deploy the setting.
- From another application, press `Ctrl+Space` and confirm the Ghostty quick terminal opens; press it again and confirm it hides.
