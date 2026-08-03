# Explicit Session Goal Identity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make an explicit `set_session_goal` call replace an inherited or manual-looking Pi/tmux identity and repair stale identity when the durable goal is unchanged.

**Architecture:** Add an explicit replacement flag to the existing managed-name operation. The tool path enables it, while automatic generation and restoration retain their current manual-name guard. Change goal persistence so same-value calls reconcile identity without appending duplicate history.

**Tech Stack:** TypeScript Pi extension, Node.js assertion harness in `tests/pi-managed-hooks.sh`, Ansible provisioning.

## Global Constraints

- An explicit `set_session_goal` call is authoritative for the durable goal, Pi session name, and tmux identity.
- Automatic goal generation and restoration must preserve a genuine manual session name.
- Same-value explicit calls must reconcile stale identity without appending another `session-goal` entry.
- Keep existing serialization, marker-write failure handling, and live-name race checks.
- Do not change activity detection, tmux label truncation, session forking, or general manual-name behavior outside the explicit tool path.

---

### Task 1: Authoritative explicit identity reconciliation

**Files:**
- Modify: `tests/pi-managed-hooks.sh:1170-1210`
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts:149-178,797-820,884-900`

**Interfaces:**
- Consumes: `setManagedPiSessionName(pi, ctx, sessionName, maySet)` and `applySessionGoal(pi, ctx, subject, options)`.
- Produces: `setManagedPiSessionName(pi, ctx, sessionName, maySet, replaceExistingName)` where `replaceExistingName` defaults to `false`; `applySessionGoal` accepts `options.replaceExistingName`; the `set_session_goal` tool passes `{ replaceExistingName: true }`.

- [ ] **Step 1: Change the explicit-tool regression test to require replacement**

Replace the current assertions that preserve `renamed manual investigation` with assertions that the tool sets `updated durable theme`, writes the managed marker, and publishes a goal identity:

```js
assert.equal(customEntries.length, manualToolEntries + 1, "goal tool persists a changed explicit goal");
assert.equal(currentSessionName, "updated durable theme", "goal tool replaces an inherited or manual-looking Pi name");
assert.equal(managedPiSessionName, "updated durable theme", "goal tool claims managed ownership for the explicit identity");
assert.ok(calls.some((call) => call.command === "tmux-agent-state" && call.args.join(" ") === "set-identity goal updated durable theme"), "goal tool publishes the explicit tmux goal identity");
```

Then call the tool again with the same goal. Assert that `customEntries.length` does not increase and that marker/name/identity reconciliation still occurs after resetting the visible name and marker to stale inherited values.

```js
const sameGoalEntryCount = customEntries.length;
currentSessionName = "Implement cmdrunner→command-proxy migration";
managedPiSessionName = "Implement cmdrunner→command-proxy migra…";
calls.length = 0;
await withStdoutTTY(true, () => sessionGoalTool.execute(
  "same-explicit-goal",
  { goal: "updated durable theme" },
  subjectSignal,
  undefined,
  ctx,
));
assert.equal(customEntries.length, sameGoalEntryCount, "same explicit goal does not append duplicate durable history");
assert.equal(currentSessionName, "updated durable theme", "same explicit goal repairs an inherited Pi name");
assert.equal(managedPiSessionName, "updated durable theme", "same explicit goal repairs a truncated managed marker");
assert.ok(calls.some((call) => call.command === "tmux-agent-state" && call.args.join(" ") === "set-identity goal updated durable theme"), "same explicit goal republishes the repaired tmux identity");
```

- [ ] **Step 2: Run the focused harness and confirm the new expectations fail**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: FAIL because the current explicit tool preserves the old visible name or skips same-value reconciliation.

- [ ] **Step 3: Add explicit replacement to managed naming**

Change the managed-name signature and guards:

```ts
async function setManagedPiSessionName(
  pi,
  ctx,
  sessionName,
  maySet = () => true,
  replaceExistingName = false,
) {
```

Treat an already matching name as complete only when it is unambiguously managed. Bypass only the manual-name rejection when `replaceExistingName` is true:

```ts
if (currentName === sessionName && (!inTmux() || currentName === lastManagedSessionName)) return true;
if (!replaceExistingName && currentName && currentName !== lastManagedSessionName) return false;
```

Keep marker writes before `pi.setSessionName`, and retain the current post-write live-name race check.

- [ ] **Step 4: Reconcile unchanged explicit goals without duplicate history**

In `applySessionGoal`, persist only changed values, but always run naming and publication:

```ts
const goalChanged = normalized !== currentSessionGoal;
if (goalChanged) {
  pi.appendEntry(SESSION_GOAL_ENTRY_TYPE, { subject: normalized });
  currentSessionGoal = normalized;
}
renderSessionFooter(ctx);
```

Pass the replacement option into managed naming:

```ts
const named = await setManagedPiSessionName(
  pi,
  ctx,
  normalized,
  maySet,
  options.replaceExistingName === true,
);
```

Make the registered tool authoritative:

```ts
const goal = await applySessionGoal(pi, ctx, params.goal, { replaceExistingName: true });
```

- [ ] **Step 5: Run the managed-hooks harness**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: `pi-managed-hooks checks complete` with exit status 0. Existing automatic-restoration tests must still show that manual names are preserved.

- [ ] **Step 6: Run repository checks for the changed files**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; only the plan, extension, and managed-hooks test are changed beyond the committed design.

- [ ] **Step 7: Commit the implementation**

Use the `z-commit` skill to commit:

- `roles/common/files/pi/extensions/managed-hooks.ts`
- `tests/pi-managed-hooks.sh`

Commit message: `Make explicit session goals authoritative`

---

### Task 2: Deploy and verify the repaired identity path

**Files:**
- No source files added.
- Verify deployed file: `~/.pi/agent/extensions/managed-hooks.ts` after provisioning.

**Interfaces:**
- Consumes: the authoritative `set_session_goal` behavior from Task 1.
- Produces: deployed extension behavior and empirical proof that the affected pane uses `Fix PR conflict and footer signals`.

- [ ] **Step 1: Provision the NMB worktree**

Run from the worktree:

```bash
bin/provision
```

Expected: successful Ansible recap with `failed=0`.

- [ ] **Step 2: Verify the deployed extension matches the worktree**

Run:

```bash
cmp roles/common/files/pi/extensions/managed-hooks.ts ~/.pi/agent/extensions/managed-hooks.ts
```

Expected: exit status 0.

- [ ] **Step 3: Reapply the affected session goal**

Deliver a message to the active session for `019fc3a7-d42c-7b2c-9ade-35b19e457f8c` that instructs it to invoke:

```text
set_session_goal({ goal: "Fix PR conflict and footer signals" })
```

If the session cannot process the message without restart, restart or reload that Pi session after provisioning and then invoke the same tool call.

- [ ] **Step 4: Verify the pane identity**

Run against the pane bound to the affected session file:

```bash
TMUX_PANE=<affected-pane> tmux-agent-state status
tmux show-options -qv -p -t <affected-pane> @pi_managed_session_name
tmux show-options -qv -p -t <affected-pane> @window-label
```

Expected values:

```text
active	goal	Fix PR conflict and footer signals
Fix PR conflict and footer signals
Fix PR conflict and footer signals
```

- [ ] **Step 5: Run final verification**

Run:

```bash
bash tests/pi-managed-hooks.sh
git diff --check
git status --short --branch
```

Expected: managed-hooks checks complete, no whitespace errors, and a clean worktree after commits.

- [ ] **Step 6: Open the pull request**

Use the `pull-request` skill. Include the failing behavior, focused test command, provisioning result, and empirical pane identity proof in the PR description. Do not merge the PR.
