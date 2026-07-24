# Stable Goal Terminal Title Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make goal/manual terminal titles use the existing task-only 40-column window label while guiding generated goals toward 40 characters.

**Architecture:** `tmux-agent-state` remains the canonical renderer and truncator for `@window-label`. `tmux-remote-title` becomes source-aware and consumes that canonical label only for active `goal` and `manual` tasks; all other title sources keep their contextual rendering. Pi goal persistence keeps its 80-character validation contract while generation and update guidance target 40 characters.

**Tech Stack:** Bash, tmux pane options, TypeScript Pi extension, shell regression tests.

## Global Constraints

- Keep activity and every PR-state indicator unchanged, including merged and closed dots.
- Keep repository/worktree context in `@pane-label` and the pane border.
- Preserve existing agent and branch terminal-title behavior.
- Keep durable goal validation at 80 characters; 40 characters is guidance plus the existing display truncation boundary.
- Make changes only in the NMB repository-managed sources, never deployed `~/.local/bin` files.

---

### Task 1: Source-aware goal/manual terminal titles

**Files:**
- Modify: `tests/tmux-label-contract.sh:204-233`
- Modify: `roles/common/files/bin/tmux-remote-title:30-50,310-345`

**Interfaces:**
- Consumes: pane options `@task_label`, `@task_state`, `@task_source`, `@task_context`, and `@window-label`.
- Produces: visible terminal title text; existing `[nmb-ind=activity,pr-state]` and `[nmb-edge=...]` transport markers remain appended by the existing pipeline.

- [ ] **Step 1: Write failing title-selection tests**

Extend the fake tmux `show-options` cases:

```bash
      @task_label) printf '%s' "$TMUX_TEST_TASK_LABEL" ;;
      @task_state) printf '%s' "$TMUX_TEST_TASK_STATE" ;;
      @task_source) printf '%s' "${TMUX_TEST_TASK_SOURCE:-}" ;;
      @task_context) printf '%s' "$TMUX_TEST_TASK_CONTEXT" ;;
      @window-label) printf '%s' "${TMUX_TEST_WINDOW_LABEL:-}" ;;
      @pane-label) printf '%s' "$TMUX_TEST_PANE_LABEL" ;;
```

Add focused cases after the existing active canonical title assertion:

```bash
remote_goal_title="$(TMUX_PANE=%31 TMUX_REMOTE_TITLE_HOST_TAG=remote-host TMUX_TEST_TASK_LABEL='A durable goal that is intentionally longer than forty characters' TMUX_TEST_TASK_STATE=active TMUX_TEST_TASK_SOURCE=goal TMUX_TEST_TASK_CONTEXT=project TMUX_TEST_WINDOW_LABEL='A durable goal that is intentionally lo…' TMUX_TEST_PANE_LABEL='(A durable goal that is intentionally longer than forty characters) project | remote-host' TMUX_REMOTE_TITLE_ACTIVITY=waiting TMUX_REMOTE_TITLE_PR_STATE=merged PATH="$remote_task_tmux_dir:$PATH" "$REMOTE_TITLE" print)"
assert_equals "$remote_goal_title" "A durable goal that is intentionally lo… [nmb-ind=waiting,merged]" "remote active goal title uses capped task-only window label"

remote_manual_title="$(TMUX_PANE=%31 TMUX_REMOTE_TITLE_HOST_TAG=remote-host TMUX_TEST_TASK_LABEL='Manual task identity' TMUX_TEST_TASK_STATE=active TMUX_TEST_TASK_SOURCE=manual TMUX_TEST_TASK_CONTEXT=project TMUX_TEST_WINDOW_LABEL='Manual task identity' TMUX_TEST_PANE_LABEL='(Manual task identity) project | remote-host' PATH="$remote_task_tmux_dir:$PATH" "$REMOTE_TITLE" print)"
assert_equals "$remote_manual_title" "Manual task identity" "remote active manual title uses task-only window label"

remote_goal_fallback_title="$(TMUX_PANE=%31 TMUX_REMOTE_TITLE_HOST_TAG=remote-host TMUX_TEST_TASK_LABEL='Missing cached goal' TMUX_TEST_TASK_STATE=active TMUX_TEST_TASK_SOURCE=goal TMUX_TEST_TASK_CONTEXT=project TMUX_TEST_WINDOW_LABEL='' TMUX_TEST_PANE_LABEL='(Missing cached goal) project | remote-host' PATH="$remote_task_tmux_dir:$PATH" "$REMOTE_TITLE" print)"
assert_equals "$remote_goal_fallback_title" "(Missing cached goal) project | remote-host" "remote active goal falls back when cached window label is absent"
```

