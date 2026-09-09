# Hammerspoon Browser Update Restarts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Gracefully restart running Brave and Google Chrome instances at 4:00 AM through Hammerspoon so pending updates can take effect.

**Architecture:** A focused Lua module owns the daily timer and an independent non-blocking restart state machine for each browser. The managed Hammerspoon configuration loads the module, while Ansible installs it before the existing configuration reload.

**Tech Stack:** Lua 5.4, Hammerspoon `hs.timer` and `hs.application`, Ansible YAML

**Spec:** `docs/superpowers/specs/2026-09-09-hammerspoon-browser-update-restarts-design.md`

## Global Constraints

- Schedule the callback daily at exactly `04:00` through Hammerspoon.
- Manage only `com.brave.Browser` and `com.google.Chrome`.
- Never launch a browser that was absent when its restart began.
- Request only a normal quit. Never call `kill9`, send an uncatchable signal, or otherwise force-quit.
- Wait at most 60 seconds for each browser and do not block Hammerspoon.
- Relaunch only after the application is no longer running.
- Do not add or modify a LaunchAgent, cron job, or browser session setting.
- Install and deploy all artifacts only through this repository.

---

### Task 1: Browser Restart Scheduler and Managed Hammerspoon Integration

**Files:**
- Create: `tests/browser-update-restart.lua`
- Create: `roles/macos/files/hammerspoon/browser_update_restart.lua`
- Modify: `roles/macos/tasks/main.yml:520-620`

**Interfaces:**
- Consumes: injected dependency functions `scheduleAt(time, interval, callback)`, `doEvery(seconds, callback)`, `find(bundleID)`, `quit(app)`, `launch(bundleID)`, `now()`, and `logError(message)`.
- Produces: `require("browser_update_restart").new(dependencies)` returning a controller with `start()` and `runNow()` methods, plus module-level `start(dependencies)` that owns and retains the production controller. Controller `start()` returns the retained daily timer.

- [x] **Step 1: Write the failing behavioral test**

Create `tests/browser-update-restart.lua`. Require the production module through
`roles/macos/files/hammerspoon/?.lua`. Build a deterministic harness with an
application table, recorded quit/launch/error arrays, a controllable clock, and
captured daily and polling callbacks.

The test must assert these observable cases:

```lua
local controller = browserRestart.new(dependencies)
local dailyTimer = controller.start()
assertEqual("04:00", scheduled.time, "daily restart time")
assertEqual("1d", scheduled.interval, "daily restart interval")
assertEqual(dailyTimer, scheduled.timer, "start returns retained daily timer")

scheduled.callback()
assertEqual(0, #events.quit, "absent browsers are not quit")
assertEqual(0, #events.launch, "absent browsers are not launched")

applications["com.brave.Browser"] = {bundleID = "com.brave.Browser"}
controller.runNow()
assertEqual("com.brave.Browser", events.quit[#events.quit], "running Brave quits normally")
polls[#polls].callback()
assertEqual(0, #events.launch, "running Brave is not launched before exit")
applications["com.brave.Browser"] = nil
polls[#polls].callback()
assertEqual("com.brave.Browser", events.launch[#events.launch], "stopped Brave relaunches")
assertEqual(true, polls[#polls].stopped, "successful poll stops")

applications["com.google.Chrome"] = {bundleID = "com.google.Chrome"}
controller.runNow()
clock = clock + 60
polls[#polls].callback()
assertEqual(true, polls[#polls].stopped, "timed-out poll stops")
assertEqual(1, #events.error, "timeout logs one error")
assertEqual(1, #events.launch, "timeout does not relaunch Chrome")
```

Also add cases that prove a failed normal quit creates no poll or launch, a
failed relaunch logs an error, and Brave can complete while Chrome times out.
The fake application API must expose no force-quit function, so the production
module cannot satisfy tests through one. Add a weak-reference test that calls
the module-level `start(dependencies)`, drops the returned controller, performs
two full Lua garbage collections, and proves the scheduled daily timer remains
reachable.

- [x] **Step 2: Run the test and verify RED**

Run:

```bash
lua tests/browser-update-restart.lua
```

Expected: failure because `browser_update_restart` cannot be found.

- [x] **Step 3: Implement the minimal restart module**

Create `roles/macos/files/hammerspoon/browser_update_restart.lua` with:

