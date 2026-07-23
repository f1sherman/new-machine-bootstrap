# Pi Session Goal Conversation Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent conversational replies such as `C` from replacing a useful managed Pi session goal by giving the bounded goal evaluator the preceding assistant response.

**Architecture:** Add one pure extraction helper to the existing managed-hooks extension. It scans the active session branch for the latest assistant message, keeps text blocks only, bounds their combined tail to 800 characters, and adds that context to the already-isolated goal evaluator request; all queueing, lifecycle, persistence, and naming behavior stays intact.

**Tech Stack:** TypeScript Pi extension, Node.js assertion harness embedded in Bash, tmux helper mocks

## Global Constraints

- Include at most 800 characters of preceding assistant text.
- Do not include full session history, tool results, reasoning blocks, images, or older messages.
- Do not add evaluator calls or change the existing model, timeout, async queue, prompt coalescing, lifecycle guards, persistence, output validation, or managed-name ownership rules.
- If no usable assistant text exists or extraction fails, frame the assistant context as `(none)`.
- Keep the change limited to `roles/common/files/pi/extensions/managed-hooks.ts` and `tests/pi-managed-hooks.sh`.

---

### Task 1: Add bounded preceding-assistant context to goal evaluation

**Files:**
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts:5-14, 600-715, 830-838`
- Test: `tests/pi-managed-hooks.sh:115-150, 500-670`

**Interfaces:**
- Produces: `precedingAssistantContext(ctx): string`, returning the final 800 characters of combined text blocks from the latest assistant message or `""`.
- Extends queued evaluator requests with `assistantContext: string`.
- Extends evaluator framing with `Preceding assistant context: <text-or-(none)>` between current goal and newest user prompt.

- [ ] **Step 1: Add failing framing and behavior tests**

In `tests/pi-managed-hooks.sh`, build branch entries containing a prior assistant message before the existing nonblocking goal evaluation. Include multiple text blocks plus ignored thinking and tool-call blocks:

```js
const assistantPrefix = "x".repeat(900);
const expectedAssistantTail = `${assistantPrefix}\nChoose one:\nA. Keep it\nB. Pause\nC. Continue`.slice(-800);
branchEntries = [
  { type: "custom", customType: "session-goal", data: { subject: "persistent Pi session goals" } },
  {
    type: "message",
    message: {
      role: "assistant",
      content: [
        { type: "text", text: assistantPrefix },
        { type: "thinking", thinking: "private reasoning" },
        { type: "toolCall", id: "call-1", name: "read", arguments: {} },
        { type: "text", text: "Choose one:\nA. Keep it\nB. Pause\nC. Continue" },
      ],
    },
  },
];
```

Change the prompt to `C`, then assert the child input is exactly bounded and framed:

```js
assert.equal(
  goalChildCalls[0].args.at(-1),
  `Current goal: persistent Pi session goals\nPreceding assistant context: ${expectedAssistantTail}\nNew user prompt: C`,
  "goal child receives bounded preceding assistant context for a choice reply",
);
assert.equal(goalChildCalls[0].args.at(-1).includes("private reasoning"), false, "goal context excludes thinking blocks");
assert.equal(goalChildCalls[0].args.at(-1).includes("call-1"), false, "goal context excludes tool-call blocks");
```

Resolve that evaluation with `KEEP`, flush asynchronous work, and assert no custom goal entry or managed session rename occurred:

```js
const entriesBeforeChoice = customEntries.length;
const namesBeforeChoice = sessionNames.length;
goalChildDeferred.resolve(ok("KEEP\n"));
goalChildDeferred = undefined;
await flushAsyncWork();
assert.equal(customEntries.length, entriesBeforeChoice, "choice reply keeps the existing broad goal");
assert.equal(sessionNames.length, namesBeforeChoice, "choice reply does not rename the managed session");
```

Add two focused framing cases after the queue is idle:

```js
branchEntries = [];
goalChildResults.push(ok("KEEP\n"));
await handlers.get("before_agent_start")({
  prompt: "initial task",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await flushAsyncWork();
assert.match(goalChildCalls.at(-1).args.at(-1), /Preceding assistant context: \(none\)/, "missing assistant context is explicit");

branchEntries = [{
  type: "message",
  message: { role: "assistant", content: [{ type: "text", text: "Should I proceed?" }] },
}];
goalChildResults.push(ok("renamed broad goal\n"));
await handlers.get("before_agent_start")({
  prompt: "Actually, switch to a different broad goal",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await flushAsyncWork();
assert.equal(customEntries.at(-1).data.subject, "renamed broad goal", "explicit redirect still updates the goal");
```

Also update the exact system-prompt assertion to require the new instruction:

```text
Track the session's broad goal. Use the preceding assistant context to interpret the newest user prompt. Replies that answer, select from, approve, or continue the preceding assistant message should return KEEP when they remain within the current broad goal. Given the current goal and newest user prompt, return KEEP when the broad goal is unchanged. Otherwise return one concise noun phrase of at most 80 characters. Output only KEEP or the phrase on one line, without quotes, a goal: prefix, or explanation.
```

- [ ] **Step 2: Run the contract test and confirm the new assertions fail**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: FAIL because the evaluator input lacks `Preceding assistant context`, and the exact system prompt still has the old wording.

- [ ] **Step 3: Implement minimal bounded context extraction and framing**

In `roles/common/files/pi/extensions/managed-hooks.ts`, add the fixed bound and revised evaluator instruction:

```ts
const SESSION_GOAL_ASSISTANT_CONTEXT_MAX_LENGTH = 800;
const SESSION_GOAL_CHILD_SYSTEM_PROMPT = [
  "Track the session's broad goal.",
  "Use the preceding assistant context to interpret the newest user prompt.",
  "Replies that answer, select from, approve, or continue the preceding assistant message should return KEEP when they remain within the current broad goal.",
  "Given the current goal and newest user prompt, return KEEP when the broad goal is unchanged.",
  "Otherwise return one concise noun phrase of at most 80 characters.",
  "Output only KEEP or the phrase on one line, without quotes, a goal: prefix, or explanation.",
].join(" ");
```

Add the extraction helper near the existing session-goal helpers:

```ts
function precedingAssistantContext(ctx) {
  try {
    const entries = ctx?.sessionManager?.getBranch?.() || [];
    for (let index = entries.length - 1; index >= 0; index -= 1) {
      const entry = entries[index];
      if (entry?.type !== "message" || entry.message?.role !== "assistant") continue;
      if (!Array.isArray(entry.message.content)) return "";
      const text = entry.message.content
        .filter((block) => block?.type === "text" && typeof block.text === "string")
        .map((block) => block.text)
        .join("\n")
        .trim();
      return text.slice(-SESSION_GOAL_ASSISTANT_CONTEXT_MAX_LENGTH);
    }
  } catch {
    return "";
  }
  return "";
}
```

Extend evaluator framing:

```ts
async function evaluateSessionGoal(pi, request, signal) {
  const current = request.currentGoal || "(none)";
  const assistantContext = request.assistantContext || "(none)";
  const framedPrompt = `Current goal: ${current}\nPreceding assistant context: ${assistantContext}\nNew user prompt: ${request.prompt}`;
```

Capture the context once when queueing, so asynchronous execution uses the conversation state associated with that request:

```ts
function queueSessionGoalEvaluation(pi, prompt, cwd, ctx) {
  pendingSessionGoalRequest = {
    sequence: ++sessionGoalSequence,
    generation: sessionGoalGeneration,
    sessionFile: ctx?.sessionManager?.getSessionFile?.() || "",
    currentGoal: currentSessionGoal,
    assistantContext: precedingAssistantContext(ctx),
    prompt,
    cwd,
    ctx,
  };
```

- [ ] **Step 4: Run focused verification**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: `pi-managed-hooks checks complete` and exit 0. Existing intentional warning diagnostics may still appear.

- [ ] **Step 5: Run repository-level static and contract checks**

Run:

```bash
git diff --check
bash tests/ci-test-inventory.sh
```

Expected: both commands exit 0 with no whitespace errors or missing CI test registration.

- [ ] **Step 6: Commit the implementation**

Use the repository commit skill with only these files:

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Make Pi session goals conversation aware" \
  roles/common/files/pi/extensions/managed-hooks.ts \
  tests/pi-managed-hooks.sh
```
