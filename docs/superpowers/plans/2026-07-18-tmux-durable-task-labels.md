# Durable tmux Task Labels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep a branch-first task identity visible in tmux's top and bottom bars before branching, during work, after cleanup, and through nested SSH.

**Architecture:** `tmux-agent-state` owns pane-local `@task_label`, `@task_source`, and `@task_state`, plus rendered `@window-label` and `@pane-label` caches. Agent prompt hooks publish provisional subjects; worktree lifecycle captures branches and explicitly completes them; remote title helpers transport structured contextual labels while the outer tmux extracts a task-only top label.

**Tech Stack:** Bash, tmux user options/formats, Git, TypeScript Pi extension hooks, Ansible-managed templates, shell test harnesses.

## Global Constraints

- Top label contains only task identity plus optional `~ ` or `✓ ` marker.
- Top label is at most 40 terminal character cells, including marker and Unicode ellipsis.
- Bottom label retains full task identity, repository, and remote host context.
- Feature branch beats provisional subject; provisional subject beats repo/directory fallback.
- The detected default branch, including `main` or `master`, never replaces useful task identity.
- Failed Git lookup, failed cleanup, or degraded remote title never erases captured identity.
- Only successful `repo-end` completion adds `✓`.
- No direct changes outside this repository; deploy only through `bin/provision`.
- No permanent compatibility inference for obsolete subject-completion options.

---

### Task 1: Durable task-state model and renderer

**Files:**
- Modify: `roles/common/files/bin/tmux-agent-state`
- Modify: `roles/common/files/bin/tmux-agent-subject`
- Rewrite tests: `tests/tmux-agent-state.sh`
- Replace obsolete-focused test: `tests/tmux-agent-state-completed-subject.sh`

**Interfaces:**
- Consumes: `TMUX`, `TMUX_PANE`, optional file-backed `TMUX_AGENT_STATE_DIR`, pane path, and existing contextual `@pane-label`.
- Produces: `tmux-agent-state set-provisional <subject>`, `activate-branch <path>`, `clear-worktree`, `complete-worktree`, `clear-task`, `refresh`, and `status`; pane options `@task_label`, `@task_source`, `@task_state`, `@window-label`, and `@pane-label`.

- [ ] **Step 1: Replace state tests with failing task-transition cases**

Add assertions that exercise the public commands rather than old `@agent_subject*` options:

```bash
"$STATE" set-provisional "tmux label persistence"
assert_file_contains "$state_dir/%1.@task_label" "tmux label persistence" "stores provisional label"
assert_file_contains "$state_dir/%1.@task_source" "agent" "stores provisional source"
assert_file_contains "$state_dir/%1.@task_state" "provisional" "stores provisional state"
assert_file_contains "$state_dir/%1.@window-label" "~ tmux label persistence" "renders provisional top label"

"$STATE" activate-branch "$feature_worktree"
assert_file_contains "$state_dir/%1.@task_label" "feature/durable-label" "captures branch"
assert_file_contains "$state_dir/%1.@task_state" "active" "activates branch"
assert_file_contains "$state_dir/%1.@window-label" "feature/durable-label" "branch replaces subject"

"$STATE" complete-worktree
assert_file_contains "$state_dir/%1.@window-label" "✓ feature/durable-label" "renders completed branch"
assert_no_file "$state_dir/%1.@agent_worktree_path" "completion clears worktree path"

status="$($STATE status)"
assert_eq $'completed\tbranch\tfeature/durable-label' "$status" "status contract"
```

Add cases for an empty sanitized subject, `clear-task`, obsolete option cleanup, default-branch rejection, Git lookup failure retaining identity, full bottom label retention, and a long label whose rendered top is exactly 40 cells ending in `…`.

- [ ] **Step 2: Run tests and confirm the old implementation fails**

Run:

```bash
bash tests/tmux-agent-state.sh
bash tests/tmux-agent-state-completed-subject.sh
```

Expected: failures for missing `set-provisional`, `activate-branch`, and task options.

