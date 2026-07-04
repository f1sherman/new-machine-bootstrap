# Pi Session Naming and Session Viewer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Pi sessions auto-name themselves from managed tmux labels and install the richer Pi session browser.

**Architecture:** Extend the existing managed Pi extension so tmux remains the source of truth: the extension refreshes tmux pane/window labels, reads `@window-label`, and calls `pi.setSessionName()` only for names it manages. Add `pi-session-manager` to the existing managed Pi package install tasks for macOS and Linux.

**Tech Stack:** Pi TypeScript extension loaded by `jiti`, Node.js test harness in `tests/pi-managed-hooks.sh`, Ansible YAML tasks in `roles/common/tasks/main.yml`, Ruby contract test for package command policy.

## Global Constraints

- Make changes only inside this repository worktree.
- Do not edit deployed files under `~`; provisioning overwrites them.
- Keep tmux as the source of truth for label formatting.
- Do not overwrite manually named Pi sessions unless the current name was previously set by the managed Pi hook.
- Pi package installation must be managed by Ansible and remain idempotent.
- Use existing `warn()` and `exec()` helpers for best-effort extension commands.
- Use the managed commit helper instead of raw `git commit`.

---

## File Structure

- `roles/common/files/pi/extensions/managed-hooks.ts`: add session-name synchronization helpers and wire them into `session_start` plus bash `tool_result`.
- `tests/pi-managed-hooks.sh`: extend the Node harness to stub tmux label reads, `pi.setSessionName()`, and `tool_result` behavior.
- `roles/common/tasks/main.yml`: install `npm:pi-session-manager` for both macOS and Linux alongside `pi-subdir-context`.
- `tests/paranoid-package-tools.rb`: update the package command allowlist fixture so the policy test accepts the new `pi install npm:pi-session-manager` pattern in tests.

---

### Task 1: Add Pi Session Name Sync to Managed Hooks

**Files:**
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts`
- Test: `tests/pi-managed-hooks.sh`

**Interfaces:**
- Consumes: existing `exec(pi, command, args, options)`, `tmuxOption(pi, key)`, `inTmux()`, and `warn(message, error)` helpers.
- Produces: `syncSessionNameFromTmux(pi, ctx): Promise<void>`, used by `session_start` and later tasks.

- [ ] **Step 1: Write failing session-start test assertions**

In `tests/pi-managed-hooks.sh`, inside the generated Node script, replace the current `pi` object and session-start assertion block with this structure.

```js
const sessionNames = [];
let currentSessionName = "";
let windowLabel = "pi main-repo";

const pi = {
  on(event, handler) {
    handlers.set(event, handler);
  },
  setSessionName(name) {
    currentSessionName = name;
    sessionNames.push(name);
  },
  async exec(command, args) {
    calls.push({ command, args });
    if (command === "tmux-agent-state") return ok();
    if (command === "tmux-update-pane-label") return ok();
    if (command === "tmux-window-label") return ok();
    if (command === "tmux" && args[0] === "show-options" && args.at(-1) === "@window-label") return ok(`${windowLabel}\n`);
    if (command === "tmux" && args[0] === "set-option") return ok();
    if (command === "tmux") return fail();
    if (command === "git" && args.includes("rev-parse")) {
      if (args.some((arg) => String(arg).startsWith("/missing"))) return fail();
      return ok(args.some((arg) => String(arg).startsWith(worktreeRoot)) ? `${worktreeRoot}\n` : "/repo\n");
    }
    if (command === "git" && args.includes("branch")) {
      return ok(args.includes(worktreeRoot) ? "feature\n" : `${branch}\n`);
    }
    return fail();
  },
};

const ctx = {
  cwd: "/repo",
  sessionManager: {
    getSessionName() {
      return currentSessionName;
    },
  },
};

await handlers.get("session_start")({}, ctx);
assert.deepEqual(calls.slice(-4), [
  { command: "tmux-agent-state", args: ["set-kind", "pi"] },
  { command: "tmux-update-pane-label", args: ["%1"] },
  { command: "tmux-window-label", args: ["%1"] },
  { command: "tmux", args: ["show-options", "-qv", "-p", "-t", "%1", "@window-label"] },
], "session_start binds pi kind, refreshes tmux labels, and reads the rendered window label");
assert.deepEqual(sessionNames, ["pi main-repo"], "session_start names the Pi session from tmux @window-label");
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/pi-session-naming-viewer
bash tests/pi-managed-hooks.sh
```

Expected: FAIL because `session_start` does not call `tmux-update-pane-label`, `tmux-window-label`, or `pi.setSessionName()` yet.

- [ ] **Step 3: Implement session-name synchronization helpers**

In `roles/common/files/pi/extensions/managed-hooks.ts`, after `tmuxOption(pi, key)`, add:

```ts
let lastManagedSessionName = "";

async function refreshTmuxLabels(pi) {
  if (!inTmux()) return;
  await exec(pi, "tmux-update-pane-label", [process.env.TMUX_PANE]);
  await exec(pi, "tmux-window-label", [process.env.TMUX_PANE]);
}

