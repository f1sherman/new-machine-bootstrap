# Tmux Subject Feedback Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent Pi’s decorated provisional tmux label from feeding back into the raw task subject and accumulating `~` markers.

**Architecture:** Preserve the existing canonical task-status interface while adding canonical `state` and `source` metadata to valid non-branch results. Before the fallback tmux-window-label-to-Pi-session-name sync, return early for provisional agent tasks; session-goal and branch naming paths remain unchanged.

**Tech Stack:** TypeScript Pi extension, Node.js assertion harness, Bash test runner

## Global Constraints

- Change only the Pi managed-hook feedback boundary.
- Do not strip or reject literal `~` or `✓` characters in shell subject helpers.
- Preserve session-goal, branch, fallback window-label, and manual session-name behavior.
- Follow test-driven development: observe the regression test fail before changing production code.

---

### Task 1: Block provisional display-label feedback

**Files:**
- Modify: `tests/pi-managed-hooks.sh:377-399`
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts:111-124,462-477`

**Interfaces:**
- Consumes: `tmux-agent-state status` output formatted as `<state>\t<source>\t<subject>`.
- Produces: `canonicalSessionNameStatus(pi)` results with existing `kind` semantics plus `state` and `source` on valid canonical non-branch tasks; `syncSessionNameFromTmux(pi, ctx)` skips rendered-label fallback for `{ kind: "non-branch", state: "provisional", source: "agent" }`.

- [ ] **Step 1: Write the failing regression test**

Insert before the existing `windowLabel = "pi main-repo feature-work"` successful-bash assertion in `tests/pi-managed-hooks.sh`:

```js
taskStatus = "provisional\tagent\tInvestigate reviewer failures\n";
currentSessionName = "";
managedPiSessionName = "";
windowLabel = "~ Investigate reviewer failures";
sessionNames.length = 0;
calls.length = 0;
await handlers.get("tool_result")({ toolName: "bash", isError: false }, ctx);
await handlers.get("tool_result")({ toolName: "bash", isError: false }, ctx);
assert.deepEqual(sessionNames, [], "provisional rendered labels never become Pi session names");
assert.equal(calls.filter((call) => (
  call.command === "tmux" && call.args.at(-1) === "@window-label"
)).length, 0, "provisional task sync never reads the decorated window label");

taskStatus = "";
```

Keep the existing fallback-name assertions after this block. Resetting `taskStatus` proves panes without canonical task state continue to use `@window-label`.

- [ ] **Step 2: Run the test and verify the expected failure**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: FAIL at `provisional rendered labels never become Pi session names`, with actual session names containing `~ Investigate reviewer failures`.

- [ ] **Step 3: Return canonical non-branch metadata**

In `canonicalSessionNameStatus`, retain existing validation and branch handling, then replace the final return with:

```ts
  if (state === "active" && source === "branch") return { kind: "branch", subject };
  return { kind: "non-branch", state, source };
```

Blank status must continue returning `{ kind: "non-branch" }`, and malformed or failed status must continue returning `{ kind: "unavailable" }`.

- [ ] **Step 4: Guard fallback session-name synchronization**

At the beginning of `syncSessionNameFromTmux`, after the tmux check and before reading `@window-label`, add:

```ts
  const namingStatus = await canonicalSessionNameStatus(pi);
  if (namingStatus.kind === "unavailable") return;
  if (namingStatus.state === "provisional" && namingStatus.source === "agent") return;
```

This prevents display decoration from entering identity while preserving fallback sync for blank canonical state and existing behavior for other valid task states.

- [ ] **Step 5: Run focused tests and verify green**

Run:

```bash
bash tests/pi-managed-hooks.sh
bash tests/tmux-agent-state.sh
```

Expected: both scripts end with their `checks complete` messages and exit 0.

- [ ] **Step 6: Run repository checks**

Run:

```bash
git diff --check
bash tests/pi-managed-hooks.sh
bash tests/tmux-agent-state.sh
bash tests/tmux-label-contract.sh
```

Expected: `git diff --check` emits nothing; all three test scripts exit 0 and print their completion messages.

- [ ] **Step 7: Commit the implementation**

Commit only the implementation and regression test:

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Stop provisional tmux labels feeding back into subjects" \
  tests/pi-managed-hooks.sh \
  roles/common/files/pi/extensions/managed-hooks.ts
```

- [ ] **Step 8: Provision and perform live verification**

Run:

```bash
bin/provision
```

Then start or use a Pi pane on the default branch, set a provisional subject once, run multiple harmless bash tools, and inspect:

```bash
tmux-agent-state status
tmux show-options -qv -p -t "$TMUX_PANE" @task_label
```

Expected: status remains `provisional\tagent\t<raw subject>` and `@task_label` never gains a leading display `~` after repeated bash results.
