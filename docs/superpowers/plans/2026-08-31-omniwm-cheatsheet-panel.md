# OmniWM Cheat-Sheet Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `Control+Option+H` as a laptop-specific toggle for a secure, floating Hammerspoon cheat-sheet panel.

**Architecture:** A focused Lua module owns panel state, file loading, HTML escaping, screen placement, and hotkeys. Ansible installs the authoritative Markdown mirror and module inside the existing OmniWM host gate. The OmniWM reconciler reserves the shortcut and adds one exact-title floating rule.

**Tech Stack:** Ansible, Ruby/Minitest, Lua 5.4, Hammerspoon `hs.webview`, OmniWM TOML reconciliation

**Spec:** `docs/superpowers/specs/2026-08-31-omniwm-cheatsheet-panel-design.md`

## Global Constraints

- Keep `docs/omniwm-cheatsheet.md` as the only repository source of truth.
- Install only through the existing `brian-macbook-pro` OmniWM host gate.
- Use `Control+Option+H`; Escape is active only while the panel is visible.
- Do not change Finder scratchpad or Photos behavior.
- Do not add network or Markdown-rendering dependencies.
- Do not run live provisioning in this implementation session.

---

### Task 1: Build and test the panel module

**Files:**
- Create: `roles/macos/files/hammerspoon/omniwm_cheatsheet.lua`
- Create: `tests/omniwm-cheatsheet-panel.lua`

**Interfaces:**
- Consumes: `hs.webview`, `hs.hotkey`, `hs.mouse`, `hs.drawing`, and `hs.notify`.
- Produces: `M.new({path, notify}) -> controller`, where the controller exposes `toggle()`, `show()`, and `hide()`.

- [ ] **Step 1: Write the failing behavioral test**

Create a Lua test harness with stub webview, hotkey, screen, and notification
objects. Assert that the production module:

```lua
local controller = module.new({path = markdownPath, notify = notify})
controller:show()
assertContains(webview.htmlValue, "&lt;script&gt;&amp;&quot;&#39;")
assertTrue(escapeHotkey.enabled)
controller:toggle()
assertFalse(webview.visible)
assertFalse(escapeHotkey.enabled)
```

Also change the temporary Markdown between shows and assert the new HTML is
loaded, delete the file and assert notification without stale display, and
assert the centered frame and all-Spaces behavior.

- [ ] **Step 2: Run the test and verify failure**

Run: `lua tests/omniwm-cheatsheet-panel.lua`
Expected: FAIL because `omniwm_cheatsheet.lua` does not exist.

- [ ] **Step 3: Implement the minimal module**

Implement:

```lua
function M.new(options)
  -- retain one webview, one disabled Escape hotkey, and explicit show/hide state
end
```

Use `io.open`, escape `&`, `<`, `>`, `"`, and `'`, emit static CSP-protected
HTML, create the webview with JavaScript disabled, set utility/resizable/titled
style, floating level, `canJoinAllSpaces` and `fullScreenAuxiliary`, and center a
68%-by-78% frame on `hs.mouse.getCurrentScreen():frame()` on each show.

- [ ] **Step 4: Run the focused test**

Run: `lua tests/omniwm-cheatsheet-panel.lua`
Expected: PASS with all panel lifecycle assertions.

### Task 2: Reserve the shortcut and floating rule

**Files:**
- Modify: `roles/macos/files/configure-omniwm-settings`
- Modify: `tests/configure-omniwm-settings.rb`

**Interfaces:**
- Consumes: managed hotkey and app-rule TOML blocks.
- Produces: an unassigned `Control+Option+H` conflict and an exact
  `org.hammerspoon.Hammerspoon` plus `OmniWM Cheat Sheet` rule with
  `layout = "float"` in both deferred and active assignment modes.

- [ ] **Step 1: Add failing reconciler assertions**

Add a fixture hotkey using `Control+Option+H`. Assert it becomes `Unassigned`.
Assert both reconciliation modes create exactly one exact-title Hammerspoon rule
with `layout = "float"`, no workspace assignment, and byte-for-byte idempotency.

- [ ] **Step 2: Run the reconciler test and verify failure**

Run: `ruby tests/configure-omniwm-settings.rb`
Expected: FAIL because the shortcut and rule are not managed.

- [ ] **Step 3: Implement narrow reconciliation**

Extend `RuleTarget` with optional `layout`. Add the exact Hammerspoon target.
Create or update targets with a layout even in deferred assignment mode. Render
`layout` in new rules. Add `Control+Option+H` to reserved bindings without
removing unrelated custom bindings.

- [ ] **Step 4: Run the reconciler tests**

Run: `ruby tests/configure-omniwm-settings.rb`
Expected: all tests pass.

### Task 3: Deploy and connect the panel

**Files:**
- Modify: `roles/macos/tasks/install_omniwm.yml`
- Modify: `roles/macos/files/hammerspoon/omniwm.lua`
- Modify: `docs/omniwm-cheatsheet.md`

**Interfaces:**
- Consumes: the panel module and authoritative Markdown.
- Produces: installed files under `~/.hammerspoon` and
  `~/.local/share/omniwm`, plus the global `Control+Option+H` binding.

- [ ] **Step 1: Add Ansible deployment tasks**

Create `~/.local/share/omniwm` with mode `0755`, copy
`docs/omniwm-cheatsheet.md` to the managed mirror with mode `0644`, and copy
`omniwm_cheatsheet.lua` beside the existing Hammerspoon helper. Use an Ansible
`copy` source relative path that reaches the repository document without adding
a second repository copy.

- [ ] **Step 2: Bind the panel module**

At Hammerspoon initialization, require the module, construct it with
`$HOME/.local/share/omniwm/omniwm-cheatsheet.md`, bind
`hs.hotkey.bind({"ctrl", "alt"}, "H", controller.toggle)`, and retain the
controller and hotkey objects.

- [ ] **Step 3: Update the authoritative cheat sheet**

Add `⌃⌥H` under windows available from every workspace. Explain that the same
shortcut or Escape hides the panel.

- [ ] **Step 4: Run complete static verification**

Run:

```text
lua tests/omniwm-cheatsheet-panel.lua
ruby tests/configure-omniwm-settings.rb
luac -p roles/macos/files/hammerspoon/omniwm.lua
luac -p roles/macos/files/hammerspoon/omniwm_cheatsheet.lua
ansible-playbook playbook.yml --syntax-check
git diff --check main..HEAD
git status --short
```

Expected: all commands pass and only intended files are changed before commit.

- [ ] **Step 5: Commit the implementation**

Use `~/.pi/agent/skills/z-commit/commit.sh` with the plan and all implementation
files. Leave no staged or unstaged changes.

## Self-review

- Spec coverage: every panel, security, display, Space, deployment, floating,
  shortcut, documentation, test, and rollback requirement maps to a task.
- Placeholder scan: no placeholders or deferred implementation steps remain.
- Type consistency: the module constructor and controller methods are consistent
  across tests, integration, and implementation.
- Scope: Finder and Photos logic is explicitly unchanged.

**Plan status:** Self-approved. Continue directly with implementation.