async function syncSessionNameFromTmux(pi, ctx) {
  if (!inTmux()) return;
  if (typeof pi.setSessionName !== "function") return;

  const label = await tmuxOption(pi, "@window-label");
  if (!label) return;

  const currentName = ctx?.sessionManager?.getSessionName?.() || "";
  if (currentName === label) {
    lastManagedSessionName = label;
    return;
  }
  if (currentName && currentName !== lastManagedSessionName) return;

  try {
    pi.setSessionName(label);
    lastManagedSessionName = label;
  } catch (error) {
    warn("set Pi session name from tmux label failed", error);
  }
}
```

- [ ] **Step 4: Wire helpers into `session_start`**

Replace the existing `session_start` handler in `roles/common/files/pi/extensions/managed-hooks.ts` with:

```ts
  pi.on("session_start", async (_event, ctx) => {
    if (!inTmux()) return;
    await exec(pi, "tmux-agent-state", ["set-kind", "pi"]);
    await refreshTmuxLabels(pi);
    await syncSessionNameFromTmux(pi, ctx);
  });
```

- [ ] **Step 5: Run the focused test and verify it passes**

Run:

```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/pi-session-naming-viewer
bash tests/pi-managed-hooks.sh
```

Expected: PASS with `pi-managed-hooks checks complete`.

- [ ] **Step 6: Commit Task 1**

Run:

```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/pi-session-naming-viewer
~/.claude/skills/_commit/commit.sh -m "Name Pi sessions from tmux labels" roles/common/files/pi/extensions/managed-hooks.ts tests/pi-managed-hooks.sh
```

Expected: a commit is created with no AI attribution.

---

### Task 2: Sync Pi Session Names After Tmux Label Changes

**Files:**
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts`
- Test: `tests/pi-managed-hooks.sh`

**Interfaces:**
- Consumes: `syncSessionNameFromTmux(pi, ctx): Promise<void>` from Task 1.
- Produces: a `tool_result` hook that updates managed Pi session names after successful bash commands.

- [ ] **Step 1: Write failing tests for bash-result synchronization and manual-name preservation**

In `tests/pi-managed-hooks.sh`, after the session-start assertions from Task 1, add:

```js
assert.equal(typeof handlers.get("tool_result"), "function", "registers tool_result hook");

windowLabel = "pi feature-work";
await handlers.get("tool_result")({ toolName: "bash", isError: false }, ctx);
assert.deepEqual(sessionNames, ["pi main-repo", "pi feature-work"], "successful bash results resync managed Pi session names from tmux");

currentSessionName = "manual investigation name";
windowLabel = "pi later-worktree";
await handlers.get("tool_result")({ toolName: "bash", isError: false }, ctx);
assert.equal(currentSessionName, "manual investigation name", "manual Pi session names are not overwritten by managed tmux sync");
assert.deepEqual(sessionNames, ["pi main-repo", "pi feature-work"], "manual-name preservation does not call setSessionName again");

await handlers.get("tool_result")({ toolName: "read", isError: false }, ctx);
assert.deepEqual(sessionNames, ["pi main-repo", "pi feature-work"], "non-bash tool results do not resync session names");

await handlers.get("tool_result")({ toolName: "bash", isError: true }, ctx);
assert.deepEqual(sessionNames, ["pi main-repo", "pi feature-work"], "failed bash results do not resync session names");
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/pi-session-naming-viewer
bash tests/pi-managed-hooks.sh
```

Expected: FAIL because no `tool_result` handler is registered.

- [ ] **Step 3: Register the `tool_result` hook**

In `roles/common/files/pi/extensions/managed-hooks.ts`, after the `before_agent_start` hook and before the `tool_call` hook, add:

```ts
  pi.on("tool_result", async (event, ctx) => {
    if (event.toolName !== "bash") return;
    if (event.isError) return;
    await syncSessionNameFromTmux(pi, ctx);
  });
```

- [ ] **Step 4: Run the focused test and verify it passes**

Run:

```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/pi-session-naming-viewer
bash tests/pi-managed-hooks.sh
```

Expected: PASS with `pi-managed-hooks checks complete`.

- [ ] **Step 5: Commit Task 2**

Run:

```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/pi-session-naming-viewer
~/.claude/skills/_commit/commit.sh -m "Resync Pi session names after tmux label changes" roles/common/files/pi/extensions/managed-hooks.ts tests/pi-managed-hooks.sh
```

Expected: a commit is created with no AI attribution.

---

### Task 3: Install the Pi Session Viewer Package

**Files:**
- Modify: `roles/common/tasks/main.yml`
- Modify: `tests/paranoid-package-tools.rb`

**Interfaces:**
- Consumes: existing Ansible package install task pattern using `{{ mise_bin }} exec node@{{ tool_versions.runtimes.node }} -- pi install npm:<package>`.
- Produces: managed installation of `npm:pi-session-manager` on macOS and Linux.

