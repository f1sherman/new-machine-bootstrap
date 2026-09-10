# Pi Submit Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show `Submitting...` immediately while Pi's managed prompt preflight hook runs.

**Architecture:** The existing managed `before_agent_start` hook will own one temporary keyed footer status. A `try`/`finally` boundary will preserve all existing return and error behavior while guaranteeing cleanup.

**Tech Stack:** TypeScript Pi extension, Bash and Node.js test harness

**Spec:** `docs/superpowers/specs/2026-10-09-pi-submit-feedback-design.md`

## Global Constraints

- Keep session naming and tmux subject generation behavior unchanged.
- Do not modify Pi core or deployed files outside this repository.
- Clear the temporary status after success, early return, or exception.

---

### Task 1: Managed prompt preflight feedback

**Files:**
- Modify: `tests/pi-managed-hooks.sh`
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts`

**Interfaces:**
- Consumes: Pi `ctx.ui.setStatus(key, value)` from `before_agent_start`.
- Produces: temporary `managed-hooks-submit` footer status with text
  `Submitting...`; clears it by passing `undefined`.

- [x] **Step 1: Write the failing behavioral test**

Record `setStatus` calls in the existing Pi context stub. Add a deferred subject-child
result. Start `before_agent_start` without resolving the child and assert that the
latest status call is:

```javascript
{ key: "managed-hooks-submit", value: "Submitting..." }
```

Resolve the child, await the handler, and assert that the latest status call is:

```javascript
{ key: "managed-hooks-submit", value: undefined }
```

- [x] **Step 2: Run the focused test and verify failure**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: failure because the production handler does not set the submit status.

- [x] **Step 3: Add the temporary status boundary**

Wrap the existing handler body without changing its internal decisions:

```typescript
pi.on("before_agent_start", async (event, ctx) => {
  ctx.ui.setStatus("managed-hooks-submit", "Submitting...");
  try {
    const notes = [];
    const cwd = await boundWorktreePath(pi, event.systemPromptOptions.cwd || ctx.cwd);
    if (!ctx?.sessionManager?.getSessionName?.()) {
      startInitialSessionGoalEvaluation(pi, event.prompt, cwd, ctx);
    }

    if (REPO_START_TRIGGERS.test(event.prompt) && await onMainBranch(pi, cwd)) {
      notes.push("You are on main. Before changing files, run `repo-start <branch>` and continue from the created worktree.");
    }

    if (await needsSubjectReminder(pi) && !await setSubjectFromSubagent(pi, event.prompt, cwd, ctx.signal)) {
      notes.push("Choose a concise task subject, then run `tmux-agent-subject set \"<short subject>\"` before continuing. The provisional label will be replaced by the feature branch.");
    }

    if (notes.length === 0) return;
    return {
      message: {
        customType: "managed-hooks-reminder",
        content: notes.join("\n\n"),
        display: true,
      },
    };
  } finally {
    ctx.ui.setStatus("managed-hooks-submit", undefined);
  }
});
```

- [x] **Step 4: Run focused and syntax verification**

Run:

```bash
bash tests/pi-managed-hooks.sh
node --check roles/common/files/pi/extensions/managed-hooks.ts
```

Expected: both commands exit with status 0.

- [x] **Step 5: Provision the managed extension**

Run:

```bash
bin/provision
```

Expected: provisioning exits with status 0 and deploys the extension from this
worktree.

- [x] **Step 6: Confirm deployed source matches the worktree**

Run:

```bash
cmp roles/common/files/pi/extensions/managed-hooks.ts \
  "$HOME/.pi/agent/extensions/managed-hooks.ts"
```

Expected: exit status 0.

- [x] **Step 7: Commit the implementation**

Commit these files with no AI attribution:

```bash
~/.pi/agent/skills/z-commit/commit.sh \
  -m "fix(pi): show prompt submission feedback" \
  tests/pi-managed-hooks.sh \
  roles/common/files/pi/extensions/managed-hooks.ts \
  docs/superpowers/plans/2026-10-09-pi-submit-feedback.md
```
