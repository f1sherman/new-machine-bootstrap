# Pi Attention Bell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an NMB-managed global Pi extension that emits a terminal BEL whenever Pi is waiting for Brian's input.

**Architecture:** The common role will install a new global Pi extension into `~/.pi/agent/extensions/`. The extension emits BEL on `agent_end` and wraps Pi's documented blocking UI methods to emit BEL before extension prompts. Tests cover the extension behavior directly and provisioning wiring; the live Ghostty bounce is verified manually in a real Pi session.

**Tech Stack:** Ansible common role, Pi TypeScript extension API, Bash/Node test harnesses, GitHub Actions integration-test workflow.

## Global Constraints

- Manage the source in NMB; do not edit deployed files in `~/.pi/agent/extensions/` directly.
- Emit BEL (`\x07`) as the attention primitive.
- Do not emit OSC 9, OSC 777, macOS notification commands, `notify-send`, or other desktop notification integrations.
- Apply globally to every Pi session managed by this repo.
- The UI-method wrapper must be idempotent and fail-open.
- Include end-to-end validation for both `agent_end` and extension prompt coverage.

---

## File Structure

- `roles/common/files/pi/extensions/pi-attention-bell.ts`: new Pi extension. Single responsibility: request terminal attention on Pi user-input wait points.
- `roles/common/tasks/main.yml`: install the new extension into `~/.pi/agent/extensions/` next to `managed-hooks.ts`.
- `tests/pi-attention-bell.sh`: CI-safe behavior/provisioning contract test. Imports the extension with mocked Pi contexts and asserts BEL, wrapper idempotency, fail-open behavior, and no desktop notification implementation.
- `.github/workflows/integration-test.yml`: run the CI-safe contract test. Do not run local/live bounce proof in CI.

---

### Task 1: Add the Pi attention bell extension and behavior contract test

**Files:**
- Create: `roles/common/files/pi/extensions/pi-attention-bell.ts`
- Create: `tests/pi-attention-bell.sh`

**Interfaces:**
- Consumes: Pi extension API object with `on(event, handler)`.
- Produces: default export `piAttentionBell(pi)` registering `agent_end` and `session_start` handlers.
- Produces: `requestAttention()` internal helper that writes exactly one BEL byte per call when stdout is a TTY, and skips non-interactive stdout.
- Produces: wrapped `ctx.ui.select`, `confirm`, `input`, `editor`, and `custom` methods that call the original methods with original `this` and arguments.

- [ ] **Step 1: Write the failing behavior test**

Create `tests/pi-attention-bell.sh` with this content:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
EXTENSION="$REPO_ROOT/roles/common/files/pi/extensions/pi-attention-bell.ts"
TASKS="$REPO_ROOT/roles/common/tasks/main.yml"

if [ ! -f "$EXTENSION" ]; then
  echo "missing extension: $EXTENSION" >&2
  exit 1
fi

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

cp "$EXTENSION" "$TMPROOT/pi-attention-bell.mjs"

node_cmd=(node)
if ! command -v node >/dev/null 2>&1; then
  mise_bin="${MISE_BIN:-$HOME/.local/bin/mise}"
  node_version="$(yq -r '.tool_versions.runtimes.node' "$REPO_ROOT/vars/tool_versions.yml")"
  node_cmd=("$mise_bin" exec "node@$node_version" -- node)
fi

if ! grep -F 'src: pi/extensions/pi-attention-bell.ts' "$TASKS" >/dev/null; then
  echo "main.yml does not install pi-attention-bell.ts" >&2
  exit 1
fi

if grep -E 'osascript|display notification|terminal-notifier|notify-send|zenity|OSC 9|OSC 777|]9;|]777;' "$EXTENSION" >/dev/null; then
  echo "extension must not use desktop notifications or OSC notification sequences" >&2
  exit 1
fi

cat >"$TMPROOT/check.mjs" <<'NODE'
import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

const extensionPath = process.argv[2];
const { default: install } = await import(pathToFileURL(extensionPath));

const handlers = new Map();
const pi = {
  on(event, handler) {
    handlers.set(event, handler);
  },
};

let captured = "";
const originalWrite = process.stdout.write;
process.stdout.write = (chunk, encoding, callback) => {
  captured += String(chunk);
  if (typeof encoding === "function") encoding();
  if (typeof callback === "function") callback();
  return true;
};

