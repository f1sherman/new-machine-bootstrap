# Cyberpunk 2077 Pi Theme Design

## Goal

Add an optional Pi theme inspired by the balanced Night City visual style from Cyberpunk 2077. The theme must be comfortable during long coding sessions. It must not change the active Pi theme.

## Scope

The change will:

- Add one managed theme named `cyberpunk-2077`.
- Provision it to `~/.pi/agent/themes/cyberpunk-2077.json`.
- Preserve the current Pi theme setting.
- Support isolated testing with `pi --theme cyberpunk-2077`.

The change will not add a second theme variant, custom UI behavior, icons, labels, or decorations.

## Visual Design

The theme will use a dark Night City palette:

- Deep navy and blue-black for backgrounds.
- Electric cyan for the primary accent.
- Restrained neon yellow for warnings and selected emphasis.
- Magenta for high-intensity states.
- Warm red for errors and removed diff lines.
- Green-cyan for success and added diff lines.
- Soft off-white for normal text.
- Cool gray-blue for muted and tertiary text.

Normal prose and most syntax colors will remain neutral. Neon colors will identify structure, state, links, headings, and borders. Thinking-level borders will progress from gray-blue through cyan to magenta.

## Repository Integration

The source theme will be stored with the existing managed Pi files under `roles/common/files/pi/`. The common role will:

1. Create `~/.pi/agent/themes` when it does not exist.
2. Copy the theme to `~/.pi/agent/themes/cyberpunk-2077.json`.
3. Leave `~/.pi/agent/settings.json` unchanged.

The theme will use Pi's documented JSON schema and define every required color token. Reusable palette values will be declared in `vars` and referenced by `colors`.

## Test Workflow

Run `bin/provision` to install the managed theme. Start a separate Pi process with:

```bash
pi --theme cyberpunk-2077
```

Pi hot reloads an active custom theme. During tuning, edit the repository source, run provisioning, and inspect the separate themed session. Normal Pi sessions will keep their existing theme.

## Verification

Verification will confirm:

- The theme file is valid JSON.
- All required Pi color tokens exist.
- Every variable reference resolves.
- Ansible accepts the new tasks in check mode.
- `bin/provision` installs the theme at the expected path.
- Pi loads the installed theme by name.
- User messages, tool states, Markdown, code highlighting, diffs, and thinking-level borders remain legible.

Contrast and readability take priority over visual fidelity.
