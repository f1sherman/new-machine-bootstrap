# Persistent Pi Session Goal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep a durable, asynchronously updated session goal in Pi's status bar while managed Pi session names continue switching from the pre-branch subject to the feature branch.

**Architecture:** Extend the existing managed Pi extension with independent goal restoration, rendering, and evaluation state. Persist changed goals as custom Pi session entries, evaluate every expanded prompt in a coalesced background GPT-5.4 mini child, and consult canonical tmux task state only when deciding whether an automatic session rename is allowed.

**Tech Stack:** TypeScript Pi extension APIs, Node.js child execution through `pi.exec`, Bash test harness with Node.js assertions, tmux helper commands.

## Global Constraints

- Status text is exactly `goal: <subject>`; a session without a valid subject shows `goal: determining…`.
- Goal evaluation uses `openai-codex/gpt-5.4-mini`, thinking off, no tools, extensions, skills, templates, themes, context files, session, or approval.
- Evaluation runs after every expanded user prompt and must not delay the main agent.
- Only one goal child may run at once; rapid prompts retain only the newest pending request and stale results never apply.
- Subjects are one-line noun phrases, at most 80 characters, with no controls, quotes, `goal:` prefix, or explanation.
- Persist goal changes as custom Pi entries excluded from model context.
- Preserve existing tmux pane/window/branch/worktree/remote-title behavior.
- Preserve manual `/name` values.
- Notify on consecutive evaluator failures 3, 13, 23, and every 10 thereafter; any valid `KEEP` or subject resets the counter.
- Do not expose user prompts or raw child output in diagnostics.

---

## File Structure

- `roles/common/files/pi/extensions/managed-hooks.ts` — retain existing managed-hook responsibilities and add the session-goal state machine, evaluator, persistence, status rendering, naming gate, and lifecycle cancellation.
- `tests/pi-managed-hooks.sh` — extend the existing Node-based extension harness with deterministic UI, custom-entry, deferred-child, lifecycle, coalescing, naming, and failure-notification coverage.

No new runtime file or dependency is needed. The goal state machine belongs beside the existing subject child and managed session-name logic because it reuses the same Pi lifecycle, model invocation policy, and manual-name boundary.

---

### Task 1: Restore and render durable session goals

**Files:**
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts:1-120,527-538`
- Test: `tests/pi-managed-hooks.sh:20-115`

**Interfaces:**
- Consumes: `ctx.sessionManager.getBranch()`, `ctx.ui.setStatus(key, value)`, Pi custom entries.
- Produces: `restoreSessionGoal(ctx): string`, `renderSessionGoal(ctx): void`, constants `SESSION_GOAL_ENTRY_TYPE`, `SESSION_GOAL_STATUS_KEY`, and mutable `currentSessionGoal` used by later tasks.

- [ ] **Step 1: Add failing status and restore tests**

Extend the generated `check.mjs` harness state near the other arrays:

```js
const statuses = [];
const customEntries = [];
let branchEntries = [];
```

Add `appendEntry` to the `pi` stub and UI/session branch methods to `ctx`:

```js
appendEntry(customType, data) {
  customEntries.push({ customType, data });
},
```

```js
ui: {
  setStatus(key, value) {
    statuses.push({ key, value });
  },
  notify() {},
},
sessionManager: {
  getSessionName() {
    return currentSessionName;
  },
  getSessionFile() {
    return "/sessions/current.jsonl";
  },
  getBranch() {
    return branchEntries;
  },
},
```

Before the existing first `session_start` naming assertions, add:

```js
statuses.length = 0;
branchEntries = [];
await handlers.get("session_start")({ reason: "startup" }, ctx);
assert.deepEqual(statuses.at(-1), {
  key: "session-goal",
  value: "goal: determining…",
}, "new sessions show the determining goal placeholder");