```lua
local M = {}
local browsers = {
  {name = "Brave Browser", bundleID = "com.brave.Browser"},
  {name = "Google Chrome", bundleID = "com.google.Chrome"},
}
local timeoutSeconds = 60
local pollSeconds = 1

local function defaultDependencies()
  local logger = hs.logger.new("browser-update-restart", "info")
  return {
    scheduleAt = hs.timer.doAt,
    doEvery = hs.timer.doEvery,
    find = hs.application.get,
    quit = function(app)
      local ok, result = pcall(function() return app:kill() end)
      return ok and result ~= false
    end,
    launch = hs.application.launchOrFocusByBundleID,
    now = hs.timer.secondsSinceEpoch,
    logError = function(message) logger.e(message) end,
  }
end
```

`M.new(dependencies)` must use the injected table or `defaultDependencies()`.
It must keep the daily timer and all poll timers in controller-owned state.
For each browser, `runNow()` must find the application once, skip when absent,
request `quit`, and only create a poll when quit succeeds. Each poll callback
must find the bundle again. If absent, it must stop and remove its timer before
calling `launch`. If launch returns false, it must log a browser-specific error.
If the application is still present at `deadline = now() + 60`, it must stop and
remove the timer and log a timeout. It must not relaunch on timeout. `start()`
must create only one daily timer with:

```lua
dependencies.scheduleAt("04:00", "1d", controller.runNow)
```

Repeated controller `start()` calls must return the existing daily timer instead
of adding another schedule. Module-level `M.start(dependencies)` must construct,
start, and privately retain one production controller, then return that same
controller on later calls. Return `M` at the end of the file.

- [x] **Step 4: Run the focused test and verify GREEN**

Run:

```bash
lua tests/browser-update-restart.lua
luac -p roles/macos/files/hammerspoon/browser_update_restart.lua
```

Expected: the behavioral test prints one PASS line and Lua syntax validation
returns status 0.

- [x] **Step 5: Add the Ansible and init.lua integration**

In `roles/macos/tasks/main.yml`, after the Hammerspoon configuration directory
and before the managed `init.lua`, add a copy task:

```yaml
- name: Install browser update restart Hammerspoon module
  copy:
    src: hammerspoon/browser_update_restart.lua
    dest: ~/.hammerspoon/browser_update_restart.lua
    mode: '0644'
```

At the top of the managed `init.lua` content after `hs.ipc.cliInstall()`, start
the module-owned controller:

```lua
require("browser_update_restart").start()
```

Do not alter the optional `init.local.lua` hook or add launchd tasks.

- [x] **Step 6: Run focused and regression verification**

Run:

```bash
lua tests/browser-update-restart.lua
for test_file in tests/omniwm-*.lua; do lua "$test_file"; done
luac -p roles/macos/files/hammerspoon/browser_update_restart.lua
ansible-playbook playbook.yml --syntax-check
```

Expected: all Lua tests pass, `luac` returns status 0, and Ansible reports that
`playbook.yml` passes syntax validation.

- [x] **Step 7: Commit the implementation**

Run:

```bash
bash ~/.local/share/skills/_commit/commit.sh \
  -m "Restart running browsers for nightly updates" \
  tests/browser-update-restart.lua \
  roles/macos/files/hammerspoon/browser_update_restart.lua \
  roles/macos/tasks/main.yml
```

Expected: one implementation commit and a clean worktree.

### Task 2: Provision and Verify the Live Hammerspoon Configuration

**Files:**
- No source file changes expected.

**Interfaces:**
- Consumes: the committed Ansible task, Lua module, and managed `init.lua` integration from Task 1.
- Produces: deployed `~/.hammerspoon/browser_update_restart.lua` and a reloaded Hammerspoon configuration with one daily timer.

- [x] **Step 1: Run check mode**

Run:

```bash
bin/provision --check
```

Expected: provisioning completes without failure and reports the new module and
managed `init.lua` as pending changes.

- [x] **Step 2: Provision the current macOS host**

Run:

```bash
bin/provision
```

Expected: provisioning installs the module, updates `init.lua`, reloads
Hammerspoon, and completes without failure.

- [x] **Step 3: Confirm the deployed module and loaded package**

Run:

```bash
cmp roles/macos/files/hammerspoon/browser_update_restart.lua \
  "$HOME/.hammerspoon/browser_update_restart.lua"
hs -c 'print(package.loaded["browser_update_restart"] ~= nil)'
```

Expected: `cmp` returns status 0 and Hammerspoon prints `true`. Do not invoke
`runNow()` because that would restart active browsers outside the scheduled
window.

- [x] **Step 4: Confirm repository state**

Run:

```bash
git diff --check
git status --short --branch
```

Expected: no diff errors and no uncommitted source changes.
