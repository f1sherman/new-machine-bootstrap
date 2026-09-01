# OmniWM Workspace Stability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve live OmniWM workspace placement during settings deployment and route Ghostty links when Hammerspoon lacks a usable sender PID.

**Architecture:** Let OmniWM's settings watcher apply settings-only updates without a process restart. Put URL-source classification in a small pure Lua module, then let the existing Hammerspoon helper gather sender and OmniWM state before it selects dedicated or normal Safari routing.

**Tech Stack:** Ansible, Lua, Hammerspoon, OmniWM IPC, Ruby test runner

**Spec:** `docs/superpowers/specs/2026-09-01-omniwm-workspace-stability-design.md`

## Global Constraints

- Do not issue bulk live window moves.
- Keep explicit non-Ghostty senders on normal Safari routing.
- Do not log URLs.
- Preserve restart behavior for an OmniWM app update, LaunchAgent update, or absent job.
- Keep current workspace assignments and shortcuts unchanged.

---

### Task 1: URL source recovery

**Files:**
- Create: `roles/macos/files/hammerspoon/omniwm_url_source.lua`
- Create: `tests/omniwm-url-source.lua`
- Modify: `roles/macos/files/hammerspoon/omniwm.lua`
- Modify: `roles/macos/tasks/install_omniwm.yml`

**Interfaces:**
- Consumes: sender bundle ID, active workspace number, and OmniWM window snapshots.
- Produces: `source.shouldRouteGhostty(senderBundle, activeWorkspace, windows) -> boolean`.

- [ ] **Step 1: Write the failing Lua test**

Create a table-driven test that requires `omniwm_url_source.lua` and checks:

```lua
assert(route("com.mitchellh.ghostty", 9, {}) == true)
assert(route("com.tinyspeck.slackmacgap", 3, visibleGhostty) == false)
assert(route(nil, 3, visibleGhostty) == true)
assert(route("org.hammerspoon.Hammerspoon", 3, visibleGhostty) == true)
assert(route(nil, 2, hiddenGhostty) == false)
assert(route(nil, 2, ghosttyInWorkspace3) == false)
```

The fixture windows must use the production OmniWM fields: `app.bundleId`,
`workspace.number`, and `isVisible`.

- [ ] **Step 2: Run the test and confirm the expected failure**

Run:

```bash
lua tests/omniwm-url-source.lua
```

Expected: failure because `omniwm_url_source.lua` does not exist.

- [ ] **Step 3: Implement the pure classifier**

Return `true` immediately for an explicit Ghostty sender. Return `false`
immediately for any explicit sender other than Hammerspoon. Treat nil and
Hammerspoon as unavailable. For an unavailable sender, return `true` only when
one current window has the Ghostty bundle ID, the active workspace number, and
`isVisible == true`.

- [ ] **Step 4: Integrate the classifier**

Require `omniwm_url_source` from `omniwm.lua`. In `hs.urlevent.httpCallback`,
resolve a positive sender PID to a bundle ID. If the classifier can decide from
an explicit sender, route immediately. Otherwise query the active workspace and
windows, pass the snapshots to the classifier, and select the existing
`routeGhosttyURL` or `openNormallyInSafari` path.

Log sender PID, sender bundle, and the final `ghostty` or `normal` decision at
info level. Do not log `fullURL`.

Install `omniwm_url_source.lua` into `~/.hammerspoon/` before `omniwm.lua`.

- [ ] **Step 5: Run focused validation**

Run:

```bash
lua tests/omniwm-url-source.lua
luac -p roles/macos/files/hammerspoon/omniwm_url_source.lua
luac -p roles/macos/files/hammerspoon/omniwm.lua
```

Expected: all commands exit 0.

- [ ] **Step 6: Commit Task 1**

Commit the four Task 1 files with an imperative message that describes Ghostty
source recovery.

### Task 2: Settings deployment without a live restart

**Files:**
- Modify: `roles/macos/tasks/install_omniwm.yml`

**Interfaces:**
- Consumes: the existing prelaunch drift result, job state, app update state,
  plist update state, and final IPC ping.
- Produces: a lifecycle where settings-only drift uses OmniWM external reload.

- [ ] **Step 1: Record the failing lifecycle condition**

Inspect the current task flow and record that a loaded job plus settings drift
runs `launchctl bootout`, reconciles settings, and then bootstraps. Confirm this
against `/tmp/provision-20260831-195143.log`.

Expected: the log shows all three actions as changed at the reported incident
time.

- [ ] **Step 2: Remove settings-only process mutations**

Remove `Stop loaded OmniWM job before prelaunch reconciliation`. Let the
prelaunch reconciler write while the job remains loaded. Remove the
post-configuration stop and reload tasks. Remove the obsolete prelaunch-stop
term from the bootstrap condition.

Keep bootstrap when the app changed, the plist changed, or the job is absent.
Keep the final retried `omniwmctl ping` check.

- [ ] **Step 3: Run static and focused validation**

Run:

```bash
ansible-playbook playbook.yml --syntax-check
git diff --check
ruby tests/configure-omniwm-settings.rb
lua tests/omniwm-url-source.lua
```

Expected: all commands exit 0.

- [ ] **Step 4: Commit Task 2**

Commit `roles/macos/tasks/install_omniwm.yml` with an imperative message that
explains why settings-only deployment keeps OmniWM running.

### Task 3: Safe live verification

**Files:**
- No source changes expected.

**Interfaces:**
- Consumes: the completed Task 1 and Task 2 commits.
- Produces: target-Mac evidence without bulk window movement.

- [ ] **Step 1: Capture the live baseline**

Record the OmniWM PID and a JSON map of each current window ID to workspace
number. Also record the dedicated Safari Hammerspoon setting.

- [ ] **Step 2: Provision the branch**

Run:

```bash
bin/provision
```

Expected: provisioning exits 0. A settings-only change does not change the
OmniWM PID. Existing window IDs retain their workspace numbers.

- [ ] **Step 3: Verify Ghostty routing**

Open one harmless HTTPS link from Ghostty. Confirm Hammerspoon logs a `ghostty`
decision without the URL. Confirm the link becomes a new tab in the dedicated
Safari window in the active workspace.

- [ ] **Step 4: Verify normal routing**

Open one harmless HTTPS link from an explicit non-Ghostty application. Confirm
Hammerspoon logs a `normal` decision and Safari handles the link normally.

- [ ] **Step 5: Run final verification**

Run the syntax, Ruby, Lua, and diff checks again. Confirm the worktree is clean
after the final implementation commit.
