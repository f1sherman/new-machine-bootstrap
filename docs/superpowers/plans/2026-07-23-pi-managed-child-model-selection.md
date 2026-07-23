# Pi Managed Child Model Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route both managed Pi child tasks through Codex subscription authentication when available and the OpenAI API-key provider otherwise.

**Architecture:** Replace the fixed model constant with a synchronous shared resolver in `managed-hooks.ts`. The resolver honors an environment override, inspects Pi's canonical auth file, and caches the selection by a metadata signature that changes on rewrite or atomic replacement.

**Tech Stack:** TypeScript Pi extension, Node.js contract tests, Bash test harness, Ansible provisioning

## Global Constraints

- Codex OAuth model: `openai-codex/gpt-5.4-mini`.
- OpenAI API-key model: `openai/gpt-4.1-mini`.
- Manual override: non-empty `PI_MANAGED_CHILD_MODEL`.
- Missing, malformed, unreadable, incomplete, or non-OAuth Codex auth selects the OpenAI model.
- Do not log auth contents or credentials.
- Preserve existing child prompts, isolation flags, thinking settings, timeouts, output validation, queueing, and failure handling.
- Do not add network preflight checks or provider fallback retries.

---

### Task 1: Resolve and cache the managed child model

**Files:**
- Modify: `tests/pi-managed-hooks.sh:10-165,416-563`
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts:1-16,510-535,673-687`

**Interfaces:**
- Consumes: `process.env.PI_MANAGED_CHILD_MODEL`, `process.env.HOME`, and `~/.pi/agent/auth.json`.
- Produces: `managedChildModel(): string`, returning the override, `openai-codex/gpt-5.4-mini`, or `openai/gpt-4.1-mini`.
- Cache key: auth-file `dev`, `ino`, `size`, `mtimeMs`, and `ctimeMs`; missing state uses a stable sentinel.

- [ ] **Step 1: Add failing model-selection and cache tests**

Before importing the extension, point `HOME` at the test root and create `.pi/agent`. Add fixture helpers that write, replace, remove, and chmod `auth.json`. Wrap `fs.readFileSync` with an auth-path counter, restoring it in the existing cleanup path.

Exercise both managed-child call sites and assert these exact outcomes:

```javascript
assert.equal(modelArg(subjectCall), "openai-codex/gpt-5.4-mini");
assert.equal(modelArg(goalChildCalls.at(-1)), "openai-codex/gpt-5.4-mini");
assert.equal(authReadCount, 1, "unchanged auth metadata reuses parsed selection");
assert.equal(modelArg(callAfterAuthRemoval), "openai/gpt-4.1-mini");
assert.equal(modelArg(callAfterMalformedAuth), "openai/gpt-4.1-mini");
assert.equal(modelArg(callAfterIncompleteOAuth), "openai/gpt-4.1-mini");
assert.equal(modelArg(callAfterNonOAuthAuth), "openai/gpt-4.1-mini");
assert.equal(modelArg(callAfterAtomicReplacement), "openai-codex/gpt-5.4-mini");
process.env.PI_MANAGED_CHILD_MODEL = "custom-provider/custom-model";
assert.equal(modelArg(callWithOverride), "custom-provider/custom-model");
```

Use a complete authenticated fixture:

```json
{
  "openai-codex": {
    "type": "oauth",
    "access": "test-access",
    "refresh": "test-refresh",
    "expires": 0
  }
}
```

The `expires: 0` case proves an expired access token remains eligible when refresh data exists. For unreadable auth, accept a read failure induced through the wrapped `readFileSync`, avoiding platform-dependent chmod behavior.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: FAIL because the extension still passes fixed `openai/gpt-5.4-mini`, does not inspect auth, and does not honor the override.

- [ ] **Step 3: Implement the minimal cached resolver**

Replace `SUBJECT_CHILD_MODEL` with:

```typescript
const CODEX_MANAGED_CHILD_MODEL = "openai-codex/gpt-5.4-mini";
const OPENAI_MANAGED_CHILD_MODEL = "openai/gpt-4.1-mini";
const MANAGED_CHILD_MODEL_OVERRIDE = "PI_MANAGED_CHILD_MODEL";
let cachedManagedChildAuthSignature;
let cachedManagedChildModel = OPENAI_MANAGED_CHILD_MODEL;
```

Add focused helpers:

```typescript
function managedChildAuthPath() {
  return path.join(process.env.HOME || "", ".pi", "agent", "auth.json");
}

