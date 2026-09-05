# ChatGPT Chrome Link Focus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Open ChatGPT links in the single Chrome window in the active OmniWM workspace and focus that exact window.

**Architecture:** Extend the pure URL-source helper with exact ChatGPT sender and Chrome target selection. Use a tested routing state machine that focuses the selected OmniWM window, captures Chrome's own window ID, revalidates focus, and targets tab creation through that ID without moving or summoning windows.

**Tech Stack:** Lua, Hammerspoon, OmniWM IPC, Chrome AppleScript, Markdown

**Spec:** `docs/superpowers/specs/2026-09-05-chatgpt-chrome-link-focus-design.md`

## Global Constraints

- Apply this behavior only through the existing laptop-gated OmniWM provisioning path.
- Do not move or summon any window.
- Do not infer ChatGPT when sender identity is unavailable.
- Use normal Chrome routing exactly once on pre-open failure.
- Do not reopen the URL after successful tab creation.
- Do not provision or restart OmniWM without explicit user approval.

---

### Task 1: Classify ChatGPT and select its Chrome target

**Files:**
- Modify: `roles/macos/files/hammerspoon/omniwm_url_source.lua`
- Test: `tests/omniwm-url-source.lua`

**Interfaces:**
- Produces: `isChatGPTSender(senderBundle) -> boolean`
- Produces: `isChromeBrowserWindow(window) -> boolean`
- Produces: `resolveActiveChromeWindow(activeWorkspace, windows) -> window|nil, error|string|nil`

- [ ] **Step 1: Write failing behavioral tests**

Add cases that execute the production helper and verify:

```lua
assertEqual(true, source.isChatGPTSender("com.openai.codex"), "ChatGPT sender")
assertEqual(false, source.isChatGPTSender("com.apple.Safari"), "non-ChatGPT sender")
```

Add target cases for one eligible Chrome window, no Chrome window, a Chrome
window in another workspace, an empty-title Chrome panel, and two eligible
Chrome windows. Require one exact target only.

- [ ] **Step 2: Run the test and confirm failure**

Run: `lua tests/omniwm-url-source.lua`

Expected: FAIL because the new helper functions do not exist.

- [ ] **Step 3: Implement the pure helpers**

Use exact bundle IDs, a non-empty title, and exact numeric workspace equality.
Return an error for multiple eligible targets. Return no target and no error for
zero eligible targets.

- [ ] **Step 4: Run the focused test**

Run: `lua tests/omniwm-url-source.lua`

Expected: PASS.

- [ ] **Step 5: Commit**

Commit the helper and test as `Classify ChatGPT Chrome link targets`.

### Task 2: Route and focus ChatGPT links

**Files:**
- Create: `roles/macos/files/hammerspoon/omniwm_chatgpt_router.lua`
- Create: `tests/omniwm-chatgpt-router.lua`
- Modify: `roles/macos/files/hammerspoon/omniwm.lua`
- Modify: `roles/macos/tasks/install_omniwm.yml`
- Modify: `.github/workflows/integration-test.yml`
- Modify: `docs/omniwm-cheatsheet.md`

**Interfaces:**
- Consumes: `urlSource.isChatGPTSender`
- Consumes: `urlSource.resolveActiveChromeWindow`
- Produces: `chatGPTRouter.route(window, url, deps)`
- Produces: ChatGPT URL dispatch with exact OmniWM and Chrome window identity

- [ ] **Step 1: Add normal Chrome fallback**

Add `openNormallyInChrome(url)`. Use
`hs.urlevent.openURLWithBundle(url, "com.google.Chrome")`. Notify if it fails.

- [ ] **Step 2: Write the routing state-machine test**

Create an injected orchestration test. Verify the order `focus`, Chrome ID
capture, exact focus confirmation, exact-ID tab creation, and final focus.
Verify one fallback for each pre-creation failure. Verify no fallback after tab
creation when tab selection or final focus fails.

- [ ] **Step 3: Add exact Chrome tab creation**

After exact OmniWM focus, capture Chrome's AppleScript ID for its front window.
Reconfirm the same opaque OmniWM ID without changing focus. Create the tab in
`first window whose id is N`. Select the new tab in a separate AppleScript
operation so the caller can distinguish a creation failure from a later
selection failure. Escape the URL with `appleScriptLiteral`.

- [ ] **Step 4: Add the exact-window route**

Query the active workspace and windows. Resolve one target with the pure helper.
Use `focusSummonedWindow(target.id, ...)` only as an existing bounded exact-ID
focus helper; do not summon the window. Delegate the focus, ID capture,
revalidation, tab creation, fallback, and final focus sequence to
`omniwm_chatgpt_router.lua`.

- [ ] **Step 5: Dispatch ChatGPT before Ghostty routing**

In `hs.urlevent.httpCallback`, route exact sender bundle `com.openai.codex` to
the ChatGPT route before the current explicit-sender branch. Keep current
Ghostty and unknown-sender behavior unchanged. Log the route decision without
the URL.

- [ ] **Step 6: Deploy and test the router module**

Add the router module to `install_omniwm.yml`. Add its behavioral test to the
integration workflow.

- [ ] **Step 7: Update the cheat sheet**

In `docs/omniwm-cheatsheet.md`, document that ChatGPT links open in and focus the
single Chrome window in the active workspace. Document normal Chrome fallback
when the target is absent or ambiguous.

- [ ] **Step 8: Run static and behavioral verification**

Run:

```bash
lua tests/omniwm-url-source.lua
lua tests/omniwm-chatgpt-router.lua
luac -p roles/macos/files/hammerspoon/omniwm.lua
luac -p roles/macos/files/hammerspoon/omniwm_chatgpt_router.lua
ruby tests/configure-omniwm-settings.rb
rg -n 'summon|move-to-workspace' roles/macos/files/hammerspoon/omniwm.lua
```

Expected: All tests and syntax checks pass. Inspection confirms the new ChatGPT
route contains no move or summon call.

- [ ] **Step 9: Commit**

Commit the router and documentation as `Focus Chrome for ChatGPT links`.

### Task 3: Final review and pull request

**Files:**
- Review: all branch changes against `origin/main`

**Interfaces:**
- Consumes: completed implementation and verification evidence
- Produces: clean branch and open GitHub pull request

- [ ] **Step 1: Verify the complete branch**

Run the focused Lua test, Lua syntax check, Ruby suite, `git diff --check`, and
`git status --short`.

- [ ] **Step 2: Review safety properties**

Confirm that the ChatGPT route never moves or summons windows, never logs URLs,
and never opens a duplicate URL after successful tab creation.

- [ ] **Step 3: Update commits if review finds a defect**

Make a focused correction, rerun the affected checks, and commit it.

- [ ] **Step 4: Open the pull request**

Push the clean branch and use the repository pull-request workflow. Include a
`## Verification` section that follows repository policy.