try {
  install(pi);

  assert.equal(typeof handlers.get("agent_end"), "function", "registers agent_end handler");
  assert.equal(typeof handlers.get("session_start"), "function", "registers session_start handler");

  await handlers.get("agent_end")({}, {});
  Object.defineProperty(process.stdout, "isTTY", { configurable: true, value: true });
  assert.equal(captured, "\x07", "agent_end emits one BEL when stdout is a TTY");

  captured = "";
  const calls = [];
  const ui = {
    async select(...args) { calls.push(["select", this, args]); return "choice"; },
    async confirm(...args) { calls.push(["confirm", this, args]); return true; },
    async input(...args) { calls.push(["input", this, args]); return "value"; },
    async editor(...args) { calls.push(["editor", this, args]); return "edited"; },
    async custom(...args) { calls.push(["custom", this, args]); return "custom"; },
    notify() { throw new Error("notify should not be wrapped"); },
  };
  const ctx = { ui };

  await handlers.get("session_start")({}, ctx);
  await handlers.get("session_start")({}, ctx);

  assert.equal(await ui.select("Pick", ["A"]), "choice");
  assert.equal(await ui.confirm("Confirm", "Message"), true);
  assert.equal(await ui.input("Input", "hint text"), "value");
  assert.equal(await ui.editor("Editor", "prefill"), "edited");
  assert.equal(await ui.custom(() => ({})), "custom");

  assert.equal(captured, "\x07\x07\x07\x07\x07", "each blocking UI method emits one BEL after idempotent wrapping");
  assert.deepEqual(calls.map((call) => call[0]), ["select", "confirm", "input", "editor", "custom"]);
  assert.ok(calls.every((call) => call[1] === ui), "wrappers preserve original this binding");

  captured = "";
  const badCtx = { ui: null };
  await handlers.get("session_start")({}, badCtx);
  assert.equal(captured, "", "bad UI context fails open without BEL spam");

  console.log("pi-attention-bell checks complete");
} finally {
  process.stdout.write = originalWrite;
}
NODE

"${node_cmd[@]}" "$TMPROOT/check.mjs" "$TMPROOT/pi-attention-bell.mjs"
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
bash tests/pi-attention-bell.sh
```

Expected: FAIL with `missing extension: .../roles/common/files/pi/extensions/pi-attention-bell.ts`.

- [ ] **Step 3: Add the minimal extension implementation**

Create `roles/common/files/pi/extensions/pi-attention-bell.ts` with this content:

```typescript
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const WRAPPED_MARKER = Symbol.for("nmb.piAttentionBell.wrappedUi");
const ATTENTION_METHODS = ["select", "confirm", "input", "editor", "custom"] as const;

type AttentionMethod = (typeof ATTENTION_METHODS)[number];
type UiWithMarker = Record<string | symbol, unknown>;

function requestAttention(): void {
  try {
    if (!process.stdout.isTTY) return;

    process.stdout.write("\x07");
  } catch {
    // Attention must never break Pi interaction.
  }
}

function wrapUiMethod(ui: UiWithMarker, methodName: AttentionMethod): void {
  const original = ui[methodName];
  if (typeof original !== "function") return;

  ui[methodName] = function wrappedAttentionMethod(this: unknown, ...args: unknown[]) {
    requestAttention();
    return original.apply(this, args);
  };
}

function wrapAttentionUi(ui: unknown): void {
  try {
    if (!ui || typeof ui !== "object") return;

    const mutableUi = ui as UiWithMarker;
    if (mutableUi[WRAPPED_MARKER]) return;

    for (const methodName of ATTENTION_METHODS) {
      wrapUiMethod(mutableUi, methodName);
    }

    mutableUi[WRAPPED_MARKER] = true;
  } catch {
    // Fail open: Pi should keep working even if its UI object changes.
  }
}

export default function piAttentionBell(pi: ExtensionAPI) {
  pi.on("agent_end", async () => {
    requestAttention();
  });

  pi.on("session_start", async (_event, ctx) => {
    wrapAttentionUi(ctx.ui);
  });
}
```

- [ ] **Step 4: Run test to verify it now fails only on provisioning wiring**

Run:

```bash
bash tests/pi-attention-bell.sh
```

Expected: FAIL with `main.yml does not install pi-attention-bell.ts`.

- [ ] **Step 5: Commit extension and behavior test**

Run:

```bash
bash ~/.local/share/skills/_commit/commit.sh -m "Add Pi attention bell extension" roles/common/files/pi/extensions/pi-attention-bell.ts tests/pi-attention-bell.sh
```

Expected: one commit containing the extension and its behavior test.

---

### Task 2: Install the extension via the common role and add CI coverage

**Files:**
- Modify: `roles/common/tasks/main.yml`
- Modify: `.github/workflows/integration-test.yml`

**Interfaces:**
- Consumes: `roles/common/files/pi/extensions/pi-attention-bell.ts` from Task 1.
- Produces: Ansible task installing it to `{{ ansible_facts['user_dir'] }}/.pi/agent/extensions/pi-attention-bell.ts` with mode `0644`.
- Produces: GitHub Actions step running `bash tests/pi-attention-bell.sh`.

- [ ] **Step 1: Add the failing CI/provisioning expectation is already present**

Run:

```bash
bash tests/pi-attention-bell.sh
```

Expected: FAIL with `main.yml does not install pi-attention-bell.ts`.

- [ ] **Step 2: Add the Ansible install task**

In `roles/common/tasks/main.yml`, immediately after the existing task named `Install managed pi-coding-agent hooks`, add:

```yaml
- name: Install managed pi-coding-agent attention bell extension
  copy:
    src: pi/extensions/pi-attention-bell.ts
    dest: "{{ ansible_facts['user_dir'] }}/.pi/agent/extensions/pi-attention-bell.ts"
    mode: '0644'
