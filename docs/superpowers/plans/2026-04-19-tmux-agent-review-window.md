# Tmux Agent Review Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add tmux-managed read-only review windows so `M-d`, `M-f`, and `M-r` let a running agent session open diffs or files, then bounce back to the coding pane without restarting the session.

**Architecture:** Keep review state inside tmux via pane/window user options, not temp files. Add focused shell helpers for opening diffs, opening files, and toggling pane-review pairs; then wire them into both tmux configs and Ansible-managed script installation. Reuse existing repo patterns for shell tests, SSH-aware tmux bindings, and `git-diff-untracked`.

**Tech Stack:** Bash shell helpers, tmux user options, delta, bat, less, Ansible copy tasks, repo shell test harnesses

---

## File map

**Create:**
- `roles/common/files/bin/review-diff`
- `roles/common/files/bin/review-file`
- `roles/common/files/bin/tmux-review-lib.sh`
- `roles/common/files/bin/tmux-review-open`
- `roles/common/files/bin/tmux-review-toggle`
- `roles/common/files/bin/tmux-review-open.test`
- `roles/common/files/bin/tmux-review-toggle.test`
- `tests/tmux-review-provisioning.sh`

**Modify:**
- `roles/common/tasks/main.yml`
- `roles/macos/templates/dotfiles/tmux.conf`
- `roles/linux/files/dotfiles/tmux.conf`

## Task 1: Lock behavior with failing tests

**Files:**
- Create: `roles/common/files/bin/tmux-review-open.test`
- Create: `roles/common/files/bin/tmux-review-toggle.test`
- Create: `tests/tmux-review-provisioning.sh`

- [ ] **Step 1: Write the failing review-open state test**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/tmux-review-open"

if [ ! -x "$SCRIPT" ]; then
  printf 'ERROR: %s is not executable (or does not exist)\n' "$SCRIPT" >&2
  exit 2
fi

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

pass=0
fail=0

state_file() {
  printf '%s/%s.%s\n' "$1" "$2" "$3"
}

read_state() {
  local path
  path="$(state_file "$1" "$2" "$3")"
  [ -f "$path" ] || return 1
  cat "$path"
}

assert_equal() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass=$((pass + 1))
    printf 'PASS  %s\n' "$name"
  else
    fail=$((fail + 1))
    printf 'FAIL  %s\n' "$name"
    printf '      expected: %q\n' "$expected"
    printf '      actual  : %q\n' "$actual"
  fi
}

# Case: first open creates review window and stores pane/window mappings.
# Case: second open from same pane reuses the review window id.
# Case: separate pane gets a different review window id.
# Case: ssh pane requests forwarding instead of local open.
```

- [ ] **Step 2: Run the review-open test to verify it fails**

Run: `bash roles/common/files/bin/tmux-review-open.test`
Expected: FAIL because `tmux-review-open` does not exist yet.

- [ ] **Step 3: Write the failing toggle test**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/tmux-review-toggle"

if [ ! -x "$SCRIPT" ]; then
  printf 'ERROR: %s is not executable (or does not exist)\n' "$SCRIPT" >&2
  exit 2
fi

# Case: origin pane jumps to mapped review window.
# Case: review window jumps back to mapped origin pane.
# Case: missing review/origin shows status message and exits cleanly.
```

- [ ] **Step 4: Run the toggle test to verify it fails**

Run: `bash roles/common/files/bin/tmux-review-toggle.test`
Expected: FAIL because `tmux-review-toggle` does not exist yet.

- [ ] **Step 5: Write the failing provisioning/config wiring test**

