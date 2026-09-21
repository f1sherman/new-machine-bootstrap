# Todoist Personal Safari Routing Design

Status: Self-approved

## Goal

Open links clicked in Todoist in the Safari Personal profile window and focus
that exact window.

## Current behavior

Todoist has bundle ID `com.todoist.mac.Todoist`. The URL handler treats it as a
generic application, so Safari chooses the receiving window.

## Recommended approach

Add exact Todoist sender classification and exact Personal Safari window
selection. Reuse the existing dedicated-Safari route used for Slack. Open the
tab by Safari native window ID, then navigate to and focus that OmniWM window.

Require exactly one Safari title that starts with `Personal —`. If the target is
missing or ambiguous, report the ambiguity when applicable and use normal Safari
once. Do not move or summon any window.

## Alternatives

1. **Recommended: exact Personal profile routing.** This matches Slack-to-Work
   routing and gives deterministic behavior.
2. Let Safari select a window. This is the current broken behavior.
3. Assign all Todoist links through a browser profile URL scheme. Safari does
   not provide a stable profile-specific URL scheme.

## Boundaries

- No workspace, window, or profile changes.
- No changes to Ghostty, ChatGPT, Slack, or generic link routing.
- No live provisioning or Hammerspoon reload without explicit approval.

## Verification

Execute production sender and target-selection code in focused Lua tests. Extend
the dedicated-Safari router test for a Todoist-specific error message. Run all
OmniWM tests, Lua syntax checks, Ruby settings tests, Ansible syntax, and diff
checks.