function managedChildAuthSignature(authPath) {
  try {
    const stat = fs.statSync(authPath);
    return [stat.dev, stat.ino, stat.size, stat.mtimeMs, stat.ctimeMs].join(":");
  } catch {
    return "missing";
  }
}

function hasCodexOAuth(auth) {
  const credential = auth?.["openai-codex"];
  return credential?.type === "oauth"
    && typeof credential.access === "string" && credential.access.length > 0
    && typeof credential.refresh === "string" && credential.refresh.length > 0;
}

function managedChildModel() {
  const override = process.env[MANAGED_CHILD_MODEL_OVERRIDE]?.trim();
  if (override) return override;

  const authPath = managedChildAuthPath();
  const signature = managedChildAuthSignature(authPath);
  if (signature === cachedManagedChildAuthSignature) return cachedManagedChildModel;

  cachedManagedChildAuthSignature = signature;
  try {
    const auth = JSON.parse(fs.readFileSync(authPath, "utf8"));
    cachedManagedChildModel = hasCodexOAuth(auth)
      ? CODEX_MANAGED_CHILD_MODEL
      : OPENAI_MANAGED_CHILD_MODEL;
  } catch {
    cachedManagedChildModel = OPENAI_MANAGED_CHILD_MODEL;
  }
  return cachedManagedChildModel;
}
```

Resolve `const model = managedChildModel();` immediately before each `pi.exec` and use `"--model", model` in both `setSubjectFromSubagent` and `evaluateSessionGoal`.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: exit 0 with `pi-managed-hooks checks complete`.

- [ ] **Step 5: Refactor fixtures and resolver names while staying green**

Remove duplicated fixture setup, keep helper names specific to managed-child model selection, and ensure test cleanup restores environment variables and patched filesystem methods.

Run:

```bash
bash tests/pi-managed-hooks.sh
git diff --check
```

Expected: both commands exit 0; `git diff --check` emits no output.

- [ ] **Step 6: Commit implementation**

Commit `roles/common/files/pi/extensions/managed-hooks.ts` and `tests/pi-managed-hooks.sh` with an imperative message describing auth-aware managed-child routing.

---

### Task 2: Verify and deploy the selected provider behavior

**Files:**
- Verify only: `roles/common/files/pi/extensions/managed-hooks.ts`
- Verify only: `tests/pi-managed-hooks.sh`

**Interfaces:**
- Consumes: the completed `managedChildModel()` implementation.
- Produces: deployed `~/.pi/agent/extensions/managed-hooks.ts` and end-to-end evidence for the selected models available on this machine.

- [ ] **Step 1: Run repository contract verification**

Run:

```bash
bash tests/pi-managed-hooks.sh
bash tests/tmux-label-contract.sh
git diff --check
```

Expected: all commands exit 0, with no assertion failures or whitespace errors.

- [ ] **Step 2: Provision from the feature worktree**

Run:

```bash
bin/provision
```

Expected: exit 0 and the managed-hooks installation task deploys the feature-worktree source.

- [ ] **Step 3: Verify deployed source identity**

Run:

```bash
cmp roles/common/files/pi/extensions/managed-hooks.ts "$HOME/.pi/agent/extensions/managed-hooks.ts"
```

Expected: exit 0 with no output.

- [ ] **Step 4: Exercise available child providers directly**

Confirm this machine's Codex OAuth entry has non-empty `access` and `refresh` fields without printing their values, then run the isolated child command with `openai-codex/gpt-5.4-mini`. If OpenAI API-key auth is available, run the same command with `openai/gpt-4.1-mini`.

```bash
pi --mode text --print --no-session \
  --model MODEL --thinking off \
  --no-tools --no-extensions --no-skills --no-prompt-templates \
  --no-themes --no-context-files --no-approve \
  --system-prompt "Output only KEEP" \
  $'Current goal: test\nNew user prompt: test'
```

Expected for each available provider: exit 0 and exactly `KEEP` on stdout. Report an unavailable credential path as untested rather than successful.

- [ ] **Step 5: Run final verification and inspect the diff**

Run:

```bash
bash tests/pi-managed-hooks.sh
bash tests/tmux-label-contract.sh
git diff --check
git status --short
git diff HEAD^ -- roles/common/files/pi/extensions/managed-hooks.ts tests/pi-managed-hooks.sh
```

Expected: tests exit 0, no whitespace errors, only intended implementation/test changes beyond committed spec and plan.

- [ ] **Step 6: Commit any verification-driven fixes**

If verification required source or test changes, commit them atomically. Otherwise leave the existing implementation commit unchanged and proceed to PR creation.
