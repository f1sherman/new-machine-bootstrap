# Slack Work Safari Window Creation Design

Status: Self-approved

## Problem and goal

When no Work Safari window is managed by OmniWM, Slack's link route uses normal Safari. Safari can then put the link in Personal. Open a Work Safari window first and open the Slack link only after that window is confirmed. Never route a Slack link into another profile.

## Assumptions and boundaries

- Slack's bundle ID is `com.tinyspeck.slackmacgap`.
- The installed Safari menu has an enabled `File → New Window → New Work Window` item. Hammerspoon can find it through `hs.application:findMenuItem` without changing windows. No undocumented Safari profile URL scheme is assumed.
- Only a missing Work window triggers creation. More than one Work window is ambiguous: report an error, do not create another or guess.
- A creation or tab error must not fall back to normal Safari, because that can select Personal. Notify the user to retry after opening Work Safari. Do not move, summon, resize, or close windows.
- Keep Todoist, Fastmail, Ghostty, and generic links unchanged. Do not provision or reload Hammerspoon or run a live link check without separate approval.

## Recommended approach

Extend the existing profile router with an optional asynchronous target-creation callback and a Slack-only fail-closed policy. When no Work window is found, use Hammerspoon's `selectMenuItem({"File", "New Window", "New Work Window"})` on Safari. Poll OmniWM for exactly one Work Safari window before opening the URL as a tab by native window ID, then navigate and focus its exact OmniWM window. If menu selection, polling, or tab creation fails, notify and do not open the link elsewhere. Keep the existing router unchanged for other senders.

Alternatives: Leaving normal Safari fallback repeats the reported wrong-profile outcome. Guessing Safari's profile from its front window can also open Personal. A private Safari profile URL scheme is not documented. The menu command with target confirmation uses an observed interface and preserves the existing routing flow.

## Verification

Test the production router's no-target, ambiguous, creation, and tab-error paths with controlled Hammerspoon boundaries. Run the full OmniWM Lua suite, syntax checks, settings tests, and Ansible syntax. A live no-Work-window check would close or change existing windows and requires separate approval. The PR alone does not prove live behavior.
