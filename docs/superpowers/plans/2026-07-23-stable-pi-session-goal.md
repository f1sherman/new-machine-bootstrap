# Stable Pi Session Goal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate one stable Pi session goal from the first prompt, preserve it as automatic Pi/tmux identity across branches, and provide an explicit skill-driven update path.

**Architecture:** Extend tmux task state with persistent `goal` and `manual` identity sources that branch activation cannot replace. Simplify the managed Pi extension from a per-prompt queue into a one-time retryable initial evaluator, expose one canonical `set_session_goal` tool, and add a Pi-only user-invoked skill that calls that tool with supplied or inferred wording.

**Tech Stack:** TypeScript/JavaScript Pi extension API, Bash tmux state helpers, Node.js assertion harness, Ruby managed-skill contract tests, Ansible file deployment

## Global Constraints

- A normal session makes one successful initial goal-evaluator child call; prompts after a valid durable goal make none.
- Initial generation remains asynchronous and retries only while no valid goal exists.
- Session goals are one line, normalized, free of control characters, quotes, and `goal:` prefixes, non-empty, and at most 80 characters.
- A durable goal overrides branch-based automatic naming; manual Pi `/name` remains the visible-name escape hatch.
- Branch activation continues updating worktree and pane context without replacing active `goal` or `manual` identity.
- The registered `set_session_goal(goal: string)` tool is the only explicit mutation interface; it invokes no child model.
- The Pi-only `z-update-session-goal` skill uses supplied arguments when present and otherwise infers from conversation, then calls the tool exactly once.
- Preserve durable custom-entry restoration, session/tree lifecycle safety, no-prompt diagnostics, and operation outside tmux.
- Remove preceding-assistant context, `KEEP`, per-prompt queueing/coalescing, and continuous failure-notification logic.

---

### Task 1: Add persistent goal and manual tmux identity sources

**Files:**
- Modify: `roles/common/files/bin/tmux-agent-state:122-214, 220-300`
- Test: `tests/tmux-agent-state.sh:130-250`

**Interfaces:**
- Produces: `tmux-agent-state set-identity goal <subject>` storing `active<TAB>goal<TAB><subject>` with an 80-character maximum.
- Produces: `tmux-agent-state set-identity manual <name>` storing `active<TAB>manual<TAB><name>` with a 512-character maximum.
- Changes: `activate-branch` and `complete-worktree` preserve active `goal`/`manual` task identity while still refreshing worktree context.

- [ ] **Step 1: Add failing persistent-identity contract cases**

In `tests/tmux-agent-state.sh`, after provisional identity assertions and before the existing branch-replacement case, add goal coverage:

```bash
"$STATE" set-identity goal "stable session identity"
assert_file_eq "$state_dir/%1.@task_label" "stable session identity" "goal stores stable label"
assert_file_eq "$state_dir/%1.@task_source" "goal" "goal stores goal source"
assert_file_eq "$state_dir/%1.@task_state" "active" "goal stores active state"
assert_file_eq "$state_dir/%1.@window-label" "stable session identity" "goal renders stable top label"
assert_eq $'active\tgoal\tstable session identity' "$("$STATE" status)" "goal status contract"

"$STATE" activate-branch "$repo"
assert_file_eq "$state_dir/%1.@task_label" "stable session identity" "branch preserves goal label"
assert_file_eq "$state_dir/%1.@task_source" "goal" "branch preserves goal source"
assert_file_eq "$state_dir/%1.@agent_worktree_path" "$repo" "branch still binds goal worktree"
assert_file_eq "$state_dir/%1.@window-label" "stable session identity" "branch keeps goal top label"
assert_file_eq "$state_dir/%1.@pane-label" "(feature/durable-label) repo | host-a" "goal pane keeps branch context"

"$STATE" complete-worktree
assert_file_eq "$state_dir/%1.@task_state" "active" "worktree completion preserves active goal"
assert_file_eq "$state_dir/%1.@window-label" "stable session identity" "worktree completion preserves goal label"
```

Reset task state, then add manual coverage:

```bash
"$STATE" clear-task
"$STATE" set-identity manual "manual investigation"
assert_eq $'active\tmanual\tmanual investigation' "$("$STATE" status)" "manual status contract"
"$STATE" activate-branch "$repo"
assert_file_eq "$state_dir/%1.@task_label" "manual investigation" "branch preserves manual label"
assert_file_eq "$state_dir/%1.@task_source" "manual" "branch preserves manual source"
"$STATE" complete-worktree
assert_file_eq "$state_dir/%1.@task_state" "active" "worktree completion preserves manual identity"
```

