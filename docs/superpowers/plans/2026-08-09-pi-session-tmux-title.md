# Pi Session tmux Title Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the built-in Pi session name the only session identity and always publish it as the tmux tab title.

**Architecture:** Simplify `managed-hooks.ts` so automatic goal generation and `set_session_goal` write Pi's built-in session name. Publish that name through the existing `tmux-agent-state set-identity` pipeline on startup, resume, tree navigation, and name changes. Remove the separate custom goal entry, footer goal state, tmux managed-name marker, and precedence logic.

**Tech Stack:** TypeScript Pi extension, Node.js test harness, Bash, tmux helper scripts

## Global Constraints

- The term "goal" remains guidance for choosing a broad, stable session name; it is not separate stored state.
- The most recent call to automatic naming, `set_session_goal`, or `/name` wins, except automatic naming only runs for an unnamed session.
- Nested, print-mode, and subagent Pi processes must not change tmux state.
- Existing tmux formatting, truncation, indicators, remote titles, branch labels, and directory fallbacks remain unchanged.
- Title update failures must not interrupt Pi.

---

### Task 1: Replace separate goal state with the Pi session name

**Files:**
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts`
- Test: `tests/pi-managed-hooks.sh`

**Interfaces:**
- Consumes: Pi `session_start`, `session_info_changed`, `session_tree`, and `before_agent_start` events; `pi.setSessionName(name)`; `ctx.sessionManager.getSessionName()`; `tmux-agent-state set-identity manual <name>`.
- Produces: `set_session_goal({ goal })`, which validates the phrase, sets the Pi session name, and publishes the live name to the owning tmux pane.

- [ ] **Step 1: Replace goal-storage test fixtures with single-name assertions**

Remove `entries`, `branchEntries`, `managedSessionName`, marker read/write deferrals, and custom `appendEntry` assertions from `tests/pi-managed-hooks.sh`. Keep the asynchronous generated-name deferral so the test still exercises stale automatic work.

Add assertions with this behavior:

```javascript
currentSessionName = "";
publishedIdentity = { source: "", subject: "" };
await handlers.get("session_start")({ reason: "resume" }, ctx);
assert.deepEqual(publishedIdentity, { source: "", subject: "" },
  "an unnamed resumed session does not replace the tmux fallback");

currentSessionName = "restored session name";
await withStdoutTTY(() => handlers.get("session_start")({ reason: "resume" }, ctx));
assert.deepEqual(publishedIdentity, {
  source: "manual",
  subject: "restored session name",
}, "same-pane resume publishes the restored Pi session name");

await withStdoutTTY(() => goalTool.execute(
  "rename-session",
  { goal: "new broad name" },
  ctx.signal,
  undefined,
  ctx,
));
assert.equal(currentSessionName, "new broad name");
assert.deepEqual(publishedIdentity, {
  source: "manual",
  subject: "new broad name",
});
assert.equal(calls.some((call) => call.command === "tmux"
  && call.args.includes("@pi_managed_session_name")), false,
  "single-name flow does not use the old tmux ownership marker");
```

Retain a race test where automatic generation starts while unnamed, `/name` changes the live name before the child completes, and the generated result does not replace or publish over the manual name.

- [ ] **Step 2: Run the focused test and confirm the old implementation fails**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: FAIL because resume publication still depends on old goal and marker ownership, and `set_session_goal` still appends a custom goal entry.

- [ ] **Step 3: Remove separate goal and marker state**

In `managed-hooks.ts`, remove these concepts and their helper paths:

```javascript
SESSION_GOAL_ENTRY_TYPE
SESSION_GOAL_STATUS_KEY
SESSION_GOAL_PLACEHOLDER
MANAGED_PI_SESSION_NAME_OPTION
currentSessionGoal
lastManagedSessionName
storedSessionGoal()
restoreSessionGoal()
setManagedPiSessionName()
syncSessionNameFromTmux()
piSessionNameFromTmuxLabel()
```

Change footer rendering to show only the live Pi session name:

```javascript
function renderSessionFooter(ctx, sessionName = ctx?.sessionManager?.getSessionName?.()) {
  const normalizedName = sessionName?.trim() || "";
  ctx?.ui?.setStatus?.(
    SESSION_NAME_STATUS_KEY,
    normalizedName ? ctx.ui.theme.fg("accent", `📁 ${normalizedName}`) : undefined,
  );
}
```

- [ ] **Step 4: Implement serialized session-name setting and tmux publication**

Keep generation invalidation and serialization, but serialize name operations instead of custom goal persistence. Use these boundaries:

```javascript
async function publishCurrentSessionName(pi, ctx, expectedName) {
  const normalizedExpectedName = expectedName?.trim() || "";
  if (!normalizedExpectedName || !ownsTmuxPane()) return false;
  const liveName = ctx?.sessionManager?.getSessionName?.()?.trim() || "";
  if (liveName !== normalizedExpectedName) return false;
  return writeTmuxIdentity(pi, "manual", normalizedExpectedName);
}

