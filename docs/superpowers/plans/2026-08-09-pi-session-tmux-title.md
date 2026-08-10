# Pi Session tmux Title Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the built-in Pi session name the only session identity and always publish it as the tmux tab title.

**Architecture:** Simplify `managed-hooks.ts` so automatic goal generation and `set_session_name({ name })` write Pi's built-in session name. Publish that name through the existing `tmux-agent-state set-identity` pipeline on startup, resume, tree navigation, and name changes. Remove the separate custom goal entry, footer goal state, tmux managed-name marker, and precedence logic.

**Tech Stack:** TypeScript Pi extension, Node.js test harness, Bash, tmux helper scripts

## Global Constraints

- The term "goal" remains guidance for choosing a broad, stable session name; it is not separate stored state.
- The most recent call to automatic naming, `set_session_name`, or `/name` wins, except automatic naming only runs for an unnamed session.
- Register only `set_session_name({ name })`; do not keep a `set_session_goal` compatibility alias.
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
- Produces: `set_session_name({ name })`, which validates the phrase, sets the Pi session name, and publishes the live name to the owning tmux pane.

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

await withStdoutTTY(() => sessionNameTool.execute(
  "rename-session",
  { name: "new broad name" },
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

Expected: FAIL because resume publication still depends on old goal and marker ownership, and the old goal tool still appends a custom goal entry.

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

Make `set_session_name({ name })` call `applySessionName()` without custom entry persistence.

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

### Task 3: Rename the public session tool

**Files:**
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts`
- Modify: `roles/common/files/config/skills/pi/z-update-session-goal/SKILL.md`
- Test: `tests/pi-managed-hooks.sh`

**Interfaces:**
- Consumes: Pi `registerTool()`, the existing `applySessionName(pi, ctx, subject)` helper, and the managed `z-update-session-goal` skill.
- Produces: `set_session_name({ name: string })`, which returns `details: { name }` and publishes the validated live session name. The managed skill calls this interface exactly once.

- [ ] **Step 1: Write a failing public-interface test**

Change the test harness to record registered tool names and capture only the new tool:

```javascript
const registeredToolNames = [];
let sessionNameTool;

registerTool(definition) {
  registeredToolNames.push(definition.name);
  if (definition.name === "set_session_name") sessionNameTool = definition;
},
```

Replace the tool invocation with the new parameter and assert that no compatibility alias exists:

```javascript
const renameResult = await withStdoutTTY(() => sessionNameTool.execute(
  "rename-session",
  { name: "new broad name" },
  ctx.signal,
  undefined,
  ctx,
));
assert.equal(currentSessionName, "new broad name");
assert.deepEqual(renameResult.details, { name: "new broad name" });
assert.equal(registeredToolNames.includes("set_session_goal"), false,
  "the extension does not register the old goal tool alias");
```

- [ ] **Step 2: Run the focused test and confirm it fails**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: FAIL because `sessionNameTool` is undefined while the extension still registers `set_session_goal`.

- [ ] **Step 3: Rename the registered tool and its public data**

Replace the public registration in `managed-hooks.ts` with:

```javascript
pi.registerTool({
  name: "set_session_name",
  label: "Set Session Name",
  description: "Set the durable broad name and automatic identity for the current Pi session. Call only when the user's overall objective materially changes. Keep the existing name during implementation phases, debugging steps, testing, deployment, PR work, and other subtasks. Prefer at most 40 characters.",
  parameters: {
    type: "object",
    properties: {
      name: { type: "string", description: "Concise broad session name that describes the overall objective, not the current step; prefer at most 40 characters (maximum 80)" },
    },
    required: ["name"],
    additionalProperties: false,
  },
  async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
    const name = await applySessionName(pi, ctx, params.name);
    return {
      content: [{ type: "text", text: `Session name set to: ${name}` }],
      details: { name },
    };
  },
});
```

Change the validation error in `applySessionName()` from `Session goal must` to `Session name must`. Keep internal automatic-generation helpers unchanged because they still generate a broad goal phrase for an unnamed session.

Update `z-update-session-goal/SKILL.md` to call the new public interface:

```markdown
- Call `set_session_name({ name })` exactly once. Pass the phrase as `name`.
```

Change its final mutation-interface sentence to name `set_session_name`. Keep the skill name because "goal" describes its user-facing purpose, not separate storage.

- [ ] **Step 4: Run focused verification**

Run:

```bash
bash tests/pi-managed-hooks.sh
bash tests/tmux-agent-state.sh
git diff --check
```

Expected: both test scripts exit 0, and the diff check prints no errors.

- [ ] **Step 5: Confirm the old public name is absent**

Run:

```bash
if rg -n 'set_session_goal|Set Session Goal' \
  roles/common/files/pi/extensions/managed-hooks.ts \
  roles/common/files/config/skills/pi/z-update-session-goal/SKILL.md; then
  exit 1
fi
rg -F 'set_session_name({ name })' \
  roles/common/files/config/skills/pi/z-update-session-goal/SKILL.md
```

Expected: the first search has no matches. The second search prints the skill instruction.

- [ ] **Step 6: Commit the rename**

Commit these files with the repository commit workflow:

```text
roles/common/files/pi/extensions/managed-hooks.ts
roles/common/files/config/skills/pi/z-update-session-goal/SKILL.md
tests/pi-managed-hooks.sh
```

Use commit message: `Rename Pi session naming tool`.

- [ ] **Step 7: Provision and verify the managed extension**

Run:

```bash
bin/provision
cmp \
  roles/common/files/pi/extensions/managed-hooks.ts \
  "$HOME/.pi/agent/extensions/managed-hooks.ts"
cmp \
  roles/common/files/config/skills/pi/z-update-session-goal/SKILL.md \
  "$HOME/.pi/agent/skills/z-update-session-goal/SKILL.md"
```

Expected: provisioning succeeds and both `cmp` commands exit 0.
