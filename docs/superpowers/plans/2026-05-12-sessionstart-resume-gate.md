# SessionStart Resume Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Emit the tmux worktree rebinding reminder only on SessionStart resume events, not on brand-new Claude or Codex sessions.

**Architecture:** Keep the existing SessionStart hooks as the metadata and label-refresh owners. Add a narrow `source == resume` condition around only the additionalContext reminder path, preserving startup binding for `cldr` and `cdxr`.

**Tech Stack:** Bash hook scripts, `jq`, tmux pane options, existing shell test harnesses.

---

## File Structure

| File | Responsibility |
|---|---|
| `roles/common/files/bin/tmux-claude-session-start` | Claude SessionStart hook. Already parses `source`; will gate the worktree reminder on `source == resume`. |
| `roles/common/files/bin/codex-bind-tmux-pane` | Codex SessionStart hook. Will parse `source` and gate the worktree reminder on `source == resume`. |
| `tests/tmux-claude-session-start.sh` | Claude hook regression tests for startup silence, resume reminder, and nested startup guard. |
| `tests/codex-bind-tmux-pane.sh` | Codex hook regression tests for startup silence, resume reminder, and missing-source silence. |

No ansible task changes are planned. The Codex hook registration remains `matcher: "startup|resume"` because startup still binds pane metadata.

## Task 1: Claude Red Tests

**Files:**
- Modify: `tests/tmux-claude-session-start.sh`
- Test: `tests/tmux-claude-session-start.sh`

- [ ] **Step 1: Add startup and missing-source silence tests**

In `tests/tmux-claude-session-start.sh`, add these scenarios after Scenario A and before the current resume-without-worktree scenario. Keep the current helper functions unchanged.

```bash
# ----- Scenario A2: startup with @agent_worktree_path UNSET; nudge suppressed but label refresh fires. -----
stubdir_a2="$TMPROOT/stub-a2"
make_stubs "$stubdir_a2" "" ""
out_a2="$(run_hook "$stubdir_a2" '{"session_id":"abc","source":"startup"}')"

assert_empty "$out_a2" "Startup: no nudge JSON emitted when @agent_worktree_path is unset"
assert_file_contains "$TMPROOT/tmux.log" "@persist_claude_session_id abc" "Startup: session id bound to pane"
assert_file_contains "$TMPROOT/update-pane-label.log" "%1" "Startup: tmux-update-pane-label still invoked"
assert_file_contains "$TMPROOT/window-label.log" "%1" "Startup: tmux-window-label still invoked"

# ----- Scenario A3: missing source with @agent_worktree_path UNSET; nudge suppressed. -----
stubdir_a3="$TMPROOT/stub-a3"
make_stubs "$stubdir_a3" "" ""
out_a3="$(run_hook "$stubdir_a3" '{"session_id":"abc"}')"

assert_empty "$out_a3" "Missing source: no nudge JSON emitted when @agent_worktree_path is unset"
assert_file_contains "$TMPROOT/update-pane-label.log" "%1" "Missing source: tmux-update-pane-label still invoked"
assert_file_contains "$TMPROOT/window-label.log" "%1" "Missing source: tmux-window-label still invoked"
```

- [ ] **Step 2: Run the Claude hook test and verify RED**

Run:

```bash
bash tests/tmux-claude-session-start.sh
```

Expected result before production code changes:

```text
FAIL  Startup: no nudge JSON emitted when @agent_worktree_path is unset
expected empty, got: {
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "You are resuming a session ...
```

If the test fails for a syntax error or missing helper instead, fix the test and rerun until it fails because startup emits the reminder.

## Task 2: Claude Green Implementation

**Files:**
- Modify: `roles/common/files/bin/tmux-claude-session-start`
- Test: `tests/tmux-claude-session-start.sh`

- [ ] **Step 1: Gate the Claude reminder on resume**

Replace the final worktree reminder block in `roles/common/files/bin/tmux-claude-session-start` with this exact shape:

