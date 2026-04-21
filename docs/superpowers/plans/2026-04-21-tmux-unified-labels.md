# Tmux Unified Labels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make tmux pane-border labels and top-bar window labels use one repo-first contract locally and remotely, keep remote labels from degrading to bare-host names, and add a visible separator between window names.

**Architecture:** Add one shared tmux label formatter under `roles/common/files/bin/` and route `tmux-pane-label`, `tmux-window-label`, and `tmux-remote-title` through it. Keep `worktree-start` and pane-local explicit worktree state as the preferred remote fast path, then add a narrow guard in the window/session rename helpers so a structured remote label is not overwritten by a transient host-only title.

**Tech Stack:** Bash, tmux, git, Ansible-managed dotfiles, shell test harnesses.

---

### Task 1: Lock the new label contract in failing tests

**Files:**
- Modify: `roles/common/files/bin/tmux-pane-label.test`
- Modify: `roles/common/files/bin/tmux-window-label.test`
- Modify: `roles/common/files/bin/tmux-remote-title.test`
- Modify: `roles/common/files/bin/tmux-session-name.test`
- Modify: `roles/common/files/bin/tmux-window-bar-config.test`

- [ ] **Step 1: Add repo-first expectations to `tmux-pane-label.test`**

Append or update cases so the expected outputs become:

```bash
run_case \
  "local git pane shows branch and repo" \
  "tty-local-git" \
  "$git_repo/subdir" \
  "zsh" \
  "(feature/foo) repo" \
  "shell: zsh" \
  "0" \
  "0"

run_case \
  "remote repo fallback shows repo and host" \
  "tty-remote-repo" \
  "$git_repo/subdir" \
  "ssh" \
  "repo | claw02" \
  "ssh dev@claw02 -p 22" \
  "1" \
  "0"
```

- [ ] **Step 2: Add the remote stickiness regression case to `tmux-window-label.test`**

Add one case that proves a bare host must not overwrite an already-structured remote window name:

```bash
run_case \
  "%15" \
  $'@11\t1\t(feature/foo) repo | claw02\t/dev/ttys005\t/tmp/repo\tssh\tclaw02\t%15' \
  "ignored-helper-output"

if grep -Fq "rename-window" "$tmux_log"; then
  printf 'not ok - degraded remote title skips rename\n' >&2
  exit 1
fi
printf 'ok - degraded remote title skips rename\n'
```

- [ ] **Step 3: Add repo-first remote title cases to `tmux-remote-title.test`**

Update expectations to:

```bash
run_print_case \
  "linked clean worktree prints branch repo host" \
  "$main_repo" \
  "$linked_wt" \
  "9100" \
  $'9100 S+ codex codex --cd /tmp/irrelevant' \
  "claw02" \
  "(feature/title-sync) linked-wt | claw02"

run_print_case \
  "stale explicit pid falls back to repo and host" \
  "$main_repo/subdir" \
  "$linked_wt" \
  "9999" \
  $'9100 S+ codex codex --cd /tmp/irrelevant' \
  "claw02" \
  "repo | claw02"
```

- [ ] **Step 4: Add the remote-preserve case to `tmux-session-name.test`**

Keep one structured-title case and add one degraded-title guard:

```bash
TMUX_DISPLAY_OUTPUT=$'/dev/ttys001\t/tmp/repo\tclaw02\t$1\t(feature/foo) repo | claw02'
PS_ARGS_OUTPUT="ssh dev@claw02"

if grep -Fq "rename-session -t \$1 claw02" "$tmux_log"; then
  printf 'not ok - degraded title must not replace structured session name\n' >&2
  exit 1
fi
printf 'ok - degraded title preserves structured session name\n'
```

- [ ] **Step 5: Add the top-bar separator expectation**

Extend `roles/common/files/bin/tmux-window-bar-config.test` with:

```bash
assert_contains "$file" "set -g window-status-separator ' || '"
```

- [ ] **Step 6: Run the focused red tests**

Run:

```bash
bash roles/common/files/bin/tmux-pane-label.test
bash roles/common/files/bin/tmux-window-label.test
bash roles/common/files/bin/tmux-remote-title.test
bash roles/common/files/bin/tmux-session-name.test
bash roles/common/files/bin/tmux-window-bar-config.test
```