```bash
#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

pass=0
fail=0

assert_contains() {
  local file="$1"
  local needle="$2"
  if grep -Fq -- "$needle" "$repo_root/$file"; then
    pass=$((pass + 1))
    printf 'PASS  %s contains %s\n' "$file" "$needle"
  else
    fail=$((fail + 1))
    printf 'FAIL  %s missing %s\n' "$file" "$needle"
  fi
}

assert_contains "roles/common/tasks/main.yml" "tmux-review-open"
assert_contains "roles/common/tasks/main.yml" "tmux-review-toggle"
assert_contains "roles/common/tasks/main.yml" "review-diff"
assert_contains "roles/common/tasks/main.yml" "review-file"
assert_contains "roles/macos/templates/dotfiles/tmux.conf" "bind-key -n M-d"
assert_contains "roles/macos/templates/dotfiles/tmux.conf" "bind-key -n M-f"
assert_contains "roles/macos/templates/dotfiles/tmux.conf" "bind-key -n M-r"
assert_contains "roles/linux/files/dotfiles/tmux.conf" "bind-key -n M-d"
assert_contains "roles/linux/files/dotfiles/tmux.conf" "bind-key -n M-f"
assert_contains "roles/linux/files/dotfiles/tmux.conf" "bind-key -n M-r"

printf '\npassed=%s failed=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 6: Run the provisioning/config test to verify it fails**

Run: `bash tests/tmux-review-provisioning.sh`
Expected: FAIL because the scripts and tmux bindings are not wired yet.

- [ ] **Step 7: Commit the red tests**

Run:

```bash
git add roles/common/files/bin/tmux-review-open.test roles/common/files/bin/tmux-review-toggle.test tests/tmux-review-provisioning.sh
git commit -m "test: add tmux review workflow coverage"
```

Expected: commit succeeds with only the new failing tests.

## Task 2: Implement the review helpers

**Files:**
- Create: `roles/common/files/bin/tmux-review-lib.sh`
- Create: `roles/common/files/bin/review-diff`
- Create: `roles/common/files/bin/review-file`
- Create: `roles/common/files/bin/tmux-review-open`
- Create: `roles/common/files/bin/tmux-review-toggle`
- Test: `roles/common/files/bin/tmux-review-open.test`
- Test: `roles/common/files/bin/tmux-review-toggle.test`

- [ ] **Step 1: Add the shared tmux review library**

```bash
#!/usr/bin/env bash

tmux_review_state_file() {
  printf '%s/%s.%s\n' "$TMUX_REVIEW_STATE_DIR" "$1" "$2"
}

tmux_review_set_option() {
  local target_type="$1" target="$2" option_name="$3" value="$4"
  if [ -n "${TMUX_REVIEW_STATE_DIR:-}" ]; then
    mkdir -p "$TMUX_REVIEW_STATE_DIR"
    printf '%s' "$value" > "$(tmux_review_state_file "$target" "$option_name")"
  else
    tmux set-option "-${target_type}t" "$target" "$option_name" "$value" >/dev/null 2>&1
  fi
}

tmux_review_clear_option() {
  local target_type="$1" target="$2" option_name="$3"
  if [ -n "${TMUX_REVIEW_STATE_DIR:-}" ]; then
    rm -f "$(tmux_review_state_file "$target" "$option_name")"
  else
    tmux set-option "-${target_type}t" "$target" -u "$option_name" >/dev/null 2>&1
  fi
}
```

- [ ] **Step 2: Add the diff renderer**

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  printf 'review-diff: not inside a git repository\n' >&2
  exit 1
}

render_section() {
  local title="$1"
  local cmd="$2"
  local output

  output="$(cd "$repo_root" && eval "$cmd")"
  [ -n "$output" ] || return 1

  printf '=== %s ===\n\n' "$title"
  if command -v delta >/dev/null 2>&1; then
    printf '%s' "$output" | delta
  else
    printf '%s' "$output"
  fi
  printf '\n\n'
}

{
  render_section "Staged Changes" "git --no-pager diff --cached" || true
  render_section "Working Tree Changes" "~/.local/bin/git-diff-untracked --no-pager" || true
} | if command -v less >/dev/null 2>&1; then less -R; else cat; fi
```

- [ ] **Step 3: Add the file renderer**

```bash
#!/usr/bin/env bash
set -euo pipefail

path="${1:-}"
[ -n "$path" ] || {
  printf 'review-file: path is required\n' >&2
  exit 1
}
[ -f "$path" ] || {
  printf 'review-file: file not found: %s\n' "$path" >&2
  exit 1
}

if command -v bat >/dev/null 2>&1; then
  bat --paging=never --style=numbers --color=always "$path"
else
  cat "$path"
fi | if command -v less >/dev/null 2>&1; then less -R; else cat; fi
```

- [ ] **Step 4: Add the tmux review opener**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/tmux-review-lib.sh"

mode="${1:-}"
subject="${2:-}"

[ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || {
  printf 'tmux-review-open: tmux is required\n' >&2
  exit 1
}

# Resolve origin pane/window, detect ssh-pane forwarding, allocate or reuse a
# review window, write @review_window_id and @review_origin_* options, send the
# requested command into the review window, and switch-client to it.
```

- [ ] **Step 5: Add the tmux review toggle helper**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/tmux-review-lib.sh"

[ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || {
  printf 'tmux-review-toggle: tmux is required\n' >&2
  exit 1
}

# If current pane has @review_window_id, jump to that window.
# Else if current window has @review_origin_pane_id, jump back to origin pane.
# Else show a tmux display-message and exit 0.
```

- [ ] **Step 6: Run the focused helper tests and make them pass**

Run:

```bash
bash roles/common/files/bin/tmux-review-open.test
bash roles/common/files/bin/tmux-review-toggle.test
```

Expected: both PASS with `0 failed`.

- [ ] **Step 7: Commit the helper implementation**

Run:

```bash
git add roles/common/files/bin/tmux-review-lib.sh roles/common/files/bin/review-diff roles/common/files/bin/review-file roles/common/files/bin/tmux-review-open roles/common/files/bin/tmux-review-toggle roles/common/files/bin/tmux-review-open.test roles/common/files/bin/tmux-review-toggle.test
git commit -m "feat: add tmux review helpers"
```

Expected: commit succeeds with helper scripts plus passing helper tests.

## Task 3: Wire tmux bindings, provisioning, and full verification

**Files:**
- Modify: `roles/common/tasks/main.yml`
- Modify: `roles/macos/templates/dotfiles/tmux.conf`
- Modify: `roles/linux/files/dotfiles/tmux.conf`
- Test: `tests/tmux-review-provisioning.sh`

- [ ] **Step 1: Install the new helpers from Ansible**

```yaml
- name: Install tmux review helpers
  copy:
    backup: yes
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin/{{ item.name }}'
    src: '{{ playbook_dir }}/roles/common/files/bin/{{ item.name }}'
    mode: '{{ item.mode }}'
  loop:
    - { name: tmux-review-lib.sh, mode: '0644' }
    - { name: review-diff, mode: '0755' }
    - { name: review-file, mode: '0755' }
    - { name: tmux-review-open, mode: '0755' }
    - { name: tmux-review-toggle, mode: '0755' }
```

- [ ] **Step 2: Add the tmux bindings to macOS and Linux configs**

```tmux
bind-key -n M-d if-shell "$is_ssh" 'send-keys M-d' 'run-shell -b "tmux-review-open diff"'
bind-key -n M-f if-shell "$is_ssh" 'send-keys M-f' 'command-prompt -p "review file:" "run-shell -b \"tmux-review-open file %%\""'
bind-key -n M-r if-shell "$is_ssh" 'send-keys M-r' 'run-shell -b "tmux-review-toggle"'
```

Use the existing `is_ssh` expression in each tmux config so nested tmux flows
forward the key to the inner remote session instead of opening a local review.

- [ ] **Step 3: Run the provisioning/config test and make it pass**

Run: `bash tests/tmux-review-provisioning.sh`
Expected: PASS with `0 failed`.

- [ ] **Step 4: Run repo-level verification for this feature**

Run:

```bash
bash roles/common/files/bin/tmux-review-open.test
bash roles/common/files/bin/tmux-review-toggle.test
bash tests/tmux-review-provisioning.sh
ansible-playbook playbook.yml --syntax-check
```

Expected:
- all three shell tests PASS with `0 failed`
- syntax check exits `0`

- [ ] **Step 5: Commit the wiring and verification changes**

Run:

```bash
git add roles/common/tasks/main.yml roles/macos/templates/dotfiles/tmux.conf roles/linux/files/dotfiles/tmux.conf tests/tmux-review-provisioning.sh
git commit -m "feat: add tmux review key bindings"
```

Expected: commit succeeds with wiring changes and passing verification.

- [ ] **Step 6: Final manual verification checklist**

Run these manually in a provisioned tmux environment after `bin/provision`:

```bash
M-d   # opens diff review for current pane
M-r   # returns to coding pane
M-f   # prompts for file path and opens file review
```

Expected:
- same-pane review reuses its paired review window
- a second coding pane gets a different review window
- SSH pane forwards review keys to the inner tmux layer