Add boundary assertions: goal accepts 80 characters and rejects 81; manual accepts 512 and rejects 513. Restore a provisional task before the existing branch-replacement tests so their original behavior remains covered.

- [ ] **Step 2: Run the tmux state test and verify red**

Run:

```bash
bash tests/tmux-agent-state.sh
```

Expected: FAIL at `goal stores stable label` because `set-identity` does not exist.

- [ ] **Step 3: Implement persistent identity commands and branch preservation**

In `roles/common/files/bin/tmux-agent-state`, add:

```bash
persistent_identity_source() {
  case "$1" in
    goal|manual) return 0 ;;
    *) return 1 ;;
  esac
}

set_identity() {
  local pane="$1" source="$2" subject="$3" max_length
  case "$source" in
    goal) max_length=80 ;;
    manual) max_length=512 ;;
    *) return 0 ;;
  esac
  subject="$(sanitize_subject "$subject")"
  [[ -n "$subject" ]] || return 0
  (( ${#subject} <= max_length )) || return 0
  set_task "$pane" "$subject" "$source" active
  refresh "$pane"
}
```

In `activate_branch`, after validating the non-default branch and setting `@agent_worktree_path`, preserve persistent identity:

```bash
  set_pane_option "$pane" @agent_worktree_path "$path"
  current_source="$(get_pane_option "$pane" @task_source 2>/dev/null || true)"
  current_state="$(get_pane_option "$pane" @task_state 2>/dev/null || true)"
  if [[ "$current_state" == "active" ]] && persistent_identity_source "$current_source"; then
    refresh "$pane"
    return 0
  fi
  set_task "$pane" "$branch" branch active
```

Change `complete_task` to leave persistent identity active:

```bash
  [[ -n "$label" && -n "$source" ]] || return 0
  persistent_identity_source "$source" && return 0
  set_task "$pane" "$label" "$source" completed
```

Protect all active explicit identities in `set-provisional`:

```bash
    if [[ "$current_state" == "active" ]]; then
      case "$current_source" in branch|goal|manual) exit 0 ;; esac
    fi
```

Add command dispatch:

```bash
  set-identity)
    source="${1:-}"
    shift || true
    set_identity "$pane" "$source" "$*"
    ;;
```

- [ ] **Step 4: Run focused tmux verification**

Run:

```bash
bash tests/tmux-agent-state.sh
bash tests/tmux-label-contract.sh
```

Expected: both exit 0 and print their completion lines.

- [ ] **Step 5: Commit tmux identity support**

Use the repository commit skill for only:

```text
roles/common/files/bin/tmux-agent-state
tests/tmux-agent-state.sh
```

Suggested subject: `Preserve Pi goal identity across branches`

---

### Task 2: Replace continuous evaluation with initial generation and an explicit tool