Expected: FAIL because the existing scripts still emit leaf-directory local labels, allow degraded remote renames, and keep an empty window separator.

- [ ] **Step 7: Commit the red tests**

```bash
git add \
  roles/common/files/bin/tmux-pane-label.test \
  roles/common/files/bin/tmux-window-label.test \
  roles/common/files/bin/tmux-remote-title.test \
  roles/common/files/bin/tmux-session-name.test \
  roles/common/files/bin/tmux-window-bar-config.test
git -c commit.gpgsign=false commit -m "Add tmux unified label tests"
```

### Task 2: Implement one shared label formatter and route tmux helpers through it

**Files:**
- Create: `roles/common/files/bin/tmux-label-format`
- Modify: `roles/common/files/bin/tmux-pane-label`
- Modify: `roles/common/files/bin/tmux-window-label`
- Modify: `roles/common/files/bin/tmux-remote-title`
- Modify: `roles/common/files/bin/tmux-session-name`
- Modify: `roles/common/tasks/main.yml`
- Test: `roles/common/files/bin/tmux-pane-label.test`
- Test: `roles/common/files/bin/tmux-window-label.test`
- Test: `roles/common/files/bin/tmux-remote-title.test`
- Test: `roles/common/files/bin/tmux-session-name.test`

- [ ] **Step 1: Create `tmux-label-format` as the shared formatter**

Create `roles/common/files/bin/tmux-label-format` with a small CLI surface:

```bash
#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
path="${2:-}"
host="${3:-}"

dir_basename() {
  local raw="${1%/}"
  raw="${raw##*/}"
  [ -n "$raw" ] || raw="/"
  printf '%s\n' "$raw"
}

repo_root() {
  git -C "$1" rev-parse --show-toplevel 2>/dev/null
}

repo_basename() {
  local root
  root="$(repo_root "$1")" || return 1
  dir_basename "$root"
}

branch_name() {
  git -C "$1" branch --show-current 2>/dev/null
}

dirty_marker() {
  [ -n "$(git --no-optional-locks -C "$1" status --porcelain 2>/dev/null)" ]
}

format_local() {
  local repo branch
  repo="$(repo_basename "$1" 2>/dev/null || true)"
  branch="$(branch_name "$1" || true)"
  if [ -n "$branch" ] && [ -n "$repo" ]; then
    if dirty_marker "$1"; then
      printf '(*%s) %s\n' "$branch" "$repo"
    else
      printf '(%s) %s\n' "$branch" "$repo"
    fi
  elif [ -n "$repo" ]; then
    printf '%s\n' "$repo"
  else
    dir_basename "$1"
  fi
}

format_remote() {
  local base
  base="$(format_local "$1")"
  printf '%s | %s\n' "$base" "$2"
}

case "$mode" in
  local) format_local "$path" ;;
  remote) format_remote "$path" "$host" ;;
esac
```

- [ ] **Step 2: Rework `tmux-pane-label` to use the shared formatter**

Replace the current local branch/dir construction with formatter calls:

```bash
label_formatter="${TMUX_LABEL_FORMAT_BIN:-$HOME/.local/bin/tmux-label-format}"

local_label() {
  "$label_formatter" local "${1:-$pane_current_path}"
}

remote_label() {
  "$label_formatter" remote "$1" "$2"
}

label="$(remote_label "$pane_current_path" "$remote_host")"
```

Keep the existing explicit agent-worktree detection, but return formatter output:

```bash
local_label "$explicit_worktree_path"
```

- [ ] **Step 3: Rework `tmux-remote-title` to use the shared formatter**

Use the formatter for both explicit-worktree and fallback cases:

```bash
explicit_title() {
  "$label_formatter" remote "$1" "$2"
}

fallback_title() {
  "$label_formatter" remote "$1" "$2"
}
```

The remote title helper should no longer build the string itself.

- [ ] **Step 4: Rework `tmux-window-label` to preserve structured remote labels**

Before falling back to helper output, add this guard:

```bash
is_structured_remote_label() {
  case "$1" in
    *" | "*) return 0 ;;
    *) return 1 ;;
  esac
}

case "$pane_current_command" in
  ssh|gh|ruby)
    if is_structured_remote_label "$pane_title"; then
      label="$pane_title"
    elif is_structured_remote_label "$window_name"; then
      exit 0
    fi
    ;;
esac
```

