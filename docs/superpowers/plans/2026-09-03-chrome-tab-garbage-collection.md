# Chrome Tab Garbage Collection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install a laptop-only Chrome extension that closes unpinned tabs after 60 minutes without activity.

**Architecture:** A Manifest V3 service worker delegates to an independently testable controller. The controller uses `chrome.tabs` for stable tab identity, activity, active state, and pinned state; `chrome.storage.session` holds temporary grace timestamps; and `chrome.alarms` triggers one-minute cleanup passes.

**Tech Stack:** Chrome Manifest V3 extension APIs, JavaScript, Node.js built-in test runner, Ansible, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-03-chrome-tab-garbage-collection-design.md`

## Global Constraints

- Run only on the Ansible host `Brians-MacBook-Pro`.
- Close only unpinned, inactive Chrome tabs with at least 60 minutes of inactivity.
- Give tabs a fresh 60-minute grace period after browser startup, delayed alarm wake, activation, or unpinning.
- Re-read each candidate by stable tab ID before removal.
- Fail open on enumeration or state errors.
- Store no URLs or browser history.
- Do not publish the extension or add third-party dependencies.

---

### Task 1: Tested Chrome cleanup controller

**Files:**
- Create: `roles/macos/files/chrome-tab-gc-extension/tab_gc.js`
- Create: `tests/chrome-tab-gc.test.js`

**Interfaces:**
- Consumes: injected object `{chrome, now, idleMs, alarmPeriodMinutes}`.
- Produces: `ChromeTabGC.create(options)` returning `{start(), collect()}`.
- Production export: assign `ChromeTabGC` on `globalThis`; also export it with `module.exports` when Node provides `module`.
- Session storage schema: `{browserGraceAt: number, lastSweepAt: number, activityByTab: object, unpinnedAtByTab: object}`.

- [ ] **Step 1: Write failing safety and threshold tests**

Use `node:test` and `node:assert/strict`. Build a fake Chrome API that records alarm creation, listeners, tab queries, final `tabs.get` calls, and removals. Start with these tab fixtures:

```js
const hour = 60 * 60 * 1000;
const tabs = [
  {id: 1, active: false, pinned: false, lastAccessed: now - hour},
  {id: 2, active: true, pinned: false, lastAccessed: now - hour * 2},
  {id: 3, active: false, pinned: true, lastAccessed: now - hour * 2},
];
```

Assert that first startup closes nothing, a later pass closes tab 1 at the exact threshold, and tabs 2 and 3 remain. Also assert `tabs.get(1)` occurs before `tabs.remove(1)`.

- [ ] **Step 2: Run the focused test and verify failure**

Run: `node --test tests/chrome-tab-gc.test.js`

Expected: FAIL because `tab_gc.js` does not exist.

- [ ] **Step 3: Implement the minimum controller and storage boundary**

Implement constants and helpers with these signatures:

```js
const DEFAULT_IDLE_MS = 60 * 60 * 1000;
const DEFAULT_ALARM_PERIOD_MINUTES = 1;
const WAKE_GAP_MULTIPLIER = 2;

