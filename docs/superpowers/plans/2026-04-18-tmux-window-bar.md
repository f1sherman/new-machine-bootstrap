# tmux Window Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace unhelpful tmux window labels like `zsh` with branch-first, active-pane-driven labels in both the top window bar and pane border, while keeping native tmux rendering and existing navigation bindings.

**Architecture:** Add one shared helper that derives label text from pane context (`branch dir`, `dir`, or remote host/context), and a second helper that updates `window_name` from the active pane using that same text. Wire both into the existing tmux and zsh hooks, update the tmux configs to remove visible window/pane numbers, and verify behavior with repo-local shell tests plus macOS end-to-end tmux checks.

**Tech Stack:** bash, tmux 3.6a format strings, Ansible-managed dotfiles, repo-local shell test harnesses.

**Spec:** `docs/superpowers/specs/2026-04-18-tmux-window-bar-design.md`

---

## File Structure

- `roles/common/files/bin/tmux-pane-label`
  Responsibility: derive one label string from pane context without ever emitting generic shell names.
- `roles/common/files/bin/tmux-pane-label.test`
  Responsibility: TDD harness for local git, local non-git, SSH, Codespaces, DevPod, and shell-suppression cases.
- `roles/common/files/bin/tmux-window-label`
  Responsibility: rename the current tmux window from the active pane's derived label.
- `roles/common/files/bin/tmux-window-label.test`
  Responsibility: TDD harness for active-pane rename, no-op on inactive panes, and no-op when the label is unchanged.
- `roles/common/files/bin/tmux-window-bar-config.test`
  Responsibility: text-level regression test for helper install tasks, tmux config invariants, and zsh hook wiring.
- `roles/common/tasks/main.yml`
  Responsibility: install the new shared helpers into `~/.local/bin`.
- `roles/common/templates/dotfiles/zshrc`
  Responsibility: trigger live session/window label refresh on `chpwd` and `precmd`.
- `roles/macos/templates/dotfiles/tmux.conf`
  Responsibility: macOS tmux config with top-bar rendering, pane-border label rendering, and update hooks.
- `roles/linux/files/dotfiles/tmux.conf`
  Responsibility: Linux tmux config with the same behavior and rendering model.

## Task 1: Build the shared pane-label helper with TDD

**Files:**
- Create: `roles/common/files/bin/tmux-pane-label`
- Create: `roles/common/files/bin/tmux-pane-label.test`
- Test: `roles/common/files/bin/tmux-pane-label.test`

- [ ] **Step 1: Write the failing test harness**

Create `roles/common/files/bin/tmux-pane-label.test` with cases for:

- local git pane -> `feature/foo repo`
- local non-git pane -> `tmp`
- plain SSH pane -> `claw02`
- Codespaces pane -> parsed codespace name
- DevPod pane -> parsed workspace name
- shell-backed local pane -> never `zsh`

Use a fake `ps` binary on `PATH` so the harness controls pane process output by tty. Create temporary git repositories with `git init -b main` and `.git/HEAD` contents that exercise branch parsing.

- [ ] **Step 2: Run the new harness and confirm RED**

Run:

```bash
bash roles/common/files/bin/tmux-pane-label.test
```

Expected: non-zero exit because `roles/common/files/bin/tmux-pane-label` does not exist yet.

- [ ] **Step 3: Implement `tmux-pane-label`**

Create `roles/common/files/bin/tmux-pane-label` as a bash script that accepts:

```text
tmux-pane-label <pane_tty> <pane_current_path>
```

Behavior:

- inspect `ps -o args= -t "$pane_tty"` once
- if the pane is an SSH/Codespaces/DevPod pane, emit host/context label
- else, if the path is inside a git worktree, emit `branch dir`
- else emit directory basename
- never emit `zsh`, `bash`, `sh`, or `login`
- always exit `0` on fallback paths

- [ ] **Step 4: Run the harness to confirm GREEN**

Run:

