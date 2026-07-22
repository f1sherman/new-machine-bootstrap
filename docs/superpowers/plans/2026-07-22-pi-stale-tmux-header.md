# Pi Conversation-Aware Tmux Header Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace stale provisional tmux window headers when a pane switches Pi conversations, while preserving active branch labels and republishing structured titles on client attach.

**Architecture:** The managed Pi extension compares the pane-bound Pi session file with the active session file. A changed binding causes the active Pi session name to flow through the existing `tmux-agent-subject`/`tmux-agent-state` authority path; Pi rename events use the same path. Existing tmux client-attach hooks additionally invoke the established `tmux-remote-title publish` bridge.

**Tech Stack:** TypeScript Pi extension, Node assertion harness, tmux configuration, Bash integration tests, Ansible provisioning.

## Global Constraints

- Keep Linux `set-titles off`; do not restore raw pane-title propagation.
- Keep active branch task labels authoritative over Pi conversation names.
- Do not rename tmux sessions or change Ghostty's `#S` title policy.
- Treat missing tmux/session/name state and helper failures as non-blocking.
- Do not couple NMB to remote-pi footer strings, notifications, or mesh collision suffixes.

---

### Task 1: Synchronize provisional tmux subjects with Pi sessions

**Files:**
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts`
- Test: `tests/pi-managed-hooks.sh`

**Interfaces:**
- Consumes: `ctx.sessionManager.getSessionFile(): string | undefined`, `ctx.sessionManager.getSessionName(): string | undefined`, pane option `@persist_pi_session_file`, and `tmux-agent-subject set <subject>`.
- Produces: `syncTmuxSubjectFromSession(pi, ctx): Promise<void>` and a `session_info_changed` event handler that route non-empty Pi names through `tmux-agent-subject`.

- [ ] **Step 1: Write failing session-switch tests**

Extend the Node harness state with a pane-bound session file and make the tmux stub return and update it:

```javascript
let boundPiSessionFile = "/sessions/previous.jsonl";
let activeSessionFile = "/sessions/current.jsonl";

if (command === "tmux" && args[0] === "show-options" && args.at(-1) === "@persist_pi_session_file") {
  return boundPiSessionFile ? ok(`${boundPiSessionFile}\n`) : fail();
}
if (command === "tmux" && args[0] === "set-option" && args.includes("@persist_pi_session_file")) {
  boundPiSessionFile = args.at(-1);
  return ok();
}
```

Return `activeSessionFile` from `getSessionFile()`. Add assertions that a different binding and non-empty current name invoke:

```javascript
{
  command: "tmux-agent-subject",
  args: ["set", "Investigate mount probe flapping"],
}
```

before `tmux-update-pane-label`. Add cases proving the same binding, an absent previous binding, and an empty current name do not invoke `tmux-agent-subject`.

- [ ] **Step 2: Write failing rename-event tests**

Assert that `session_info_changed` is registered. Invoke it with `{ name: "Updated conversation" }` and assert `tmux-agent-subject set "Updated conversation"`; invoke it with `{ name: undefined }` and assert no subject command.

- [ ] **Step 3: Run the focused test and verify RED**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: failure because `session_info_changed` is unregistered and changed session bindings do not call `tmux-agent-subject`.

- [ ] **Step 4: Implement session-aware subject synchronization**

Add a helper near the existing tmux/session helpers:

```typescript
async function syncTmuxSubjectFromSession(pi, ctx) {
  if (!inTmux()) return;
  const sessionFile = ctx?.sessionManager?.getSessionFile?.() || "";
  const sessionName = ctx?.sessionManager?.getSessionName?.()?.trim() || "";
  if (!sessionFile || !sessionName) return;

  const boundSessionFile = await tmuxOption(pi, "@persist_pi_session_file");
  if (!boundSessionFile || boundSessionFile === sessionFile) return;

  await exec(pi, "tmux-agent-subject", ["set", sessionName]);
}
```

Call it in `session_start` before `refreshTmuxLabels(pi)`. Register:

```typescript
pi.on("session_info_changed", async (event) => {
  const sessionName = event.name?.trim() || "";
  if (!sessionName || !inTmux()) return;
  await exec(pi, "tmux-agent-subject", ["set", sessionName]);
});
```

Do not duplicate branch-authority logic; `tmux-agent-state set-provisional` already refuses to replace an active branch task.

- [ ] **Step 5: Run focused and adjacent tests**

Run:

```bash
bash tests/pi-managed-hooks.sh
bash tests/tmux-agent-state.sh
```

Expected: both exit 0; outputs end with `pi-managed-hooks checks complete` and `tmux-agent-state checks complete`.

- [ ] **Step 6: Commit the managed-hook change**

Use the `z-commit` skill to commit:

- `roles/common/files/pi/extensions/managed-hooks.ts`
- `tests/pi-managed-hooks.sh`

Commit message: `Sync tmux headers when Pi conversations change`

---

### Task 2: Republish structured titles when tmux clients attach

**Files:**
- Modify: `roles/macos/templates/dotfiles/tmux.conf`
- Modify: `roles/linux/files/dotfiles/tmux.conf`
- Test: `tests/tmux-managed-bars-contract.sh`

**Interfaces:**
- Consumes: tmux `client-attached` hook and `tmux-remote-title publish`.
- Produces: one base attach hook per managed configuration that performs existing PATH/maintenance work and asynchronously republishes the active structured title.

- [ ] **Step 1: Write failing hook contract assertions**

After reading `attach_hooks`, add:

```bash
assert_equals "$(grep -c 'tmux-remote-title publish' <<<"$attach_hooks" || true)" "1" \
  "repeated config sourcing preserves one client-attached title publisher"