If no structured remote title exists, keep using the shared pane-label helper.

- [ ] **Step 5: Rework `tmux-session-name` with the same narrow preserve rule**

When the pane is remote:

```bash
case "$pane_title" in
  *" | "*)
    name="$pane_title"
    ;;
  *)
    case "$current_name" in
      *" | "*)
        exit 0
        ;;
    esac
    ;;
esac
```

Do not otherwise expand session naming scope.

- [ ] **Step 6: Install the shared formatter**

Add a copy task in `roles/common/tasks/main.yml`:

```yaml
- name: Install tmux-label-format script
  copy:
    backup: yes
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin/tmux-label-format'
    src: '{{ playbook_dir }}/roles/common/files/bin/tmux-label-format'
    mode: 0755
```

- [ ] **Step 7: Run the focused green tests**

Run:

```bash
bash roles/common/files/bin/tmux-pane-label.test
bash roles/common/files/bin/tmux-window-label.test
bash roles/common/files/bin/tmux-remote-title.test
bash roles/common/files/bin/tmux-session-name.test
```

Expected: PASS for repo-first local labels, repo-backed remote fallback, dirty remote titles, and degraded-title preservation.

- [ ] **Step 8: Commit the formatter and helper rewrites**

```bash
git add \
  roles/common/files/bin/tmux-label-format \
  roles/common/files/bin/tmux-pane-label \
  roles/common/files/bin/tmux-window-label \
  roles/common/files/bin/tmux-remote-title \
  roles/common/files/bin/tmux-session-name \
  roles/common/tasks/main.yml \
  roles/common/files/bin/tmux-pane-label.test \
  roles/common/files/bin/tmux-window-label.test \
  roles/common/files/bin/tmux-remote-title.test \
  roles/common/files/bin/tmux-session-name.test
git -c commit.gpgsign=false commit -m "Unify tmux label formatting"
```

### Task 3: Wire the tmux configs, verify end to end, and prepare the branch for PR

**Files:**
- Modify: `roles/macos/templates/dotfiles/tmux.conf`
- Modify: `roles/linux/files/dotfiles/tmux.conf`
- Modify: `roles/common/files/bin/tmux-window-bar-config.test`
- Test: `roles/common/files/bin/tmux-window-bar-config.test`

- [ ] **Step 1: Add the explicit window separator to both tmux configs**

Change:

```tmux
set -g window-status-separator ''
```

to:

```tmux
set -g window-status-separator ' || '
```

in:

```text
roles/macos/templates/dotfiles/tmux.conf
roles/linux/files/dotfiles/tmux.conf
```

- [ ] **Step 2: Run the config test**

Run:

```bash
bash roles/common/files/bin/tmux-window-bar-config.test
```

Expected: PASS with the new separator assertion and existing window-bar assertions.

- [ ] **Step 3: Run broader verification**

Run:

```bash
bash roles/common/files/bin/tmux-pane-label.test
bash roles/common/files/bin/tmux-window-label.test
bash roles/common/files/bin/tmux-remote-title.test
bash roles/common/files/bin/tmux-session-name.test
bash roles/common/files/bin/tmux-window-bar-config.test
bin/provision --check
```

Expected: all tmux label/config tests pass, and `bin/provision --check` exits 0.

- [ ] **Step 4: Verify the finished behavior against the spec**

Check these items against the code and test evidence:

```text
[ ] local git pane contract is "(branch) repo" / "(*branch) repo"
[ ] local non-git pane contract is "dir"
[ ] remote linked-worktree contract is "(branch) repo | host" / "(*branch) repo | host"
[ ] remote repo fallback is "repo | host"
[ ] degraded bare-host remote titles do not overwrite a structured window label
[ ] top bar uses " || " between windows
```

- [ ] **Step 5: Commit the tmux config and verification changes**

```bash
git add \
  roles/macos/templates/dotfiles/tmux.conf \
  roles/linux/files/dotfiles/tmux.conf \
  roles/common/files/bin/tmux-window-bar-config.test
git -c commit.gpgsign=false commit -m "Add tmux window separators"
```

- [ ] **Step 6: Create the PR after verification**

After the verification commands above are fresh and passing, use the repo PR workflow to open a pull request from this worktree branch with the spec, plan, and implementation commits.