**Files:**
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts:5-25, 120-190, 650-930`
- Test: `tests/pi-managed-hooks.sh:110-310, 640-1280`

**Interfaces:**
- Produces: registered Pi tool `set_session_goal` with required `{ goal: string }` input.
- Consumes: `tmux-agent-state set-identity goal|manual <subject>` from Task 1.
- Changes: `before_agent_start` launches evaluation only while `currentSessionGoal` is empty.

- [ ] **Step 1: Change the harness to capture the tool and add failing initial-only tests**

In `tests/pi-managed-hooks.sh`, add `let sessionGoalTool;` and capture registration in the Pi stub:

```js
registerTool(definition) {
  if (definition.name === "set_session_goal") sessionGoalTool = definition;
},
```

After extension installation, assert the tool contract:

```js
assert.equal(sessionGoalTool.name, "set_session_goal", "registers explicit session goal tool");
assert.deepEqual(sessionGoalTool.parameters.required, ["goal"], "goal tool requires goal text");
```

Replace per-prompt/context/coalescing expectations with these cases:

```js
branchEntries = [];
goalChildResults.push(ok("stable session identity\n"));
await handlers.get("before_agent_start")({
  prompt: "make session goals stable",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await flushAsyncWork();
assert.equal(goalChildCalls.length, 1, "first prompt evaluates initial goal once");
assert.equal(goalChildCalls[0].args.at(-1), "New session prompt: make session goals stable", "initial child receives only first prompt");
assert.equal(customEntries.at(-1).data.subject, "stable session identity", "initial goal persists");

await handlers.get("before_agent_start")({
  prompt: "C",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await flushAsyncWork();
assert.equal(goalChildCalls.length, 1, "later prompts do not reevaluate a durable goal");
```

Add retry after failure while unset, restored-goal suppression, and one-running-child suppression. Remove all assertions for `KEEP`, assistant context, pending prompt coalescing, recurring failure counts, and changed-goal evaluation after a goal exists.

- [ ] **Step 2: Add failing explicit tool, race, and naming tests**

Call the captured tool using its Pi execute signature:

```js
const entriesBeforeTool = customEntries.length;
const toolResult = await sessionGoalTool.execute(
  "goal-call-1",
  { goal: "cross branch theme" },
  subjectSignal,
  undefined,
  ctx,
);
assert.equal(customEntries.length, entriesBeforeTool + 1, "explicit tool persists changed goal");
assert.equal(customEntries.at(-1).data.subject, "cross branch theme", "explicit tool stores requested goal");
assert.equal(statuses.at(-1).value, "goal: cross branch theme", "explicit tool rerenders goal status");
assert.match(toolResult.content[0].text, /cross branch theme/, "explicit tool reports applied goal");
assert.ok(calls.some((call) => call.command === "tmux-agent-state" && call.args.join(" ") === "set-identity goal cross branch theme"), "explicit tool publishes goal identity");
```

Call it again with the same normalized goal and assert no duplicate entry. For invalid multiline, quoted, prefixed, control-character, empty, and 81-character values, assert rejection and no state/name/tmux calls.

Start a deferred initial evaluator, invoke the tool before it settles, resolve the stale child with another goal, and assert the explicit goal remains current and no stale entry appears.

Set a manual Pi name and simulate `session_info_changed`; assert `set-identity manual <name>`. Then invoke the goal tool and assert durable status changes while visible `currentSessionName` and manual tmux identity remain unchanged.

Simulate an extension-managed goal name event and assert it publishes `set-identity goal`, not `manual`.

- [ ] **Step 3: Run the managed-hook test and verify red**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: FAIL because no tool is registered and the extension still evaluates every prompt.

- [ ] **Step 4: Implement one canonical goal application path**

Keep `normalizeSessionGoalSubject`, but remove `KEEP` handling. Add:

```js
async function publishTmuxIdentity(pi, source, subject) {
  if (!ownsTmuxPane()) return false;
  const result = await exec(pi, "tmux-agent-state", ["set-identity", source, subject]);
  return result.code === 0 && !result.killed;
}
```

Before calling `pi.setSessionName`, establish managed ownership so the resulting `session_info_changed` event cannot be mistaken for manual input:

```js
  lastManagedSessionName = sessionName;
  if (inTmux()) {
    await exec(pi, "tmux", [
      "set-option", "-p", "-t", process.env.TMUX_PANE,
      MANAGED_PI_SESSION_NAME_OPTION, sessionName,
    ]);
  }
  pi.setSessionName(sessionName);
```

Inside the extension factory, replace the old synchronous `applySessionGoal` with one asynchronous canonical function:

```js
async function applySessionGoal(pi, ctx, subject) {
  const normalized = normalizeSessionGoalSubject(subject);
  if (!normalized) throw new Error("Session goal must be one line, unquoted, and at most 80 characters.");
  if (normalized === currentSessionGoal) return normalized;

  pi.appendEntry(SESSION_GOAL_ENTRY_TYPE, { subject: normalized });
  currentSessionGoal = normalized;
  renderSessionGoal(ctx);
  const named = await setManagedPiSessionName(pi, ctx, normalized);
  if (named) await publishTmuxIdentity(pi, "goal", normalized);
  return normalized;
}
```

Register the tool with an inline JSON schema so the copied `.mjs` test remains dependency-free:

```js
pi.registerTool({
  name: "set_session_goal",
  label: "Set Session Goal",
  description: "Set the durable broad goal and automatic identity for the current Pi session",
  parameters: {
    type: "object",
    properties: {
      goal: { type: "string", description: "Concise broad session goal, at most 80 characters" },
    },
    required: ["goal"],
    additionalProperties: false,
  },
  async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
    const goal = await applySessionGoal(pi, ctx, params.goal);
    return { content: [{ type: "text", text: `Session goal set to: ${goal}` }], details: { goal } };
  },
});
```

- [ ] **Step 5: Replace the queue with retryable initial generation**

Use one generation, running flag, and abort controller; remove sequence, pending request, queue drain, assistant-context extraction, `KEEP`, coalescing, and recurring failure counters.

Frame the child with only:

```js
const SESSION_GOAL_CHILD_SYSTEM_PROMPT = "Return one concise noun phrase of at most 80 characters describing the new session's broad goal. Output only the phrase on one line, without quotes, a goal: prefix, or explanation.";
const framedPrompt = `New session prompt: ${request.prompt}`;
```

Implement:

```js
async function evaluateInitialSessionGoal(pi, request, signal) {
  return pi.exec("pi", [
    "--mode", "text", "--print", "--no-session",
    "--model", SUBJECT_CHILD_MODEL, "--thinking", "off",
    "--no-tools", "--no-extensions", "--no-skills",
    "--no-prompt-templates", "--no-themes", "--no-context-files",
    "--no-approve", "--system-prompt", SESSION_GOAL_CHILD_SYSTEM_PROMPT,
    `New session prompt: ${request.prompt}`,
  ], { cwd: request.cwd, timeout: SUBJECT_CHILD_TIMEOUT_MS, signal });
}
```

The launcher must return immediately, skip when a goal/running child exists, and before applying confirm generation, session file, and `currentSessionGoal === ""`. On failure, clear running state and leave the next prompt eligible to retry. Session start/tree/shutdown abort and invalidate pending work.

In `before_agent_start`:

```js
if (!currentSessionGoal) startInitialSessionGoalEvaluation(pi, event.prompt, cwd, ctx);
```

- [ ] **Step 6: Publish goal versus manual lifecycle identity**

Allow `goal` and `manual` in `canonicalSessionNameStatus` parsing. On session start:

- restore/render durable goal;
- if current Pi name is manual, publish `manual` and do not rename;
- otherwise, if a goal exists, restore it as the managed Pi name and publish `goal`;
- otherwise retain existing provisional/directory fallback until initial generation succeeds.

In `session_info_changed`, compare `event.name` with `lastManagedSessionName` and `@pi_managed_session_name`:

```js
const marker = await tmuxOption(pi, MANAGED_PI_SESSION_NAME_OPTION);
const managedGoal = Boolean(currentSessionGoal)
  && sessionName === currentSessionGoal
  && (sessionName === lastManagedSessionName || sessionName === marker);
await publishTmuxIdentity(pi, managedGoal ? "goal" : "manual", sessionName);
```

The goal tool relies on `setManagedPiSessionName` returning false for manual names, so it persists/renders the new goal without replacing manual visible identity.

- [ ] **Step 7: Run focused extension verification**

Run:

```bash
bash tests/pi-managed-hooks.sh
bash tests/tmux-agent-state.sh
bash tests/tmux-label-contract.sh
git diff --check
```

Expected: all commands exit 0; managed-hook intentional failure diagnostics may still appear.

- [ ] **Step 8: Commit the extension change**

Use the repository commit skill for only:

```text
roles/common/files/pi/extensions/managed-hooks.ts
tests/pi-managed-hooks.sh
```

Suggested subject: `Generate stable Pi session goals once`

---

### Task 3: Add the explicit update skill and retire obsolete PR documentation

**Files:**
- Create: `roles/common/files/config/skills/pi/z-update-session-goal/SKILL.md`
- Modify: `tests/pi-shared-skills.rb:8-18, 45-65`
- Delete: `docs/superpowers/plans/2026-07-23-pi-session-goal-conversation-context.md` (already renamed by this plan commit)
- Keep: `docs/superpowers/plans/2026-07-23-stable-pi-session-goal.md`
- Keep: `docs/superpowers/specs/2026-07-23-stable-pi-session-goal-design.md`

**Interfaces:**
- Consumes: registered `set_session_goal(goal: string)` tool from Task 2.
- Produces: user command `/skill:z-update-session-goal [optional wording]`.

- [ ] **Step 1: Add failing Pi-only skill contract coverage**

In `tests/pi-shared-skills.rb`, make the Pi-only exception explicit:

```ruby
pi_only_names = ["z-update-session-goal"]
expected_pi_names = (source_skill_dirs.map do |path|
  "z-#{File.basename(path).sub(/^_/, "")}"
end + pi_only_names).uniq.sort
```

Add:

```ruby
update_goal_file = File.join(pi_root, "z-update-session-goal", "SKILL.md")
update_goal_contents = File.read(update_goal_file)
abort "Pi goal skill must be user-invoked only" unless update_goal_contents.include?("disable-model-invocation: true")
abort "Pi goal skill must use the canonical tool" unless update_goal_contents.include?("`set_session_goal`")
abort "Pi goal skill must support supplied wording" unless update_goal_contents.include?("arguments were supplied")
abort "Pi goal skill must support inference" unless update_goal_contents.include?("no arguments were supplied")
abort "Pi goal skill must call the tool exactly once" unless update_goal_contents.include?("exactly once")
abort "Pi goal skill must not mutate session files" unless update_goal_contents.include?("Do not edit Pi session files")
```

- [ ] **Step 2: Run the skill contract and verify red**

Run:

```bash
ruby tests/pi-shared-skills.rb
```

Expected: abort with missing `z-update-session-goal/SKILL.md`.

- [ ] **Step 3: Create the user-invoked skill**

Create `roles/common/files/config/skills/pi/z-update-session-goal/SKILL.md`:

```markdown
---
name: z-update-session-goal
description: Update the durable broad goal and automatic identity of the current Pi session. User-invoked when the session theme changes.
disable-model-invocation: true
---

# Update Session Goal

Update the current Pi session's durable broad goal.

- If arguments were supplied after the skill command, treat them as the requested theme.
- If no arguments were supplied, infer the broad theme from the current conversation.
- Normalize the result into one concise noun phrase, maximum 80 characters, with no quotes or `goal:` prefix.
- Call `set_session_goal` exactly once with that phrase.
- Report the applied goal briefly.

Do not edit Pi session files. Do not invoke tmux helpers or rename git branches directly. The `set_session_goal` tool is the only mutation interface.
```

- [ ] **Step 4: Run skill and repository contract verification**

Run:

```bash
ruby tests/pi-shared-skills.rb
bash tests/pi-managed-hooks.sh
bash tests/tmux-agent-state.sh
bash tests/tmux-label-contract.sh
bash tests/ci-test-inventory.sh
git diff --check
```

Expected: every command exits 0 and CI inventory reports no unregistered test-like files.

- [ ] **Step 5: Commit the skill**

Use the repository commit skill for only:

```text
roles/common/files/config/skills/pi/z-update-session-goal/SKILL.md
tests/pi-shared-skills.rb
```

Suggested subject: `Add explicit Pi session goal update skill`

---

### Task 4: End-to-end verification and PR replacement

**Files:**
- Verify only; no source changes expected.
- Update PR #367 title/body metadata after commits are pushed.

**Interfaces:**
- Confirms Tasks 1-3 compose into one deployed behavior.

- [ ] **Step 1: Run complete focused verification from a clean worktree**

Run:

```bash
bash tests/pi-managed-hooks.sh
bash tests/tmux-agent-state.sh
bash tests/tmux-label-contract.sh
ruby tests/pi-shared-skills.rb
bash tests/ci-test-inventory.sh
git diff --check
git status --short
```

Expected: all tests exit 0, CI inventory passes, diff check is silent, and tracked worktree status is clean.

- [ ] **Step 2: Provision managed files**

Run:

```bash
bin/provision
```

Expected: Ansible recap reports `failed=0`.

- [ ] **Step 3: Verify deployed files match source**

Run:

```bash
cmp roles/common/files/pi/extensions/managed-hooks.ts "$HOME/.pi/agent/extensions/managed-hooks.ts"
cmp roles/common/files/config/skills/pi/z-update-session-goal/SKILL.md "$HOME/.pi/agent/skills/z-update-session-goal/SKILL.md"
```

Expected: both commands exit 0.

- [ ] **Step 4: Push and replace PR metadata**

Push `fix/pi-session-goal-context`, retitle PR #367 to `Keep Pi session goals stable across branches`, and replace its body so it describes:

- one initial asynchronous goal evaluation;
- no automatic reevaluation after a durable goal exists;
- goal/manual tmux identity surviving branch activation;
- `/skill:z-update-session-goal [optional wording]`;
- focused test and provisioning evidence.

Do not create a second PR.
