# Pi Managed Background Jobs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Pi start allowlisted provisioning and full-test commands as managed background jobs, restrict the agent to read-only work, and automatically continue when the job ends.

**Architecture:** Override Pi's built-in `bash` tool with a sequential wrapper. The wrapper delegates ordinary commands unchanged and starts strict allowlist matches through an injected process adapter. Process-global state holds one job across extension reload, while active-tool filtering and a `tool_call` hook enforce the read-only boundary.

**Tech Stack:** TypeScript Pi extension API 0.84.2, Node.js child processes and file APIs, Bash behavioral test harness, Ansible, GitHub Actions.

## Global Constraints

- Support only `bin/provision`, `bin/test`, and `bin/test-ruby`, including `./` forms and the strict SSH form in the design.
- Keep nonmatches synchronous through Pi's built-in Bash tool.
- Permit only `read`, `grep`, `find`, and `ls` while one managed job is active.
- Set the replacement Bash tool to `executionMode: "sequential"`.
- Keep one managed job per Pi process and preserve it across `/reload`.
- Terminate the process group on explicit cancel or normal Pi quit.
- Block session switch and fork while a managed job is active.
- Store full output in a mode `0600` log below a mode `0700` temporary directory.
- Inject a bounded completion message with `triggerTurn: true` and `deliverAs: "steer"`.
- Do not add an external package dependency.
- Do not change user-entered `!` or `!!` commands.

---

### Task 1: Managed job classifier and lifecycle

**Files:**
- Create: `roles/common/files/pi/extensions/managed-background-jobs.ts`
- Create: `tests/pi-managed-background-jobs.sh`

**Interfaces:**
- Consumes: `createBashToolDefinition(cwd)` from `@earendil-works/pi-coding-agent` and Pi extension lifecycle APIs.
- Produces: default extension installer; strict internal `classifyManagedCommand(command)`; adapter seam at `Symbol.for("nmb.pi-managed-background-jobs.adapters")`; process state at `Symbol.for("nmb.pi-managed-background-jobs.process-state")`.
- Job state fields: `id`, `child`, `pid`, `command`, `cwd`, `startedAt`, `logPath`, `savedActiveTools`, `finished`, and `controller`.

- [ ] **Step 1: Write the failing behavioral harness**

Create a Bash harness that copies the TypeScript extension to a temporary `.mjs`
file and imports it with controlled adapters. The fake Pi API must record tool
registration, active-tool changes, custom messages, commands, and lifecycle
handlers. The fake child must expose `emitExit(code, signal)` and record process
group termination.

The test must contain assertions equivalent to:

```javascript
assert.equal(classify("bin/provision --limit dev"), true);
assert.equal(classify("./bin/test ci"), true);
assert.equal(classify("bin/test-ruby"), true);
assert.equal(classify("ssh dev 'bin/provision --tags common_role'"), true);
assert.equal(classify("ssh dev 'cd /repo && ./bin/test ci'"), true);
assert.equal(classify("bin/provision | tee /tmp/log"), false);
assert.equal(classify("env CI=1 bin/test"), false);
assert.equal(classify("bin/test $(date)"), false);
assert.equal(classify("ssh dev 'bin/test; rm -rf /tmp/x'"), false);
assert.equal(registeredBash.executionMode, "sequential");
```

Start a controlled managed job and assert:

```javascript
const pending = controlledChild();
adapters.spawnQueue.push(pending);
const result = await registeredBash.execute(
  "call-1",
  { command: "bin/provision --limit dev" },
  undefined,
  undefined,
  context,
);
assert.match(result.content[0].text, /Managed background job bg-1 started/);
assert.deepEqual(pi.activeToolChanges.at(-1), ["read", "grep", "find", "ls"]);
assert.equal(pending.completed, false);
```

Also assert that a normal command delegates once to the built-in Bash adapter,
that a second managed start fails, and that the active `tool_call` hook blocks
`write`, `edit`, `bash`, and an unknown custom tool but allows the four read-only
tools.

Drive controlled exits for code `0`, nonzero code, and signal exit. Assert exact
tool restoration, one bounded completion message, `triggerTurn: true`,
`deliverAs: "steer"`, duration, log path, and tail. Cover cancel, reload,
session switch, fork, normal quit, environment injection, spawn failure, and log
failure. Assert that cancellation and exit races restore tools once.

- [ ] **Step 2: Run the harness to verify RED**

Run:

```bash
bash tests/pi-managed-background-jobs.sh
```

Expected: FAIL because
`roles/common/files/pi/extensions/managed-background-jobs.ts` does not exist.

- [ ] **Step 3: Implement the strict classifier**