```bash
if [ "$source" = "resume" ]; then
  worktree_path="$(tmux show-options -pqv -t "$TMUX_PANE" @agent_worktree_path 2>/dev/null || true)"
  if [ -z "$worktree_path" ]; then
    reminder='You are resuming a session in a tmux pane that has no active worktree bound to it. If your prior work in this session was in a git worktree (e.g. a linked worktree under `.worktrees/<branch>`), run `tmux-agent-worktree set <absolute-worktree-path>` so this tmux pane and window reflect the active worktree. Resolve the path from your conversation history, plan files, or `.coding-agent/` state. If this session is not using a worktree, ignore this reminder.'
    jq -n --arg ctx "$reminder" '{
      "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": $ctx
      }
    }' || true
  fi
fi
```

Keep the existing label refresh calls before this block.

- [ ] **Step 2: Run the Claude hook test and verify GREEN**

Run:

```bash
bash tests/tmux-claude-session-start.sh
```

Expected result:

```text
PASS  Startup: no nudge JSON emitted when @agent_worktree_path is unset
PASS  Missing source: no nudge JSON emitted when @agent_worktree_path is unset
PASS  Part 2: hookEventName is SessionStart when @agent_worktree_path is unset
tmux-claude-session-start checks complete
```

- [ ] **Step 3: Commit the Claude change**

Run:

```bash
/Users/brian/.codex/skills/_commit/commit.sh -m "Gate Claude worktree reminder on resume" tests/tmux-claude-session-start.sh roles/common/files/bin/tmux-claude-session-start
```

## Task 3: Codex Red Tests

**Files:**
- Modify: `tests/codex-bind-tmux-pane.sh`
- Test: `tests/codex-bind-tmux-pane.sh`

- [ ] **Step 1: Make existing Codex resume cases explicit**

In `tests/codex-bind-tmux-pane.sh`, update the existing Scenario A, Scenario B, and Scenario C payloads to include `"source":"resume"`:

```bash
out_a="$(run_hook "$stubdir_a" '{"session_id":"abc","cwd":"/tmp/launch","transcript_path":"/tmp/t.jsonl","source":"resume"}')"
out_b="$(run_hook "$stubdir_b" '{"session_id":"abc","cwd":"/tmp/launch","transcript_path":"/tmp/t.jsonl","source":"resume"}')"
out_c="$(run_hook "$stubdir_c" '{"session_id":"abc","cwd":"/tmp/launch","transcript_path":"/tmp/t.jsonl","source":"resume"}')"
```

- [ ] **Step 2: Add startup and missing-source silence tests**

Add these scenarios after Scenario A and before the resume-without-worktree scenario:

```bash
# ----- Scenario A2: startup with @agent_worktree_path UNSET; nudge suppressed but label refresh fires. -----
stubdir_a2="$TMPROOT/stub-a2"
make_stubs "$stubdir_a2" ""
out_a2="$(run_hook "$stubdir_a2" '{"session_id":"abc","cwd":"/tmp/launch","transcript_path":"/tmp/t.jsonl","source":"startup"}')"

assert_empty "$out_a2" "Startup: no nudge JSON emitted when @agent_worktree_path is unset"
assert_file_contains "$TMPROOT/tmux.log" "@codex_session_id abc" "Startup: session id bound to pane"
assert_file_contains "$TMPROOT/update-pane-label.log" "%1" "Startup: tmux-update-pane-label still invoked"
assert_file_contains "$TMPROOT/window-label.log" "%1" "Startup: tmux-window-label still invoked"

# ----- Scenario A3: missing source with @agent_worktree_path UNSET; nudge suppressed. -----
stubdir_a3="$TMPROOT/stub-a3"
make_stubs "$stubdir_a3" ""
out_a3="$(run_hook "$stubdir_a3" '{"session_id":"abc","cwd":"/tmp/launch","transcript_path":"/tmp/t.jsonl"}')"

assert_empty "$out_a3" "Missing source: no nudge JSON emitted when @agent_worktree_path is unset"
assert_file_contains "$TMPROOT/update-pane-label.log" "%1" "Missing source: tmux-update-pane-label still invoked"
assert_file_contains "$TMPROOT/window-label.log" "%1" "Missing source: tmux-window-label still invoked"
```

