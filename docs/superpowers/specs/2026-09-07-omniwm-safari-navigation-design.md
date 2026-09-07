# OmniWM Safari Navigation Design

**Status:** Self-approved

## Goal

After a normal non-browser link opens in Safari, navigate to and focus the exact
Safari window that received the tab.

## Evidence

A Messages event used the normal Safari route. Safari’s front native window was
ID `105`, which matched the Personal Safari window in OmniWM workspace 2.
Hammerspoon activated Safari, but OmniWM stayed on another virtual workspace.
Application activation alone does not navigate OmniWM workspaces.

## Non-goals

- Do not move or summon a Safari window.
- Do not choose a Safari profile before Safari opens the URL.
- Do not change Ghostty or ChatGPT exact routing.
- Do not provision or restart Hammerspoon without explicit approval.

## Recommended approach

Open the URL with Safari as today. After a short bounded delay, read Safari’s
front native window ID. Query OmniWM windows and match that native ID to one
Safari browser window by decoding the existing opaque OmniWM ID. Run
`omniwmctl window navigate <opaque-id>`, then confirm that exact window becomes
focused.

If ID capture, matching, navigation, or focus confirmation fails, report the
error and use application focus without opening the URL again. This preserves
the already-open tab and prevents duplicates.

## Alternatives considered

- Application activation only: already fails across OmniWM workspaces.
- Always navigate to Personal Safari: can target the wrong window or profile.
- Summon Safari into the sender workspace: changes the visible workspace layout
  and is less predictable than visiting the tab’s home workspace.

## Components

- `omniwm_safari_router.lua`: Coordinate delayed ID capture, matching,
  navigation, focus confirmation, and safe fallback through injected operations.
- `omniwm_url_source.lua`: Resolve one Safari browser window from a native ID.
- `omniwm.lua`: Adapt Hammerspoon, Safari AppleScript, and OmniWM IPC operations.
- Focused Lua tests: Exercise operation order and all failure paths.
- `docs/omniwm-cheatsheet.md`: Explain that normal links switch to the Safari
  window that received the tab.

## Error handling

The route opens the URL once. No later failure opens it again. A failure after
URL opening reports one notification and attempts normal Safari application
focus. Ambiguous or absent native-ID matches fail closed.

## Verification

Run the new state-machine test, URL-source test, existing browser and ChatGPT
routing tests, Lua syntax checks, Ruby settings tests, Ansible syntax check, and
diff check. Inspect the new route for move and summon commands.

## Rollout

Merge through a pull request. Live deployment and a Messages link check require
explicit user approval.
