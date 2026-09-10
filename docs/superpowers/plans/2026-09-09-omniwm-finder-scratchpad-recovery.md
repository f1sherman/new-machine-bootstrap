# OmniWM Finder Scratchpad Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recover the exact Downloads Finder window as scratchpad slot 1 after OmniWM loses scratchpad state.

**Architecture:** Add a dependency-injected recovery state machine to the existing Downloads helper. The Hammerspoon adapter selects one exact Downloads Finder window, performs bounded exact-ID focus and assignment checks, hides the recovered scratchpad, and restores the prior focus or workspace.

**Tech Stack:** Lua, Hammerspoon, OmniWM IPC, Ansible

**Spec:** `docs/superpowers/specs/2026-09-09-omniwm-finder-scratchpad-recovery-design.md`

## Global Constraints

- Do not change unrelated Finder windows.
- Do not create, close, move, or summon a window.
- Stop on missing, occupied, or ambiguous state.
- Restore the prior exact focused window when possible.
- Do not provision before the pull request merges.

---

### Task 1: Downloads recovery state machine

**Files:**
- Modify: `roles/macos/files/hammerspoon/omniwm_downloads.lua`
- Modify: `tests/omniwm-downloads.lua`

**Interfaces:**
- Produces: `downloads.recoverScratchpad(snapshot, actions)`
- `snapshot` contains `scratchpad`, `downloadsWindows`, `focusedWindow`, and `activeWorkspace`.
- `actions` provides `navigate`, `confirmFocused`, `assign`, `confirmAssigned`, `hide`, `restoreWindow`, `restoreWorkspace`, `notify`, and `done` callbacks.

- [ ] **Step 1: Add failing safe-selection tests**

Add cases that stop without mutation when scratchpad slot 1 is occupied, when no
ordinary Downloads Finder exists, and when more than one candidate exists.
Require the candidate bundle ID and exact title to be selected by the adapter,
not inferred inside the state machine.

- [ ] **Step 2: Add failing success and failure-path tests**

Test this exact order:

```text
navigate -> confirmFocused -> assign -> confirmAssigned -> hide -> restoreWindow
```

Also test navigation, focus, assignment, confirmation, and hide failures. Assert
that each path calls `done` once and restores the prior exact window after any
operation that changed focus. Test workspace restoration when no prior focused
window exists.

- [ ] **Step 3: Run the focused test and confirm failure**

Run: `lua tests/omniwm-downloads.lua`

Expected: FAIL because `recoverScratchpad` does not exist.

- [ ] **Step 4: Implement the minimal state machine**

Implement `recoverScratchpad` in `omniwm_downloads.lua`. Use callbacks only.
Do not call Hammerspoon or OmniWM directly from this module. Track whether
navigation began so recovery restores focus exactly once.

- [ ] **Step 5: Run the focused test**

Run: `lua tests/omniwm-downloads.lua`

Expected: PASS.

- [ ] **Step 6: Commit the state machine**

Commit the two files with message `Recover lost Finder scratchpad state`.

---

### Task 2: Live Hammerspoon adapter and documentation

**Files:**
- Modify: `roles/macos/files/hammerspoon/omniwm.lua`
- Modify: `docs/omniwm-cheatsheet.md`

**Interfaces:**
- Consumes: `downloads.recoverScratchpad(snapshot, actions)` from Task 1.
- Produces: one delayed readiness loop and one `recoverDownloadsScratchpad()`
  call after OmniWM IPC becomes ready.

- [ ] **Step 1: Add exact live-state queries**

Query scratchpad slot 1, all OmniWM windows, the active workspace, and the
focused window. Select Downloads candidates only when:

```lua
bundleID(window) == "com.apple.finder"
  and window.title == os.getenv("HOME") .. "/Downloads"
  and window.isScratchpad ~= true
```

Stop with a notification for multiple candidates. Treat zero candidates as a
quiet no-op.

- [ ] **Step 2: Add bounded adapters**

Use existing exact-ID helpers for navigation and focus confirmation. Assign
scratchpad slot 1 only after exact focus is confirmed. Poll until that exact
window reports `scratchpadIndex == 1`. If it remains visible, toggle scratchpad
slot 1 and poll until hidden. Navigate back to the saved exact focused window.
If none exists, switch to the saved workspace number.

- [ ] **Step 3: Wait for IPC and schedule one recovery attempt**

After all helper functions are defined, wait one second and probe OmniWM IPC.
Retry the probe once per second for up to 30 attempts. Run
`recoverDownloadsScratchpad()` once after a successful probe. Do not repeat the
recovery on an interval.

- [ ] **Step 4: Update the cheat sheet**

Explain that Hammerspoon repairs one exact `~/Downloads` Finder scratchpad after
OmniWM restarts. State that ambiguous Finder state causes no change.

- [ ] **Step 5: Run focused verification**

Run:

```bash
lua tests/omniwm-downloads.lua
luac -p roles/macos/files/hammerspoon/omniwm.lua
luac -p roles/macos/files/hammerspoon/omniwm_downloads.lua
ruby tests/configure-omniwm-settings.rb
ansible-playbook playbook.yml --syntax-check
git diff --check
```

Expected: all checks pass.

- [ ] **Step 6: Inspect prohibited operations**

Inspect the new recovery function and confirm it contains no
`move-to-workspace`, `summon-right`, Finder close command, or Finder creation.

- [ ] **Step 7: Commit the adapter and documentation**

Commit the two files with message `Repair Finder scratchpad after restart`.

---

### Task 3: Review and pull request

- [ ] **Step 1: Run all focused OmniWM tests**

Run all `tests/omniwm-*.lua` files plus the Ruby settings test and Ansible syntax
validation. Confirm a clean worktree.

- [ ] **Step 2: Run independent review**

Review the complete branch against `main`. Fix only valid Critical or Important
findings. Repeat verification after each fix.

- [ ] **Step 3: Open the pull request**

Push the clean branch and open a GitHub pull request. Include the root-cause PR
when it can be verified. Otherwise use `Introduced by: unknown`.

- [ ] **Step 4: Defer live repair until merge**

Do not provision or run the recovery against live windows before merge. After
merge, use the user’s explicit approval to provision and verify the current
Downloads window, restored focus, and Finder close behavior.