```

- [ ] **Step 3: Run the test to verify provisioning wiring passes locally**

Run:

```bash
bash tests/pi-attention-bell.sh
```

Expected: PASS with `pi-attention-bell checks complete`.

- [ ] **Step 4: Add the CI workflow step**

In `.github/workflows/integration-test.yml`, add this step after the existing `Run Pi managed hooks tests` step:

```yaml
      - name: Run Pi attention bell tests
        run: bash tests/pi-attention-bell.sh
```

- [ ] **Step 5: Verify the workflow edit is syntactically placed**

Run:

```bash
ruby -ryaml -e 'YAML.load_file(".github/workflows/integration-test.yml"); puts "workflow yaml ok"'
```

Expected: PASS with `workflow yaml ok`.

- [ ] **Step 6: Commit provisioning and CI wiring**

Run:

```bash
bash ~/.local/share/skills/_commit/commit.sh -m "Install Pi attention bell extension" roles/common/tasks/main.yml .github/workflows/integration-test.yml
```

Expected: one commit containing only Ansible and workflow wiring.

---

### Task 3: Perform manual live Ghostty bounce proof

**Files:** none

**Interfaces:**
- Consumes: installed or CLI-loaded `roles/common/files/pi/extensions/pi-attention-bell.ts`.
- Produces: manual verification evidence that Ghostty bounces when the live Pi session emits BEL.

- [ ] **Step 1: Verify Ghostty handles BEL**

Run `sleep 3; printf '\a'`, switch away from Ghostty during the sleep, and confirm the app bounces.

- [ ] **Step 2: Verify live Pi completion bounces Ghostty**

Load the extension into a real Pi session, switch away from Ghostty while a short prompt runs, and confirm Ghostty bounces when Pi returns to input.

Expected: manual proof recorded in the PR notes; no committed pseudo-terminal helper.

### Task 4: Final verification, provisioning check, and PR

**Files:**
- No required code changes.
- Update PR description with verification commands and manual live bounce result.

**Interfaces:**
- Consumes: all commits from Tasks 1-3.
- Produces: verified branch pushed to origin with PR opened.

- [ ] **Step 1: Run the CI-safe test subset touched by this change**

Run:

```bash
bash tests/pi-attention-bell.sh
ruby -ryaml -e 'YAML.load_file(".github/workflows/integration-test.yml"); puts "workflow yaml ok"'
```

Expected: both commands pass.

- [ ] **Step 2: Perform the live bounce proof**

Run:

```bash
manual live Ghostty bounce proof
```

Expected: Ghostty bounces when the live Pi session emits BEL.

- [ ] **Step 3: Run a targeted Ansible check for the local host if practical**

Run:

```bash
bin/provision --check --diff
```

Expected: completes successfully. If it is too broad or environment-specific, record the reason in the PR and rely on the static install test plus manual live bounce proof.

- [ ] **Step 4: Confirm the branch is clean and ahead**

Run:

```bash
git status --short --branch
git log --oneline origin/main..HEAD
```

Expected: clean working tree and commits for spec, plan, implementation, tests, and provisioning.

- [ ] **Step 5: Push and open PR**

Use the repo PR workflow. The PR description must include:

- Summary of the extension and BEL behavior.
- Verification commands and results.
- Whether `bin/provision --check --diff` was run or why it was skipped.
- Note whether the manual live Ghostty bounce proof passed.

Expected: PR opened; do not merge.

---

## Plan Self-Review

- Spec coverage: extension source, Ansible installation, BEL-only behavior, fail-open/idempotent wrapping, static tests, manual live bounce proof, and PR verification are all covered.
- Completion scan: no incomplete-marker steps remain; code and commands are explicit.
- Type consistency: `piAttentionBell`, `requestAttention`, `wrapAttentionUi`, and `pi.on("agent_end"|"session_start")` names are consistent across tasks.
