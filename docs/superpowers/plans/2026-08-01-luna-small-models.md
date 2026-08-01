# Luna Small Models Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Use GPT-5.6 Luna for managed lightweight Pi child tasks while preserving provider selection based on authentication.

**Architecture:** Keep the existing model-selection function and authentication cache unchanged. Replace only the two provider-specific model constants and update the focused integration test expectations that exercise Codex OAuth preference, OpenAI fallback, and explicit override behavior.

**Tech Stack:** TypeScript Pi extension, Node.js integration test harness, Bash, Ansible

## Global Constraints

- Use `openai-codex/gpt-5.6-luna` when usable Codex OAuth credentials exist.
- Use `openai/gpt-5.6-luna` when Codex OAuth is unavailable or unusable.
- Keep `openai-codex` preferred and keep the existing authentication selection logic unchanged.
- Do not edit historical specifications, historical plans, generated artifacts, other worktrees, or unrelated Claude agent model settings.
- Do not add compatibility detection, a configuration option, or a shared abstraction.

---

### Task 1: Replace Managed Lightweight Models

**Files:**
- Modify: `tests/pi-managed-hooks.sh:619-861`
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts:6-7`

**Interfaces:**
- Consumes: Existing `selectManagedChildModel()` behavior and `PI_MANAGED_CHILD_MODEL` override.
- Produces: Provider-qualified Luna model identifiers passed through the existing Pi child argument builder.

- [ ] **Step 1: Change focused test expectations to Luna**

Replace each current expected managed model string in `tests/pi-managed-hooks.sh`:

```text
openai-codex/gpt-5.4-mini -> openai-codex/gpt-5.6-luna
openai/gpt-4.1-mini       -> openai/gpt-5.6-luna
```

Keep the `custom-provider/custom-model` override expectation unchanged.

- [ ] **Step 2: Run the focused test to verify RED**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: FAIL because the extension still supplies `openai-codex/gpt-5.4-mini` or `openai/gpt-4.1-mini` while the assertions require Luna.

- [ ] **Step 3: Change the production constants to Luna**

In `roles/common/files/pi/extensions/managed-hooks.ts`, use:

```typescript
const CODEX_MANAGED_CHILD_MODEL = "openai-codex/gpt-5.6-luna";
const OPENAI_MANAGED_CHILD_MODEL = "openai/gpt-5.6-luna";
```

Do not change model selection, authentication inspection, caching, failure handling, or override behavior.

- [ ] **Step 4: Run focused verification to verify GREEN**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: exit 0 with `pi-managed-hooks checks complete`.

- [ ] **Step 5: Confirm no active small-model identifiers remain**

Run:

```bash
rg -n 'openai-codex/gpt-5\.4-mini|openai/gpt-4\.1-mini' \
  roles tests \
  --glob '!docs/superpowers/**'
```

Expected: no output and exit 1.

- [ ] **Step 6: Run repository and provisioning verification**

Run every `run:` command from `.github/workflows/integration-test.yml` that is valid on the current macOS host, then run:

```bash
bin/provision
bin/provision --check
```

Expected: all applicable integration commands exit 0; provisioning exits 0; check mode reports no failed tasks and no changes.

- [ ] **Step 7: Commit the implementation**

```bash
~/.pi/agent/skills/z-commit/commit.sh \
  -m "Use Luna for lightweight Pi children" \
  roles/common/files/pi/extensions/managed-hooks.ts \
  tests/pi-managed-hooks.sh
```