```

Extend the static configuration loop so each config's base `client-attached` line must contain both `tmux-client-attached` and `tmux-remote-title publish`.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
bash tests/tmux-managed-bars-contract.sh
```

Expected: failure at `client-attached title publisher` because attach currently performs only `tmux-client-attached` maintenance.

- [ ] **Step 3: Add attach-time title publication**

Change the base hook in both tmux configs to:

```tmux
set-hook -g client-attached 'run-shell -b "$HOME/.local/bin/tmux-client-attached \"$PATH\""; run-shell -b "TMUX_HOOK_PANE_ID=#{pane_id} $HOME/.local/bin/tmux-hook-run tmux-remote-title publish"'
```

Keep indexed status reconciliation and macOS Ghostty manifest hooks unchanged.

- [ ] **Step 4: Run focused and adjacent tmux tests**

Run:

```bash
bash tests/tmux-managed-bars-contract.sh
ruby tests/tmux-pane-title-changed.rb
bash tests/tmux-label-contract.sh
```

Expected: all exit 0; managed-bars reports all checks passed, pane-title reports zero failures, and label-contract completes successfully.

- [ ] **Step 5: Commit the attach publisher**

Use the `z-commit` skill to commit:

- `roles/macos/templates/dotfiles/tmux.conf`
- `roles/linux/files/dotfiles/tmux.conf`
- `tests/tmux-managed-bars-contract.sh`

Commit message: `Republish tmux task titles on client attach`

---

### Task 3: Provision and end-to-end verification

**Files:**
- Verify only; no planned source changes.

**Interfaces:**
- Consumes: Tasks 1-2 and the repository provisioning workflow.
- Produces: empirical proof that managed files deploy and all title contracts remain green.

- [ ] **Step 1: Run repository verification**

Run:

```bash
bash tests/pi-managed-hooks.sh
bash tests/tmux-agent-state.sh
ruby tests/tmux-pane-title-changed.rb
bash tests/tmux-managed-bars-contract.sh
bash tests/tmux-label-contract.sh
git diff --check
```

Expected: every command exits 0 and `git diff --check` prints nothing.

- [ ] **Step 2: Apply managed configuration**

Run:

```bash
bin/provision
```

Expected: Ansible exits 0 with `failed=0`.

- [ ] **Step 3: Verify deployed configuration**

Run:

```bash
tmux show-hooks -g client-attached
tmux show-options -gv set-titles
```

Expected on macOS: the base attach hook contains `tmux-remote-title publish`; `set-titles` remains `on`. On a provisioned Linux development host, `set-titles` remains `off`.

- [ ] **Step 4: Inspect final branch state**

Run:

```bash
git status --short
git log --oneline origin/main..HEAD
git diff --check origin/main...HEAD
```

Expected: no uncommitted source changes, coherent spec/plan/implementation commits, and no whitespace errors.

- [ ] **Step 5: Request review and open the pull request**

Use the `requesting-code-review` skill, address worthwhile findings, rerun affected verification, then invoke the `pull-request` skill. Include the stale provisional-label root cause and verification evidence in the PR body.
