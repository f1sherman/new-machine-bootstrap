# Herdr Single-Tab Workspace Name Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use engineering:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Synchronize a Herdr workspace with its Pi session name only when the workspace contains one tab.

**Architecture:** Extend the existing Herdr publication path in `managed-hooks.ts`. Query the containing workspace through Herdr's direct CLI API, parse its tab count, and conditionally rename it after the existing tab rename. Keep failures non-blocking through the existing command wrapper.

**Tech Stack:** TypeScript Pi extension, Node.js test harness embedded in Bash, Herdr CLI JSON API.

## Global Constraints

- Continue renaming the containing Herdr tab for all tab counts.
- Rename or clear the containing workspace only when `tab_count` is exactly `1`.
- Skip workspace publication when context, lookup output, or command execution is unavailable or invalid.
- Do not add persistent state or compatibility inference.
- Keep Herdr failures non-blocking for Pi and tmux lifecycle behavior.

---

### Task 1: Conditional Herdr workspace synchronization

**Files:**
- Modify: `tests/pi-managed-hooks.sh:25-275`
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts:84-100`

**Interfaces:**
- Consumes: `HERDR_ENV`, `HERDR_TAB_ID`, `HERDR_WORKSPACE_ID`, and `pi.exec(command, args)`.
- Produces: `renameCurrentHerdrWorkspaceIfSingleTab(pi, name): Promise<boolean>` and an updated `renameCurrentHerdrTab(pi, name)` publication flow.

**Reviewer Verification:**
- Run `bash tests/pi-managed-hooks.sh`. Expected output ends with `pi managed hooks checks passed` and covers one-tab rename and clear, multi-tab preservation, and invalid lookup behavior.
- After provisioning, use `herdr workspace get "$HERDR_WORKSPACE_ID"` after a Pi name change. Expected: the workspace and tab labels match in a one-tab workspace; after adding a second tab, only the Pi tab label changes.

- [ ] **Step 1: Add failing behavioral coverage**

Add a `herdrWorkspaceResultQueue` to the production-extension test harness. Make the mocked `pi.exec` return queued results for `herdr workspace get`. Extend the existing Herdr assertions with exact command checks for:

```js
process.env.HERDR_WORKSPACE_ID = "w1";
herdrWorkspaceResultQueue.push(ok(JSON.stringify({
  id: "cli:workspace:get",
  result: { workspace: { workspace_id: "w1", tab_count: 1 } },
})));
```

Assert the command sequence includes:

```js
{ command: "herdr", args: ["tab", "rename", "w1:t2", sessionName] }
{ command: "herdr", args: ["workspace", "get", "w1"] }
{ command: "herdr", args: ["workspace", "rename", "w1", sessionName] }
```

Repeat for an empty session name. Add a `tab_count: 2` case that asserts no `workspace rename` call. Add failed and invalid-JSON lookup cases that also assert no workspace rename call. Delete both Herdr ID environment variables after the cases.

- [ ] **Step 2: Run the focused test and confirm failure**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: FAIL because no `herdr workspace get` or `herdr workspace rename` call exists.

- [ ] **Step 3: Implement the minimal workspace helper**

Add a workspace-ID guard parallel to `currentHerdrTabId`. Add a helper that:

```ts
const result = await exec(pi, "herdr", ["workspace", "get", workspaceId]);
if (result.code !== 0 || result.killed) return false;
let response;
try {
  response = JSON.parse(result.stdout);
} catch {
  return false;
}
if (response?.result?.workspace?.tab_count !== 1) return false;
const rename = await exec(pi, "herdr", ["workspace", "rename", workspaceId, name]);
return rename.code === 0 && !rename.killed;
```

Invoke it after the existing tab rename. Return true when either applicable Herdr rename succeeds so existing tmux-independent publication semantics remain intact.

- [ ] **Step 4: Run the focused test and confirm success**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: PASS with `pi managed hooks checks passed`.

- [ ] **Step 5: Run syntax and diff checks**

Run:

```bash
node --check roles/common/files/pi/extensions/managed-hooks.ts
git diff --check
git status --short
```

Expected: syntax check and diff check exit `0`; status lists only the intended implementation, test, and plan changes.

- [ ] **Step 6: Commit the implementation and plan**

Stage only:

```text
roles/common/files/pi/extensions/managed-hooks.ts
tests/pi-managed-hooks.sh
docs/superpowers/plans/2026-08-14-herdr-single-tab-workspace-name.md
```

Commit with `fix(pi): sync single-tab Herdr workspace name`.

### Task 2: Provision and end-to-end verification

**Files:**
- No source changes expected.

**Interfaces:**
- Consumes: committed common-role extension and `bin/provision`.
- Produces: deployed Pi extension behavior and reviewer-facing command evidence.

**Reviewer Verification:**
- Preserve the successful `bin/provision` result and Herdr CLI label observations in the pull request test plan.

- [ ] **Step 1: Apply the managed extension**

Run from the implementation worktree:

```bash
bin/provision
```

Expected: exit `0` with the Pi extension installed from this worktree.

- [ ] **Step 2: Verify a one-tab workspace**

In a disposable one-tab Herdr workspace, rename the Pi session. Run:

```bash
herdr tab get "$HERDR_TAB_ID"
herdr workspace get "$HERDR_WORKSPACE_ID"
```

Expected: both JSON records show the new Pi session name as their label.

- [ ] **Step 3: Verify a multi-tab workspace**

Add a second tab, record the current workspace label, and rename the Pi session again. Run the same two `get` commands.

Expected: the current Pi tab has the new session label and the workspace keeps its prior label.

- [ ] **Step 4: Run final verification**

Run:

```bash
bash tests/pi-managed-hooks.sh
git diff --check
git status --short --branch
```

Expected: all checks pass and the committed branch has no tracked or untracked changes.
