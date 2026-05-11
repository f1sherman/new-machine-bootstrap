# tmux window label refresh on Claude/Codex resume — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh the tmux window label on Claude/Codex SessionStart, and nudge the agent to republish worktree state when the pane lacks `@agent_worktree_path`.

**Architecture:** Two existing SessionStart hook scripts (`tmux-claude-session-start`, `codex-bind-tmux-pane`) each gain two appended behaviors after their existing session-id writes: (1) call `tmux-update-pane-label` and `tmux-window-label` to re-render the cached label and window name; (2) when `@agent_worktree_path` is unset, emit `hookSpecificOutput.additionalContext` JSON instructing the agent to call `tmux-agent-worktree set <path>`. Spec at `docs/superpowers/specs/2026-05-11-tmux-window-label-on-agent-resume-design.md`.

**Tech Stack:** Bash, `jq` (already a dependency), tmux options, Claude Code / Codex SessionStart hook contract (`hookSpecificOutput.additionalContext`).

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `roles/common/files/bin/tmux-claude-session-start` | Modify | Claude SessionStart hook: existing session-id capture + new label refresh + new conditional nudge. |
| `roles/common/files/bin/codex-bind-tmux-pane` | Modify | Codex SessionStart hook: existing session-id capture + new label refresh + new conditional nudge. |
| `tests/tmux-claude-session-start.sh` | Create | Bash test harness exercising both new behaviors against the Claude hook via stubbed tmux. |
| `tests/codex-bind-tmux-pane.sh` | Create | Bash test harness exercising both new behaviors against the Codex hook via stubbed tmux. |
| `.github/workflows/integration-test.yml` | Modify | Wire the two new test scripts into CI so `ci-test-inventory.sh` is satisfied. |

Each test file is self-contained (no shared harness) and follows the style of `tests/tmux-label-contract.sh` — bash, stub `tmux` and helper binaries via `PATH` prepending, log calls to files in a temp dir, assert via `grep`.

The Part 1 helpers are invoked by their bare names (`tmux-update-pane-label`, `tmux-window-label`), found via `$PATH`. This mirrors what `tmux-pane-title-changed` already does. In production, provisioning puts `~/.local/bin` on `$PATH`; in tests, we prepend a stub bin dir to `$PATH`. (The spec mentioned `$HOME/.local/bin/...` paths — using `$PATH` is a defensive simplification that matches the rest of the repo.)

---

## Task 1: TDD Claude Part 1 — label refresh on SessionStart

**Files:**
- Create: `tests/tmux-claude-session-start.sh`
- Modify: `roles/common/files/bin/tmux-claude-session-start`

### Background for the implementer

`tmux-claude-session-start` currently captures the Claude session id into a pane option and exits. We're appending two lines that invoke `tmux-update-pane-label` and `tmux-window-label` against `$TMUX_PANE`, so any pane resuming an agent gets its cached label and window name re-rendered.

The helpers swallow their own errors; we add `|| true` to keep the hook script's `exit 0` contract.

### Steps

- [ ] **Step 1: Create the test file with a Part 1 (label refresh) scenario**