- [ ] **Step 3: Implement explicit state transitions**

Refactor `tmux-agent-state` around these helpers and command cases:

```bash
clear_obsolete_options() {
  local pane="$1" key
  for key in @agent_subject @agent_subject_stale @agent_subject_done @agent_completed_window_label; do
    clear_pane_option "$pane" "$key"
  done
}

set_task() {
  local pane="$1" label="$2" source="$3" state="$4"
  set_pane_option "$pane" @task_label "$label"
  set_pane_option "$pane" @task_source "$source"
  set_pane_option "$pane" @task_state "$state"
  clear_obsolete_options "$pane"
}

case "$cmd" in
  set-provisional) set_task "$pane" "$(sanitize_subject "$*")" agent provisional ;;
  activate-branch) activate_branch "$pane" "${1:-}" ;;
  clear-worktree) clear_worktree_options "$pane" ; refresh "$pane" ;;
  complete-worktree) clear_worktree_options "$pane"; complete_task "$pane"; refresh "$pane" ;;
  clear-task) clear_task_options "$pane"; refresh "$pane" ;;
  refresh) refresh "$pane" ;;
  status) print_status "$pane" ;;
esac
```

`activate_branch` must validate an absolute Git worktree path, read `git branch --show-current`, detect `origin/HEAD` with conventional `main`/`master` fallback, and leave current task state untouched for an empty/default branch. `render` must create task-only `@window-label`; create provisional/completed contextual `@pane-label`; retain the existing contextual pane label when live Git metadata vanishes; and truncate only the top label.

- [ ] **Step 4: Update the subject wrapper**

Map the existing user-facing interface without retaining old storage semantics:

```bash
set) shift; "$state" set-provisional "$@" ;;
clear) "$state" clear-task ;;
status) "$state" status ;;
```

- [ ] **Step 5: Run focused tests**

Run:

```bash
bash tests/tmux-agent-state.sh
bash tests/tmux-agent-state-completed-subject.sh
```

Expected: all task-state, sanitization, fallback, and truncation checks pass.

- [ ] **Step 6: Commit the core state model**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Add durable tmux task identity state" \
  roles/common/files/bin/tmux-agent-state \
  roles/common/files/bin/tmux-agent-subject \
  tests/tmux-agent-state.sh \
  tests/tmux-agent-state-completed-subject.sh
```

---

### Task 2: Capture branches and complete only successful repo cleanup

**Files:**
- Modify: `roles/common/files/bin/tmux-agent-worktree`
- Modify: `roles/common/files/bin/repo-end`
- Modify: `tests/tmux-label-contract.sh`
- Modify: `tests/tmux-pane-link.sh`
- Modify: `tests/repo-lifecycle.sh`

**Interfaces:**
- Consumes: Task 1 commands `activate-branch`, `clear-worktree`, and `complete-worktree`.
- Produces: `tmux-agent-worktree set|sync-current|clear|complete`; `repo-end` calls `complete` only after cleanup succeeds.

- [ ] **Step 1: Add failing worktree lifecycle tests**

Update file-backed fixtures to assert:

```bash
TMUX=1 TMUX_PANE=%12 TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$AGENT_WORKTREE" set "$feature_worktree"
assert_file_contains "$state_dir/%12.@task_label" "feature/durable-label" "set captures branch identity"

TMUX=1 TMUX_PANE=%12 TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$AGENT_WORKTREE" clear
assert_file_contains "$state_dir/%12.@task_state" "active" "ordinary clear does not complete task"

