# PR tmux status display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let NMB tmux lifecycle hooks refresh an agent pane label from HNP's PR-aware `tmux-label-format` helper when that helper is installed.

**Architecture:** NMB still owns tmux pane state and rendering. `tmux-agent-worktree set` and `sync-current` will prefer the external `tmux-label-format local <path>` formatter for explicit agent worktree labels, then fall back to the built-in `(branch) repo | host` label when the formatter is absent, empty, or failing.

**Tech Stack:** Bash, tmux user options, existing shell integration tests.

---

## File Structure

- Modify `roles/common/files/bin/tmux-agent-worktree` to call `tmux-label-format local <path>` before built-in label construction.
- Modify `tests/tmux-label-contract.sh` to prove `set` and `sync-current` use the formatter and retain fallback behavior.

### Task 1: NMB HNP-Aware Pane Label Refresh

**Files:**
- Modify: `roles/common/files/bin/tmux-agent-worktree`
- Test: `tests/tmux-label-contract.sh`

- [ ] **Step 1: Write failing formatter-backed tests**

In `tests/tmux-label-contract.sh`, after the existing `repo-start tmux writer stores repo branch pane label` assertion and before the clear case, add:

```bash
formatter_bin="$TMPROOT/formatter-bin"
mkdir -p "$formatter_bin"
cat >"$formatter_bin/tmux-label-format" <<STUB
#!/usr/bin/env bash
if [ "\$1" = "local" ] && [ "\$2" = "$repo_path" ]; then
  printf '(feature/label fj#42) label-repo\n'
  exit 0
fi
printf 'unexpected tmux-label-format args: %s\n' "\$*" >&2
exit 1
STUB
chmod +x "$formatter_bin/tmux-label-format"

formatter_state_dir="$TMPROOT/state-formatter"
TMUX=1 \
TMUX_PANE="%8" \
TMUX_AGENT_WORKTREE_STATE_DIR="$formatter_state_dir" \
TMUX_AGENT_WORKTREE_PANE_TTY=/dev/null \
PATH="$formatter_bin:$stub_bin:$PATH" \
  "$AGENT_WORKTREE" set "$repo_path"

assert_file_contains "$formatter_state_dir/%8.@pane-label" "(feature/label fj#42) label-repo" "tmux writer uses tmux-label-format when available"

sync_state_dir="$TMPROOT/state-sync-current"
(
  cd "$repo_path"
  TMUX=1 \
  TMUX_PANE="%9" \
  TMUX_AGENT_WORKTREE_STATE_DIR="$sync_state_dir" \
  TMUX_AGENT_WORKTREE_PANE_TTY=/dev/null \
  PATH="$formatter_bin:$stub_bin:$PATH" \
    "$AGENT_WORKTREE" sync-current
)

assert_file_contains "$sync_state_dir/%9.@pane-label" "(feature/label fj#42) label-repo" "sync-current uses tmux-label-format when available"
```

- [ ] **Step 2: Run RED test**

Run:

```bash
bash tests/tmux-label-contract.sh
```

Expected: fail because `tmux-agent-worktree` still uses its built-in label formatter.

- [ ] **Step 3: Implement formatter preference**

In `roles/common/files/bin/tmux-agent-worktree`, add this function before `repo_label_for_path`:

```bash
formatted_repo_label_for_path() {
  local path="$1" formatter label

  formatter="$(command -v tmux-label-format 2>/dev/null)" || return 1
  label="$("$formatter" local "$path" 2>/dev/null || true)"
  [ -n "$label" ] || return 1
  printf '%s\n' "$label"
}
```

Then make `repo_label_for_path` prefer the formatter:

```bash
repo_label_for_path() {
  local path="$1" repo branch host formatted

  formatted="$(formatted_repo_label_for_path "$path" 2>/dev/null || true)"
  if [ -n "$formatted" ]; then
    printf '%s\n' "$formatted"
    return 0
  fi

  repo="$(repo_basename "$path" 2>/dev/null || true)"
  branch="$(branch_for_path "$path" 2>/dev/null || true)"
  host="$(host_tag)"
  [ -n "$repo" ] || repo="$(dir_basename "$path")"
```

Keep the rest of the existing fallback body unchanged.

- [ ] **Step 4: Run GREEN tests**

Run:

```bash
bash tests/tmux-label-contract.sh
bash tests/tmux-pane-link.sh
```

Expected: both pass.

- [ ] **Step 5: Commit Task 1**

Run:

```bash
/home/brian/.codex/skills/_commit/commit.sh -m "Refresh agent labels with PR-aware formatter" \
  roles/common/files/bin/tmux-agent-worktree \
  tests/tmux-label-contract.sh
```
