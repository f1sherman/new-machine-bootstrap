# Pi Session Goal Provider Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make managed Pi subject and session-goal children use the provisioned OpenAI API-key provider.

**Architecture:** Update the single shared child-model constant used by both managed child call sites. Lock the provider contract in the existing shell-based managed-hooks test suite, then provision and run the real isolated child command.

**Tech Stack:** TypeScript Pi extension, Bash/Node contract tests, Ansible provisioning

## Global Constraints

- Use `openai/gpt-5.4-mini`.
- Keep child prompts, isolation flags, timeout, validation, and failure handling unchanged.
- Do not add provider fallback logic or require Codex OAuth.

---

### Task 1: Correct the managed child provider

**Files:**
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts:6`
- Test: `tests/pi-managed-hooks.sh`

**Interfaces:**
- Consumes: `SUBJECT_CHILD_MODEL`, shared by tmux-subject and session-goal `pi.exec` calls.
- Produces: Child invocations selecting `openai/gpt-5.4-mini`.

- [ ] **Step 1: Write the failing provider contract test**

Add assertions beside the existing managed-hooks source contract checks:

```javascript
assert.match(source, /const SUBJECT_CHILD_MODEL = "openai\/gpt-5[.]4-mini";/, "managed children use provisioned OpenAI provider");
assert.doesNotMatch(source, /openai-codex\/gpt-5[.]4-mini/, "managed children do not require Codex OAuth");
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `tests/pi-managed-hooks.sh`
Expected: FAIL at `managed children use provisioned OpenAI provider` because the source still contains `openai-codex/gpt-5.4-mini`.

- [ ] **Step 3: Change the shared model identifier**

```typescript
const SUBJECT_CHILD_MODEL = "openai/gpt-5.4-mini";
```

- [ ] **Step 4: Run focused and repository contract verification**

Run:

```bash
tests/pi-managed-hooks.sh
tests/tmux-label-contract.sh
git diff --check
```

Expected: all tests exit 0 and `git diff --check` emits no output.

- [ ] **Step 5: Provision and exercise the deployed child**

Run `bin/provision`, then invoke Pi with the same model and isolation flags used by `evaluateSessionGoal`:

```bash
pi --mode text --print --no-session \
  --model openai/gpt-5.4-mini --thinking off \
  --no-tools --no-extensions --no-skills --no-prompt-templates \
  --no-themes --no-context-files --no-approve \
  --system-prompt "Output only KEEP" \
  $'Current goal: test\nNew user prompt: test'
```

Expected: exit 0 and exactly `KEEP` on stdout.

- [ ] **Step 6: Commit implementation**

Commit `roles/common/files/pi/extensions/managed-hooks.ts` and `tests/pi-managed-hooks.sh` with an imperative message explaining the credential-path fix.
