# ChatGPT Chrome Link Focus Design

**Status:** Self-approved

## Goal

When ChatGPT opens an HTTP or HTTPS link, open the link in the single Chrome
browser window in the active OmniWM workspace. Then transfer focus to that exact
window.

## Non-goals

- Do not move or summon any window.
- Do not infer ChatGPT when the sender identity is unavailable.
- Do not change workspace assignments or keyboard shortcuts.
- Do not change Ghostty-to-Safari routing.

## Assumptions

- The ChatGPT application bundle ID is `com.openai.codex`.
- A Chrome browser window has bundle ID `com.google.Chrome` and a non-empty
  title.
- Exact routing is safe only when the active workspace contains one matching
  Chrome window.
- Zero or multiple matching windows require normal Chrome routing.

## Recommended approach

Add pure source and target classification functions to
`omniwm_url_source.lua`. Dispatch ChatGPT before the existing Ghostty route.
Query the active workspace and OmniWM windows. Select one eligible Chrome window
in that workspace. Focus and confirm its opaque OmniWM window ID. Capture
Chrome's AppleScript ID for the focused front window. Reconfirm the exact
OmniWM window before tab creation. Create the tab through the captured Chrome
window ID. Confirm focus again after tab creation.

Create and select the Chrome tab as separate operations. This makes successful
tab creation explicit. Use normal Chrome routing exactly once if selection,
initial focus, ID capture, focus revalidation, or tab creation fails. If tab
creation succeeds but tab selection or final focus fails, report the error
without opening a duplicate tab.

This approach uses OmniWM for exact focus identity. It captures Chrome's own
window ID only while that exact OmniWM window remains focused. AppleScript then
targets the captured Chrome ID instead of the mutable front window.

## Alternatives considered

### Decode the OmniWM ID for direct Chrome AppleScript targeting

This would avoid the focus-to-front-window race. The repository proves the ID
mapping only for Safari. Chrome can use a different ID namespace. This option is
not sufficiently reliable without a live experiment.

### Open normally in Chrome and detect the receiving window

This is simpler. It cannot reliably select one of several existing Chrome
windows. Keep it only as the safe fallback.

## Components and interfaces

- `omniwm_url_source.lua`
  - Identifies the exact ChatGPT sender.
  - Identifies eligible Chrome browser windows.
  - Resolves exactly one eligible Chrome window in the active workspace.
- `omniwm.lua`
  - Dispatches ChatGPT links.
  - Queries OmniWM state and adapts Hammerspoon operations.
  - Captures a directly addressable Chrome window ID.
  - Creates and selects a Chrome tab in that exact window.
- `omniwm_chatgpt_router.lua`
  - Coordinates exact focus, ID capture, tab creation, and fallback behavior.
- `tests/omniwm-url-source.lua`
  - Executes production classification and selection logic.
- `tests/omniwm-chatgpt-router.lua`
  - Executes the production routing state machine with injected operations.
- `docs/omniwm-cheatsheet.md`
  - Documents the ChatGPT link workflow.

## Error handling

- Missing sender identity retains current non-ChatGPT behavior.
- Zero or multiple Chrome targets use normal Chrome routing.
- OmniWM query or focus failure reports the error and uses normal Chrome
  routing.
- Chrome Automation denial or tab creation failure reports the error and uses
  normal Chrome routing.
- Final focus failure reports the error but does not open the URL again.
- Logs include routing metadata but never include the URL.

## Testing and verification

- Add behavioral Lua cases for the ChatGPT sender and Chrome target selection.
- Cover one target, no target, wrong workspace, empty title, and ambiguity.
- Add state-machine cases for pre-creation failures, partial creation, final
  focus failure, fallback counts, and operation order.
- Run both Lua production tests and Lua syntax checks.
- Run the existing OmniWM settings Ruby suite to detect integration regressions.
- Inspect the diff for window move or summon commands in the new route.
- Do not provision or restart OmniWM without explicit user approval.

## Rollout

Merge through a pull request. Deployment and live confirmation are separate and
require the user's explicit approval. Live confirmation must verify that a link
from ChatGPT opens in the Chrome window in the current workspace and focuses
that window without moving any window.
