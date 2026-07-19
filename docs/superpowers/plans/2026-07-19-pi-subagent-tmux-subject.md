# Pi Subagent Tmux Subject Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate and apply Pi's provisional tmux task subject in an isolated child process before the main agent turn.

**Architecture:** `managed-hooks.ts` invokes a sessionless, tool-free Pi child with discovery disabled and validates its one-line response before the parent hook calls `tmux-agent-subject`. Successful labeling adds nothing to the main context; child or validation failures retain the current reminder fallback. The persistent Pi AGENTS fragment drops its main-agent labeling instruction.

**Tech Stack:** Pi TypeScript extension API, `pi.exec`, Node.js assertion harness, Bash

## Global Constraints

- Pi only; Claude and Codex behavior remains unchanged.
- Child model: `openai-codex/gpt-5.3-codex-spark` with thinking disabled.
- Child timeout: 15 seconds.
- Child has no tools, extensions, skills, prompt templates, themes, context files, or saved session.
- Accept exactly one non-empty line of at most 512 characters.
- Never interpolate the user prompt into a shell command or include it in failure diagnostics.
- Failure must not block the main task; inject the existing reminder instead.

---

### Task 1: Isolated subject generation and fallback

**Files:**
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts`
- Modify: `tests/pi-managed-hooks.sh`

**Interfaces:**
- Produces: `normalizeGeneratedSubject(output: string): string`, returning a validated subject or `""`.
- Produces: `setSubjectFromSubagent(pi, prompt: string, cwd: string): Promise<boolean>`, returning whether generation and `tmux-agent-subject set` both succeeded.
- Consumes: existing `needsSubjectReminder(pi): Promise<boolean>` and `exec(pi, command, args, options)` helpers.

- [ ] **Step 1: Add failing automatic-label tests**

Extend the mock state near the top of `tests/pi-managed-hooks.sh`:

```js
let subjectChildResult = ok("improve tmux labels\n");
let subjectChildError;
let subjectApplyResult = ok();
```

Place these assignments immediately after the existing `ok` and `fail` helper declarations. Extend `pi.exec` before the default `return fail()`:

```js
    if (command === "pi") {
      if (subjectChildError) throw subjectChildError;
      return subjectChildResult;
    }
    if (command === "tmux-agent-subject") return subjectApplyResult;
