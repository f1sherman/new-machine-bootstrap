# Pi Footer Goal Deduplication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hide redundant `goal:` footer text when `pi-session-manager` already displays the identical automatic session name.

**Architecture:** Make the existing goal renderer compare durable goal state with Pi's current session name, clearing only exact duplicates. Re-render after automatic naming and on `session_info_changed` so automatic and manual name transitions update immediately while all persistence and tmux identity behavior remains unchanged.

**Tech Stack:** TypeScript Pi extension, Node assertions embedded in Bash contract tests.

## Global Constraints

- Exact non-empty goal/session-name equality clears only the `session-goal` status.
- Missing or different session names retain `goal: <goal>`.
- Missing goals retain `goal: determining…`.
- Distinct manual names and goals remain simultaneously visible through their separate extensions.
- Do not modify `pi-session-manager`, goal generation, goal persistence, automatic naming policy, or tmux identity publication.

---

### Task 1: Synchronize Goal Status With Session Names

**Files:**
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts:703-707,792-804,912-916`
- Test: `tests/pi-managed-hooks.sh:330-430,1150-1220`

**Interfaces:**
- Consumes: `ctx.sessionManager.getSessionName() -> string | undefined`, existing `currentSessionGoal`, Pi `session_info_changed` events.
- Produces: unchanged `renderSessionGoal(ctx) -> void`; `session-goal` status is `undefined` only when current name exactly equals current goal.

- [ ] **Step 1: Add failing duplicate-suppression tests**

Add assertions to the restored-goal and name-change scenarios:

```js
statuses.length = 0;
currentSessionName = "persistent Pi session goals";
await handlers.get("session_start")({ reason: "matching managed goal resume" }, ctx);
assert.deepEqual(statuses.at(-1), {
  key: "session-goal",
  value: undefined,
}, "matching automatic session name suppresses duplicate goal status");
```

After the manual rename event, assert a distinct goal remains visible:

```js
assert.deepEqual(statuses.at(-1), {
  key: "session-goal",
  value: "goal: manual-safe durable goal",
}, "manual session rename keeps a distinct durable goal visible");
```

After the extension-managed goal name event, assert exact equality clears the status:

```js
assert.deepEqual(statuses.at(-1), {
  key: "session-goal",
  value: undefined,
}, "managed session name event suppresses duplicate durable goal status");
```

Update existing assertions that currently expect `goal: <goal>` after automatic naming to expect `undefined`, while retaining assertions for determining and distinct manual-name cases.

- [ ] **Step 2: Run the focused test to verify RED**

Run:

```bash
tests/pi-managed-hooks.sh
```

Expected: FAIL because matching goal/name pairs still render `goal: <goal>` and `session_info_changed` does not re-render goal status.

- [ ] **Step 3: Implement exact duplicate suppression**

Change the renderer to:

```ts
function renderSessionGoal(ctx) {
  const sessionName = ctx?.sessionManager?.getSessionName?.()?.trim() || "";
  const duplicate = Boolean(currentSessionGoal) && sessionName === currentSessionGoal;
  ctx?.ui?.setStatus?.(
    SESSION_GOAL_STATUS_KEY,
    duplicate ? undefined : `goal: ${currentSessionGoal || SESSION_GOAL_PLACEHOLDER}`,
  );
}
```

After `setManagedPiSessionName` returns in `applySessionGoal`, call `renderSessionGoal(ctx)` before identity publication so the status reflects the name that was just assigned.

At the start of `session_info_changed`, call `renderSessionGoal(ctx)` before the existing empty-name/ownership guard. Do not alter identity publication logic.

- [ ] **Step 4: Run focused and repository verification**

Run:

```bash
tests/pi-managed-hooks.sh
bash -n tests/pi-managed-hooks.sh
bin/test
ansible-playbook playbook.yml --syntax-check
git diff --check
```

Expected: all commands exit `0`; the managed-hooks contract confirms placeholder, duplicate, manual-name, persistence, race, and identity behavior.

- [ ] **Step 5: Commit implementation**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Suppress duplicate Pi goal footer text" \
  roles/common/files/pi/extensions/managed-hooks.ts \
  tests/pi-managed-hooks.sh
```

- [ ] **Step 6: Provision and verify live behavior**

Run Linux provisioning from this worktree with `bin/provision`. Verify the deployed managed-hooks checksum matches source, reload Pi, and confirm the footer shows only `📁 <name>` when name equals goal while retaining `goal: <goal>` for a distinct manual name.