Create a shell-word tokenizer that returns `undefined` for unquoted control
operators, command substitutions, backticks, redirections, incomplete quotes,
or trailing escapes. Use it to implement these exact decisions:

```typescript
const MANAGED_EXECUTABLES = new Set([
  "bin/provision", "./bin/provision",
  "bin/test", "./bin/test",
  "bin/test-ruby", "./bin/test-ruby",
]);

type ManagedClassification =
  | { kind: "local"; words: string[] }
  | { kind: "ssh"; words: string[]; remoteCommand: string }
  | undefined;

function classifyManagedCommand(command: string): ManagedClassification;
```

For SSH, accept only narrow connection flags and the value options `-b`, `-c`,
`-e`, `-F`, `-i`, `-l`, `-m`, and `-p`. Reject caller-supplied `-o` options,
X11 forwarding, tunnels, proxy options, and control-master options. Require an
explicit `-F /dev/null` and one IP destination. Commands that need user SSH
configuration stay synchronous. Join the remaining words as the remote command
only after the local tokenizer has established safe word boundaries. Preserve
backslashes that remain literal inside local double quotes. Accept either an
allowlisted executable or `cd PATH &&` followed by one allowlisted executable.
Reject any other remote control syntax.

Export the classifier only as a named test seam. The default export remains the
Pi extension installer.

- [ ] **Step 4: Implement adapters and process-global state**

Use these adapter operations so the harness controls all side effects:

```typescript
interface ManagedJobAdapters {
  now(): number;
  randomId(): string;
  makeLog(sessionId: string, jobId: string): {
    path: string;
    fd: number;
  };
  spawn(command: string, options: {
    cwd: string;
    env: NodeJS.ProcessEnv;
    logFd: number;
  }): ChildProcess;
  readTail(path: string, maxBytes: number): Promise<string>;
  close(fd: number): void;
  killProcessGroup(pid: number, signal: NodeJS.Signals): void;
  setTimeout(callback: () => void, milliseconds: number): unknown;
  clearTimeout(timer: unknown): void;
  warn(message: string): void;
}
```

The production adapter must create the private log directory, open a `0600`
file, run the shell with `-lc`, set `detached: true`, close stdin, send both
output streams to the log, and call `unref()`.

Resolve Pi session environment values from `ctx.sessionManager`, `ctx.model`, and
`ctx.thinkingLevel` immediately before spawn. Remove stale inherited `PI_*`
session variables before adding current values.

Store shared state under `Symbol.for(...)`. Keep mutable controller callbacks in
the shared state so a reloaded extension can replace them without replacing the
child exit listener.

- [ ] **Step 5: Implement the sequential Bash override and read-only gate**

Create the built-in definition once and register a wrapper:

```typescript
const builtIn = createBashToolDefinition(process.cwd());
pi.registerTool({
  ...builtIn,
  executionMode: "sequential",
  async execute(toolCallId, params, signal, onUpdate, ctx) {
    const classification = classifyManagedCommand(params.command);
    if (!classification) {
      return builtIn.execute(toolCallId, params, signal, onUpdate, ctx);
    }
    return startManagedJob(params.command, ctx);
  },
});
```

Use the extension installation working directory, not a later session directory,
in the built-in definition. On successful spawn, save `pi.getActiveTools()` and
set only the intersection with `read`, `grep`, `find`, and `ls`.

Register a `tool_call` handler that returns this result for every other tool while
a job is active:

```typescript
{
  block: true,
  reason: "A managed background job is active. Only read-only inspection tools are available.",
  terminate: false,
}
```

- [ ] **Step 6: Implement completion, cancellation, and lifecycle hooks**

Use one idempotent `finishJob` path for child exit and spawn errors. Restore the
saved tools once. Read at most 16 KiB from the end of the log and cap the injected
text at 200 lines. Call:

```typescript
pi.sendMessage({
  customType: "managed-background-job-complete",
  content: completionText,
  display: true,
  details: completionDetails,
}, {
  triggerTurn: true,
  deliverAs: "steer",
});
```

Register `/background-jobs` and `/background-cancel`. Cancellation sends
`SIGTERM` to `-pid`, then schedules `SIGKILL` after five seconds if the same job
is still active.

Return `{ cancel: true }` from `session_before_switch` and
`session_before_fork` while a job is active. On `session_start`, replace the
shared controller and reapply the gate when a job survived reload. On
`session_shutdown`, preserve the child for `reload`; terminate it for `quit`,
`new`, `resume`, and `fork`.

- [ ] **Step 7: Run focused tests to verify GREEN**

Run:

```bash
bash tests/pi-managed-background-jobs.sh
```

Expected: PASS with a final line:
`Pi managed background job checks complete`.

