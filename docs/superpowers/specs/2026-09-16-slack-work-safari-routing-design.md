# Slack Work Safari Routing Design

Status: Self-approved

## Goal

Open links clicked in Slack in the single Safari Work profile window. Then focus
that exact window in its home OmniWM workspace.

## Non-goals

- Do not move or summon any window.
- Do not change Safari profiles or workspace assignments.
- Do not change routing from Ghostty, ChatGPT, or other applications.
- Do not infer Slack when the sender identity is missing.

## Evidence and assumptions

- Slack reports the bundle ID `com.tinyspeck.slackmacgap`.
- The current callback classifies Slack as a normal sender. Normal Safari opening
  selects Safari's current front window, which is often the Personal profile.
- The managed Work Safari rule identifies a titled Safari window whose title
  starts with `Work —` and assigns it to workspace 9.
- The live system currently has one Work Safari window in workspace 9.

## Recommended approach

Add explicit Slack sender classification and exact Work Safari resolution to the
existing URL-source module. Dispatch Slack before the generic non-Ghostty path.
Open the tab through Safari's native window ID, then navigate to the exact
OmniWM window ID.

Use a small state machine with injected operations. A failure before tab
creation can fall back once to normal Safari. A failure after tab creation must
only notify because fallback would duplicate the URL.

This approach follows the existing ChatGPT and Ghostty routing boundaries. It
uses exact IDs and does not change window placement.

## Alternatives considered

### Open normally and then locate the receiving Safari window

This is the current behavior. Safari can choose the Personal profile before the
handler observes the receiving window. Reject this approach because it cannot
select the Work profile reliably.

### Route all links from workspace 9 to Work Safari

This would also affect unrelated applications and missing sender identities.
Reject this approach because the requested rule is source-specific.

### Summon Work Safari into the current workspace

This matches the Ghostty workflow, but Slack and Work Safari already share
workspace 9. Reject this approach because it changes the visible workspace
layout and is not needed.

## Components

### URL-source classification

- Match Slack only by its exact bundle ID.
- Match Work Safari only when the bundle ID is Safari and the title starts with
  `Work —`.
- Require exactly one Work Safari candidate. Report ambiguity instead of
  guessing.

### Slack router

- Receive the selected window and URL.
- Create the tab in the exact Safari native window.
- Navigate to the exact OmniWM window after creation.
- Use normal Safari once only when selection or tab creation fails.
- Notify without reopening when navigation fails after creation.

### Hammerspoon integration

- Dispatch Slack before generic sender routing.
- Query managed windows and select the Work Safari target.
- Reuse existing Safari native-ID decoding, exact tab creation, and bounded
  exact-ID navigation helpers.
- Log routing decisions without logging URLs.

## Error handling

- No or ambiguous Work Safari target: notify when ambiguous, then use normal
  Safari once.
- Invalid native ID or tab creation failure: notify, then use normal Safari
  once.
- Navigation failure after tab creation: notify only. Do not create a duplicate
  tab.

## Verification

- Add pure tests for exact Slack sender matching.
- Add pure tests for Work Safari selection, absence, titleless panels, and
  ambiguity.
- Add state-machine tests for success, pre-creation fallback, and no fallback
  after tab creation.
- Run all focused OmniWM Lua tests and Lua syntax checks.
- Run the Ruby OmniWM settings tests and Ansible syntax check.
- After merge and approval to provision, click a Slack link and confirm that it
  opens in Work Safari and focuses workspace 9 without moving a window.

## Rollout

Deploy only on `brian-macbook-pro` through the existing OmniWM host gate. Update
the OmniWM cheat sheet with the Slack workflow.