```

Replace the current empty/completed reminder assertions with cases that assert:

```js
branch = "feature";
taskStatus = "";
calls.length = 0;
const automaticSubject = await handlers.get("before_agent_start")({
  prompt: "improve tmux labels; printf injected",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, { cwd: "/repo" });
assert.equal(automaticSubject, undefined, "valid child subject adds no main-context reminder");
const childCall = calls.find((call) => call.command === "pi");
assert.ok(childCall, "missing task invokes isolated Pi child");
assert.deepEqual(childCall.args.slice(0, -1), [
  "--mode", "text",
  "--print",
  "--no-session",
  "--model", "openai-codex/gpt-5.3-codex-spark",
  "--thinking", "off",
  "--no-tools",
  "--no-extensions",
  "--no-skills",
  "--no-prompt-templates",
  "--no-themes",
  "--no-context-files",
  "--no-approve",
  "--system-prompt", "Return one concise noun phrase describing the user's task. Output only the phrase on one line, with no quotes, prefix, or explanation.",
], "subject child disables context-bearing resources");
assert.equal(childCall.args.at(-1), "improve tmux labels; printf injected", "prompt is passed as one argv value");
assert.deepEqual(calls.find((call) => call.command === "tmux-agent-subject"), {
  command: "tmux-agent-subject",
  args: ["set", "improve tmux labels"],
}, "parent applies the validated child subject");

subjectChildResult = ok("start another task\n");
taskStatus = "completed\tbranch\told-task\n";
calls.length = 0;
const completedAutomaticSubject = await handlers.get("before_agent_start")({
  prompt: "start another task",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, { cwd: "/repo" });
assert.equal(completedAutomaticSubject, undefined, "completed task is automatically relabeled");
assert.ok(calls.some((call) => call.command === "pi"), "completed task invokes isolated Pi child");
```

Keep the active/provisional loop, clear `calls` for each state, and add:

```js
assert.equal(calls.some((call) => call.command === "pi"), false, `${state.split("\t")[0]} task skips subject child`);
```

Add fallback cases:

```js
for (const [name, result] of [
  ["empty", ok("\n")],
  ["multiline", ok("first line\nsecond line\n")],
  ["oversized", ok(`${"x".repeat(513)}\n`)],
  ["failed", fail()],
  ["timed out", { stdout: "", stderr: "", code: 1, killed: true }],
]) {
  subjectChildResult = result;
  subjectChildError = undefined;
  taskStatus = "";
  calls.length = 0;
  const fallback = await handlers.get("before_agent_start")({
    prompt: `fallback ${name}`,
    systemPrompt: "",
    systemPromptOptions: { cwd: "/repo" },
  }, { cwd: "/repo" });
  assert.match(fallback.message.content, /tmux-agent-subject set/, `${name} child result preserves reminder fallback`);
  assert.equal(calls.some((call) => call.command === "tmux-agent-subject"), false, `${name} child result is not applied`);
}

subjectChildResult = ok("valid subject\n");
subjectApplyResult = fail();
taskStatus = "";
const applyFallback = await handlers.get("before_agent_start")({
  prompt: "fallback apply failure",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, { cwd: "/repo" });
assert.match(applyFallback.message.content, /tmux-agent-subject set/, "subject apply failure preserves reminder fallback");
subjectApplyResult = ok();

subjectChildResult = ok("unused\n");
subjectChildError = new Error("child unavailable");
taskStatus = "";
const thrownFallback = await handlers.get("before_agent_start")({
  prompt: "fallback thrown error",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, { cwd: "/repo" });
assert.match(thrownFallback.message.content, /tmux-agent-subject set/, "thrown child error preserves reminder fallback");
subjectChildError = undefined;
```

- [ ] **Step 2: Run the hook test to verify failure**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: FAIL because no `pi` child or `tmux-agent-subject` application occurs.

- [ ] **Step 3: Implement the isolated child flow**

Add constants near the top of `managed-hooks.ts`:

```ts
const SUBJECT_CHILD_TIMEOUT_MS = 15000;
const SUBJECT_CHILD_MODEL = "openai-codex/gpt-5.3-codex-spark";
const SUBJECT_CHILD_SYSTEM_PROMPT = "Return one concise noun phrase describing the user's task. Output only the phrase on one line, with no quotes, prefix, or explanation.";
const SUBJECT_MAX_LENGTH = 512;
```

Add these helpers immediately after `needsSubjectReminder`:

```ts
function normalizeGeneratedSubject(output) {
  const subject = output.trim();
  if (!subject || subject.length > SUBJECT_MAX_LENGTH || subject.includes("\n") || subject.includes("\r")) return "";
  return subject;
}

async function setSubjectFromSubagent(pi, prompt, cwd) {
  let result;
  try {
    result = await pi.exec("pi", [
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
      "--system-prompt", SUBJECT_CHILD_SYSTEM_PROMPT,
      prompt,
    ], { cwd, timeout: SUBJECT_CHILD_TIMEOUT_MS });
  } catch (error) {
    warn("tmux subject child failed", error);
    return false;
  }

  if (result.code !== 0 || result.killed) {
    warn("tmux subject child failed", result.stderr || `exit ${result.code}`);
    return false;
  }

  const subject = normalizeGeneratedSubject(result.stdout);
  if (!subject) {
    warn("tmux subject child returned an invalid subject", "empty, multiline, or over 512 characters");
    return false;
  }

  const applied = await exec(pi, "tmux-agent-subject", ["set", subject]);
  return applied.code === 0;
}
```

Replace the reminder branch inside `before_agent_start`:

```ts
    if (await needsSubjectReminder(pi) && !await setSubjectFromSubagent(pi, event.prompt, cwd)) {
      notes.push("Choose a concise task subject, then run `tmux-agent-subject set \"<short subject>\"` before continuing. The provisional label will be replaced by the feature branch.");
    }
```

- [ ] **Step 4: Run the focused hook test**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: `pi-managed-hooks checks complete` with exit 0.

- [ ] **Step 5: Commit the isolated hook behavior**

Use the `z-commit` skill to commit:

```text
roles/common/files/pi/extensions/managed-hooks.ts
tests/pi-managed-hooks.sh
```

Commit message: `Delegate Pi tmux subject selection`

---

### Task 2: Remove persistent main-agent labeling guidance

**Files:**
- Modify: `roles/common/files/pi/AGENTS.md.d/00-base.md`
- Modify: `tests/pi-agent-assemble-agents.sh`

**Interfaces:**
- Consumes: automatic subject handling from Task 1.
- Produces: Pi's assembled base context without a persistent `tmux-agent-subject` instruction.

- [ ] **Step 1: Add a failing context-isolation assertion**

Add before the final success line in `tests/pi-agent-assemble-agents.sh`:

```bash
if rg -n 'tmux-agent-subject|Tmux task label' \
  "$REPO_ROOT/roles/common/files/pi/AGENTS.md.d/00-base.md"; then
  fail "Pi base fragment should leave tmux subject selection to managed hooks"
fi
printf 'PASS  Pi base fragment omits main-agent tmux subject guidance\n'
```

- [ ] **Step 2: Run the assembly test to verify failure**

Run:

```bash
bash tests/pi-agent-assemble-agents.sh
```

Expected: FAIL with `Pi base fragment should leave tmux subject selection to managed hooks`.

- [ ] **Step 3: Remove the persistent instruction**

Delete this line from `roles/common/files/pi/AGENTS.md.d/00-base.md`:

```md
* Tmux task label: on the first prompt for a task, if `tmux-agent-state status` is empty or completed, run `tmux-agent-subject set "<short subject>"` with a concise noun phrase. This provisional `~` label is replaced by the feature branch and the captured branch remains with `✓` after cleanup.
```

Do not change the Claude or Codex base fragments or reminders.

- [ ] **Step 4: Run focused tests**

Run:

```bash
bash tests/pi-agent-assemble-agents.sh
bash tests/pi-managed-hooks.sh
```

Expected: both exit 0 and print their completion messages.

- [ ] **Step 5: Commit the context cleanup**

Use the `z-commit` skill to commit:

```text
roles/common/files/pi/AGENTS.md.d/00-base.md
tests/pi-agent-assemble-agents.sh
```

Commit message: `Remove main-agent tmux subject guidance`

---

### Task 3: Provision and end-to-end verification

**Files:**
- Verify only; no expected source changes.

**Interfaces:**
- Consumes: Tasks 1 and 2.
- Produces: deployed Pi extension/base fragment and empirical verification evidence.

- [ ] **Step 1: Run repository checks**

Run:

```bash
bash tests/pi-managed-hooks.sh
bash tests/pi-agent-assemble-agents.sh
git diff --check origin/main...HEAD
```

Expected: both test scripts complete with exit 0; `git diff --check` prints nothing.

- [ ] **Step 2: Apply managed files**

Run:

```bash
bin/provision
```

Expected: exit 0 with no failed Ansible tasks.

- [ ] **Step 3: Verify deployed files**

Run:

```bash
cmp roles/common/files/pi/extensions/managed-hooks.ts "$HOME/.pi/agent/extensions/managed-hooks.ts"
if rg -n 'tmux-agent-subject|Tmux task label' "$HOME/.pi/agent/AGENTS.md.d/00-base.md"; then exit 1; fi
```

Expected: `cmp` exits 0; `rg` finds no persistent Pi label instruction.

- [ ] **Step 4: Inspect final repository state**

Run:

```bash
git status --short --branch
git log --oneline origin/main..HEAD
```

Expected: clean feature branch with the design, plan, hook behavior, and context-cleanup commits.
