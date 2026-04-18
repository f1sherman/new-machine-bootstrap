# tmux Window Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an always-visible top tmux window bar on both macOS and Linux dev hosts while keeping the existing bottom pane-border status and current navigation bindings intact.

**Architecture:** Re-enable tmux's native top status bar and use its built-in current-session window list as the persistent "virtual tabs" layer. Keep the existing bottom `pane-border-status` bar unchanged for branch/path/host detail, and enforce the config shape with a small repo-local shell regression test instead of adding new runtime helpers.

**Tech Stack:** tmux 3.6a format strings, bash, Ansible-managed tmux config files, repo-local shell test harnesses.

**Spec:** `docs/superpowers/specs/2026-04-18-tmux-window-bar-design.md`

**Phases and human-review gates:**

1. **Phase 1** — Add a config regression harness that fails against the current `status off` config. Human review gate before changing dotfiles.
2. **Phase 2** — Update both managed tmux configs to enable the top bar and satisfy the harness. Human review gate after the green test run.
3. **Phase 3** — Apply and verify on macOS with `bin/provision`, `tmux source-file`, and a disposable verification session. Human review gate.
4. **Phase 4** — Repeat end-to-end verification on a Linux dev host before calling the feature done.

---

## File Structure

- `roles/common/files/bin/tmux-window-bar-config.test`
  Responsibility: text-level regression test that asserts both managed tmux configs enable the top bar, keep the bottom pane border, preserve navigation bindings, and remove the old `status off` / `tmux-window-name`-only current-window format.
- `roles/macos/templates/dotfiles/tmux.conf`
  Responsibility: macOS tmux config template. This is the source of truth for `~/.tmux.conf` on macOS after `bin/provision`.
- `roles/linux/files/dotfiles/tmux.conf`
  Responsibility: Linux dev-host tmux config. This is the source of truth for `~/.tmux.conf` on Linux after `bin/provision`.

No Ansible task changes are required for this feature. Existing provisioning already deploys these tmux config files.

## Phase 1 — Config regression harness

### Task 1: Add a failing text-level test for the top bar

**Files:**
- Create: `roles/common/files/bin/tmux-window-bar-config.test`
- Test: `roles/common/files/bin/tmux-window-bar-config.test`

- [ ] **Step 1.1: Create the regression harness**

Create `roles/common/files/bin/tmux-window-bar-config.test` with exactly this content:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

pass=0
fail=0

assert_contains() {
  local file="$1"
  local needle="$2"

  if grep -Fq -- "$needle" "$REPO_ROOT/$file"; then
    pass=$((pass + 1))
    printf 'PASS  %s contains %s\n' "$file" "$needle"
  else
    fail=$((fail + 1))
    printf 'FAIL  %s missing %s\n' "$file" "$needle"
  fi
}

assert_not_contains() {
  local file="$1"
  local needle="$2"

  if grep -Fq -- "$needle" "$REPO_ROOT/$file"; then
    fail=$((fail + 1))
    printf 'FAIL  %s unexpectedly contains %s\n' "$file" "$needle"
  else
    pass=$((pass + 1))
    printf 'PASS  %s omits %s\n' "$file" "$needle"
  fi
}

assert_tmux_file() {
  local file="$1"

  assert_contains "$file" "set -g status on"
  assert_contains "$file" "set -g status-position top"
  assert_contains "$file" "set -g status-justify left"
  assert_contains "$file" "set -g status-style 'bg=black,fg=colour252'"
  assert_contains "$file" "set -g status-left ''"
  assert_contains "$file" "set -g status-right ''"
  assert_contains "$file" "set -g status-left-length 0"
  assert_contains "$file" "set -g status-right-length 0"
  assert_contains "$file" "set -g window-status-separator ''"
  assert_contains "$file" "set -g window-status-style 'bg=colour236,fg=colour252'"
  assert_contains "$file" "set -g window-status-current-style 'bg=colour51,fg=black,bold'"
  assert_contains "$file" "set -g window-status-format ' #{window_index} #{=/18/...:window_name}#{?window_activity_flag,+,}#{?window_bell_flag,!,} '"
  assert_contains "$file" "set -g window-status-current-format ' #{window_index} #{=/18/...:window_name}#{?window_activity_flag,+,}#{?window_bell_flag,!,} '"
  assert_contains "$file" "set -g pane-border-status bottom"
  assert_contains "$file" "bind -n M-n next-window"
  assert_contains "$file" "bind -n M-p previous-window"
  assert_contains "$file" "bind-key -n M-w display-popup -E -w 95% -h 90% tmux-switch-window"
  assert_contains "$file" "bind-key -n M-8 display-popup -E -w 60% -h 60% tmux-switch-session"
  assert_not_contains "$file" "set -g status off"
  assert_not_contains "$file" "set -g window-status-current-format ' | #(\$HOME/.local/bin/tmux-window-name #{pane_tty})'"
}