- [ ] **Step 3: Run the Codex hook test and verify RED**

Run:

```bash
bash tests/codex-bind-tmux-pane.sh
```

Expected result before production code changes:

```text
FAIL  Startup: no nudge JSON emitted when @agent_worktree_path is unset
expected empty, got: {
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "You are resuming a session ...
```

If the test fails for a syntax error or missing helper instead, fix the test and rerun until it fails because startup emits the reminder.

## Task 4: Codex Green Implementation

**Files:**
- Modify: `roles/common/files/bin/codex-bind-tmux-pane`
- Test: `tests/codex-bind-tmux-pane.sh`

- [ ] **Step 1: Parse Codex SessionStart source**

In `roles/common/files/bin/codex-bind-tmux-pane`, add this parse near the existing `session_id`, `cwd`, and `transcript_path` parses:

```bash
source="$(printf '%s' "$payload" | jq -r '.source // empty' 2>/dev/null || true)"
```

- [ ] **Step 2: Gate the Codex reminder on resume**

Replace the final worktree reminder block with this exact shape:

```bash
if [ "$source" = "resume" ]; then
  worktree_path="$(tmux show-options -pqv -t "$TMUX_PANE" @agent_worktree_path 2>/dev/null || true)"
  if [ -z "$worktree_path" ]; then
    reminder='You are resuming a session in a tmux pane that has no active worktree bound to it. If your prior work in this session was in a git worktree (e.g. a linked worktree under `.worktrees/<branch>`), run `tmux-agent-worktree set <absolute-worktree-path>` so this tmux pane and window reflect the active worktree. Resolve the path from your conversation history, plan files, or `.coding-agent/` state. If this session is not using a worktree, ignore this reminder.'
    jq -n --arg ctx "$reminder" '{
      "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": $ctx
      }
    }' || true
  fi
fi
```

Keep the existing label refresh calls before this block.

- [ ] **Step 3: Run the Codex hook test and verify GREEN**

Run:

```bash
bash tests/codex-bind-tmux-pane.sh
```

Expected result:

```text
PASS  Startup: no nudge JSON emitted when @agent_worktree_path is unset
PASS  Missing source: no nudge JSON emitted when @agent_worktree_path is unset
PASS  Part 2: hookEventName is SessionStart when @agent_worktree_path is unset
codex-bind-tmux-pane checks complete
```

- [ ] **Step 4: Commit the Codex change**

Run:

```bash
/Users/brian/.codex/skills/_commit/commit.sh -m "Gate Codex worktree reminder on resume" tests/codex-bind-tmux-pane.sh roles/common/files/bin/codex-bind-tmux-pane
```

## Task 5: Final Verification

**Files:**
- Verify only; no planned edits.

- [ ] **Step 1: Run focused hook tests**

Run:

```bash
bash tests/tmux-claude-session-start.sh
bash tests/codex-bind-tmux-pane.sh
```

Expected result:

```text
tmux-claude-session-start checks complete
codex-bind-tmux-pane checks complete
```

- [ ] **Step 2: Run CI inventory**

Run:

```bash
bash tests/ci-test-inventory.sh
```

Expected result:

```text
PASS
```

- [ ] **Step 3: Inspect final diff**

Run:

```bash
git status --short
git diff --check
git log --oneline --decorate -5
```

Expected:

- `git status --short` is clean.
- `git diff --check` exits 0.
- Recent commits include the plan commit plus the Claude and Codex implementation commits.

- [ ] **Step 4: Open PR**

After verification passes, run the repo's pull-request flow from this worktree. Do not ask for another approval prompt.