Set `TMUX_TEST_TASK_SOURCE=branch` on the existing active branch case so it explicitly proves branch behavior remains contextual.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
bash tests/tmux-label-contract.sh
```

Expected: the new goal/manual assertions fail because `tmux-remote-title` still returns contextual active titles; existing assertions pass.

- [ ] **Step 3: Implement source-aware selection**

In `main`, read the two additional pane options and select the cached label only for active goal/manual state:

```bash
  local host title worktree_path worktree_pid active_agent_pid info
  local task_label task_state task_source task_context window_label

  task_label="$(read_pane_option "@task_label" 2>/dev/null || true)"
  task_state="$(read_pane_option "@task_state" 2>/dev/null || true)"
  task_source="$(read_pane_option "@task_source" 2>/dev/null || true)"
  task_context="$(read_pane_option "@task_context" 2>/dev/null || true)"
  window_label="$(read_pane_option "@window-label" 2>/dev/null || true)"
  if [ "$task_state" = "active" ] && [ -n "$window_label" ]; then
    case "$task_source" in
      goal|manual) title="$window_label" ;;
    esac
  fi
  if [ -z "${title:-}" ] && [ -n "$task_label" ] && [ -n "$task_state" ] && [ -n "$task_context" ]; then
    title="$(managed_task_title "$task_label" "$task_state" "$task_context" "$host" 2>/dev/null || true)"
  fi
```

Do not alter indicator or edge marker functions.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
bash tests/tmux-label-contract.sh
bash tests/tmux-agent-state.sh
```

Expected: both suites complete with no failures; merged indicator and 40-column truncation assertions remain green.

- [ ] **Step 5: Commit the behavior change**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Use stable goal labels in terminal titles" \
  tests/tmux-label-contract.sh \
  roles/common/files/bin/tmux-remote-title
```

---

### Task 2: Guide goals toward 40 characters

**Files:**
- Modify: `tests/pi-managed-hooks.sh:720-740`
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts:13,870-882`
- Modify: `roles/common/files/config/skills/pi/z-update-session-goal/SKILL.md:10-16`

**Interfaces:**
- Consumes: first expanded Pi prompt and explicit `set_session_goal(goal)` requests.
- Produces: generation/tool guidance targeting 40 characters; `normalizeSessionGoal` continues accepting 80 and rejecting 81 characters.

- [ ] **Step 1: Write failing guidance tests**

Change the expected isolated child prompt to:

```text
Return one concise noun phrase of at most 40 characters describing the new session's broad goal. Output only the phrase on one line, without quotes, a goal: prefix, or explanation.
```

Add assertions near the registered goal tool checks:

```javascript
assert.match(sessionGoalTool.description, /at most 40 characters/, "goal tool guides concise 40-character identities");
assert.match(sessionGoalTool.parameters.properties.goal.description, /at most 40 characters/, "goal argument guides concise 40-character identities");
```

Keep the existing 80/81-character validation assertions unchanged. Add a shell contract assertion that `z-update-session-goal/SKILL.md` contains `target 40 characters` and still delegates mutation to `set_session_goal`.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: prompt/tool guidance assertions fail because production text still says 80 characters.

- [ ] **Step 3: Implement concise guidance without changing validation**

Update only guidance strings:

```typescript
const SESSION_GOAL_CHILD_SYSTEM_PROMPT = "Return one concise noun phrase of at most 40 characters describing the new session's broad goal. Output only the phrase on one line, without quotes, a goal: prefix, or explanation.";
```

Use `at most 40 characters` in the tool description and argument description. In the skill, replace the 80-character instruction with:

```markdown
- Normalize the result into one concise noun phrase targeting 40 characters or fewer, with no quotes or `goal:` prefix.
```

Leave `normalizeSessionGoal` and its 80-character error unchanged.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
bash tests/pi-managed-hooks.sh
bash tests/tmux-agent-state.sh
```

Expected: both suites complete successfully, including 80 accepted / 81 rejected and display truncation cases.

- [ ] **Step 5: Commit the guidance change**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Guide Pi session goals toward concise labels" \
  tests/pi-managed-hooks.sh \
  roles/common/files/pi/extensions/managed-hooks.ts \
  roles/common/files/config/skills/pi/z-update-session-goal/SKILL.md
```

---

### Task 3: Full verification and deployment proof

**Files:**
- Verify all committed files from Tasks 1-2.

**Interfaces:**
- Consumes: completed task commits.
- Produces: verified branch ready for review and deployment through NMB provisioning after merge.

- [ ] **Step 1: Run focused regression suites**

```bash
bash tests/tmux-label-contract.sh
bash tests/tmux-agent-state.sh
bash tests/pi-managed-hooks.sh
```

Expected: all suites complete with no failures.

- [ ] **Step 2: Run the local CI inventory contract**

```bash
bash tests/ci-test-inventory.sh
```

Expected: `1 passed, 0 failed`. The full provision-backed integration workflow runs on GitHub after the PR is pushed.

- [ ] **Step 3: Inspect final scope**

```bash
git status --short
git diff --check main...HEAD
git diff --stat main...HEAD
```

Expected: clean worktree, no whitespace errors, and changes limited to the approved spec, plan, title renderer/tests, and goal guidance/tests.

- [ ] **Step 4: Review and open the PR**

Invoke the repository review workflow, resolve actionable findings, then invoke the `pull-request` skill. This is non-visual behavior; no screenshot proof is required.