Write `tests/tmux-claude-session-start.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
HOOK="$REPO_ROOT/roles/common/files/bin/tmux-claude-session-start"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

pass_case() { printf 'PASS  %s\n' "$1"; }
fail_case() { printf 'FAIL  %s\n%s\n' "$1" "$2" >&2; exit 1; }

assert_equals() {
  local actual="$1" expected="$2" name="$3"
  if [ "$actual" != "$expected" ]; then
    fail_case "$name" "expected '$expected', got '$actual'"
  fi
  pass_case "$name"
}

assert_file_contains() {
  local path="$1" needle="$2" name="$3"
  if [ ! -f "$path" ]; then
    fail_case "$name" "missing file: $path"
  fi
  if ! grep -Fq -- "$needle" "$path"; then
    fail_case "$name" "missing '$needle' in $path"
  fi
  pass_case "$name"
}

assert_empty() {
  local content="$1" name="$2"
  if [ -n "$content" ]; then
    fail_case "$name" "expected empty, got: $content"
  fi
  pass_case "$name"
}

assert_file_empty() {
  local path="$1" name="$2"
  if [ -s "$path" ]; then
    fail_case "$name" "expected empty file; contents: $(cat "$path")"
  fi
  pass_case "$name"
}

# make_stubs <stubdir> <worktree_path_response> <existing_session_response>
make_stubs() {
  local stubdir="$1" worktree_response="$2" existing_session_response="$3"
  mkdir -p "$stubdir"

  cat >"$stubdir/tmux" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMPROOT/tmux.log"
case "\$1" in
  show-options)
    for arg in "\$@"; do
      case "\$arg" in
        @agent_worktree_path) printf '%s' "$worktree_response"; exit 0 ;;
        @persist_claude_session_id) printf '%s' "$existing_session_response"; exit 0 ;;
      esac
    done
    exit 0
    ;;
esac
exit 0
STUB
  chmod +x "$stubdir/tmux"

  cat >"$stubdir/tmux-update-pane-label" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMPROOT/update-pane-label.log"
exit 0
STUB
  chmod +x "$stubdir/tmux-update-pane-label"

  cat >"$stubdir/tmux-window-label" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMPROOT/window-label.log"
exit 0
STUB
  chmod +x "$stubdir/tmux-window-label"
}

run_hook() {
  local stubdir="$1" payload="$2"
  : > "$TMPROOT/tmux.log"
  : > "$TMPROOT/update-pane-label.log"
  : > "$TMPROOT/window-label.log"
  printf '%s' "$payload" | TMUX_PANE="%1" PATH="$stubdir:$PATH" "$HOOK"
}

# ----- Scenario A: resume with @agent_worktree_path set; Part 1 refresh fires. -----
stubdir_a="$TMPROOT/stub-a"
make_stubs "$stubdir_a" "/some/worktree" ""
out_a="$(run_hook "$stubdir_a" '{"session_id":"abc","source":"resume"}')"

assert_file_contains "$TMPROOT/update-pane-label.log" "%1" "Part 1: tmux-update-pane-label invoked with TMUX_PANE on resume"
assert_file_contains "$TMPROOT/window-label.log" "%1" "Part 1: tmux-window-label invoked with TMUX_PANE on resume"

printf 'tmux-claude-session-start checks complete\n'
```

Mark executable:

```bash
chmod +x tests/tmux-claude-session-start.sh
```

- [ ] **Step 2: Run the test, confirm it fails**

```bash
bash tests/tmux-claude-session-start.sh
```

