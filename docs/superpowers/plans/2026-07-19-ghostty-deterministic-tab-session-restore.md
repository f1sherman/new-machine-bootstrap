# Ghostty Deterministic Tab Session Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recreate the saved regular Ghostty tab set deterministically and attach each surface to its intended tmux session.

**Architecture:** Disable unreliable native surface restoration. The first helper in a new Ghostty process initializes and claims from the existing locked manifest queue, then a one-shot AppleScript builder creates one tab per remaining queue entry and waits for each claim before continuing.

**Tech Stack:** Bash, AppleScript, jq, tmux, Ruby/Minitest, Ansible

## Global Constraints

- Work only in the existing isolated worktree.
- `window-save-state = never` makes startup surface count deterministic.
- Quick-terminal exclusion remains structural through Ghostty regular-tab enumeration.
- Never release the tmux startup lock before reserving a selected session.
- The builder must not hold the tmux startup lock while creating tabs.
- Stop on queue timeout or AppleScript error; never create remaining tabs blindly.
- Diagnostics remain best-effort, nonblocking, single-line, synchronized, and bounded.
- Production changes require a failing regression first.

---

## Completed foundation

The branch already includes and tests:

- PID-owned selection reservations and safe visible fallback;
- exact tmux lookup through `=session:`;
- ordered validated regular-tab manifest saving;
- per-Ghostty-process restore queue initialization and consumption;
- malformed queue recovery and non-Ghostty bypass;
- bounded diagnostics and report sections;
- explicit protection against a new process replacing last-good state with a partial different set.

---

### Task 1: Request a builder only from the queue initializer

**Files:**
- Modify: `roles/common/files/bin/tmux-attach-or-new`
- Modify: `tests/tmux-restore-startup.rb`

**Interfaces:**
- Produces `tabs_restore_needed=1` only after initializing a nonempty queue for a new Ghostty PID.
- Invokes `${TMUX_GHOSTTY_TABS_RESTORE:-$HOME/.local/bin/ghostty-session-tabs-restore}` after `unlock_startup`.
- Passes `TMUX_GHOSTTY_APP_PID`, `TMUX_GHOSTTY_MANIFEST`, and `TMUX_GHOSTTY_RESTORE_QUEUE`.

- [ ] **Step 1: Write failing invocation tests**

Add a fake builder that records PID, manifest, queue, and whether the startup lock can be acquired. Assert:

```ruby
assert_equal 1, builder_invocations.length
assert_equal "200", builder_invocations.first.fetch("ghostty_pid")
assert_equal "unlocked", builder_invocations.first.fetch("lock_state")
```

Also assert no invocation for same-process manifests, invalid manifests, empty pending queues, and non-Ghostty helpers.

- [ ] **Step 2: Run RED**

```bash
ruby tests/tmux-restore-startup.rb
```

Expected: builder invocation assertion fails because no builder is launched.

- [ ] **Step 3: Implement minimal invocation**

Set a local flag during successful queue initialization. After reserving the first target and calling `unlock_startup`, launch the executable builder in the background with explicit environment paths. Log `tab_builder_skipped` if the flag is set but the executable is absent.

- [ ] **Step 4: Run GREEN**

```bash
ruby tests/tmux-restore-startup.rb
bash -n roles/common/files/bin/tmux-attach-or-new
shellcheck roles/common/files/bin/tmux-attach-or-new
```

Expected: all pass.

---

### Task 2: Build tabs sequentially from queue claims

**Files:**
- Create: `roles/macos/files/bin/ghostty-session-tabs-restore`
- Create: `tests/ghostty-session-tabs-restore.rb`
- Modify: `.github/workflows/integration-test.yml`

**Interfaces:**
- Consumes `TMUX_GHOSTTY_APP_PID`, `TMUX_GHOSTTY_MANIFEST`, and `TMUX_GHOSTTY_RESTORE_QUEUE`.
- Optional test/operation controls: `TMUX_GHOSTTY_TABS_RESTORE_LOCK`, `TMUX_GHOSTTY_TABS_RESTORE_TIMEOUT`, and `TMUX_GHOSTTY_TABS_RESTORE_POLL_INTERVAL`.
- Calls Ghostty AppleScript `new tab in targetWindow` and `select tab`.

