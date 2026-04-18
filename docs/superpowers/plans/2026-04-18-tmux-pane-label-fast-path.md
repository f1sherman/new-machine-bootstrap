# Tmux Pane Label Fast Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the unconditional `ps` call from the local tmux pane-label hot path while preserving SSH, Codespaces, and DevPod labels.

**Architecture:** Keep the existing helper-based tmux label architecture. Extend `tmux-pane-label` and `tmux-window-label` to accept `pane_current_command` as a non-visible hint, use a local fast path that derives labels from `pane_current_path` plus direct `.git/HEAD` reads, and only fall back to `ps` for remote-candidate commands (`ssh`, `gh`, `ruby`). Update both tmux config files to pass the extra hint and verify behavior through the existing shell test harnesses plus a fresh `bin/provision`.

**Tech Stack:** tmux, bash helper scripts, existing shell test harnesses, Ansible-managed dotfiles

---

### Task 1: Extend `tmux-pane-label` regression coverage

**Files:**
- Modify: `roles/common/files/bin/tmux-pane-label.test`
- Test: `roles/common/files/bin/tmux-pane-label.test`

- [ ] **Step 1: Change the test harness to pass a third `pane_current_command` argument and record whether `ps` was called**

```bash
run_case() {
  local name="$1" tty="$2" path="$3" pane_current_command="$4" expected="$5" fixture="$6" expected_ps_calls="$7"

  printf '%s\n' "$fixture" > "$tmp_root/$tty"
  : > "$ps_log"

  local output ps_calls
  output="$(PATH="$fake_bin:$PATH" PS_CALL_LOG="$ps_log" PS_FIXTURE_DIR="$tmp_root" bash "$script" "$tty" "$path" "$pane_current_command" 2>/dev/null || true)"
  ps_calls="$(wc -l < "$ps_log" | tr -d ' ')"

  assert_eq "$ps_calls" "$expected_ps_calls" "$name ps call count"
  assert_eq "$output" "$expected" "$name output"
}
```

- [ ] **Step 2: Add local fast-path cases that should skip `ps` entirely**

```bash
run_case \
  "local git pane skips ps" \
  "tty-local-git" \
  "$git_repo" \
  "zsh" \
  "feature/foo repo" \
  "shell: zsh" \
  "0"

run_case \
  "local non-git pane skips ps" \
  "tty-local-tmp" \
  "$tmp_dir" \
  "bash" \
  "tmp" \
  "shell: login" \
  "0"
```

- [ ] **Step 3: Add remote-candidate cases that must still consult `ps` and preserve remote labels**

```bash
run_case \
  "plain ssh pane keeps host label" \
  "tty-ssh" \
  "$tmp_dir" \
  "ssh" \
  "claw02" \
  "ssh dev@claw02 -p 22" \
  "1"

run_case \
  "codespaces pane keeps codespace label" \
  "tty-codespace" \
  "$tmp_dir" \
  "gh" \
  "space-alpha" \
  "gh codespace ssh --codespace space-alpha" \
  "1"

run_case \
  "devpod pane keeps workspace label via ruby hint" \
  "tty-devpod" \
  "$tmp_dir" \
  "ruby" \
  "workspace-beta" \
  "devpod ssh workspace-beta" \
  "1"
```

- [ ] **Step 4: Add the fallback case proving a remote-candidate hint that is not actually remote still returns the local label**

```bash
run_case \
  "ruby local pane falls back to local label" \
  "tty-ruby-local" \
  "$tmp_dir" \
  "ruby" \
  "tmp" \
  "ruby script/server" \
  "1"
```

- [ ] **Step 5: Run the pane-label test to verify the new expectations fail before implementation**

Run: `bash roles/common/files/bin/tmux-pane-label.test`

Expected: FAIL because `tmux-pane-label` still always calls `ps` and does not yet use the third argument as a fast-path gate.

### Task 2: Extend plumbing tests for the new argument

**Files:**
- Modify: `roles/common/files/bin/tmux-window-label.test`
- Modify: `roles/common/files/bin/tmux-window-bar-config.test`
- Test: `roles/common/files/bin/tmux-window-label.test`
- Test: `roles/common/files/bin/tmux-window-bar-config.test`

- [ ] **Step 1: Update `tmux-window-label.test` so the fake helper logs the third argument**

```bash
cat > "$fake_bin/tmux-pane-label" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log="${PANE_LABEL_LOG:?}"
printf '%s|%s|%s\n' "${1:-}" "${2:-}" "${3:-}" >> "$log"
printf '%s\n' "${PANE_LABEL_OUTPUT:-}"
EOF
```

- [ ] **Step 2: Update the display-message fixture and assertions to include `#{pane_current_command}`**

```bash
run_case \
  "%11" \
  $'@7\t1\tmain dotfiles\t/dev/ttys001\t/tmp/repo\tzsh' \
  "feature/foo repo"

assert_file_contains "$tmux_log" $'display-message -p -t %11 #{window_id}\t#{pane_active}\t#{window_name}\t#{pane_tty}\t#{pane_current_path}\t#{pane_current_command}' "active pane queries tmux"
assert_file_contains "$pane_label_log" "/dev/ttys001|/tmp/repo|zsh" "active pane derives label"
```

- [ ] **Step 3: Update `tmux-window-bar-config.test` so both tmux configs must pass `#{pane_current_command}` into `tmux-pane-label`**