function create({
  chrome,
  now = Date.now,
  idleMs = DEFAULT_IDLE_MS,
  alarmPeriodMinutes = DEFAULT_ALARM_PERIOD_MINUTES,
}) { /* return {start, collect} */ }
```

`start()` must register alarm, activation, update, and alarm listeners, then initialize session state. `collect()` must read state, grant delayed-alarm grace when `now - lastSweepAt` exceeds two alarm periods, query all tabs, select candidates, call `tabs.get(id)`, re-check the current tab, and call `tabs.remove(id)` only when still eligible.

- [ ] **Step 4: Run the focused tests and verify pass**

Run: `node --test tests/chrome-tab-gc.test.js`

Expected: PASS for startup, threshold, active, pinned, and revalidation cases.

- [ ] **Step 5: Add failing event, restart, and error tests**

Add cases for:

```text
activation refreshes one tab
pinned-to-unpinned transition grants fresh grace
pinning does not make a tab eligible
reordered and moved tabs retain identity by ID
missing tabs are pruned after a complete enumeration
multiple active tabs in separate windows remain
late alarm grants global grace
clock rollback cannot close early
enumeration or storage failure closes nothing
candidate disappearance and removal failure do not affect other candidates
final revalidation sees active or pinned and skips removal
```

- [ ] **Step 6: Run the expanded test and verify failure**

Run: `node --test tests/chrome-tab-gc.test.js`

Expected: FAIL on the newly added event and error cases.

- [ ] **Step 7: Complete event and fail-open behavior**

Activation and unpin listeners must update session state by tab ID. State writes must merge with the current session object. A failed state read or complete enumeration must return before any removal. Candidate-level `tabs.get` and `tabs.remove` failures must be logged and must not abort safe handling of other candidates. Prune only after successful enumeration.

- [ ] **Step 8: Run the complete controller test**

Run: `node --test tests/chrome-tab-gc.test.js`

Expected: all cases PASS.

- [ ] **Step 9: Commit the controller**

Run the repository commit helper with message `Add safe Chrome tab cleanup policy` and explicit paths for the controller and test.

---

### Task 2: Extension runtime and laptop-only provisioning

**Files:**
- Create: `roles/macos/files/chrome-tab-gc-extension/manifest.json`
- Create: `roles/macos/files/chrome-tab-gc-extension/service_worker.js`
- Create: `roles/macos/files/chrome-tab-gc-extension/README.md`
- Modify: `roles/macos/tasks/install_omniwm.yml`
- Modify: `.github/workflows/integration-test.yml`

**Interfaces:**
- Consumes: `ChromeTabGC.create({chrome})` from Task 1.
- Produces: unpacked extension directory at `~/.local/share/chrome-tab-gc-extension` on `Brians-MacBook-Pro`.

- [ ] **Step 1: Write failing packaging assertions**

Extend `tests/chrome-tab-gc.test.js` to load `manifest.json` and assert:

```js
assert.equal(manifest.manifest_version, 3);
assert.equal(manifest.background.service_worker, "service_worker.js");
assert.deepEqual([...manifest.permissions].sort(), ["alarms", "storage", "tabs"]);
```

Assert `service_worker.js` imports `tab_gc.js` and calls `ChromeTabGC.create({chrome}).start()`.

- [ ] **Step 2: Run the test and verify failure**

Run: `node --test tests/chrome-tab-gc.test.js`

Expected: FAIL because the manifest and service worker do not exist.

- [ ] **Step 3: Add the manifest, service worker, and activation instructions**

Use this manifest shape:

```json
{
  "manifest_version": 3,
  "name": "ChatGPT Chrome Tab Cleanup",
  "version": "1.0.0",
  "description": "Closes unpinned Chrome tabs after 60 minutes without activity.",
  "permissions": ["alarms", "storage", "tabs"],
  "background": {"service_worker": "service_worker.js"}
}
```

The README must state the exact `chrome://extensions` Developer mode and **Load unpacked** steps and identify the deployed directory.

- [ ] **Step 4: Add laptop-only Ansible deployment**

In `roles/macos/tasks/install_omniwm.yml`, copy the extension directory recursively:

```yaml
- name: Install Chrome tab garbage collection extension
  copy:
    src: chrome-tab-gc-extension/
    dest: "{{ ansible_facts['user_dir'] }}/.local/share/chrome-tab-gc-extension/"
    mode: preserve
```

No additional hostname condition belongs in this task because `roles/macos/tasks/main.yml` already includes the complete `install_omniwm.yml` file only for `Brians-MacBook-Pro`.

- [ ] **Step 5: Add the test to CI**

Add an explicit workflow step after the Lua OmniWM tests:

```yaml
      - name: Verify Chrome tab garbage collection
        run: node --test tests/chrome-tab-gc.test.js
```

- [ ] **Step 6: Run focused verification**

Run:

```bash
node --test tests/chrome-tab-gc.test.js
python3 -m json.tool \
  roles/macos/files/chrome-tab-gc-extension/manifest.json >/dev/null
ansible-playbook playbook.yml --syntax-check
```

Expected: all commands exit 0.

- [ ] **Step 7: Commit packaging and provisioning**

Run the repository commit helper with message `Install Chrome tab cleanup on the laptop` and explicit paths for the manifest, service worker, README, Ansible task, workflow, and updated test.

---

### Task 3: Provision and end-to-end verification

**Files:**
- Modify only if defects are found in Task 1 or Task 2 files.

**Interfaces:**
- Consumes: the committed extension and Ansible deployment.
- Produces: verified managed files and a pull-request-ready branch.

- [ ] **Step 1: Run all relevant automated tests**

Run:

```bash
node --test tests/chrome-tab-gc.test.js
lua tests/omniwm-cheatsheet-panel.lua
lua tests/omniwm-downloads.lua
lua tests/omniwm-url-source.lua
ansible-playbook playbook.yml --syntax-check
```

Expected: all commands exit 0.

- [ ] **Step 2: Provision from the feature worktree**

Run: `bin/provision`

Expected: provisioning exits 0 and reports the Chrome extension copy task as changed or unchanged.

- [ ] **Step 3: Verify deployed source without activating destructive cleanup**

Compare checksums for `manifest.json`, `service_worker.js`, and `tab_gc.js` between the worktree and `~/.local/share/chrome-tab-gc-extension`. Validate the deployed manifest with `python3 -m json.tool`.

Expected: all checksums match and JSON validation exits 0.

- [ ] **Step 4: Review branch cleanliness and diff**

Run `git status --short`, `git diff origin/main...HEAD --check`, and inspect `git diff origin/main...HEAD`.

Expected: no uncommitted files, no whitespace errors, and only task-related changes.

- [ ] **Step 5: Create the pull request**

Use the `z-pull-request` skill. The PR body must include a `## Verification` section and note that Chrome's one-time unpacked-extension activation remains manual.