statuses.length = 0;
branchEntries = [
  { type: "custom", customType: "session-goal", data: { subject: "old goal" } },
  { type: "custom", customType: "other-extension", data: { subject: "ignore me" } },
  { type: "custom", customType: "session-goal", data: { subject: "persistent Pi session goals" } },
];
await handlers.get("session_start")({ reason: "resume" }, ctx);
assert.deepEqual(statuses.at(-1), {
  key: "session-goal",
  value: "goal: persistent Pi session goals",
}, "resume restores the latest goal from the active branch");
```

- [ ] **Step 2: Run the focused test and verify the new assertions fail**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: FAIL because `ctx.ui.setStatus("session-goal", ...)` is not called.

- [ ] **Step 3: Implement restoration and status rendering**

Add constants and state near existing subject constants:

```ts
const SESSION_GOAL_ENTRY_TYPE = "session-goal";
const SESSION_GOAL_STATUS_KEY = "session-goal";
const SESSION_GOAL_PLACEHOLDER = "determining…";

let currentSessionGoal = "";
```

Add helpers before `managedHooks`:

```ts
function storedSessionGoal(entry) {
  if (entry?.type !== "custom" || entry.customType !== SESSION_GOAL_ENTRY_TYPE) return "";
  const subject = entry.data?.subject;
  return typeof subject === "string" ? subject : "";
}

function restoreSessionGoal(ctx) {
  const entries = ctx?.sessionManager?.getBranch?.() || [];
  for (let index = entries.length - 1; index >= 0; index -= 1) {
    const subject = storedSessionGoal(entries[index]);
    if (subject) return subject;
  }
  return "";
}