```bash
assert_contains "$file" "set -g pane-border-format '#{?pane_active,#[bg=black#,fg=colour51],#[bg=black#,fg=colour240]} #(~/.local/bin/tmux-pane-label \"#{pane_tty}\" \"#{pane_current_path}\" \"#{pane_current_command}\") '"
```

- [ ] **Step 4: Run the plumbing tests to verify they fail before implementation**

Run: `bash roles/common/files/bin/tmux-window-label.test`

Expected: FAIL because `tmux-window-label` still queries only `pane_tty` and `pane_current_path` and forwards only two helper arguments.

Run: `bash roles/common/files/bin/tmux-window-bar-config.test`

Expected: FAIL because both tmux config files still call `tmux-pane-label` with only two arguments.

### Task 3: Implement the fast path and verify the managed install

**Files:**
- Modify: `roles/common/files/bin/tmux-pane-label`
- Modify: `roles/common/files/bin/tmux-window-label`
- Modify: `roles/macos/templates/dotfiles/tmux.conf`
- Modify: `roles/linux/files/dotfiles/tmux.conf`
- Test: `roles/common/files/bin/tmux-pane-label.test`
- Test: `roles/common/files/bin/tmux-window-label.test`
- Test: `roles/common/files/bin/tmux-window-bar-config.test`

- [ ] **Step 1: Update `tmux-pane-label` to accept `pane_current_command`, classify remote candidates, and skip `ps` for clearly local panes**

```bash
pane_tty="${1:-}"
pane_current_path="${2:-}"
pane_current_command="${3:-}"

is_remote_candidate_command() {
  case "$1" in
    ssh|gh|ruby) return 0 ;;
    *) return 1 ;;
  esac
}

if ! is_remote_candidate_command "$pane_current_command"; then
  if branch="$(git_branch_for_path "$pane_current_path" 2>/dev/null)"; then
    printf '%s\n' "$branch $(dir_basename "$pane_current_path")"
  else
    dir_basename "$pane_current_path"
  fi
  exit 0
fi

pane_procs="$(ps -o args= -t "$pane_tty" 2>/dev/null || true)"
```

- [ ] **Step 2: Keep the existing remote parsing logic and preserve the local fallback after the `ps` path**

```bash
while IFS= read -r line; do
  case "$line" in
    *"gh codespace ssh"*|*"gh cs ssh"*)
      label="$(extract_codespace_name "$line" || true)"
      [ -n "$label" ] || label="codespace"
      break
      ;;
    *"devpod ssh"*)
      label="$(extract_devpod_workspace "$line" || true)"
      [ -n "$label" ] || label="devpod"
      break
      ;;
    ssh* )
      label="$(extract_ssh_host "$line" || true)"
      [ -n "$label" ] || label="ssh"
      break
      ;;
  esac
done <<< "$pane_procs"

if [ -z "$label" ]; then
  if branch="$(git_branch_for_path "$pane_current_path" 2>/dev/null)"; then
    label="$branch $(dir_basename "$pane_current_path")"
  else
    label="$(dir_basename "$pane_current_path")"
  fi
fi
```

- [ ] **Step 3: Update `tmux-window-label` to fetch and forward `pane_current_command` in the existing tmux RPC**

```bash
pane_info="$(tmux display-message -p -t "$pane_id" '#{window_id}	#{pane_active}	#{window_name}	#{pane_tty}	#{pane_current_path}	#{pane_current_command}' 2>/dev/null || true)"
IFS=$'\t' read -r window_id pane_active window_name pane_tty pane_current_path pane_current_command <<< "$pane_info"

label="$("$label_helper" "$pane_tty" "$pane_current_path" "$pane_current_command" 2>/dev/null || true)"
```

- [ ] **Step 4: Update both tmux configs to pass `#{pane_current_command}` into `tmux-pane-label`**

```tmux
set -g pane-border-format '#{?pane_active,#[bg=black#,fg=colour51],#[bg=black#,fg=colour240]} #(~/.local/bin/tmux-pane-label "#{pane_tty}" "#{pane_current_path}" "#{pane_current_command}") '
```

- [ ] **Step 5: Run the targeted regression tests and make sure they all pass**

Run: `bash roles/common/files/bin/tmux-pane-label.test`
Expected: PASS

Run: `bash roles/common/files/bin/tmux-window-label.test`
Expected: PASS

Run: `bash roles/common/files/bin/tmux-window-bar-config.test`
Expected: PASS

- [ ] **Step 6: Apply the managed files locally and verify the installed helper matches the repo**

Run: `bin/provision`
Expected: Ansible exits 0 and updates the managed tmux helper/config if needed.

Run: `cmp -s roles/common/files/bin/tmux-pane-label "$HOME/.local/bin/tmux-pane-label" && echo installed-helper-matches-repo`
Expected: `installed-helper-matches-repo`

- [ ] **Step 7: Commit the implementation**

```bash
git add \
  roles/common/files/bin/tmux-pane-label \
  roles/common/files/bin/tmux-window-label \
  roles/common/files/bin/tmux-pane-label.test \
  roles/common/files/bin/tmux-window-label.test \
  roles/common/files/bin/tmux-window-bar-config.test \
  roles/macos/templates/dotfiles/tmux.conf \
  roles/linux/files/dotfiles/tmux.conf
git commit -m "Reduce tmux pane label fork cost"
```