```bash
bash roles/common/files/bin/tmux-pane-label.test
```

Expected: exit `0` with all cases passing.

- [ ] **Step 5: Commit**

Run:

```bash
git add roles/common/files/bin/tmux-pane-label roles/common/files/bin/tmux-pane-label.test
git -c commit.gpgsign=false commit -m "feat(tmux): add shared pane label helper"
```

## Task 2: Build the active-pane window-label helper with TDD

**Files:**
- Create: `roles/common/files/bin/tmux-window-label`
- Create: `roles/common/files/bin/tmux-window-label.test`
- Test: `roles/common/files/bin/tmux-window-label.test`

- [ ] **Step 1: Write the failing test harness**

Create `roles/common/files/bin/tmux-window-label.test` with a fake `tmux` command and a fake `tmux-pane-label` helper. Cover:

- active pane + changed label -> `rename-window`
- active pane + unchanged label -> no rename
- inactive pane -> no rename

- [ ] **Step 2: Run the harness and confirm RED**

Run:

```bash
bash roles/common/files/bin/tmux-window-label.test
```

Expected: non-zero exit because `roles/common/files/bin/tmux-window-label` does not exist yet.

- [ ] **Step 3: Implement `tmux-window-label`**

Create `roles/common/files/bin/tmux-window-label` as a bash script that:

- accepts `pane_id` (or falls back to `$TMUX_PANE`)
- fetches `window_id`, `pane_active`, `window_name`, `pane_tty`, and `pane_current_path` from tmux
- exits without renaming when the pane is inactive
- calls `tmux-pane-label` for the new label
- renames the window only when the derived label is non-empty and different

- [ ] **Step 4: Run the harness to confirm GREEN**

Run:

```bash
bash roles/common/files/bin/tmux-window-label.test
```

Expected: exit `0` with all cases passing.

- [ ] **Step 5: Commit**

Run:

```bash
git add roles/common/files/bin/tmux-window-label roles/common/files/bin/tmux-window-label.test
git -c commit.gpgsign=false commit -m "feat(tmux): add active-pane window label helper"
```

## Task 3: Rewire configs and config tests

**Files:**
- Modify: `roles/common/files/bin/tmux-window-bar-config.test`
- Modify: `roles/common/tasks/main.yml`
- Modify: `roles/common/templates/dotfiles/zshrc`
- Modify: `roles/macos/templates/dotfiles/tmux.conf`
- Modify: `roles/linux/files/dotfiles/tmux.conf`
- Test: `roles/common/files/bin/tmux-window-bar-config.test`

- [ ] **Step 1: Rewrite the config regression harness for the new model**

Update `roles/common/files/bin/tmux-window-bar-config.test` so it asserts:

- `tmux-pane-label` and `tmux-window-label` are installed by `roles/common/tasks/main.yml`
- both tmux configs keep `status on`, `status-position top`, and `pane-border-status bottom`
- both tmux configs use `#{window_name}` plus `+` / `!`, not `#{window_index}`
- both tmux configs remove visible pane numbers from `pane-border-format`
- both tmux configs wire `tmux-window-label` into `pane-focus-in` and `client-session-changed`
- `roles/common/templates/dotfiles/zshrc` calls both `tmux-session-name` and `tmux-window-label`

- [ ] **Step 2: Run the config harness and confirm RED**

Run:

```bash
bash roles/common/files/bin/tmux-window-bar-config.test
```

Expected: non-zero exit against the current prototype config.

- [ ] **Step 3: Update Ansible install tasks**

Modify `roles/common/tasks/main.yml` to copy:

- `tmux-pane-label`
- `tmux-window-label`

into `~/.local/bin` with mode `0755`.

- [ ] **Step 4: Update the zsh hooks**

Modify `roles/common/templates/dotfiles/zshrc` so the tmux prompt hook triggers both:

- `tmux-session-name "$TMUX_PANE"`
- `tmux-window-label "$TMUX_PANE"`

Keep the commands backgrounded and quiet.