assert_tmux_file "roles/macos/templates/dotfiles/tmux.conf"
assert_tmux_file "roles/linux/files/dotfiles/tmux.conf"

printf '\n'
printf 'passed=%s failed=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 1.2: Make the harness executable**

Run:

```bash
chmod +x roles/common/files/bin/tmux-window-bar-config.test
```

- [ ] **Step 1.3: Run the harness to confirm RED**

Run:

```bash
bash roles/common/files/bin/tmux-window-bar-config.test
```

Expected:

- exit code is non-zero
- failures report missing `set -g status on`
- failures report unexpected `set -g status off`

This is the correct red state because both tmux configs still disable the top bar.

- [ ] **Step 1.4: Commit the red test**

Run:

```bash
git add roles/common/files/bin/tmux-window-bar-config.test
git -c commit.gpgsign=false commit -m "test: add tmux window bar config harness"
```

### Phase 1 Human Review Gate

**Stop here.** Present:

- new file: `roles/common/files/bin/tmux-window-bar-config.test`
- red test result showing the old `status off` config

Wait for approval before editing tmux configs.

---

## Phase 2 — Update both managed tmux configs

### Task 2: Enable the top bar in the macOS tmux template

**Files:**
- Modify: `roles/macos/templates/dotfiles/tmux.conf`
- Test: `roles/common/files/bin/tmux-window-bar-config.test`

- [ ] **Step 2.1: Replace the macOS status section**

In `roles/macos/templates/dotfiles/tmux.conf`, replace the block that begins with:

```tmux
# Global status bar: off. Each pane instead gets its own status line on the
```

and ends with:

```tmux
set -g window-status-current-format ' | #($HOME/.local/bin/tmux-window-name #{pane_tty})'
```

with exactly this block:

```tmux
# Global status bar: on at the top. It carries a thin current-session window
# list while each pane keeps its own branch/path/host detail on the bottom
# border.
set -g status on
set -g status-position top
set -g status-interval 5
set -g status-justify left
set -g status-style 'bg=black,fg=colour252'
set -g status-left ''
set -g status-right ''
set -g status-left-length 0
set -g status-right-length 0
set -g window-status-separator ''
set -g pane-border-status bottom

# Border line colors: dark grey for inactive, bright cyan for active.
# Both use black bg so the pane-border-format content sits on a consistent
# dark bar, matching the old status-bar's status-bg/status-fg.
set -g pane-border-style 'bg=black,fg=colour240'
set -g pane-active-border-style 'bg=black,fg=colour51'

set -g window-status-style 'bg=colour236,fg=colour252'
set -g window-status-current-style 'bg=colour51,fg=black,bold'
set -g window-status-format ' #{window_index} #{=/18/...:window_name}#{?window_activity_flag,+,}#{?window_bell_flag,!,} '
set -g window-status-current-format ' #{window_index} #{=/18/...:window_name}#{?window_activity_flag,+,}#{?window_bell_flag,!,} '

set -g pane-border-format '#[bg=black,fg=yellow] [#{pane_index}]#(~/.local/bin/tmux-pane-branch #{pane_current_path})#[fg=cyan] #{b:pane_current_path} #[fg=white]#(~/.local/bin/tmux-host-tag) '
```

- [ ] **Step 2.2: Update the Linux tmux config with the same status block**

In `roles/linux/files/dotfiles/tmux.conf`, replace the block that begins with:

```tmux
# Global status bar: off. Each pane instead gets its own status line on the
```

and ends with:

```tmux
set -g window-status-current-format ' | #($HOME/.local/bin/tmux-window-name #{pane_tty})'
```

with exactly this block:

```tmux
# Global status bar: on at the top. It carries a thin current-session window
# list while each pane keeps its own branch/path/host detail on the bottom
# border.
set -g status on
set -g status-position top
set -g status-interval 5
set -g status-justify left
set -g status-style 'bg=black,fg=colour252'
set -g status-left ''
set -g status-right ''
set -g status-left-length 0
set -g status-right-length 0
set -g window-status-separator ''
set -g pane-border-status bottom

# Border line colors: dark grey for inactive, bright cyan for active.
# Both use black bg so the pane-border-format content sits on a consistent
# dark bar, matching the old status-bar's status-bg/status-fg.
set -g pane-border-style 'bg=black,fg=colour240'
set -g pane-active-border-style 'bg=black,fg=colour51'

set -g window-status-style 'bg=colour236,fg=colour252'
set -g window-status-current-style 'bg=colour51,fg=black,bold'
set -g window-status-format ' #{window_index} #{=/18/...:window_name}#{?window_activity_flag,+,}#{?window_bell_flag,!,} '
set -g window-status-current-format ' #{window_index} #{=/18/...:window_name}#{?window_activity_flag,+,}#{?window_bell_flag,!,} '

set -g pane-border-format '#[bg=black,fg=yellow] [#{pane_index}]#(~/.local/bin/tmux-pane-branch #{pane_current_path})#[fg=cyan] #{b:pane_current_path} #[fg=white]#(~/.local/bin/tmux-host-tag) '
```

- [ ] **Step 2.3: Run the regression harness to confirm GREEN**

Run:

```bash
bash roles/common/files/bin/tmux-window-bar-config.test
```

Expected:

- exit code `0`
- final line is `passed=40 failed=0`

- [ ] **Step 2.4: Sanity-check the diff**

Run:

```bash
git diff -- roles/macos/templates/dotfiles/tmux.conf roles/linux/files/dotfiles/tmux.conf roles/common/files/bin/tmux-window-bar-config.test
```

Expected:

- only the new harness and the two tmux config status sections changed
- `pane-border-format` remains intact
- `M-w`, `M-8`, `M-n`, and `M-p` bindings are untouched

- [ ] **Step 2.5: Commit the green config change**

Run:

```bash
git add roles/common/files/bin/tmux-window-bar-config.test roles/macos/templates/dotfiles/tmux.conf roles/linux/files/dotfiles/tmux.conf
git -c commit.gpgsign=false commit -m "feat(tmux): add always-on window bar"
```

### Phase 2 Human Review Gate

**Stop here.** Present:

- updated files: `roles/macos/templates/dotfiles/tmux.conf`, `roles/linux/files/dotfiles/tmux.conf`
- test result: `passed=40 failed=0`
- note that the plan intentionally uses native `window_name` and native activity/bell markers only

Wait for approval before provisioning.

---

## Phase 3 — macOS provisioning and end-to-end verification

### Task 3: Apply and verify on macOS

**Files:**
- Runtime only: managed macOS environment after `bin/provision`

- [ ] **Step 3.1: Provision the macOS machine from the repo source**

Run:

```bash
bin/provision
```

Expected:

- Ansible exits `0`
- recap ends with `failed=0`

- [ ] **Step 3.2: Reload the installed tmux config**

Run:

```bash
tmux source-file "$HOME/.tmux.conf"
```

Expected:

- exit code `0`
- no error output

- [ ] **Step 3.3: Confirm the key global options are live**

Run:

```bash
tmux show -gv status
```

Expected:

```text
on
```

Run:

```bash
tmux show -gv status-position
```

Expected:

```text
top
```

Run:

```bash
tmux show -gv pane-border-status
```

Expected:

```text
bottom
```

Run:

```bash
tmux show -gv window-status-format
```

Expected:

```text
 #{window_index} #{=/18/...:window_name}#{?window_activity_flag,+,}#{?window_bell_flag,!,} 
```

- [ ] **Step 3.4: Create a disposable verification session**

Run:

```bash
tmux kill-session -t =window-bar-check 2>/dev/null || true
```

Run:

```bash
tmux new-session -d -s window-bar-check -n editor
```