TMUX=1 TMUX_PANE=%12 TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$AGENT_WORKTREE" complete
assert_file_contains "$state_dir/%12.@task_state" "completed" "explicit completion marks task"
```

Change `tests/repo-lifecycle.sh`'s stub expectation from `clear` to `complete`, and add an unsuccessful cleanup case proving no completion call is logged.

- [ ] **Step 2: Isolate the existing label-contract fixture**

Change the fallback fixture so it does not inherit the enclosing linked worktree branch. Run the helper against the fixture's own initialized repo or pass an explicit non-repo path, then retain this expectation:

```bash
assert_eq "label-repo | remote-host [nmb-edge=hj]" "$title" "remote title fixture owns its repo context"
```

- [ ] **Step 3: Run lifecycle tests and confirm failure**

Run:

```bash
bash tests/tmux-label-contract.sh
bash tests/tmux-pane-link.sh
bash tests/repo-lifecycle.sh
```

Expected: new `complete` assertions fail; the previously observed inherited-branch baseline failure is gone after fixture isolation.

- [ ] **Step 4: Route worktree commands through task state**

Replace old subject/window preservation helpers with direct state calls:

```bash
activate_task_branch() {
  TMUX_AGENT_STATE_DIR="${TMUX_AGENT_WORKTREE_STATE_DIR:-}" \
    "$(agent_state_bin)" activate-branch "$1" >/dev/null 2>&1 || true
}

clear_task_worktree() {
  TMUX_AGENT_STATE_DIR="${TMUX_AGENT_WORKTREE_STATE_DIR:-}" \
    "$(agent_state_bin)" clear-worktree >/dev/null 2>&1 || true
}