- [ ] **Step 5: Update both tmux configs**

Modify `roles/macos/templates/dotfiles/tmux.conf` and `roles/linux/files/dotfiles/tmux.conf` so:

- the top bar format is label-only:
  ` #{window_name}#{?window_activity_flag,+,}#{?window_bell_flag,!,} `
- no window index is shown
- `pane-border-format` calls `tmux-pane-label "#{pane_tty}" "#{pane_current_path}"` and shows no pane index
- `pane-focus-in` and `client-session-changed` update both session name and window label

- [ ] **Step 6: Run the config harness to confirm GREEN**

Run:

```bash
bash roles/common/files/bin/tmux-window-bar-config.test
```

Expected: exit `0` with all assertions passing.

- [ ] **Step 7: Commit**

Run:

```bash
git add roles/common/files/bin/tmux-window-bar-config.test roles/common/tasks/main.yml roles/common/templates/dotfiles/zshrc roles/macos/templates/dotfiles/tmux.conf roles/linux/files/dotfiles/tmux.conf
git -c commit.gpgsign=false commit -m "feat(tmux): wire active-pane labels into tmux chrome"
```

## Task 4: Verify on macOS

**Files:**
- Runtime only: local macOS machine after `bin/provision`

- [ ] **Step 1: Provision from the worktree**

Run:

```bash
bin/provision
```

Expected: Ansible recap ends with `failed=0`.

- [ ] **Step 2: Reload and inspect live tmux options**

Run:

```bash
tmux source-file "$HOME/.tmux.conf"
tmux show -gv status
tmux show -gv status-position
tmux show -gv pane-border-status
tmux show -gv window-status-format
tmux show -gv pane-border-format
```

Expected:

- `status` is `on`
- `status-position` is `top`
- `pane-border-status` is `bottom`
- neither format shows visible window/pane numbers

- [ ] **Step 3: Verify live labels in a disposable tmux session**

Create a disposable session, then verify:

- local git pane label shows `branch dir`
- local non-git pane label shows `dir`
- shell-backed windows no longer show `zsh`
- the active pane's window label matches the pane border label text
- `+` and `!` markers still appear in the top bar

- [ ] **Step 4: If verification required code changes, commit them**

Only if Task 4 uncovered a real defect and you changed code, run:

```bash
git add roles/common/files/bin/tmux-pane-label roles/common/files/bin/tmux-window-label roles/common/files/bin/tmux-window-bar-config.test roles/common/tasks/main.yml roles/common/templates/dotfiles/zshrc roles/macos/templates/dotfiles/tmux.conf roles/linux/files/dotfiles/tmux.conf
git -c commit.gpgsign=false commit -m "fix(tmux): align active-pane labels with runtime behavior"
```

## Task 5: Verify on Linux and finish

**Files:**
- Runtime only: one reachable Linux dev host, if a trusted target exists

- [ ] **Step 1: Attempt Linux verification on an accessible dev host**

Use one reachable, trusted Linux dev host target. Run:

```bash
bin/provision
tmux source-file "$HOME/.tmux.conf"
```

and repeat these live checks:

- `status` is `on`
- `status-position` is `top`
- `pane-border-status` is `bottom`
- shell-backed windows no longer show `zsh`
- local git panes show `branch dir`
- local non-git panes show `dir`
- the active pane's window label matches the pane border label text
- `+` and `!` markers still appear in the top bar

- [ ] **Step 2: If Linux host verification is blocked, document the blocker**

Capture the exact blocker in the PR description and final handoff, rather than
claiming full Linux runtime verification without evidence.

- [ ] **Step 3: Create the PR**

Before opening the PR:

- run `git status --short`
- run the helper tests and config test fresh
- summarize macOS runtime verification evidence
- summarize Linux verification status honestly

Then create a GitHub PR from this branch with a concise summary of:

- helper additions
- tmux/zsh wiring changes
- macOS verification evidence
- Linux verification evidence or blocker
