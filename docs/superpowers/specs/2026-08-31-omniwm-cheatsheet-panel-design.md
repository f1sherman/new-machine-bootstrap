# OmniWM Cheat-Sheet Panel Design

**Status:** Self-approved

## Goal

Add a laptop-specific `Control+Option+H` shortcut that shows the authoritative
OmniWM cheat sheet in a centered, scrollable Hammerspoon panel above normal
windows. The same shortcut or Escape hides the panel.

## Non-goals

- Do not create a Ghostty, Herdr, or OmniWM scratchpad window.
- Do not render Markdown as rich HTML.
- Do not change Finder scratchpad behavior or other OmniWM workflows.
- Do not deploy this shortcut to macOS hosts outside the existing OmniWM host
  gate.

## Assumptions

- `docs/omniwm-cheatsheet.md` remains the repository source of truth.
- Provisioning installs a managed mirror at
  `~/.local/share/omniwm/omniwm-cheatsheet.md`; repository edits appear in the
  panel only after provisioning.
- “Current display” means the display under the mouse pointer when the panel is
  shown.
- Each show resets the panel to a centered frame derived from the current
  screen's usable frame. User resizing is intentionally not preserved between
  shows.
- The panel joins all Spaces and supports full-screen auxiliary Spaces. If the
  user changes Spaces while it is visible, it stays available. If it is visible
  on another display, the first shortcut press hides it and the next press
  shows it on the display under the pointer.

## Recommended approach

Use a separate `omniwm_cheatsheet.lua` Hammerspoon module. It reads the installed
Markdown on every show, escapes it, inserts it only into a static `<pre>` HTML
wrapper, and displays it with `hs.webview`. JavaScript and new windows are
disabled. A restrictive content security policy permits only inline style.

The panel uses a titled, resizable utility window at Hammerspoon's floating
window level. A narrow OmniWM app rule matches Hammerspoon plus the exact
`OmniWM Cheat Sheet` title and forces floating layout. This avoids relying only
on macOS utility-window classification and does not affect other Hammerspoon
windows.

A global `Control+Option+H` hotkey owns the toggle. A separate Escape hotkey is
created disabled, enabled only while the panel is visible, and disabled on every
hide path. The panel has no close button, so shortcut and Escape are the only
close paths and both preserve the reusable webview object.

The OmniWM settings reconciler reserves `Control+Option+H` by unassigning that
binding from any other OmniWM action before the Hammerspoon hotkey is installed.

## Components and boundaries

### Authoritative document and managed mirror

- `docs/omniwm-cheatsheet.md` owns content and documents `Control+Option+H`.
- `roles/macos/tasks/install_omniwm.yml` creates
  `~/.local/share/omniwm`, copies the Markdown mirror, installs the Hammerspoon
  module, and retains the existing Hammerspoon reload path.

### Hammerspoon panel module

- Reads and closes the Markdown file on each show.
- Escapes `&`, `<`, `>`, `"`, and `'`, in that order.
- Builds static HTML with no attribute or script interpolation.
- Creates one reusable webview with JavaScript disabled.
- Recomputes a clamped, centered frame from `hs.mouse.getCurrentScreen():frame()`
  for every show.
- Enables Escape only after the panel is shown and disables it before every
  hide.
- Notifies and leaves the panel hidden if the file cannot be read.

### OmniWM integration

- `omniwm.lua` requires the module and binds `Control+Option+H` to its toggle.
- The settings reconciler owns the exact floating app rule and reserved chord.
- Finder and Photos helpers remain unchanged.

## Data flow

1. Provisioning copies the authoritative Markdown to the stable data path.
2. Hammerspoon reloads and binds the toggle shortcut.
3. The shortcut hides a visible panel immediately, or starts a show operation.
4. A show operation reads the installed file and fails closed on read error.
5. The module escapes the text, builds the static HTML, centers the panel on the
   pointer screen, loads the HTML, and shows it.
6. Escape or the toggle disables Escape and hides the reusable panel.

## Error and security handling

- A missing or unreadable file triggers one Hammerspoon notification and does
  not show cached HTML.
- HTML escaping prevents modified Markdown from becoming active markup.
- The wrapper uses `default-src 'none'; style-src 'unsafe-inline'`.
- JavaScript, automatic JavaScript windows, and all new windows are disabled.
- A missing current screen triggers a notification and keeps the panel hidden.

## Alternatives considered

### Generated HTML copy

This could provide rich Markdown rendering, but creates derived content that can
drift and adds generation logic. It is unnecessary for a compact reference.

### Ghostty scratchpad

This would add shell and terminal lifecycle state, compete with the existing
Ghostty quick terminal, and conflict with Finder's scratchpad workflow.

### Inline panel code in `omniwm.lua`

This reduces one deployed file but couples panel state to unrelated IPC and URL
routing. A module provides a clear interface and supports focused behavioral
tests.

## Testing and verification

A focused Lua test executes the production panel module with stubbed Hammerspoon
APIs. It covers escaping, CSP and disabled JavaScript, reload-on-show, toggle and
Escape lifecycle, missing-file failure, current-screen centering, and
all-Spaces behavior. Existing reconciler tests cover shortcut reservation and
the exact floating rule. Verification also includes Lua syntax, Ansible syntax,
and diff checks.

Live verification after merge and provisioning must confirm panel show/hide,
Escape isolation, scrolling, resizing, Space and full-screen behavior, and
OmniWM's reported floating mode. Live provisioning is outside this implementation
run.

## Rollout and rollback

Provision only through the existing `brian-macbook-pro` OmniWM host gate. To
roll back, remove the panel module, managed Markdown mirror, hotkey binding, and
narrow app rule, then provision again. No user data migration is required.

## Self-review

The design has no placeholders. It defines display, Space, resize, Escape,
security, missing-file, deployment, test, and rollback behavior. The scope is
one coherent laptop-specific panel and excludes the independent Finder issue.
