# Slack Work Safari Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route Slack links to the exact Safari Work profile window and focus its OmniWM workspace.

**Architecture:** Extend the pure URL-source module with exact Slack and Work Safari classification. Add a dependency-injected Slack routing state machine, then dispatch Slack before generic URL routing in the Hammerspoon integration. Reuse exact Safari native-ID tab creation and exact OmniWM navigation without moving or summoning windows.

**Tech Stack:** Lua 5.4, Hammerspoon, OmniWM IPC, AppleScript, Ansible, Ruby/Minitest

**Spec:** `docs/superpowers/specs/2026-09-16-slack-work-safari-routing-design.md`

## Global Constraints

- Match Slack only by bundle ID `com.tinyspeck.slackmacgap`.
- Match Work Safari only by Safari bundle ID and a title that starts with `Work —`.
- Require one exact Work Safari candidate.
- Do not move or summon any window.
- Do not reopen the URL after a tab was created.
- Do not change Ghostty, ChatGPT, or generic URL routing.
- Deploy only through the existing `brian-macbook-pro` OmniWM host gate.

---

### Task 1: Add exact Slack-to-Work-Safari routing

**Files:**
- Modify: `roles/macos/files/hammerspoon/omniwm_url_source.lua`
- Create: `roles/macos/files/hammerspoon/omniwm_slack_router.lua`
- Modify: `roles/macos/files/hammerspoon/omniwm.lua`
- Modify: `roles/macos/tasks/install_omniwm.yml`
- Modify: `tests/omniwm-url-source.lua`
- Create: `tests/omniwm-slack-router.lua`
- Modify: `.github/workflows/integration-test.yml`
- Modify: `docs/omniwm-cheatsheet.md`

**Interfaces:**
- Produces: `isSlackSender(senderBundle) -> boolean`.
- Produces: `isWorkSafariWindow(window) -> boolean`.
- Produces: `resolveWorkSafariWindow(windows) -> window|nil, error|nil`.
- Produces: `slackRouter.route(url, target, deps)` where `deps` supplies
  `openTab`, `navigate`, `fallback`, and `notify`.
- Consumes: existing `openSafariTab`, `navigateAndConfirmWindow`,
  `openNormallyInSafari`, `M.windows`, and `M.notify` helpers.

- [ ] **Step 1: Add failing URL-source tests**

Extend `tests/omniwm-url-source.lua` with assertions equivalent to:

```lua
assertEqual(true, source.isSlackSender("com.tinyspeck.slackmacgap"), "Slack sender")
assertEqual(false, source.isSlackSender("com.apple.MobileSMS"), "non-Slack sender")

local workSafari = {
  id = "ow_work",
  app = {bundleId = "com.apple.Safari"},
  title = "Work — Inbox",
  workspace = {number = 9},
}
assertEqual(true, source.isWorkSafariWindow(workSafari), "Work Safari window")
local workTarget, workError = source.resolveWorkSafariWindow({workSafari})
assertEqual("ow_work", workTarget and workTarget.id, "one Work Safari target")
assertEqual(nil, workError, "one Work Safari target error")
```

Also assert rejection of Personal Safari, titleless Safari panels, absent targets,
and two Work Safari candidates.

- [ ] **Step 2: Add failing routing-state tests**

Create `tests/omniwm-slack-router.lua`. Load the production router and use injected
functions to record calls. Cover:

```lua
router.route("https://example.test", workSafari, {
  openTab = function(target, url)
    table.insert(calls, "open:" .. target.id)
    return true, nil
  end,
  navigate = function(id, callback)
    table.insert(calls, "navigate:" .. id)
    callback({}, nil)
  end,
  fallback = function() table.insert(calls, "fallback") end,
  notify = function(message) table.insert(calls, "notify:" .. message) end,
})
```

Assert `open:ow_work,navigate:ow_work` on success. Assert one fallback when the
target is absent or tab creation fails. Assert notification and zero fallback
when navigation fails after tab creation.

- [ ] **Step 3: Run the new tests and confirm failure**

Run:

```bash
lua tests/omniwm-url-source.lua
lua tests/omniwm-slack-router.lua
```

Expected: failure because the Slack functions and router module do not exist.

- [ ] **Step 4: Implement pure source classification and resolution**

In `omniwm_url_source.lua`, add the exact Slack bundle constant and functions:

```lua
function M.isSlackSender(senderBundle)
  return senderBundle == "com.tinyspeck.slackmacgap"
end

function M.isWorkSafariWindow(window)
  return M.isSafariBrowserWindow(window)
    and window.title:sub(1, #"Work —") == "Work —"
end
```

Implement `resolveWorkSafariWindow` with the existing Development Safari
resolver pattern. Return one candidate, `nil` when absent, and a clear error when
ambiguous.

- [ ] **Step 5: Implement the Slack state machine**

Create `omniwm_slack_router.lua` with `route(url, target, deps)`:

```lua
if not target then
  deps.fallback(url)
  return
end
local created, createError = deps.openTab(target, url)
if not created then
  deps.notify(createError or "Could not open the Slack link in Work Safari")
  deps.fallback(url)
  return
end
deps.navigate(target.id, function(_, navigateError)
  if navigateError then deps.notify(navigateError) end
end)
```

Do not call fallback after successful tab creation.

- [ ] **Step 6: Integrate Slack dispatch**

Require the new router in `omniwm.lua`. Add `routeSlackURL` that queries windows,
resolves Work Safari, and invokes the state machine with:

```lua
openTab = openSafariTab
navigate = navigateAndConfirmWindow
fallback = openNormallyInSafari
notify = M.notify
```

In `hs.urlevent.httpCallback`, check `isSlackSender` after ChatGPT and before the
generic explicit-sender branch. Log `decision=slack-work-safari` without the URL.

- [ ] **Step 7: Deploy and document the module**

Add an Ansible copy task for `omniwm_slack_router.lua` next to the other OmniWM
Hammerspoon modules. Add `lua tests/omniwm-slack-router.lua` to the integration
workflow. Update `docs/omniwm-cheatsheet.md` to state that Slack links open in
Work Safari and focus workspace 9, with normal Safari as the absent or ambiguous
target fallback.

- [ ] **Step 8: Run focused verification**

Run:

```bash
lua tests/omniwm-url-source.lua
lua tests/omniwm-slack-router.lua
for test in tests/omniwm-*.lua; do lua "$test"; done
find roles/macos/files/hammerspoon -name '*.lua' -print0 |
  xargs -0 -n1 lua -e 'assert(loadfile(arg[1]))'
ruby tests/configure-omniwm-settings.rb
ansible-playbook playbook.yml --syntax-check
```

Expected: all commands pass.

- [ ] **Step 9: Inspect the diff and commit**

Run:

```bash
git diff --check
git status --short
git diff --stat
git diff
```

Commit the implementation, tests, deployment wiring, and cheat-sheet update in
one coherent commit with an imperative message.
