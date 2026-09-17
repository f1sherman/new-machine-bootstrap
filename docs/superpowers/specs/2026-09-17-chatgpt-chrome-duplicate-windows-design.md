# ChatGPT Chrome Duplicate Windows Design

Status: Self-approved

## Goal

Open each ChatGPT link once in the existing Chrome window for the active OmniWM
workspace. Prevent extra Chrome windows and blank tabs when more than one Chrome
window exists.

## Root cause

The active workspace currently has two managed Chrome windows. The router
requires exactly one Chrome window. It therefore uses the normal Chrome fallback.
That fallback sends the URL through Launch Services and immediately focuses
Chrome without an exact window target. This path can select or create another
window and can leave a blank tab.

Hammerspoon reports Chrome's last-focused native window ID as `27293`. OmniWM
reports the same native `windowId` for the intended Chrome window. This gives the
router a reliable exact-window selector even when multiple Chrome windows exist.

## Non-goals

- Close, merge, move, or resize existing Chrome windows.
- Change Chrome profiles or workspace rules.
- Route links from applications other than ChatGPT.
- Provision or reload Hammerspoon without explicit approval.

## Recommended approach

Read Chrome's last-focused Hammerspoon window ID before selecting an OmniWM
window. Prefer the titled Chrome window in the active workspace whose native
`windowId` matches it. Keep the current unique-window selection as a fallback
when no usable preferred ID exists.

If multiple candidates remain and none matches, keep the existing normal-Chrome
fallback. Do not guess from window position, title text, or tab count.

## Alternatives

1. **Recommended: match Hammerspoon and OmniWM native IDs.** This uses a verified
   shared identifier and preserves exact-window routing.
2. Select the leftmost or oldest Chrome window. These are unstable layout
   heuristics and can select the wrong window.
3. Reject every ambiguous request. This prevents duplication but loses the link.
4. Close duplicate windows automatically. This is destructive and violates the
   requirement not to change live windows without approval.

## Components

- `omniwm.lua` reads Chrome's last-focused native window ID.
- `omniwm_url_source.lua` resolves a preferred Chrome candidate by native ID.
- Focused Lua tests execute the production resolver and routing boundary.
- The OmniWM cheat sheet documents the selection rule.

## Error handling

An unavailable or invalid Hammerspoon window ID does not fail routing. The
resolver uses the existing unique-candidate rule. A stale ID that does not match
an active-workspace candidate is ignored. Existing pre-creation fallback and
post-creation no-duplicate behavior remain unchanged.

## Verification

Run all OmniWM Lua tests, Lua syntax checks, the Ruby settings tests, Ansible
syntax check, and diff checks. Do not test with a live URL or change live windows
without explicit approval.
