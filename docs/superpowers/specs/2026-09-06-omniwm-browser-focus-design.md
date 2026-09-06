# OmniWM Browser Focus Design

**Status:** Self-approved

## Goal

Focus Safari after links from normal non-browser applications open. Prevent
Ghostty link routing from creating and moving transient Safari windows.

## Non-goals

- Do not move any live window.
- Do not change ChatGPT-to-Chrome routing.
- Do not infer a Safari profile when no exact Development window exists.
- Do not provision or restart OmniWM without user approval.

## Evidence

At 12:35:19, the Ghostty route failed after `command move-to-workspace 3`
returned `not_found`. The route created a Safari window, focused it, and then
used a global move command. Safari removed or replaced the transient target.

Todoist and Slack events used `decision=normal`. The normal Safari helper opened
the URL but did not activate Safari.

## Recommended approach

Use a small browser-opening helper that opens a URL for a bundle and then focuses
that application. It must not focus the browser when URL opening fails.

Recognize the dedicated Ghostty target only by the exact Safari Development
profile title prefix. Resolve that target across all OmniWM workspaces. A target
outside the current workspace can use the existing summon flow, which does not
change its home workspace. If no unique Development window exists, use normal
Safari routing. Remove dedicated Safari window creation and its move command.

## Alternatives considered

### Keep creating a Safari window and retry its move

This preserves automatic setup but retains the race and can move the wrong
focused window. Reject it.

### Focus Safari without changing Ghostty routing

This fixes normal links but leaves the observed `not_found` error. Reject it.

### Route every application to a browser in its active workspace

This needs a larger browser policy for workspaces without a browser. It is out
of scope.

## Components

- `omniwm_browser_opener.lua`: Open and focus a browser with injected operations.
- `omniwm_url_source.lua`: Identify and resolve the Safari Development window.
- `omniwm.lua`: Use the opener and remove transient Safari creation and movement.
- Focused Lua tests: Exercise browser focus sequencing and Development window
  resolution.
- `docs/omniwm-cheatsheet.md`: Explain normal browser focus and Ghostty fallback.

## Error handling

- URL open failure reports one error and does not focus the browser.
- Browser focus failure reports one error after the URL opens.
- Zero Development windows use normal Safari routing.
- Multiple Development windows report ambiguity and use normal Safari routing.
- Existing summon or exact-tab failures retain normal Safari fallback.

## Verification

Run focused Lua tests, Lua syntax checks, the OmniWM settings Ruby suite, Ansible
syntax check, and `git diff --check`. Inspect the Ghostty route to confirm it has
no workspace move or Safari window creation.

## Rollout

Merge through a pull request. Deployment and live checks require explicit user
approval. Live verification must use one normal application link and one
Ghostty link. It must confirm browser focus and no window movement.