Run:

```bash
tmux new-window -t =window-bar-check -n tests
```

Run:

```bash
tmux new-window -t =window-bar-check -n notes
```

Run:

```bash
tmux send-keys -t =window-bar-check:1 'echo activity-marker' C-m
```

Run:

```bash
tmux send-keys -t =window-bar-check:2 "printf '\\a'" C-m
```

- [ ] **Step 3.5: Inspect the window list in tmux**

If currently inside tmux, run:

```bash
tmux switch-client -t =window-bar-check
```

If currently outside tmux, run:

```bash
tmux attach -t =window-bar-check
```

Expected visual result:

- top bar is visible
- active window is bright cyan with dark text
- inactive windows are dark grey with light text
- labels read `0 editor`, `1 tests`, `2 notes`
- the `tests` window shows `+`
- the `notes` window shows `!`
- the bottom pane border still shows branch/path/host detail

If the top bar labels are all generic names such as `zsh`, stop here and return to design review rather than merging; that means the repo's current window naming behavior is not strong enough for this feature as specified.

- [ ] **Step 3.6: Clean up the disposable session**

Run:

```bash
tmux kill-session -t =window-bar-check
```

### Phase 3 Human Review Gate

**Stop here.** Present:

- `bin/provision` result on macOS
- live tmux option checks (`status=on`, `status-position=top`, `pane-border-status=bottom`)
- visual confirmation of active/inactive tabs and `+` / `!` markers

Wait for approval before Linux verification.

---

## Phase 4 — Linux dev-host verification

### Task 4: Apply and verify on Linux

**Files:**
- Runtime only: managed Linux dev-host environment after `bin/provision`

- [ ] **Step 4.1: Provision the Linux dev host from the repo source**

Run:

```bash
bin/provision
```

Expected:

- Ansible exits `0`
- recap ends with `failed=0`

- [ ] **Step 4.2: Reload the installed tmux config**

Run:

```bash
tmux source-file "$HOME/.tmux.conf"
```

Expected:

- exit code `0`
- no error output

- [ ] **Step 4.3: Confirm the key global options are live**

Run:

```bash
tmux show -gv status
```

Expected:

```text
on
```

Run:

```bash
tmux show -gv status-position
```

Expected:

```text
top
```

Run:

```bash
tmux show -gv pane-border-status
```

Expected:

```text
bottom
```

Run:

```bash
tmux show -gv window-status-format
```

Expected:

```text
 #{window_index} #{=/18/...:window_name}#{?window_activity_flag,+,}#{?window_bell_flag,!,} 
```

- [ ] **Step 4.4: Create a disposable verification session**

Run:

```bash
tmux kill-session -t =window-bar-check 2>/dev/null || true
```

Run:

```bash
tmux new-session -d -s window-bar-check -n editor
```

Run:

```bash
tmux new-window -t =window-bar-check -n tests
```

Run:

```bash
tmux new-window -t =window-bar-check -n notes
```

Run:

```bash
tmux send-keys -t =window-bar-check:1 'echo activity-marker' C-m
```

Run:

```bash
tmux send-keys -t =window-bar-check:2 "printf '\\a'" C-m
```

- [ ] **Step 4.5: Inspect the window list in tmux**

If currently inside tmux, run:

```bash
tmux switch-client -t =window-bar-check
```

If currently outside tmux, run:

```bash
tmux attach -t =window-bar-check
```

Expected visual result:

- top bar is visible
- active window is bright cyan with dark text
- inactive windows are dark grey with light text
- labels read `0 editor`, `1 tests`, `2 notes`
- the `tests` window shows `+`
- the `notes` window shows `!`
- the bottom pane border still shows branch/path/host detail

If the top bar labels are all generic names such as `zsh`, stop here and return to design review rather than merging; that means the repo's current window naming behavior is not strong enough for this feature as specified.

- [ ] **Step 4.6: Clean up the disposable session**

Run:

```bash
tmux kill-session -t =window-bar-check
```

### Phase 4 Human Review Gate

**Stop here.** Present:

- Linux `bin/provision` result
- live tmux option checks on Linux
- visual confirmation of active/inactive tabs and `+` / `!` markers

Once approved, the feature is complete.
