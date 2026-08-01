# Tmux Agent Title Ownership Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent unrelated desktop automations from changing a tmux pane title and clear agent-generated provisional titles when an interactive agent exits to zsh.

**Architecture:** Put a process-ancestry ownership gate in the user-facing `tmux-agent-subject` wrapper while leaving detached internal `tmux-agent-state` callers unchanged. Add a narrow state operation for `agent/provisional` cleanup and call it from the serialized title transition before rendering a zsh prompt.

**Tech Stack:** Bash, tmux formats, process inspection with `ps`, file-backed shell regression tests, Ansible provisioning.

## Global Constraints

- Accept user-facing title mutations only when the caller descends from the target pane process.
- Fail closed and exit successfully when ownership cannot be verified.
- Clear only task state whose source is `agent` and state is `provisional`.
- Preserve branch, goal, manual, and completed task identities.
- Preserve detached remote-title adoption through the internal state interface.
- Do not depend on Codex Desktop lifecycle behavior.

---

### Task 1: Gate User-Facing Subject Mutations by Pane Ownership

**Files:**
- Modify: `roles/common/files/bin/tmux-agent-subject`
- Modify: `tests/tmux-agent-state.sh`

**Interfaces:**
- Consumes: `TMUX`, `TMUX_PANE`, tmux format `#{pane_pid}`, and the caller process parent chain.
- Produces: `caller_owns_pane() -> exit 0 only when the pane PID is in the caller ancestry`; test-only overrides `TMUX_AGENT_SUBJECT_TMUX_BIN`, `TMUX_AGENT_SUBJECT_PS_BIN`, and `TMUX_AGENT_SUBJECT_CALLER_PID`.

- [ ] **Step 1: Write failing ownership tests**

Add a deterministic tmux stub and process-parent stub to `tests/tmux-agent-state.sh`. Add cases with separate state directories so existing state cannot mask a mutation:

```bash
cat >"$stub_bin/tmux-subject" <<'STUB'
#!/usr/bin/env bash
[ "$1" = display-message ] || exit 1
printf '%s\n' "${TMUX_AGENT_SUBJECT_TEST_PANE_PID:-}"
STUB

cat >"$stub_bin/ps-subject" <<'STUB'
#!/usr/bin/env bash
pid=""
while [ "$#" -gt 0 ]; do
  [ "$1" = -p ] && { shift; pid="${1:-}"; }
  shift || true
done
case "$pid" in
  300) printf '200\n' ;;
  200) printf '100\n' ;;
  400) printf '1\n' ;;
  *) exit 1 ;;
esac
STUB
```

Run `tmux-agent-subject set` with pane PID `100` and caller PID `300`; assert that provisional state is written. Run it with pane PID `100` and caller PID `400`; assert that no task files are written. Add invalid and missing pane-PID cases and assert successful no-op behavior.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
bash tests/tmux-agent-state.sh
```

Expected: FAIL because `tmux-agent-subject` does not inspect pane ownership and the unrelated caller writes provisional task state.

- [ ] **Step 3: Implement the ownership gate**

Add `caller_owns_pane` to `tmux-agent-subject`. Resolve the pane PID with:

```bash
tmux_bin="${TMUX_AGENT_SUBJECT_TMUX_BIN:-tmux}"
ps_bin="${TMUX_AGENT_SUBJECT_PS_BIN:-ps}"
caller_pid="${TMUX_AGENT_SUBJECT_CALLER_PID:-$$}"
pane_pid="$(command "$tmux_bin" display-message -p -t "$TMUX_PANE" '#{pane_pid}' 2>/dev/null)" || return 1
```

Require both PIDs to match `^[1-9][0-9]*$`. Walk from `caller_pid` toward PID 1 with `command "$ps_bin" -p "$current_pid" -o ppid=`. Trim whitespace, reject invalid or repeated parent values, and return success only when `pane_pid` is encountered.

Call this gate before the `set` and `clear` mutations. Keep `status` read-only and unchanged. On rejection, exit `0` without invoking `tmux-agent-state`.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run:

```bash
bash tests/tmux-agent-state.sh
bash -n roles/common/files/bin/tmux-agent-subject
```

Expected: all checks pass.

- [ ] **Step 5: Commit Task 1**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Restrict tmux subjects to owning panes" \
  roles/common/files/bin/tmux-agent-subject \
  tests/tmux-agent-state.sh
```

---

### Task 2: Clear Provisional Agent State on Return to Zsh

**Files:**
- Modify: `roles/common/files/bin/tmux-agent-state`
- Modify: `roles/common/files/bin/tmux-title-transition`
- Modify: `tests/tmux-agent-state.sh`
- Modify: `tests/tmux-label-contract.sh`

**Interfaces:**
- Consumes: pane options `@task_source` and `@task_state`; title-transition effective command.
- Produces: `tmux-agent-state clear-provisional`; test-only override `TMUX_TITLE_TRANSITION_AGENT_STATE_BIN`; zsh transitions clear provisional state before window rendering.

- [ ] **Step 1: Write failing narrow-cleanup tests**

In `tests/tmux-agent-state.sh`, create `agent/provisional` state with a context and invoke:

```bash
"$STATE" clear-provisional
```

Assert removal of `@task_label`, `@task_source`, `@task_state`, and `@task_context`. For each protected identity, seed the exact source/state pair and assert it remains:

```text
branch/active
goal/active
manual/active
branch/completed
```

Also assert that incomplete or empty state is a successful no-op.

- [ ] **Step 2: Run the state test and verify RED**

Run:

```bash
bash tests/tmux-agent-state.sh
```

Expected: FAIL because `clear-provisional` is not a recognized command and provisional files remain.

- [ ] **Step 3: Implement narrow cleanup**

In `tmux-agent-state`, add a helper that reads `@task_source` and `@task_state`, returns without mutation unless they are exactly `agent` and `provisional`, then calls the existing `clear_task_options` and `refresh` functions. Add this command dispatch:

```bash
clear-provisional)
  clear_provisional_task "$pane"
  ;;
```

- [ ] **Step 4: Run the state test and verify GREEN**

Run:

```bash
bash tests/tmux-agent-state.sh
bash -n roles/common/files/bin/tmux-agent-state
```

Expected: all checks pass.

- [ ] **Step 5: Write failing title-transition integration tests**

In `tests/tmux-label-contract.sh`, add a state-helper stub that appends its arguments to a log. Run one `zsh` transition and one `pi` transition with `TMUX_TITLE_TRANSITION_AGENT_STATE_BIN` pointing to that stub.

Assert for the zsh transition:

```text
clear-provisional
```

is recorded before the window-label render. Assert the non-zsh transition does not call `clear-provisional`. Keep the existing ordered-request harness so the test exercises the real transition serializer.

- [ ] **Step 6: Run the transition test and verify RED**

Run:

```bash
bash tests/tmux-label-contract.sh
```

Expected: FAIL because `tmux-title-transition` does not call the state helper.

- [ ] **Step 7: Integrate cleanup into the transition**

After the final stale-request check and before `tmux-window-label`, add:

```bash
if [ "$effective_command" = "zsh" ]; then
  agent_state_helper="${TMUX_TITLE_TRANSITION_AGENT_STATE_BIN:-tmux-agent-state}"
  if command -v "$agent_state_helper" >/dev/null 2>&1; then
    TMUX_PANE="$pane_id" command "$agent_state_helper" clear-provisional >/dev/null 2>&1 || true
  fi
fi
```

Do not call this helper for other effective commands. Keep rendering and remote publication in their current order after cleanup.

- [ ] **Step 8: Run focused regression tests and verify GREEN**

Run:

```bash
bash tests/tmux-agent-state.sh
bash tests/tmux-label-contract.sh
ruby tests/tmux-pane-title-changed.rb
bash -n roles/common/files/bin/tmux-agent-state
bash -n roles/common/files/bin/tmux-agent-subject
bash -n roles/common/files/bin/tmux-title-transition
```

Expected: all checks pass.

- [ ] **Step 9: Commit Task 2**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Clear provisional tmux titles at shell prompts" \
  roles/common/files/bin/tmux-agent-state \
  roles/common/files/bin/tmux-title-transition \
  tests/tmux-agent-state.sh \
  tests/tmux-label-contract.sh
```

---

### Task 3: Provision and Verify End to End

**Files:**
- No source changes expected.

**Interfaces:**
- Consumes: committed managed helpers and the repository provisioning entry point.
- Produces: deployed helpers that match the branch and empirical proof in a disposable tmux window.

- [ ] **Step 1: Run the complete relevant regression set**

Run:

```bash
bash tests/tmux-agent-state.sh
bash tests/codex-bind-tmux-pane.sh
bash tests/tmux-label-contract.sh
ruby tests/tmux-pane-title-changed.rb
bash tests/tmux-label-helper-provisioning.sh
```

Expected: all checks pass.

- [ ] **Step 2: Apply managed files**

Run from this worktree:

```bash
bin/provision
```

Expected: provisioning completes successfully using its built-in lock.

- [ ] **Step 3: Verify deployed files match the branch**

Run:

```bash
cmp roles/common/files/bin/tmux-agent-subject "$HOME/.local/bin/tmux-agent-subject"
cmp roles/common/files/bin/tmux-agent-state "$HOME/.local/bin/tmux-agent-state"
cmp roles/common/files/bin/tmux-title-transition "$HOME/.local/bin/tmux-title-transition"
```

Expected: all commands exit `0`.

- [ ] **Step 4: Run disposable tmux ownership and cleanup smoke tests**

Create a disposable tmux server and pane. From a child process of that pane, set a provisional subject and confirm the window shows `~ <subject>`. Run the deployed subject helper from an unrelated process with copied `TMUX` and `TMUX_PANE`; confirm it cannot replace the title. Exit the interactive agent command to zsh and confirm the pane task options are absent and the window title is the normal shell/repository label.

- [ ] **Step 5: Review the final branch**

Run:

```bash
git status --short
git diff main...HEAD --check
git log --oneline main..HEAD
```

Expected: clean worktree, no whitespace errors, and only the design, plan, ownership gate, cleanup integration, and regression tests.
