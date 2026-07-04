# Pi Session Name Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Set managed Pi session names to the meaningful work label by removing redundant `pi` and current-directory prefixes.

**Architecture:** Keep tmux label generation unchanged. Add a small normalizer in `managed-hooks.ts` and use it only before `pi.setSessionName`, so tmux panes retain their existing labels.

**Tech Stack:** TypeScript Pi extension, Node-based shell contract test.

## Global Constraints

- Modify only files in this repository worktree.
- Preserve manual Pi session name protection.
- Preserve tmux `@window-label` behavior for panes/status.
- Do not set empty Pi session names.

---

### Task 1: Add Pi Session Name Normalization

**Files:**
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts`
- Test: `tests/pi-managed-hooks.sh`

**Interfaces:**
- Consumes: `tmuxOption(pi, "@window-label")`, `ctx.cwd`, and `ctx.sessionManager.getSessionName()`.
- Produces: normalized names passed to `pi.setSessionName(name)` and recorded in `lastManagedSessionName`.

- [ ] **Step 1: Update the test expectations**

In `tests/pi-managed-hooks.sh`, adjust the managed session-name section so:

```js
let windowLabel = "pi main-repo";
const ctx = { cwd: "/repo/main-repo", sessionManager: { getSessionName() { return currentSessionName; } } };
assert.deepEqual(sessionNames, [], "directory-only pi labels do not set redundant Pi session names");
windowLabel = "pi main-repo feature-work";
assert.deepEqual(sessionNames, ["feature-work"], "successful bash results set only the meaningful Pi session name");
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `bash tests/pi-managed-hooks.sh`

Expected: FAIL because the hook still sets names from raw tmux labels.

- [ ] **Step 3: Add the normalizer and use it**

In `roles/common/files/pi/extensions/managed-hooks.ts`, add a function that strips `pi`, strips `path.basename(ctx.cwd)` from the start of the remaining label, and returns an empty string if nothing meaningful remains. In `syncSessionNameFromTmux`, compare and set the normalized name instead of the raw label.

- [ ] **Step 4: Run the focused test and verify it passes**

Run: `bash tests/pi-managed-hooks.sh`

Expected: `pi-managed-hooks checks complete`.

- [ ] **Step 5: Commit implementation**

Run:

```bash
git add roles/common/files/pi/extensions/managed-hooks.ts tests/pi-managed-hooks.sh
git commit -m "Clean up managed Pi session names"
```
