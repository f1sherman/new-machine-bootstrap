# Tmux Agent Worktree Label Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore tmux pane and window labels so agent panes show the published linked worktree label instead of the primary checkout label.

**Architecture:** Keep the current per-pane tmux chrome and fast local-label path. Make `tmux-pane-label` optionally consume pane-local explicit worktree state when tmux passes `#{pane_id}`, then fall back to today's `pane_current_path` and remote parsing behavior. Wire the new argument through tmux config and `tmux-window-label`, and cover the new path with shell tests.

**Tech Stack:** Bash, tmux format strings, git worktree metadata, existing shell test harnesses

---

### Task 1: Make `tmux-pane-label` Prefer Valid Explicit Agent Worktree State

**Files:**
- Modify: `roles/common/files/bin/tmux-pane-label`
- Test: `roles/common/files/bin/tmux-pane-label.test`

- [ ] **Step 1: Add failing tests for explicit pane state in `roles/common/files/bin/tmux-pane-label.test`**

Add a fake `tmux` binary alongside the existing fake `ps`, plus state fixtures for
`@agent_worktree_path` and `@agent_worktree_pid`. Keep the existing local/remote
cases, then add these explicit-state cases:

```bash
cat > "$fake_bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state_dir="${TMUX_STATE_DIR:?}"

case "${1:-}" in
  show-options)
    shift
    [ "${1:-}" = "-pv" ] || exit 2
    shift
    [ "${1:-}" = "-t" ] || exit 2
    pane_id="${2:-}"
    option_name="${3:-}"
    file="$state_dir/${pane_id}.${option_name}"
    [ -f "$file" ] || exit 1
    cat "$file"
    ;;
  list-panes)
    printf '%%11\n'
    ;;
esac
EOF
chmod +x "$fake_bin/tmux"
```

Add helper setup plus new cases:

```bash
write_state() {
  local pane_id="$1" option_name="$2" value="$3"
  printf '%s' "$value" > "$tmux_state_dir/${pane_id}.${option_name}"
}

linked_main="$tmp_root/main-repo"
git -c init.templateDir="$git_template" -C "$linked_main" init -b main >/dev/null
git -C "$linked_main" commit --allow-empty -m init >/dev/null
linked_worktree="$tmp_root/feature-repo"
git -C "$linked_main" worktree add -b feature/agent "$linked_worktree" >/dev/null 2>&1

run_case \
  "explicit state overrides pane path" \
  "tty-agent" \
  "$tmp_dir" \
  "zsh" \
  "feature/agent feature-repo" \
  $'9001 S+ codex codex' \
  "1" \
  "%11" \
  "$linked_worktree" \
  "9001"

run_case \
  "stale explicit pid falls back to pane path" \
  "tty-agent-stale" \
  "$git_repo" \
  "zsh" \
  "feature/foo repo" \
  $'9001 S+ codex codex' \
  "1" \
  "%11" \
  "$linked_worktree" \
  "9999"

run_case \
  "primary checkout explicit path falls back to pane path" \
  "tty-agent-main" \
  "$git_repo" \
  "zsh" \
  "feature/foo repo" \
  $'9001 S+ codex codex' \
  "1" \
  "%11" \
  "$linked_main" \
  "9001"
```

Keep `run_case` backward-compatible by making the explicit-state arguments optional.

- [ ] **Step 2: Run the targeted test to verify it fails**

Run:

```bash
bash roles/common/files/bin/tmux-pane-label.test
```

Expected: FAIL in the new explicit-state cases because `tmux-pane-label` never
reads `@agent_worktree_path` / `@agent_worktree_pid`.

- [ ] **Step 3: Implement explicit-state lookup in `roles/common/files/bin/tmux-pane-label`**

Add an optional fourth arg and the minimal helpers needed from the existing
`tmux-agent-pane-status` logic:

```bash
pane_tty="${1:-}"
pane_current_path="${2:-}"
pane_current_command="${3:-}"
pane_id="${4:-}"

get_process_lines() {
  local tty="$1"
  [ -n "$tty" ] || return 0
  ps -o pid=,stat=,comm=,args= -t "$tty" 2>/dev/null
}

is_agent_process() {
  local comm="$1" args="$2"
  case "$comm" in
    claude|codex) return 0 ;;
  esac
  printf '%s\n' "$args" | grep -Eq '(^|[[:space:]])([^[:space:]]*/)?(claude|codex)([[:space:]]|$)'
}

detect_agent_pid() {
  local tty="$1" line pid stat comm args fg_pid="" any_pid=""
  while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue
    read -r pid stat comm args <<< "$line"
    is_agent_process "${comm:-}" "${args:-}" || continue
    any_pid="$pid"
    case "$stat" in
      *+*) fg_pid="$pid" ;;
    esac
  done < <(get_process_lines "$tty")

  if [ -n "$fg_pid" ]; then
    printf '%s\n' "$fg_pid"
  elif [ -n "$any_pid" ]; then
    printf '%s\n' "$any_pid"
  fi
}

read_pane_option() {
  local pane_id="$1" option_name="$2"
  [ -n "$pane_id" ] || return 1
  tmux show-options -pv -t "$pane_id" "$option_name" 2>/dev/null
}

is_linked_worktree() {
  local path="$1" git_dir common_dir
  git_dir=$(git -C "$path" rev-parse --path-format=absolute --git-dir 2>/dev/null) || return 1
  common_dir=$(git -C "$path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  [ "$git_dir" != "$common_dir" ]
}

explicit_label() {
  local active_pid explicit_pid explicit_path branch
  [ -n "$pane_id" ] || return 1
  active_pid="$(detect_agent_pid "$pane_tty")"
  [ -n "$active_pid" ] || return 1

  explicit_pid="$(read_pane_option "$pane_id" "@agent_worktree_pid" || true)"
  explicit_path="$(read_pane_option "$pane_id" "@agent_worktree_path" || true)"
  [ -n "$explicit_pid" ] && [ "$explicit_pid" = "$active_pid" ] || return 1
  [ -d "$explicit_path" ] || return 1
  [ "$(git -C "$explicit_path" rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ] || return 1
  is_linked_worktree "$explicit_path" || return 1

  branch="$(git_branch_for_path "$explicit_path" 2>/dev/null || true)"
  [ -n "$branch" ] || return 1
  printf '%s\n' "$branch $(dir_basename "$explicit_path")"
}

if label="$(explicit_label 2>/dev/null)"; then
  printf '%s\n' "$label"
  exit 0
fi
```

Leave the current fast-path remote/local logic in place after this explicit-state
attempt.

- [ ] **Step 4: Run the targeted test to verify it passes**

Run:

```bash
bash roles/common/files/bin/tmux-pane-label.test
```

Expected: PASS for both the old fast-path cases and the new explicit-state
override/fallback cases.

- [ ] **Step 5: Commit Task 1**

Run:

```bash
~/.codex/skills/_commit/commit.sh -m "Prefer tmux labels from agent worktree state" \
  roles/common/files/bin/tmux-pane-label \
  roles/common/files/bin/tmux-pane-label.test
```

Expected: one commit containing only the helper plus its test updates.

### Task 2: Pass `pane_id` Through tmux and Window-Label Plumbing

**Files:**
- Modify: `roles/common/files/bin/tmux-window-label`
- Modify: `roles/common/files/bin/tmux-window-label.test`
- Modify: `roles/common/files/bin/tmux-window-bar-config.test`
- Modify: `roles/linux/files/dotfiles/tmux.conf`
- Modify: `roles/macos/templates/dotfiles/tmux.conf`

- [ ] **Step 1: Add failing tests for the new `pane_id` plumbing**

Update `roles/common/files/bin/tmux-window-label.test` so the fake
`tmux-pane-label` logs four arguments instead of three:

```bash
cat > "$fake_bin/tmux-pane-label" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log="${PANE_LABEL_LOG:?}"
printf '%s|%s|%s|%s\n' "${1:-}" "${2:-}" "${3:-}" "${4:-}" >> "$log"
printf '%s\n' "${PANE_LABEL_OUTPUT:-}"
EOF
```

Update assertions to require the pane id:

```bash
assert_file_contains "$pane_label_log" "/dev/ttys001|/tmp/repo|zsh|%11" "active pane derives label"
assert_file_contains "$pane_label_log" "/dev/ttys002|/tmp/repo|zsh|%12" "unchanged label still derives"
```

Update `roles/common/files/bin/tmux-window-bar-config.test` to require the new
tmux config format:

```bash
assert_contains "$file" "set -g pane-border-format '#{?pane_active,#[bg=black#,fg=colour51],#[bg=black#,fg=colour240]} #(~/.local/bin/tmux-pane-label \"#{pane_tty}\" \"#{pane_current_path}\" \"#{pane_current_command}\" \"#{pane_id}\") '"
```

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run:

```bash
bash roles/common/files/bin/tmux-window-label.test
bash roles/common/files/bin/tmux-window-bar-config.test
```

Expected: FAIL because the helper and tmux config still pass only three
arguments to `tmux-pane-label`.

- [ ] **Step 3: Implement the `pane_id` wiring**

Update `roles/common/files/bin/tmux-window-label`:

```bash
pane_info="$(tmux display-message -p -t "$pane_id" '#{window_id}	#{pane_active}	#{window_name}	#{pane_tty}	#{pane_current_path}	#{pane_current_command}	#{pane_id}' 2>/dev/null || true)"

IFS=$'\t' read -r window_id pane_active window_name pane_tty pane_current_path pane_current_command resolved_pane_id <<< "$pane_info"

label="$("$label_helper" "$pane_tty" "$pane_current_path" "$pane_current_command" "$resolved_pane_id" 2>/dev/null || true)"
```

Update both tmux config files:

```tmux
set -g pane-border-format '#{?pane_active,#[bg=black#,fg=colour51],#[bg=black#,fg=colour240]} #(~/.local/bin/tmux-pane-label "#{pane_tty}" "#{pane_current_path}" "#{pane_current_command}" "#{pane_id}") '
```

Do not change any other tmux chrome.

- [ ] **Step 4: Run the targeted tests to verify they pass**

Run:

```bash
bash roles/common/files/bin/tmux-window-label.test
bash roles/common/files/bin/tmux-window-bar-config.test
```

Expected: PASS, with the tests confirming that pane ids flow through both the
window-label helper and the tmux config templates.

- [ ] **Step 5: Commit Task 2**

Run:

```bash
~/.codex/skills/_commit/commit.sh -m "Pass pane ids into tmux pane labels" \
  roles/common/files/bin/tmux-window-label \
  roles/common/files/bin/tmux-window-label.test \
  roles/common/files/bin/tmux-window-bar-config.test \
  roles/linux/files/dotfiles/tmux.conf \
  roles/macos/templates/dotfiles/tmux.conf
```

Expected: one commit containing only the pane-id wiring and test updates.

### Task 3: Run Final Verification for the Restored Label Path

**Files:**
- Verify only; no planned file edits

- [ ] **Step 1: Run the focused verification suite**

Run:

```bash
bash roles/common/files/bin/tmux-pane-label.test
bash roles/common/files/bin/tmux-window-label.test
bash roles/common/files/bin/tmux-window-bar-config.test
bash roles/common/files/bin/tmux-agent-worktree.test
```

Expected: PASS on all four scripts.

- [ ] **Step 2: Review the final diff for scope**

Run:

```bash
git status --short
git diff --stat origin/main...
```

Expected: only the five planned implementation files plus their tests and the
already-committed spec/plan artifacts on this branch.

- [ ] **Step 3: If verification required any fixes, commit them**

If the verification step forced follow-up edits, commit only those files with:

```bash
~/.codex/skills/_commit/commit.sh -m "Fix tmux worktree label verification gaps" <files...>
```

If no fixes were needed, do not create an extra commit.