complete_task_worktree() {
  TMUX_AGENT_STATE_DIR="${TMUX_AGENT_WORKTREE_STATE_DIR:-}" \
    "$(agent_state_bin)" complete-worktree >/dev/null 2>&1 || true
}
```

Call `activate_task_branch "$path"` after publishing path/PID. `clear` removes worktree/PID/link state but preserves active identity. Add `complete` to remove the same operational state and mark identity completed.

- [ ] **Step 5: Call completion only after `repo-end` succeeds**

Rename the helper and command:

```bash
complete_repo_tmux_state() {
  [[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" ]] || return 0
  command -v tmux-agent-worktree >/dev/null 2>&1 || return 0
  tmux-agent-worktree complete >/dev/null 2>&1 || true
}
```

Invoke it after `cleanup_after_merge` and merged-branch pruning succeed, before post-cleanup callbacks. The already-on-main path uses ordinary `clear`, because it has no just-completed feature branch.

- [ ] **Step 6: Run lifecycle tests**

Run:

```bash
bash tests/tmux-agent-state.sh
bash tests/tmux-label-contract.sh
bash tests/tmux-pane-link.sh
bash tests/repo-lifecycle.sh
```

Expected: all checks pass, including isolated fixture and explicit completion ordering.

- [ ] **Step 7: Commit lifecycle integration**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Preserve branch identity through repo cleanup" \
  roles/common/files/bin/tmux-agent-worktree \
  roles/common/files/bin/repo-end \
  tests/tmux-label-contract.sh \
  tests/tmux-pane-link.sh \
  tests/repo-lifecycle.sh
```

---

### Task 3: Render task-only top labels across local and nested tmux

**Files:**
- Modify: `roles/common/files/bin/tmux-window-label`
- Modify: `roles/common/files/bin/tmux-remote-title`
- Modify: `roles/common/files/bin/tmux-sync-remote-title`
- Modify: `roles/common/files/bin/tmux-pane-title-changed`
- Modify: `tests/tmux-label-contract.sh`
- Modify: `tests/tmux-pane-title-changed.rb`
- Verify: `roles/macos/templates/dotfiles/tmux.conf`
- Verify: `roles/linux/files/dotfiles/tmux.conf`

**Interfaces:**
- Consumes: Task 1's task-only `@window-label` and contextual `@pane-label`.
- Produces: local top branch/provisional/completed label, contextual OSC remote title, and task-only outer tmux window name.

- [ ] **Step 1: Add failing top/bottom and nested-SSH contract cases**

Cover these exact transformations:

```text
@window-label=feature/durable-label
  local top -> feature/durable-label
@pane-label=(feature/durable-label) repo | dev-host
  remote OSC -> (feature/durable-label) repo | dev-host
remote OSC=(feature/durable-label) repo | dev-host
  outer top -> feature/durable-label
remote OSC=✓ (feature/durable-label) repo | dev-host
  outer top -> ✓ feature/durable-label
remote OSC=~ tmux label persistence · repo | dev-host
  outer top -> ~ tmux label persistence
```

Add a degraded-title case showing `dev-host` cannot replace an already structured task label. Assert both tmux configs still render `@pane-label` in `pane-border-format` and native `window_name` in the top status format.

- [ ] **Step 2: Run remote/label tests and confirm failures**

Run:

```bash
bash tests/tmux-label-contract.sh
ruby tests/tmux-pane-title-changed.rb
```

Expected: failures for task extraction from completed and provisional remote titles.

- [ ] **Step 3: Make cached task identity authoritative locally**

Keep `tmux-window-label`'s active-pane guard, but make `@window-label` the first and final source for managed panes. Do not strip a host suffix from this cached task-only value. Only use structured remote parsing or cwd label fallback when the cache is empty.

- [ ] **Step 4: Publish contextual task state remotely**

In `tmux-remote-title`, prefer a non-empty pane `@pane-label` when task state exists:

```bash
task_state="$(read_pane_option @task_state 2>/dev/null || true)"
task_context="$(read_pane_option @pane-label 2>/dev/null || true)"
if [ -n "$task_state" ] && [ -n "$task_context" ]; then
  title="$task_context"
  case "$title" in *" | "*) ;; *) title="$title | $host" ;; esac
fi
```

Then append the existing edge marker and publish normally. Retain current path-based fallback for panes without task state.

- [ ] **Step 5: Extract task-only identity in the outer tmux**

Add one parser shared in shape between `tmux-sync-remote-title` and `tmux-window-label`:

```bash
task_from_remote_label() {
  local local_label="${1%% | *}" marker=""
  case "$local_label" in "✓ "*) marker="✓ "; local_label="${local_label#✓ }" ;; esac
  case "$local_label" in
    "~ "*" · "*) printf '%s\n' "${local_label%% · *}" ;;
    \(*\)*) printf '%s%s\n' "$marker" "${local_label#(}" | sed 's/).*//' ;;
    *) return 1 ;;
  esac
}
```

Implement without a pipeline that can misplace the marker: extract the text between the first `(` and `)` into a variable, then print `${marker}${branch}`. Preserve existing edge-marker normalization and active remote-pane filtering.

- [ ] **Step 6: Run local and remote contract tests**

Run:

```bash
bash tests/tmux-label-contract.sh
ruby tests/tmux-pane-title-changed.rb
bash tests/tmux-edge-suffix.sh
```

Expected: all local, completed, provisional, remote, degraded-title, and edge-marker cases pass.

- [ ] **Step 7: Commit rendering and transport**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Propagate durable task labels through nested tmux" \
  roles/common/files/bin/tmux-window-label \
  roles/common/files/bin/tmux-remote-title \
  roles/common/files/bin/tmux-sync-remote-title \
  roles/common/files/bin/tmux-pane-title-changed \
  tests/tmux-label-contract.sh \
  tests/tmux-pane-title-changed.rb
```

---

### Task 4: Prompt every managed agent for a provisional subject

**Files:**
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts`
- Modify: `roles/common/files/pi/AGENTS.md.d/00-base.md`
- Create: `roles/common/files/claude/hooks/remind-agent-subject-on-prompt.sh`
- Delete: `roles/common/files/claude/hooks/remind-agent-subject-on-skill.sh`
- Modify: `roles/common/files/claude/CLAUDE.md.d/00-base.md`
- Modify: `roles/common/files/bin/codex-remind-agent-subject-on-prompt`
- Modify: `roles/common/tasks/main.yml`
- Modify: `tests/pi-managed-hooks.sh`
- Modify: `tests/agent-subject-hooks.sh`
- Modify: `tests/codex-hook-trust.sh`

**Interfaces:**
- Consumes: `tmux-agent-state status` from Task 1.
- Produces: one non-blocking prompt reminder for Pi, Claude, and Codex when task state is empty or completed; no reminder while state is provisional or active. Publishing the suggested provisional subject atomically replaces completed identity.

- [ ] **Step 1: Add failing all-agent prompt-hook tests**

Change fixtures from skill-specific triggers to ordinary task prompts:

```javascript
const subjectReminder = await beforeAgentStart({ prompt: "improve tmux labels" });
assert.match(subjectReminder.message.content, /tmux-agent-subject set/);
```

```bash
claude_out="$(printf '%s' '{"prompt":"improve tmux labels"}' | ... "$CLAUDE_HOOK")"
assert_contains "$claude_out" "tmux-agent-subject set" "Claude first prompt reminds when task missing"

codex_out="$(printf '%s' '{"prompt":"improve tmux labels"}' | ... "$CODEX_HOOK")"
assert_contains "$codex_out" "tmux-agent-subject set" "Codex first prompt reminds when task missing"
```

For each agent, add no-reminder cases when `status` reports `provisional` or
`active`, plus a reminder case when it reports `completed`. The completed label
remains visible until the agent follows the reminder and explicitly publishes
the next subject.

- [ ] **Step 2: Run hook tests and confirm ordinary prompts fail**

Run:

```bash
bash tests/pi-managed-hooks.sh
bash tests/agent-subject-hooks.sh
bash tests/codex-hook-trust.sh
```

Expected: ordinary-prompt reminder assertions fail under current initiation-skill filters.

- [ ] **Step 3: Update Pi's before-agent-start reminder**

Replace old subject/stale option reads with `tmux-agent-state status`. Trigger when status is empty or begins with `completed<TAB>`, independent of `SUBJECT_TRIGGERS`:

```typescript
const taskStatus = await exec(pi, "tmux-agent-state", ["status"]);
const currentTask = taskStatus.stdout.trim();
if (!currentTask || currentTask.startsWith("completed\t")) {
  notes.push('Choose a concise task subject, then run `tmux-agent-subject set "<short subject>"` before continuing.');
}
```

Keep session binding from clearing task state. Update managed Pi instructions to describe provisional subject, branch replacement, and completed-label retention.

- [ ] **Step 4: Replace Claude's skill hook with a prompt hook**

Create a `UserPromptSubmit` hook that reads stdin, exits unless inside tmux, calls `tmux-agent-state status`, and emits:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "Choose a concise task subject, then run `tmux-agent-subject set \"<short subject>\"` before continuing. The provisional label will be replaced by the feature branch."
  }
}
```

Emit when status is empty or begins with `completed<TAB>`. Update Ansible installation and hook-registration JSON to point at `remind-agent-subject-on-prompt.sh` with the `UserPromptSubmit` event and no skill matcher. Remove the old managed hook file.

- [ ] **Step 5: Broaden Codex's existing prompt hook**

Remove the brainstorming/systematic-debugging prompt regex. Query `tmux-agent-state status`; emit the same provisional naming instruction when status is empty or completed. Update Claude, Codex, and Pi base instructions consistently without adding agent-kind text to visible labels.

- [ ] **Step 6: Run hook and provisioning-structure tests**

Run:

```bash
bash tests/pi-managed-hooks.sh
bash tests/agent-subject-hooks.sh
bash tests/codex-hook-trust.sh
bash tests/tmux-claude-session-start.sh
bash tests/codex-bind-tmux-pane.sh
```

Expected: all prompt, status, binding, and hook-registration cases pass.

- [ ] **Step 7: Commit managed agent guidance**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Prompt coding agents for provisional tmux labels" \
  roles/common/files/pi/extensions/managed-hooks.ts \
  roles/common/files/pi/AGENTS.md.d/00-base.md \
  roles/common/files/claude/hooks/remind-agent-subject-on-prompt.sh \
  roles/common/files/claude/hooks/remind-agent-subject-on-skill.sh \
  roles/common/files/claude/CLAUDE.md.d/00-base.md \
  roles/common/files/bin/codex-remind-agent-subject-on-prompt \
  roles/common/tasks/main.yml \
  tests/pi-managed-hooks.sh \
  tests/agent-subject-hooks.sh \
  tests/codex-hook-trust.sh
```

