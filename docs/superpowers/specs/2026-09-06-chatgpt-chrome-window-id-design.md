# ChatGPT Chrome Window ID Design

**Status:** Self-approved

## Goal

Accept Chrome AppleScript window IDs that Hammerspoon returns as numeric strings
while rejecting invalid identifiers.

## Evidence

A live read-only query returned
`true|string|868906217|868906217`. The router currently requires Lua type
`number`, so it rejected the valid ID and showed an OmniWM notification.

## Recommended approach

Add a pure normalizer to `omniwm_url_source.lua`. Accept a positive integer from
either a Lua number or a decimal string. Return `nil` for empty, non-numeric,
zero, negative, or fractional values. Use the normalized number when building
the Chrome AppleScript command.

## Alternatives considered

- Accept every string and rely on `string.format`. This weakens validation.
- Remove type validation. This can pass malformed data to AppleScript.
- Change Hammerspoon. Its AppleScript bridge owns this representation, so this
  repository must normalize it.

## Testing

Execute the production normalizer with numeric strings, numbers, and invalid
values. Run the URL routing tests, ChatGPT routing test, Lua syntax check, Ruby
settings suite, Ansible syntax check, and diff check.

## Rollout

Merge through a pull request. Do not provision or restart Hammerspoon without
explicit user approval.
