# Stale Remote Window Label Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent stale restored `@window-label` values from briefly overriding structured remote task titles on pane focus.

**Architecture:** `tmux-window-label` will treat its cached top label as locally owned only when all canonical local task fields exist. Without that ownership evidence, the existing structured remote-title parser runs first and supplies the task label; ordinary path and pane-label fallbacks remain unchanged.

**Tech Stack:** Bash, tmux formats/options, shell contract tests

## Global Constraints

- Keep the fix inside `tmux-window-label` and its contract tests.
- Do not reorder tmux hooks or add restore-specific cleanup.
- Preserve cached local-label precedence when `@task_state`, `@task_source`, and `@task_label` are all present.

---

### Task 1: Validate Cached Window Label Ownership

**Files:**
- Modify: `roles/common/files/bin/tmux-window-label:17-19`
- Modify: `tests/tmux-label-contract.sh:617-644`

**Interfaces:**
- Consumes: pane-scoped tmux options `@window-label`, `@task_state`, `@task_source`, and `@task_label`.
- Produces: `label` initialized from `@window-label` only for complete local task state; otherwise the existing remote-title and fallback flow resolves it.

- [ ] **Step 1: Add failing stale-cache and valid-cache contract cases**

Update the remote-priority tmux stub so `show-options` reads `TMUX_TEST_LOCAL_TASK`:

```bash
@window-label) printf 'codex: tmux subject labels' ;;
@task_state) [ -z "${TMUX_TEST_LOCAL_TASK:-}" ] || printf 'provisional' ;;
@task_source) [ -z "${TMUX_TEST_LOCAL_TASK:-}" ] || printf 'agent' ;;
@task_label) [ -z "${TMUX_TEST_LOCAL_TASK:-}" ] || printf 'tmux subject labels' ;;
```

Invoke it once without local task state and assert the structured remote task wins:

```bash
TMUX_WINDOW_LABEL_LOG="$remote_window_label_log" PATH="$remote_window_label_tmux_dir:$PATH" "$WINDOW_LABEL" "%5"
assert_file_contains "$remote_window_label_log" "rename-window -t @5 feature/remote-title" "structured remote task overrides stale cached window label"
```

Clear the log, invoke with `TMUX_TEST_LOCAL_TASK=1`, and assert the intentional local cache wins:

```bash
: > "$remote_window_label_log"
TMUX_TEST_LOCAL_TASK=1 TMUX_WINDOW_LABEL_LOG="$remote_window_label_log" PATH="$remote_window_label_tmux_dir:$PATH" "$WINDOW_LABEL" "%5"
assert_file_contains "$remote_window_label_log" "rename-window -t @5 codex: tmux subject labels" "valid local task keeps cached window label precedence"
```

- [ ] **Step 2: Run the contract suite and confirm the regression fails**

Run: `bash tests/tmux-label-contract.sh`

Expected: FAIL at `structured remote task overrides stale cached window label`; the log contains `rename-window -t @5 codex: tmux subject labels`.

- [ ] **Step 3: Implement local cache ownership validation**

Replace unconditional cached-label initialization with complete local task-field validation:

```bash
cached_window_label="$(tmux show-options -qv -p -t "$pane_id" "@window-label" 2>/dev/null || true)"
task_state="$(tmux show-options -qv -p -t "$pane_id" "@task_state" 2>/dev/null || true)"
task_source="$(tmux show-options -qv -p -t "$pane_id" "@task_source" 2>/dev/null || true)"
task_label="$(tmux show-options -qv -p -t "$pane_id" "@task_label" 2>/dev/null || true)"
label=""
if [ -n "$task_state" ] && [ -n "$task_source" ] && [ -n "$task_label" ]; then
  label="$cached_window_label"
fi
task_label_resolved=""
```

- [ ] **Step 4: Run focused verification**

Run:

```bash
bash -n roles/common/files/bin/tmux-window-label
bash tests/tmux-label-contract.sh
```

Expected: syntax check exits 0; all tmux label contract checks pass, including both new cache-ownership assertions.

- [ ] **Step 5: Commit the implementation**

Commit `roles/common/files/bin/tmux-window-label` and `tests/tmux-label-contract.sh` with message `Fix stale remote tmux window labels`.