function renderSessionGoal(ctx) {
  ctx?.ui?.setStatus?.(
    SESSION_GOAL_STATUS_KEY,
    `goal: ${currentSessionGoal || SESSION_GOAL_PLACEHOLDER}`,
  );
}
```

At the beginning of `session_start`, before the tmux guard, restore and render so operation outside tmux still works:

```ts
pi.on("session_start", async (_event, ctx) => {
  currentSessionGoal = restoreSessionGoal(ctx);
  renderSessionGoal(ctx);
  if (!inTmux()) return;
```

- [ ] **Step 4: Run the focused test and verify it passes**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: `pi-managed-hooks checks complete` with exit 0.

- [ ] **Step 5: Commit the durable status slice**

Use the `z-commit` skill with summary `Restore durable Pi session goals in the status bar` and files:

```text
roles/common/files/pi/extensions/managed-hooks.ts
tests/pi-managed-hooks.sh
```

---

### Task 2: Add nonblocking, coalesced goal evaluation

**Files:**
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts:5-20,418-484,527-568`
- Test: `tests/pi-managed-hooks.sh:35-280`

**Interfaces:**
- Consumes: `currentSessionGoal`, `pi.exec`, `pi.appendEntry`, `before_agent_start` expanded `event.prompt`, session file identity.
- Produces: `normalizeGoalChildOutput(output): { kind: "keep" } | { kind: "subject", subject: string } | undefined`, `queueSessionGoalEvaluation(pi, request): void`, and a single-flight background queue.

- [ ] **Step 1: Add deterministic deferred-child test support**

In the generated Node harness, distinguish goal children from the existing tmux subject child by their system prompt. Add state:

```js
const goalChildCalls = [];
let goalChildResults = [];
let goalChildDeferred;

function deferred() {
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { promise, resolve };
}

async function flushAsyncWork() {
  for (let index = 0; index < 8; index += 1) await new Promise((resolve) => setImmediate(resolve));
}
```

In the `command === "pi"` stub branch, detect the goal system prompt and return queued or deferred results:

```js
if (command === "pi") {
  const systemPromptIndex = args.indexOf("--system-prompt");
  const systemPrompt = systemPromptIndex === -1 ? "" : args[systemPromptIndex + 1];
  if (systemPrompt.includes("session's broad goal")) {
    goalChildCalls.push({ args, options });
    if (goalChildDeferred) return goalChildDeferred.promise;
    return goalChildResults.shift() ?? ok("KEEP\n");
  }
  subjectChildExecOptions = options;
  if (subjectChildError) throw subjectChildError;
  return subjectChildResult;
}
```

- [ ] **Step 2: Add failing nonblocking, persistence, KEEP, and validation tests**

Set `taskStatus` to an active branch so the existing one-time tmux subject path does not create another child, then add:

```js
taskStatus = "active\tbranch\tfeature/current\n";
branchEntries = [
  { type: "custom", customType: "session-goal", data: { subject: "persistent Pi session goals" } },
];
await handlers.get("session_start")({ reason: "resume" }, ctx);

goalChildDeferred = deferred();
const nonblocking = handlers.get("before_agent_start")({
  prompt: "also cover lifecycle failures",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
assert.equal(await Promise.race([
  nonblocking.then(() => "returned"),
  new Promise((resolve) => setTimeout(() => resolve("blocked"), 25)),
]), "returned", "goal evaluation does not block before_agent_start");
assert.equal(goalChildCalls.length, 1, "every expanded prompt starts goal evaluation");
assert.match(goalChildCalls[0].args.at(-1), /Current goal: persistent Pi session goals/);
assert.match(goalChildCalls[0].args.at(-1), /New user prompt: also cover lifecycle failures/);

goalChildDeferred.resolve(ok("durable Pi goal lifecycle\n"));
goalChildDeferred = undefined;
await flushAsyncWork();
assert.deepEqual(customEntries.at(-1), {
  customType: "session-goal",
  data: { subject: "durable Pi goal lifecycle" },
}, "changed goal is persisted as a custom entry");
assert.deepEqual(statuses.at(-1), {
  key: "session-goal",
  value: "goal: durable Pi goal lifecycle",
}, "changed goal updates the status bar");

const entriesAfterChange = customEntries.length;
goalChildResults.push(ok("KEEP\n"));
await handlers.get("before_agent_start")({
  prompt: "continue",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await flushAsyncWork();
assert.equal(customEntries.length, entriesAfterChange, "KEEP does not append duplicate state");

for (const invalidOutput of [
  "\n",
  "first\nsecond\n",
  "goal: prefixed\n",
  "\"quoted subject\"\n",
  `${"x".repeat(81)}\n`,
  "control\u0007subject\n",
]) {
  goalChildResults.push(ok(invalidOutput));
  await handlers.get("before_agent_start")({
    prompt: "invalid output case",
    systemPrompt: "",
    systemPromptOptions: { cwd: "/repo" },
  }, ctx);
  await flushAsyncWork();
}
assert.equal(customEntries.length, entriesAfterChange, "invalid goal outputs are never persisted");
```

- [ ] **Step 3: Add a failing newest-prompt coalescing test**

```js
goalChildCalls.length = 0;
customEntries.length = 0;
goalChildDeferred = deferred();
await handlers.get("before_agent_start")({
  prompt: "first redirect",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await handlers.get("before_agent_start")({
  prompt: "second redirect",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await handlers.get("before_agent_start")({
  prompt: "final redirect",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
assert.equal(goalChildCalls.length, 1, "only one goal child runs concurrently");

goalChildResults.push(ok("final session theme\n"));
goalChildDeferred.resolve(ok("stale session theme\n"));
goalChildDeferred = undefined;
await flushAsyncWork();
assert.equal(goalChildCalls.length, 2, "rapid prompts collapse to one pending evaluation");
assert.match(goalChildCalls[1].args.at(-1), /New user prompt: final redirect/);
assert.equal(customEntries.some((entry) => entry.data.subject === "stale session theme"), false, "stale running output is discarded");
assert.equal(customEntries.at(-1).data.subject, "final session theme", "newest pending output applies");
```

- [ ] **Step 4: Run focused tests and verify evaluator assertions fail**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: FAIL because no session-goal child is launched or persisted.

- [ ] **Step 5: Implement goal child framing and validation**

Add constants:

```ts
const SESSION_GOAL_CHILD_SYSTEM_PROMPT = [
  "Track the session's broad goal.",
  "Given the current goal and newest user prompt, return KEEP when the broad goal is unchanged.",
  "Otherwise return one concise noun phrase of at most 80 characters.",
  "Output only KEEP or the phrase on one line, without quotes, a goal: prefix, or explanation.",
].join(" ");
const SESSION_GOAL_MAX_LENGTH = 80;
```

Add validation:

```ts
function normalizeGoalChildOutput(output, hasCurrentGoal) {
  if (typeof output !== "string" || output.includes("\n") || output.includes("\r")) return undefined;
  const value = output.trim().replace(/ +/g, " ");
  if (value === "KEEP") return hasCurrentGoal ? { kind: "keep" } : undefined;
  if (!value || value.length > SESSION_GOAL_MAX_LENGTH) return undefined;
  if (/\p{Cc}/u.test(value) || /^goal\s*:/i.test(value)) return undefined;
  if (/^["'`]|["'`]$/.test(value)) return undefined;
  return { kind: "subject", subject: value };
}
```

Frame and invoke the isolated child without logging prompt/output:

```ts
async function evaluateSessionGoal(pi, request, signal) {
  const current = request.currentGoal || "(none)";
  const framedPrompt = `Current goal: ${current}\nNew user prompt: ${request.prompt}`;
  return pi.exec("pi", [
    "--mode", "text",
    "--print",
    "--no-session",
    "--model", SUBJECT_CHILD_MODEL,
    "--thinking", "off",
    "--no-tools",
    "--no-extensions",
    "--no-skills",
    "--no-prompt-templates",
    "--no-themes",
    "--no-context-files",
    "--no-approve",
    "--system-prompt", SESSION_GOAL_CHILD_SYSTEM_PROMPT,
    framedPrompt,
  ], { cwd: request.cwd, timeout: SUBJECT_CHILD_TIMEOUT_MS, signal });
}
```

- [ ] **Step 6: Implement the single-flight background queue and persistence**

Add extension-instance state:

```ts
let sessionGoalGeneration = 0;
let sessionGoalSequence = 0;
let sessionGoalRunning = false;
let pendingSessionGoalRequest;
let sessionGoalAbortController;
```

Add safe persistence/application helpers:

```ts
function requestIsCurrent(request, ctx) {
  const sessionFile = ctx?.sessionManager?.getSessionFile?.() || "";
  return request.generation === sessionGoalGeneration && request.sessionFile === sessionFile;
}

function applySessionGoal(pi, ctx, subject) {
  if (subject === currentSessionGoal) return;
  pi.appendEntry(SESSION_GOAL_ENTRY_TYPE, { subject });
  currentSessionGoal = subject;
  renderSessionGoal(ctx);
}
```

Add queue/drain logic. Catch every detached promise rejection inside the drain:

```ts
async function drainSessionGoalQueue(pi) {
  if (sessionGoalRunning) return;
  sessionGoalRunning = true;
  try {
    while (pendingSessionGoalRequest) {
      const request = pendingSessionGoalRequest;
      pendingSessionGoalRequest = undefined;
      sessionGoalAbortController = new AbortController();

      let result;
      try {
        result = await evaluateSessionGoal(pi, request, sessionGoalAbortController.signal);
      } catch (error) {
        result = { code: 1, killed: false, error };
      }

      if (pendingSessionGoalRequest?.sequence > request.sequence) continue;
      if (!requestIsCurrent(request, request.ctx)) continue;
      if (result.code !== 0 || result.killed) continue;

      const normalized = normalizeGoalChildOutput(result.stdout.trimEnd(), Boolean(currentSessionGoal));
      if (!normalized || normalized.kind === "keep") continue;
      applySessionGoal(pi, request.ctx, normalized.subject);
    }
  } finally {
    sessionGoalAbortController = undefined;
    sessionGoalRunning = false;
    if (pendingSessionGoalRequest) void drainSessionGoalQueue(pi);
  }
}

function queueSessionGoalEvaluation(pi, prompt, cwd, ctx) {
  pendingSessionGoalRequest = {
    sequence: ++sessionGoalSequence,
    generation: sessionGoalGeneration,
    sessionFile: ctx?.sessionManager?.getSessionFile?.() || "",
    currentGoal: currentSessionGoal,
    prompt,
    cwd,
    ctx,
  };
  void drainSessionGoalQueue(pi);
}
```

Call the queue in `before_agent_start` after resolving `cwd`, without `await`:

```ts
queueSessionGoalEvaluation(pi, event.prompt, cwd, ctx);
```

Increment `sessionGoalGeneration`, clear pending/running request state, and abort any previous controller at the start of `session_start` before restoration.

- [ ] **Step 7: Run focused tests and fix only evaluator-slice failures**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: `pi-managed-hooks checks complete` with exit 0. Existing tmux subject tests must remain green.

- [ ] **Step 8: Commit the evaluator slice**

Use the `z-commit` skill with summary `Evaluate Pi session goals asynchronously with prompt coalescing` and files:

```text
roles/common/files/pi/extensions/managed-hooks.ts
tests/pi-managed-hooks.sh
```

---

### Task 3: Add naming gates, lifecycle cancellation, and repeated-failure visibility

**Files:**
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts:55-102,418-568`
- Test: `tests/pi-managed-hooks.sh:35-360`

**Interfaces:**
- Consumes: `tmux-agent-state status`, managed session-name marker, session lifecycle hooks, queue/evaluator from Task 2.
- Produces: `activeBranchTask(pi): Promise<boolean>`, `setManagedPiSessionName(pi, ctx, name): Promise<void>`, `recordSessionGoalFailure(ctx, details): void`, and clean `session_shutdown` cancellation.

- [ ] **Step 1: Add failure-warning and reset tests**

Track notifications in the harness:

```js
const notifications = [];
```

Replace the UI `notify` stub with:

```js
notify(message, level) {
  notifications.push({ message, level });
},
```

Add a `goalChildError`/failure-result queue to the goal child stub, then drive failures with an active branch task:

```js
notifications.length = 0;
for (let failure = 1; failure <= 13; failure += 1) {
  goalChildResults.push(fail());
  await handlers.get("before_agent_start")({
    prompt: `failure ${failure}`,
    systemPrompt: "",
    systemPromptOptions: { cwd: "/repo" },
  }, ctx);
  await flushAsyncWork();
}
assert.deepEqual(notifications.map((item) => item.message), [
  "Session goal updates are failing; keeping the previous goal.",
  "Session goal updates are failing; keeping the previous goal.",
], "repeated failures notify only at 3 and 13");

notifications.length = 0;
goalChildResults.push(ok("KEEP\n"), fail(), fail(), fail());
for (const prompt of ["recover", "again 1", "again 2", "again 3"]) {
  await handlers.get("before_agent_start")({
    prompt,
    systemPrompt: "",
    systemPromptOptions: { cwd: "/repo" },
  }, ctx);
  await flushAsyncWork();
}
assert.equal(notifications.length, 1, "successful KEEP resets the consecutive failure counter");
```

Capture `console.warn` and assert warning arguments contain only a fixed message plus metadata fields, never a prompt sentinel or raw stdout.

- [ ] **Step 2: Add pre-branch, branch-race, and manual-name tests**

Use a provisional agent task to avoid the old missing-subject child while representing no feature branch:

```js
taskStatus = "provisional\tagent\tstarting goal\n";
currentSessionName = "";
managedPiSessionName = "";
goalChildResults.push(ok("persistent session goal\n"));
await handlers.get("before_agent_start")({
  prompt: "build persistent session goal",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await flushAsyncWork();
assert.equal(currentSessionName, "persistent session goal", "goal names a managed session before branch creation");

currentSessionName = "manual investigation name";
managedPiSessionName = "persistent session goal";
goalChildResults.push(ok("revised persistent goal\n"));
await handlers.get("before_agent_start")({
  prompt: "revise the persistent goal",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await flushAsyncWork();
assert.equal(currentSessionName, "manual investigation name", "manual name blocks automatic goal rename");
assert.equal(statuses.at(-1).value, "goal: revised persistent goal", "manual name does not block goal status updates");

currentSessionName = "persistent session goal";
managedPiSessionName = "persistent session goal";
taskStatus = "provisional\tagent\tstarting goal\n";
goalChildDeferred = deferred();
await handlers.get("before_agent_start")({
  prompt: "race with branch creation",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
taskStatus = "active\tbranch\tfeature/session-goal\n";
currentSessionName = "feature/session-goal";
managedPiSessionName = "feature/session-goal";
goalChildDeferred.resolve(ok("goal after branch\n"));
goalChildDeferred = undefined;
await flushAsyncWork();
assert.equal(currentSessionName, "feature/session-goal", "active branch wins a late goal naming race");
assert.equal(statuses.at(-1).value, "goal: goal after branch", "late goal still updates status after branch creation");
```

- [ ] **Step 3: Add session shutdown stale-result tests**

Assert the extension registers `session_shutdown`. Start a deferred goal child, fire shutdown, start a replacement session with a different durable goal, then resolve the old child:

```js
assert.equal(typeof handlers.get("session_shutdown"), "function", "registers session_shutdown hook");

goalChildDeferred = deferred();
await handlers.get("before_agent_start")({
  prompt: "old session prompt",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await handlers.get("session_shutdown")({ reason: "resume" }, ctx);
branchEntries = [
  { type: "custom", customType: "session-goal", data: { subject: "destination goal" } },
];
await handlers.get("session_start")({ reason: "resume" }, ctx);
goalChildDeferred.resolve(ok("stale old goal\n"));
goalChildDeferred = undefined;
await flushAsyncWork();
assert.equal(statuses.at(-1).value, "goal: destination goal", "shutdown prevents stale goal application");
```

The Pi test stub should return an aborted result when the evaluator signal fires so shutdown completes deterministically.

- [ ] **Step 4: Run focused tests and verify naming/failure/lifecycle assertions fail**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: FAIL because failures are silent, goals do not rename pre-branch sessions, and `session_shutdown` is not registered.

- [ ] **Step 5: Refactor managed naming into one guarded helper**

Extract the current rename boundary from `syncSessionNameFromTmux`:

```ts
async function setManagedPiSessionName(pi, ctx, sessionName) {
  if (!sessionName || typeof pi.setSessionName !== "function") return false;
  const currentName = ctx?.sessionManager?.getSessionName?.() || "";
  if (currentName === sessionName) {
    if (await tmuxOption(pi, MANAGED_PI_SESSION_NAME_OPTION) === sessionName) {
      lastManagedSessionName = sessionName;
    }
    return true;
  }
  if (currentName && currentName !== lastManagedSessionName) return false;

  pi.setSessionName(sessionName);
  lastManagedSessionName = sessionName;
  if (inTmux()) {
    await exec(pi, "tmux", [
      "set-option", "-p", "-t", process.env.TMUX_PANE,
      MANAGED_PI_SESSION_NAME_OPTION, sessionName,
    ]);
  }
  return true;
}
```

Make `syncSessionNameFromTmux` call this helper inside its existing try/catch. This keeps current manual-name behavior and allows the goal path to reuse exactly the same boundary.

Add canonical branch detection:

```ts
async function activeBranchTask(pi) {
  if (!inTmux()) return false;
  const result = await exec(pi, "tmux-agent-state", ["status"]);
  if (result.code !== 0) return false;
  const [state, source] = result.stdout.trim().split("\t");
  return state === "active" && source === "branch";
}
```

After persisting/rendering a changed goal, recheck branch state and call `setManagedPiSessionName` only when `activeBranchTask` is false.

- [ ] **Step 6: Implement failure accounting with safe diagnostics**

Add:

```ts
let consecutiveSessionGoalFailures = 0;

function sessionGoalFailureDetails(value) {
  return {
    name: value instanceof Error ? value.name || "Error" : "SessionGoalChildResult",
    code: value?.code,
    exitCode: value?.exitCode,
    killed: value?.killed,
  };
}

function recordSessionGoalFailure(ctx, value) {
  consecutiveSessionGoalFailures += 1;
  console.warn("[managed-hooks] session goal child failed", sessionGoalFailureDetails(value));
  const shouldNotify = consecutiveSessionGoalFailures === 3
    || (consecutiveSessionGoalFailures > 3 && (consecutiveSessionGoalFailures - 3) % 10 === 0);
  if (shouldNotify) {
    ctx?.ui?.notify?.(
      "Session goal updates are failing; keeping the previous goal.",
      "warning",
    );
  }
}

function recordSessionGoalSuccess() {
  consecutiveSessionGoalFailures = 0;
}
```

In the drain, count thrown errors, nonzero/killed results, invalid output, and apply/persistence errors. Treat valid `KEEP` and valid subject output as success. Do not count stale-result discards or shutdown-triggered aborts. Wrap `applySessionGoal` in `try/catch` so persistence failure preserves the previous in-memory subject.

- [ ] **Step 7: Implement lifecycle abort and generation invalidation**

Register:

```ts
pi.on("session_shutdown", async () => {
  sessionGoalGeneration += 1;
  pendingSessionGoalRequest = undefined;
  sessionGoalAbortController?.abort();
});
```

At `session_start`, increment the generation, clear pending state, abort any inherited controller defensively, reset the failure counter, restore durable goal state, and render it before tmux-only work.

When classifying an aborted result, compare the request generation with the current generation. If it is stale, discard without diagnostics or failure accounting.

- [ ] **Step 8: Run focused tests until the complete contract passes**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: `pi-managed-hooks checks complete` with exit 0, including prior main-branch safety, current-spec tracking, tmux subject, and session-name tests.

- [ ] **Step 9: Commit naming, lifecycle, and failure behavior**

Use the `z-commit` skill with summary `Keep Pi goal updates safe across branches and session lifecycle` and files:

```text
roles/common/files/pi/extensions/managed-hooks.ts
tests/pi-managed-hooks.sh
```

---

### Task 4: Verify the integrated feature and provision it

**Files:**
- Verify: `roles/common/files/pi/extensions/managed-hooks.ts`
- Verify: `tests/pi-managed-hooks.sh`
- Verify: `docs/superpowers/specs/2026-07-21-pi-persistent-session-goal-design.md`
- Verify: `docs/superpowers/plans/2026-07-21-pi-persistent-session-goal.md`

**Interfaces:**
- Consumes: completed implementation and repository provisioning workflow.
- Produces: empirical test/provision evidence and a clean branch ready for review and PR.

- [ ] **Step 1: Run focused managed Pi hook verification**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: exit 0 and final line `pi-managed-hooks checks complete`.

- [ ] **Step 2: Run adjacent subject and Pi extension contract tests**

Run:

```bash
bash tests/agent-subject-hooks.sh
bash tests/pi-managed-hooks.sh
bash tests/pi-agent-assemble-agents.sh
bash tests/pi-attention-bell.sh
bash tests/pi-spec-shortcut.sh
```

Expected: all commands exit 0 with their normal completion messages.

- [ ] **Step 3: Run whitespace and repository diff checks**

Run:

```bash
git diff --check origin/main...HEAD
git status --short
```

Expected: no whitespace errors and no unexpected files. The committed plan may remain modified only if checkbox progress is intentionally being recorded; commit that progress before PR creation.

- [ ] **Step 4: Apply managed files through provisioning**

Run:

```bash
bin/provision
```

Expected: Ansible exits 0 and installs the updated managed Pi extension. If environmental credentials or host state prevent provisioning, record the exact blocker and continue with the deterministic repository tests rather than claiming provisioning passed.

- [ ] **Step 5: Perform an interactive smoke test when a TUI is available**

Start or reload Pi, then verify:

```text
1. A new session immediately shows goal: determining….
2. The first prompt starts while the mini evaluator runs.
3. The footer changes to goal: <broad theme>.
4. A follow-up such as "continue" keeps the theme.
5. A genuine redirect changes the theme.
6. After repo-start creates a branch, /resume/session naming shows the branch while the footer still shows the goal.
7. Resume restores the goal before another prompt is sent.
```

Expected: all observable behaviors match. If the harness has no interactive TUI, mark this evidence unavailable rather than simulated.

- [ ] **Step 6: Review the final diff against the spec**

Run:

```bash
git diff --stat origin/main...HEAD
git diff origin/main...HEAD -- roles/common/files/pi/extensions/managed-hooks.ts tests/pi-managed-hooks.sh docs/superpowers/specs/2026-07-21-pi-persistent-session-goal-design.md docs/superpowers/plans/2026-07-21-pi-persistent-session-goal.md
```

Confirm every goal, non-goal, failure threshold, lifecycle rule, and naming boundary from the spec is represented by implementation plus tests.

- [ ] **Step 7: Commit any final test-only corrections**

If verification required changes, use the `z-commit` skill with a narrow imperative summary and only the corrected files. If no files changed, do not create an empty commit.

- [ ] **Step 8: Request review, then open the PR**

Invoke the `requesting-code-review` skill. Address valid findings, rerun Task 4 verification, then invoke the repository `pull-request` skill. The PR should target `main`, reference the design and implementation plan, and include exact test/provision evidence plus any interactive-smoke limitation.