---

### Task 5: Full verification, provisioning, and empirical proof

**Files:**
- Modify only if verification finds a defect in files already listed above.

**Interfaces:**
- Consumes: all completed implementation tasks.
- Produces: verified managed configuration and PR-ready branch.

- [ ] **Step 1: Run the complete targeted suite**

```bash
set -e
for test in \
  tests/tmux-agent-state.sh \
  tests/tmux-agent-state-completed-subject.sh \
  tests/tmux-label-contract.sh \
  tests/tmux-pane-link.sh \
  tests/tmux-edge-suffix.sh \
  tests/agent-subject-hooks.sh \
  tests/pi-managed-hooks.sh \
  tests/codex-hook-trust.sh \
  tests/tmux-claude-session-start.sh \
  tests/codex-bind-tmux-pane.sh \
  tests/repo-lifecycle.sh; do
  bash "$test"
done
ruby tests/tmux-pane-title-changed.rb
```

Expected: every test exits 0; the baseline `label-repo` worktree-isolation failure no longer occurs.

- [ ] **Step 2: Run syntax and diff checks**

```bash
bash -n roles/common/files/bin/tmux-agent-state \
  roles/common/files/bin/tmux-agent-subject \
  roles/common/files/bin/tmux-agent-worktree \
  roles/common/files/bin/tmux-window-label \
  roles/common/files/bin/tmux-remote-title \
  roles/common/files/bin/tmux-sync-remote-title \
  roles/common/files/bin/repo-end \
  roles/common/files/claude/hooks/remind-agent-subject-on-prompt.sh \
  roles/common/files/bin/codex-remind-agent-subject-on-prompt
git diff --check
```