Expected: `FAIL  Part 1: tmux-update-pane-label invoked with TMUX_PANE on resume` (the hook script currently doesn't call those helpers, so the log file stays empty).

- [ ] **Step 3: Edit `roles/common/files/bin/tmux-claude-session-start` to add Part 1**

Append after the existing final `tmux set-option` line (currently the last line of the file):

```bash

# Part 1: refresh the cached pane label and rename the window. Idempotent — for
# agent worktree panes this preserves the cached @pane-label (because
# tmux-update-pane-label short-circuits when @agent_worktree_path is set) and
# only re-renders the window name. For non-agent panes it recomputes both.
tmux-update-pane-label "$TMUX_PANE" >/dev/null 2>&1 || true
tmux-window-label "$TMUX_PANE" >/dev/null 2>&1 || true
```

- [ ] **Step 4: Run the test, confirm it passes**

```bash
bash tests/tmux-claude-session-start.sh
```

Expected: both `PASS  Part 1: ...` lines, followed by `tmux-claude-session-start checks complete`.

- [ ] **Step 5: Commit**

```bash
git add tests/tmux-claude-session-start.sh roles/common/files/bin/tmux-claude-session-start
```

Then invoke the `_commit` skill with summary: "TDD Claude SessionStart Part 1: refresh window label". Subject suggestion: `Refresh window label on Claude SessionStart`. No body, no AI attribution.

---

## Task 2: TDD Claude Part 2 — nudge fires when `@agent_worktree_path` unset

**Files:**
- Modify: `tests/tmux-claude-session-start.sh` (add scenarios B and C)
- Modify: `roles/common/files/bin/tmux-claude-session-start` (add Part 2)

### Background

When the pane has no `@agent_worktree_path`, we emit a `hookSpecificOutput.additionalContext` JSON message asking the agent to call `tmux-agent-worktree set <path>`. When the option is set (same-pane resume), we emit nothing — Part 1's refresh already does the right thing using the cached label.

The JSON is built via `jq -n`, matching the pattern in `block-initiation-skill-on-main.sh` and `codex-remind-repo-start-on-dev-prompt`.

### Steps

- [ ] **Step 1: Append scenarios B and C to the test file**

Insert before the final `printf 'tmux-claude-session-start checks complete\n'` line:

```bash

# ----- Scenario B: resume with @agent_worktree_path UNSET; nudge fires with correct shape. -----
stubdir_b="$TMPROOT/stub-b"
make_stubs "$stubdir_b" "" ""
out_b="$(run_hook "$stubdir_b" '{"session_id":"abc","source":"resume"}')"

event="$(printf '%s' "$out_b" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null || true)"
ctx="$(printf '%s' "$out_b" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true)"
assert_equals "$event" "SessionStart" "Part 2: hookEventName is SessionStart when @agent_worktree_path is unset"
case "$ctx" in
  *"tmux-agent-worktree set"*) pass_case "Part 2: additionalContext mentions tmux-agent-worktree set" ;;
  *) fail_case "Part 2: additionalContext mentions tmux-agent-worktree set" "got: $ctx" ;;
esac
case "$ctx" in
  *"active worktree"*) pass_case "Part 2: additionalContext mentions 'active worktree'" ;;
  *) fail_case "Part 2: additionalContext mentions 'active worktree'" "got: $ctx" ;;
esac
# Part 1 still fires even when the nudge fires.
assert_file_contains "$TMPROOT/update-pane-label.log" "%1" "Part 1: label refresh still invoked when nudge fires"

# ----- Scenario C: resume with @agent_worktree_path SET; nudge suppressed. -----
stubdir_c="$TMPROOT/stub-c"
make_stubs "$stubdir_c" "/some/worktree" ""
out_c="$(run_hook "$stubdir_c" '{"session_id":"abc","source":"resume"}')"
assert_empty "$out_c" "Part 2 suppressed when @agent_worktree_path is set"
```

- [ ] **Step 2: Run the test, confirm scenarios B and C fail**

```bash
bash tests/tmux-claude-session-start.sh
```

Expected: scenario A still passes; scenario B fails on `hookEventName is SessionStart when @agent_worktree_path is unset` (the script currently emits nothing on stdout).

- [ ] **Step 3: Edit `roles/common/files/bin/tmux-claude-session-start` to add Part 2**

After the two lines added in Task 1, append:

```bash

# Part 2: when the pane has no @agent_worktree_path, nudge the agent (via an
# injected system reminder) to republish via `tmux-agent-worktree set`. Cross-
# pane resumes can't recover the active worktree from tmux state because the
# agent never chdirs into the worktree — the agent itself is the only authority.
# Same-pane resumes already have the option set so the nudge is skipped.
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
```

- [ ] **Step 4: Run the test, confirm all scenarios pass**

```bash
bash tests/tmux-claude-session-start.sh
```

Expected: every `PASS  ...` line including the new B and C scenarios.

- [ ] **Step 5: Commit**

```bash
git add tests/tmux-claude-session-start.sh roles/common/files/bin/tmux-claude-session-start
```

Invoke `_commit` skill. Subject suggestion: `Nudge agent to republish worktree on Claude SessionStart`.

---

## Task 3: TDD Claude — nested-call bail-out preserves no-op behavior

**Files:**
- Modify: `tests/tmux-claude-session-start.sh` (add scenario D)

### Background

The existing script has an early exit for nested `claude -p` invocations: on a startup-source hook firing when the pane already has `@persist_claude_session_id`, the script `exit 0`s before touching anything. The new Parts 1 and 2 sit *after* that exit, so they should not fire. This task asserts the existing guard wasn't broken.

### Steps

- [ ] **Step 1: Add scenario D to the test file**

Insert before the final `printf 'tmux-claude-session-start checks complete\n'`:

```bash

# ----- Scenario D: nested call (startup source + existing session id) bails before Part 1 or Part 2. -----
stubdir_d="$TMPROOT/stub-d"
make_stubs "$stubdir_d" "" "outer-session-id"
out_d="$(run_hook "$stubdir_d" '{"session_id":"new-session-id","source":""}')"
assert_empty "$out_d" "Nested call: no nudge JSON emitted"
assert_file_empty "$TMPROOT/update-pane-label.log" "Nested call: tmux-update-pane-label not invoked"
assert_file_empty "$TMPROOT/window-label.log" "Nested call: tmux-window-label not invoked"
```

- [ ] **Step 2: Run the test, expect all scenarios still pass**

```bash
bash tests/tmux-claude-session-start.sh
```

Expected: every PASS line including scenario D. (No code change should be needed — the existing early exit already short-circuits.)

If a D assertion fails, the implementation in Task 1 or Task 2 was placed *before* the early-exit `case` block instead of after the last `tmux set-option`. Fix by moving the new code to the very end of the script.

- [ ] **Step 3: Commit**

```bash
git add tests/tmux-claude-session-start.sh
```

Invoke `_commit` skill. Subject suggestion: `Add nested-call regression test for Claude SessionStart hook`.

---

## Task 4: TDD Codex Part 1 — label refresh on SessionStart

**Files:**
- Create: `tests/codex-bind-tmux-pane.sh`
- Modify: `roles/common/files/bin/codex-bind-tmux-pane`

### Background for the implementer

`codex-bind-tmux-pane` currently writes three tmux pane options (`@codex_session_id`, `@codex_session_cwd`, `@codex_session_transcript`) and exits. We're appending the same two label-refresh calls as the Claude hook. The script uses `set -euo pipefail`, so the `|| true` on each call is load-bearing.

### Steps

- [ ] **Step 1: Create the test file with Scenario A (label refresh fires)**

Write `tests/codex-bind-tmux-pane.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
HOOK="$REPO_ROOT/roles/common/files/bin/codex-bind-tmux-pane"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

pass_case() { printf 'PASS  %s\n' "$1"; }
fail_case() { printf 'FAIL  %s\n%s\n' "$1" "$2" >&2; exit 1; }

assert_equals() {
  local actual="$1" expected="$2" name="$3"
  if [ "$actual" != "$expected" ]; then
    fail_case "$name" "expected '$expected', got '$actual'"
  fi
  pass_case "$name"
}

assert_file_contains() {
  local path="$1" needle="$2" name="$3"
  if [ ! -f "$path" ]; then
    fail_case "$name" "missing file: $path"
  fi
  if ! grep -Fq -- "$needle" "$path"; then
    fail_case "$name" "missing '$needle' in $path"
  fi
  pass_case "$name"
}

assert_empty() {
  local content="$1" name="$2"
  if [ -n "$content" ]; then
    fail_case "$name" "expected empty, got: $content"
  fi
  pass_case "$name"
}

# make_stubs <stubdir> <worktree_path_response>
make_stubs() {
  local stubdir="$1" worktree_response="$2"
  mkdir -p "$stubdir"

  cat >"$stubdir/tmux" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMPROOT/tmux.log"
case "\$1" in
  show-options)
    for arg in "\$@"; do
      case "\$arg" in
        @agent_worktree_path) printf '%s' "$worktree_response"; exit 0 ;;
      esac
    done
    exit 0
    ;;
esac
exit 0
STUB
  chmod +x "$stubdir/tmux"

  cat >"$stubdir/tmux-update-pane-label" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMPROOT/update-pane-label.log"
exit 0
STUB
  chmod +x "$stubdir/tmux-update-pane-label"

  cat >"$stubdir/tmux-window-label" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMPROOT/window-label.log"
exit 0
STUB
  chmod +x "$stubdir/tmux-window-label"
}

run_hook() {
  local stubdir="$1" payload="$2"
  : > "$TMPROOT/tmux.log"
  : > "$TMPROOT/update-pane-label.log"
  : > "$TMPROOT/window-label.log"
  printf '%s' "$payload" | TMUX=1 TMUX_PANE="%1" PATH="$stubdir:$PATH" "$HOOK"
}

# ----- Scenario A: resume with @agent_worktree_path set; Part 1 refresh fires. -----
stubdir_a="$TMPROOT/stub-a"
make_stubs "$stubdir_a" "/some/worktree"
out_a="$(run_hook "$stubdir_a" '{"session_id":"abc","cwd":"/tmp/launch","transcript_path":"/tmp/t.jsonl"}')"

assert_file_contains "$TMPROOT/update-pane-label.log" "%1" "Part 1: tmux-update-pane-label invoked with TMUX_PANE"
assert_file_contains "$TMPROOT/window-label.log" "%1" "Part 1: tmux-window-label invoked with TMUX_PANE"

printf 'codex-bind-tmux-pane checks complete\n'
```

Mark executable:

```bash
chmod +x tests/codex-bind-tmux-pane.sh
```

- [ ] **Step 2: Run the test, confirm it fails**

```bash
bash tests/codex-bind-tmux-pane.sh
```

Expected: `FAIL  Part 1: tmux-update-pane-label invoked with TMUX_PANE`.

- [ ] **Step 3: Edit `roles/common/files/bin/codex-bind-tmux-pane` to add Part 1**

Append after the existing final `tmux set-option ... @codex_session_transcript ...` line:

```bash

# Part 1: refresh the cached pane label and rename the window. Idempotent.
tmux-update-pane-label "$TMUX_PANE" >/dev/null 2>&1 || true
tmux-window-label "$TMUX_PANE" >/dev/null 2>&1 || true
```

- [ ] **Step 4: Run the test, confirm it passes**

```bash
bash tests/codex-bind-tmux-pane.sh
```

Expected: both `PASS  Part 1: ...` lines.

- [ ] **Step 5: Commit**

```bash
git add tests/codex-bind-tmux-pane.sh roles/common/files/bin/codex-bind-tmux-pane
```

Invoke `_commit` skill. Subject suggestion: `Refresh window label on Codex SessionStart`.

---

## Task 5: TDD Codex Part 2 — nudge fires/suppressed based on `@agent_worktree_path`

**Files:**
- Modify: `tests/codex-bind-tmux-pane.sh`
- Modify: `roles/common/files/bin/codex-bind-tmux-pane`

### Steps

- [ ] **Step 1: Append scenarios B and C to the test file**

Insert before the final `printf 'codex-bind-tmux-pane checks complete\n'`:

```bash

# ----- Scenario B: @agent_worktree_path UNSET; nudge fires. -----
stubdir_b="$TMPROOT/stub-b"
make_stubs "$stubdir_b" ""
out_b="$(run_hook "$stubdir_b" '{"session_id":"abc","cwd":"/tmp/launch","transcript_path":"/tmp/t.jsonl"}')"

event="$(printf '%s' "$out_b" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null || true)"
ctx="$(printf '%s' "$out_b" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true)"
assert_equals "$event" "SessionStart" "Part 2: hookEventName is SessionStart when @agent_worktree_path is unset"
case "$ctx" in
  *"tmux-agent-worktree set"*) pass_case "Part 2: additionalContext mentions tmux-agent-worktree set" ;;
  *) fail_case "Part 2: additionalContext mentions tmux-agent-worktree set" "got: $ctx" ;;
esac
case "$ctx" in
  *"active worktree"*) pass_case "Part 2: additionalContext mentions 'active worktree'" ;;
  *) fail_case "Part 2: additionalContext mentions 'active worktree'" "got: $ctx" ;;
esac
assert_file_contains "$TMPROOT/update-pane-label.log" "%1" "Part 1: label refresh still invoked when nudge fires"

# ----- Scenario C: @agent_worktree_path SET; nudge suppressed. -----
stubdir_c="$TMPROOT/stub-c"
make_stubs "$stubdir_c" "/some/worktree"
out_c="$(run_hook "$stubdir_c" '{"session_id":"abc","cwd":"/tmp/launch","transcript_path":"/tmp/t.jsonl"}')"
assert_empty "$out_c" "Part 2 suppressed when @agent_worktree_path is set"
```

- [ ] **Step 2: Run, confirm scenarios B and C fail**

```bash
bash tests/codex-bind-tmux-pane.sh
```

Expected: scenarios B and C fail on the JSON shape and emptiness assertions.

- [ ] **Step 3: Edit `roles/common/files/bin/codex-bind-tmux-pane` to add Part 2**

Append after the two lines added in Task 4:

```bash

# Part 2: when the pane has no @agent_worktree_path, nudge the agent to
# republish via `tmux-agent-worktree set`. Same rationale as Claude.
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
```

- [ ] **Step 4: Run the test, confirm all scenarios pass**

```bash
bash tests/codex-bind-tmux-pane.sh
```

Expected: every PASS line.

- [ ] **Step 5: Commit**

```bash
git add tests/codex-bind-tmux-pane.sh roles/common/files/bin/codex-bind-tmux-pane
```

Invoke `_commit` skill. Subject suggestion: `Nudge agent to republish worktree on Codex SessionStart`.

---

## Task 6: Wire new test files into CI

**Files:**
- Modify: `.github/workflows/integration-test.yml`

### Background

`tests/ci-test-inventory.sh` asserts every file under `tests/` is referenced by at least one `run:` step in `.github/workflows/*.yml`. The two new test scripts must be registered or the inventory test will fail in CI.

The existing tmux test entries in `integration-test.yml` look like:

```yaml
      - name: Verify tmux label contract
        run: bash tests/tmux-label-contract.sh

      - name: Verify tmux pane-link contract
        run: bash tests/tmux-pane-link.sh
```

Add two new entries in the same style, right after them.

### Steps

- [ ] **Step 1: Inspect current CI test entries**

```bash
grep -n "tmux\|tests/" .github/workflows/integration-test.yml | head -30
```

Note the line numbers of the existing tmux test steps so the new entries can be inserted contiguously.

- [ ] **Step 2: Add the two new test invocations**

Insert (immediately after `tests/tmux-pane-link.sh` and before the next non-tmux step):

```yaml
      - name: Verify Claude SessionStart hook contract
        run: bash tests/tmux-claude-session-start.sh

      - name: Verify Codex SessionStart hook contract
        run: bash tests/codex-bind-tmux-pane.sh
```

- [ ] **Step 3: Run the CI-inventory test locally to confirm the new entries are detected**

```bash
bash tests/ci-test-inventory.sh
```

Expected: `PASS  every tracked test-like file is referenced by CI`.

- [ ] **Step 4: Run the full set of new + adjacent tests locally**

```bash
bash tests/tmux-claude-session-start.sh && \
bash tests/codex-bind-tmux-pane.sh && \
bash tests/tmux-label-contract.sh && \
bash tests/ci-test-inventory.sh
```

Expected: all four scripts exit 0 with a final summary line each.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/integration-test.yml
```

Invoke `_commit` skill. Subject suggestion: `Wire SessionStart hook tests into CI`.

---

## Final verification

After all six tasks are committed:

- [ ] **Inspect the worktree git log**

```bash
git log --oneline main..HEAD
```

Expected: 6 new commits on top of `b306dd8 Spec: add agent-nudge mechanism for cross-pane resume` (and the spec commits ahead of `main`).

- [ ] **Run every changed test plus the broader test suite**

```bash
bash tests/tmux-claude-session-start.sh && \
bash tests/codex-bind-tmux-pane.sh && \
bash tests/tmux-label-contract.sh && \
bash tests/tmux-pane-link.sh && \
ruby tests/tmux-pane-title-changed.rb && \
bash tests/ci-test-inventory.sh
```

Expected: all exit 0.

- [ ] **Eyeball the diff**

```bash
git diff main..HEAD -- roles/common/files/bin/tmux-claude-session-start roles/common/files/bin/codex-bind-tmux-pane
```

Confirm both files gained Part 1 (two helper calls) and Part 2 (one `show-options` + conditional jq emit) appended at the end, and that the existing logic is untouched.