- [ ] **Step 1: Write failing package install contract**

In `tests/paranoid-package-tools.rb`, update the `good.sh` fixture from:

```ruby
  File.write(
    File.join(dir, "good.sh"),
    "AUBE_PARANOID=true aubx safe-tool@latest\n" \
      "pi install npm:pi-subdir-context\n"
  )
```

to:

```ruby
  File.write(
    File.join(dir, "good.sh"),
    "AUBE_PARANOID=true aubx safe-tool@latest\n" \
      "pi install npm:pi-subdir-context\n" \
      "pi install npm:pi-session-manager\n"
  )
```

Then add this assertion after `violations = scan_violations(repo_root)` and before `if violations.empty?`:

```ruby
unless File.read(File.join(repo_root, "roles/common/tasks/main.yml")).include?("pi install npm:pi-session-manager")
  violations << "roles/common/tasks/main.yml: missing managed pi-session-manager install"
end
```

- [ ] **Step 2: Run the contract test and verify it fails**

Run:

```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/pi-session-naming-viewer
ruby tests/paranoid-package-tools.rb
```

Expected: FAIL with `missing managed pi-session-manager install`.

- [ ] **Step 3: Add macOS and Linux install tasks**

In `roles/common/tasks/main.yml`, after the existing `Install pi-subdir-context plugin for pi-coding-agent (Linux)` task and before `Create pi-coding-agent global extensions directory`, add:

```yaml
- name: Install pi-session-manager plugin for pi-coding-agent (macOS)
  command: "{{ mise_bin }} exec node@{{ tool_versions.runtimes.node }} -- pi install npm:pi-session-manager"
  register: pi_session_manager_plugin_macos
  changed_when: "'already installed' not in pi_session_manager_plugin_macos.stdout"
  failed_when: pi_session_manager_plugin_macos.rc != 0
  when: ansible_facts["os_family"] == "Darwin"

- name: Install pi-session-manager plugin for pi-coding-agent (Linux)
  shell: "{{ mise_bin }} exec node@{{ tool_versions.runtimes.node }} -- pi install npm:pi-session-manager"
  register: pi_session_manager_plugin_linux
  environment:
    PATH: "{{ ansible_facts['user_dir'] }}/.local/bin:{{ ansible_facts['env']['PATH'] }}"
  changed_when: "'already installed' not in pi_session_manager_plugin_linux.stdout"
  failed_when: pi_session_manager_plugin_linux.rc != 0
  when: ansible_facts["os_family"] == "Debian"
```

- [ ] **Step 4: Run the contract test and verify it passes**

Run:

```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/pi-session-naming-viewer
ruby tests/paranoid-package-tools.rb
```

Expected: PASS with `PASS  package tool invocations require paranoid mode`.

- [ ] **Step 5: Commit Task 3**

Run:

```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/pi-session-naming-viewer
~/.claude/skills/_commit/commit.sh -m "Install Pi session manager package" roles/common/tasks/main.yml tests/paranoid-package-tools.rb
```

Expected: a commit is created with no AI attribution.

---

### Task 4: Final Verification and Provisioning

**Files:**
- No new source files.
- Verify changes from Tasks 1-3.

**Interfaces:**
- Consumes: committed implementation from Tasks 1-3.
- Produces: verified branch ready for PR.

- [ ] **Step 1: Run focused tests**

Run:

```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/pi-session-naming-viewer
bash tests/pi-managed-hooks.sh
ruby tests/paranoid-package-tools.rb
```

Expected:

```text
pi-managed-hooks checks complete
PASS  package tool invocations require paranoid mode
```

- [ ] **Step 2: Run provisioning check if environment allows**

Run:

```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/pi-session-naming-viewer
bin/provision --check
```

Expected: Ansible completes without fatal errors. If unrelated host-specific check-mode tasks fail, capture the failing task names and stderr in the final report.

- [ ] **Step 3: Apply provisioning if verification permits**

Run:

```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/pi-session-naming-viewer
bin/provision
```

Expected: provisioning installs/keeps `pi-session-manager`, updates `~/.pi/agent/extensions/managed-hooks.ts`, and completes without fatal errors. If provisioning is blocked by credentials, network, or unrelated host state, record the blocker and continue to PR only if code-level tests passed.

- [ ] **Step 4: Inspect final diff and log**

Run:

```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/pi-session-naming-viewer
git status --short
git log --oneline --max-count=5
```

Expected: working tree is clean except ignored/untracked unrelated artifacts already present before this work, and recent commits include the spec, plan, and implementation commits.

- [ ] **Step 5: Open PR**

Run the repo's normal PR creation workflow after reading `.github/PULL_REQUEST_TEMPLATE.md` and checking existing PRs/issues for overlap. Target the repo's default integration branch used by this project. Include verification output for `tests/pi-managed-hooks.sh`, `tests/paranoid-package-tools.rb`, and provisioning/check-mode status.