- [ ] **Step 1: Write failing builder tests**

Use fake `osascript` and `pgrep` commands. The fake new-tab action atomically removes one queue entry and records a creation. Assert four pending names produce exactly four creations, an empty queue, and selection of the saved index. Add separate assertions for stale PID, empty queue, AppleScript failure, and a queue that never shrinks.

- [ ] **Step 2: Run RED**

```bash
ruby tests/ghostty-session-tabs-restore.rb
```

Expected: failure because the builder does not exist.

- [ ] **Step 3: Implement minimal builder**

Use a separate `flock -n` singleton. Capture the initial window ID, read pending count, create one tab, and poll until `.pending | length` decreases before the next iteration. Verify the active Ghostty PID before every creation. Select `.windows[0].selected_tab_index` only after queue length reaches zero.

- [ ] **Step 4: Run GREEN and register CI**

```bash
ruby tests/ghostty-session-tabs-restore.rb
bash tests/ci-test-inventory.sh
bash -n roles/macos/files/bin/ghostty-session-tabs-restore
shellcheck roles/macos/files/bin/ghostty-session-tabs-restore
```

Expected: all pass.

---

### Task 3: Make provisioning deterministic

**Files:**
- Modify: `roles/macos/tasks/main.yml`
- Modify: `tests/ghostty-session-manifest.rb`

- [ ] **Step 1: Change the configuration test first**

Require:

```ruby
assert_match(/line: 'window-save-state = never'/, tasks)
refute_match(/line: 'window-save-state = always'/, tasks)
```

Also assert the builder is present under `roles/macos/files/bin/` so the existing macOS script glob provisions it.

- [ ] **Step 2: Run RED**

```bash
ruby tests/ghostty-session-manifest.rb
```

Expected: configuration still says `always`.

- [ ] **Step 3: Set native state to never**

Change the existing idempotent `lineinfile` task to `window-save-state = never`. Do not add compatibility fallback logic.

- [ ] **Step 4: Run GREEN**

```bash
ruby tests/ghostty-session-manifest.rb
ansible-playbook playbook.yml --syntax-check
```

Expected: pass.

---

### Task 4: Verify, review, provision, and update PR #340

- [ ] **Step 1: Run complete automated verification**

```bash
ruby tests/tmux-restore-startup.rb
ruby tests/ghostty-session-manifest.rb
ruby tests/ghostty-session-tabs-restore.rb
bash tests/tmux-restore-diagnostics.sh
bash tests/ci-test-inventory.sh
bash tests/ghostty-quick-terminal.sh
shellcheck roles/common/files/bin/tmux-attach-or-new \
  roles/macos/files/bin/ghostty-session-manifest-save \
  roles/macos/files/bin/ghostty-session-tabs-restore
ansible-playbook playbook.yml --syntax-check
git diff --check
```

- [ ] **Step 2: Obtain a read-only review**

Review queue initialization, builder singleton behavior, timeout safety, PID checks, AppleScript targeting, and Linux bypass. Fix only reproduced issues through red-green tests.

- [ ] **Step 3: Provision and verify installed state**

```bash
bin/provision
cmp roles/common/files/bin/tmux-attach-or-new ~/.local/bin/tmux-attach-or-new
cmp roles/macos/files/bin/ghostty-session-tabs-restore ~/.local/bin/ghostty-session-tabs-restore
grep -x 'window-save-state = never' "$HOME/Library/Application Support/com.mitchellh.ghostty/config"
```

Explicitly run the manifest saver and confirm the five expected current sessions before restart.

- [ ] **Step 4: Push and update PR**

Push the branch, update the PR body from native restoration to deterministic reconstruction, reply to relevant review threads, and rearm monitoring.

- [ ] **Step 5: Real app restart**

Quit Ghostty with `Cmd-Q`, reopen, and capture tabs, clients, queue, and lifecycle events before manual intervention. Pass criteria: five regular tabs, five distinct intended sessions, empty queue, no numeric regular tabs, no blank tabs.