- [ ] **Step 8: Commit the feature unit**

Commit only:

```text
roles/common/files/pi/extensions/managed-background-jobs.ts
tests/pi-managed-background-jobs.sh
```

Use commit message:

```text
Add managed Pi background jobs
```

---

### Task 2: Provisioning and CI integration

**Files:**
- Modify: `roles/common/tasks/main.yml:1517-1541`
- Modify: `.github/workflows/integration-test.yml:85-92`

**Interfaces:**
- Consumes: `roles/common/files/pi/extensions/managed-background-jobs.ts` and `tests/pi-managed-background-jobs.sh` from Task 1.
- Produces: managed extension at `~/.pi/agent/extensions/managed-background-jobs.ts` on common-role hosts and a required CI behavioral test step.

This declarative integration does not get a source-presence test. Such a test
would restate Ansible and CI configuration and would violate the repository test
policy. `bin/provision` and the workflow execution are the correct verification.

- [ ] **Step 1: Add the Ansible copy task**

Add this task next to the other managed Pi extension copy tasks:

```yaml
- name: Install Pi managed background jobs extension
  copy:
    src: pi/extensions/managed-background-jobs.ts
    dest: "{{ ansible_facts['user_dir'] }}/.pi/agent/extensions/managed-background-jobs.ts"
    mode: '0644'
```

- [ ] **Step 2: Add the CI step**

Add this step after the managed-hooks test:

```yaml
- name: Verify Pi managed background jobs
  run: bash tests/pi-managed-background-jobs.sh
```

- [ ] **Step 3: Run focused tests after integration**

Run:

```bash
bash tests/pi-managed-background-jobs.sh
```

Expected: PASS. This confirms that the integration edit did not change extension
behavior.

- [ ] **Step 4: Commit integration**

Commit only:

```text
roles/common/tasks/main.yml
.github/workflows/integration-test.yml
```

Use commit message:

```text
Provision managed Pi background jobs
```

---

### Task 3: End-to-end verification and rollout

**Files:**
- Modify only if verification finds a valid defect in files from Tasks 1 or 2.

**Interfaces:**
- Consumes: complete extension and integration from Tasks 1 and 2.
- Produces: verified branch and deployed extension on the local machine and `dev`.

- [ ] **Step 1: Run focused behavior verification**

Run:

```bash
bash tests/pi-managed-background-jobs.sh
bash tests/pi-managed-hooks.sh
bash tests/pi-main-worktree-guard.sh
```

Expected: all commands exit `0`.

- [ ] **Step 2: Run repository CI verification**

Run:

```bash
bin/test ci
```

Expected: exit `0`. If this repository has no `bin/test`, run the exact local
commands from the `Integration Test` workflow that are applicable to changed
files, plus `bin/provision` as the repository integration entry point.

- [ ] **Step 3: Provision the local machine**

Run from this worktree:

```bash
bin/provision
```

Expected: exit `0` and install
`~/.pi/agent/extensions/managed-background-jobs.ts`.

- [ ] **Step 4: Provision dev**

Run from this worktree:

```bash
bin/provision --limit dev
```

Expected: exit `0` and install the same extension for the managed user on `dev`.

- [ ] **Step 5: Verify deployed files**

Run local and remote checksum checks against the worktree source. Use `ssh dev`
for the remote read. Confirm all three SHA-256 values are equal.

```bash
shasum -a 256 \
  roles/common/files/pi/extensions/managed-background-jobs.ts \
  "$HOME/.pi/agent/extensions/managed-background-jobs.ts"
ssh dev shasum -a 256 \
  '$HOME/.pi/agent/extensions/managed-background-jobs.ts'
```

Expected: one identical digest for the source, local installation, and dev
installation.

- [ ] **Step 6: Review the complete diff**

Run:

```bash
git diff --check origin/main...HEAD
git status --short
git diff --stat origin/main...HEAD
```

Expected: no whitespace errors and a clean worktree.

- [ ] **Step 7: Commit verification fixes only when needed**

If verification required a code correction, rerun the affected checks and commit
only that correction with an imperative message. If no file changed, do not
create an empty commit.

## Plan self-review

- Spec coverage: Tasks 1 through 3 cover classification, delegation, sequential
  execution, process state, logs, environment, gating, lifecycle, completion,
  tests, installation, CI, local rollout, and dev rollout.
- Scope: One extension and its direct integration form one coherent release.
- Test value: The harness executes production state transitions and protects a
  concurrent process and tool-authorization boundary. It meets all four project
  test gates.
- Type consistency: The adapter, classifier, state symbols, command names, event
  names, and file names are consistent across tasks.
- Placeholders: None.
- **Status:** Self-approved.