Expected: no output and exit 0.

- [ ] **Step 3: Apply managed configuration**

```bash
bin/provision
```

Expected: playbook completes with `failed=0`. This is the permitted path for updating deployed tmux and agent configuration.

- [ ] **Step 4: Verify provisioning idempotence**

```bash
bin/provision --check
```

Expected: playbook completes with `failed=0` and no unexpected managed-file changes.

- [ ] **Step 5: Verify real tmux state locally**

In a disposable pane, use the installed helpers and `tmux show-options -pqv` to prove:

```text
provisional top: ~ durable tmux labels
active top: improve-tmux-task-label-persistence (truncated to <=40 cells if needed)
active bottom: (improve-tmux-task-label-persistence) new-machine-bootstrap
completed top: ✓ improve-tmux-task-label-persistence
completed bottom: ✓ (improve-tmux-task-label-persistence) new-machine-bootstrap
```

Do not run `repo-end` on the implementation worktree for this check; use file-backed state or a disposable test repository.

- [ ] **Step 6: Verify nested SSH when an available host is already configured**

Confirm remote inner bottom includes `| <host>` and outer top contains only the provisional/branch/completed identity. If no safe configured SSH host is available, record that remote behavior is covered by automated OSC/title contract tests and list manual SSH verification as residual risk.

- [ ] **Step 7: Review the complete branch diff**

```bash
git status --short --branch
git diff origin/main...HEAD --stat
git diff origin/main...HEAD
git log --oneline origin/main..HEAD
```

Expected: only approved spec, plan, task-state/lifecycle/rendering/hook implementation, and tests are present; runtime `.pi` and `.pi-subagents` artifacts remain uncommitted.

- [ ] **Step 8: Commit any verification-only fixes**

If Step 1–7 required tracked fixes, commit only those named files with:

Use `git status --short` to select only the already-approved implementation or
test files changed by verification, then pass those exact paths to
`~/.pi/agent/skills/z-commit/commit.sh -m "Fix durable tmux label verification gaps"`.
Do not include `.pi`, `.pi-subagents`, or unrelated files. If no tracked fixes
remain, do not create an empty commit.