function applySessionName(pi, ctx, subject, options = {}) {
  return serializeNameOperation(async () => {
    const normalized = normalizeSessionGoalSubject(subject);
    if (!normalized) {
      throw new Error(
        "Session goal must be one line, unquoted, and at most 80 characters.",
      );
    }
    if (options.onlyIfUnnamed
      && (!requestIsCurrent(options.request, ctx)
        || ctx?.sessionManager?.getSessionName?.())) {
      return ctx?.sessionManager?.getSessionName?.() || "";
    }
    pi.setSessionName(normalized);
    renderSessionFooter(ctx, normalized);
    await publishCurrentSessionName(pi, ctx, normalized);
    return normalized;
  });
}
```

Before publishing, always re-read the live session name. This prevents a stale automatic generation or event handler from overwriting a newer `/name` value.

Add a clearing path for `/name` with an empty value. Read `tmux-agent-state status`; only clear state with source `goal` or `manual`. Then run `tmux-agent-state clear-task` and `tmux-agent-worktree sync-current` from the bound worktree path so branch or directory fallback state is restored. Do not clear a current `branch` or `agent` task.

```javascript
async function clearPublishedSessionName(pi, ctx) {
  if (!ownsTmuxPane()) return false;
  const status = await canonicalSessionNameStatus(pi);
  if (status.kind !== "non-branch"
    || !["goal", "manual"].includes(status.source)) return false;
  await exec(pi, "tmux-agent-state", ["clear-task"]);
  const cwd = await boundWorktreePath(pi, ctx?.cwd || "");
  await exec(pi, "tmux-agent-worktree", ["sync-current"], { cwd });
  return true;
}
```

- [ ] **Step 5: Wire lifecycle events to the single-name path**

Make `set_session_goal` call `applySessionName()` without custom entry persistence.

On `session_start`, cancel stale generation, render the current name, set tmux agent kind, bind the pane session file, and publish the current name. Do not condition publication on the previous `@persist_pi_session_file` value.

On `session_info_changed`, render and publish `event.name` after checking it still equals the live session name. If the live name is empty, call `clearPublishedSessionName()` so stale manual or legacy goal identity does not remain in the tab.

On `session_tree`, cancel stale generation, render the branch's current Pi session name, and publish it.

In `before_agent_start`, start automatic name generation only when `ctx.sessionManager.getSessionName()` is empty. Apply its result with `onlyIfUnnamed: true`.

- [ ] **Step 6: Run focused tests**

Run:

```bash
bash tests/pi-managed-hooks.sh
bash tests/tmux-agent-state.sh
```

Expected: both commands exit 0 and print their completion messages.

- [ ] **Step 7: Commit the implementation**

Commit only these files with the repository commit workflow:

```text
roles/common/files/pi/extensions/managed-hooks.ts
tests/pi-managed-hooks.sh
```

Use commit message: `Simplify Pi tmux session identity`.

### Task 2: Verify provisioning and live resume behavior

**Files:**
- No source changes expected.

**Interfaces:**
- Consumes: the committed extension and existing Ansible provisioning path.
- Produces: deployed Pi extension and empirical proof that resume restores the tmux tab from the Pi session name.

- [ ] **Step 1: Run repository verification**

Run:

```bash
bin/provision
bin/provision --check
```

Expected: provisioning succeeds. Check mode exits 0 without unexpected managed-file changes.

- [ ] **Step 2: Verify the deployed extension**

In an owning tmux pane, start or resume a named Pi session. Record the pane, current session file, Pi name, and tmux window name. Resume the same session in that pane and confirm the final window name contains the sanitized and truncated Pi session name produced by `tmux-window-label`.

Use read-only inspection commands:

```bash
printf 'pane=%s session=%s\n' "$TMUX_PANE" "$PI_SESSION_FILE"
tmux display-message -p -t "$TMUX_PANE" \
  'window=#{window_name} task=#{@task_label} source=#{@task_source}'
```

Expected: `source=manual`, `task` equals the Pi session name before tmux sanitization, and `window` is its normal sanitized/truncated form.

- [ ] **Step 3: Run final diff checks**

Run:

```bash
git diff --check
git status --short
git log -3 --oneline
```

Expected: no whitespace errors, no uncommitted implementation files, and separate design, plan, and implementation commits.
