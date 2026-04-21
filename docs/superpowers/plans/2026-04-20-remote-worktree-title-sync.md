# Remote Worktree Title Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make remote `worktree-start` and `tmux-agent-worktree set|clear` update the focused local terminal title plus local tmux session/window names immediately, with `(*branch)` dirty markers and `<directory> | <host>` fallback.

**Architecture:** Add one remote helper that computes and publishes a stable pane title from explicit worktree state or the active pane path. Add one local helper that reacts only to active remote-pane title changes that match that stable contract, then renames the local tmux session and window to the received label. Keep fork-heavy work out of hot hooks by filtering early and reusing the existing worktree state contract.

**Tech Stack:** Bash, tmux, git, Ansible-managed dotfiles, shell test harnesses.

---

### Task 1: Lock in the red tests and plan plumbing

**Files:**
- Create: `roles/common/files/bin/tmux-remote-title.test`
- Create: `roles/common/files/bin/tmux-sync-remote-title.test`
- Modify: `roles/common/files/bin/tmux-agent-worktree.test`
- Modify: `roles/common/files/bin/tmux-window-bar-config.test`
- Modify: `roles/common/files/bin/terminal-restore-config.test`
- Modify: `roles/common/tasks/main.yml`

- [ ] **Step 1: Add the remote title helper test harness**

Create `roles/common/files/bin/tmux-remote-title.test` with cases for:

```bash
run_case \
  "linked clean worktree prints branch repo host" \
  "print" \
  "tty-agent" \
  "$base_repo" \
  "%91" \
  "$linked_wt" \
  "9100" \
  $'9100 S+ codex codex --cd /tmp/irrelevant' \
  "claw02" \
  "(feature/title-sync) linked-wt | claw02"

run_case \
  "linked dirty worktree adds star" \
  "print" \
  "tty-agent-dirty" \
  "$base_repo" \
  "%92" \
  "$dirty_wt" \
  "9101" \
  $'9101 S+ codex codex --cd /tmp/irrelevant' \
  "claw02" \
  "(*feature/dirty-title) dirty-wt | claw02"

run_case \
  "clear fallback uses active directory" \
  "print" \
  "tty-clear" \
  "$base_repo" \
  "%93" \
  "" \
  "" \
  "" \
  "claw02" \
  "repo | claw02"
```

- [ ] **Step 2: Add the local sync helper test harness**

Create `roles/common/files/bin/tmux-sync-remote-title.test` with cases for:

```bash
run_case \
  "active remote pane renames session and window" \
  "%11" \
  $'$0\t1\tssh\t/dev/ttys001\t(feature/foo) repo | claw02\t$1\tmain\tmain window' \
  "rename-session -t \$1 (feature/foo) repo | claw02" \
  "rename-window -t \$0 (feature/foo) repo | claw02"

run_case \
  "non matching title is ignored" \
  "%12" \
  $'$0\t1\tssh\t/dev/ttys002\t2.1.92\t$1\tmain\tmain window' \
  "" \
  ""

run_case \
  "inactive pane is ignored" \
  "%13" \
  $'$0\t0\tssh\t/dev/ttys003\t(feature/foo) repo | claw02\t$1\tmain\tmain window' \
  "" \
  ""
```

- [ ] **Step 3: Extend the explicit state harness**

Append assertions to `roles/common/files/bin/tmux-agent-worktree.test` so `set`, `clear`, and `sync-current` verify the new title publisher is invoked:

```bash
cat > "$bindir/tmux-remote-title" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TMUX_REMOTE_TITLE_LOG"
EOF
chmod +x "$bindir/tmux-remote-title"

grep -Fqx "publish" "$TMUX_REMOTE_TITLE_LOG"
```

- [ ] **Step 4: Add config/install assertions before implementation**

Extend the config/install tests to expect:

```bash
assert_contains "roles/common/tasks/main.yml" "tmux-remote-title"
assert_contains "roles/common/tasks/main.yml" "tmux-sync-remote-title"
assert_contains "roles/macos/templates/dotfiles/tmux.conf" "tmux-sync-remote-title #{pane_id}"
assert_contains "roles/linux/files/dotfiles/tmux.conf" "tmux-sync-remote-title #{pane_id}"
assert_contains "roles/macos/templates/dotfiles/tmux.conf" "tmux-remote-title publish"
assert_contains "roles/linux/files/dotfiles/tmux.conf" "tmux-remote-title publish"
```

- [ ] **Step 5: Run the red tests**

Run:

```bash
bash roles/common/files/bin/tmux-remote-title.test
bash roles/common/files/bin/tmux-sync-remote-title.test
bash roles/common/files/bin/tmux-agent-worktree.test
bash roles/common/files/bin/tmux-window-bar-config.test
bash roles/common/files/bin/terminal-restore-config.test
```

Expected: the new helper tests fail because the scripts do not exist, and the config/install tests fail because the new hooks and install entries are missing.

- [ ] **Step 6: Commit the red state**

```bash
git add \
  roles/common/files/bin/tmux-remote-title.test \
  roles/common/files/bin/tmux-sync-remote-title.test \
  roles/common/files/bin/tmux-agent-worktree.test \
  roles/common/files/bin/tmux-window-bar-config.test \
  roles/common/files/bin/terminal-restore-config.test \
  roles/common/tasks/main.yml
git -c commit.gpgsign=false commit -m "Add remote title sync tests"
```

### Task 2: Implement the remote title publisher

**Files:**
- Create: `roles/common/files/bin/tmux-remote-title`
- Modify: `roles/common/tasks/main.yml`
- Test: `roles/common/files/bin/tmux-remote-title.test`

- [ ] **Step 1: Write the helper with print/publish modes**

Create `roles/common/files/bin/tmux-remote-title` with this structure:

```bash
#!/usr/bin/env bash
set -u

mode="${1:-publish}"
pane_id="${TMUX_PANE:-}"

is_remote_context() {
  [ -n "${SSH_CONNECTION:-}" ] || [ -n "${CODESPACES:-}" ] || [ -n "${DEVPOD_WORKSPACE_ID:-}" ]
}

branch_for_path() { ...read .git/HEAD directly... }
is_dirty_path() { [ -n "$(git --no-optional-locks -C "$1" status --porcelain 2>/dev/null)" ]; }
host_tag() { ...prefer CODESPACE_NAME / DEVPOD_WORKSPACE_ID / hostname -s... }
title_for_path() { ...emit "(*branch) repo | host", "(branch) repo | host", or "dir | host"... }

case "$mode" in
  print) printf '%s\n' "$title" ;;
  publish) printf '\033]2;%s\033\\' "$title" > "$client_tty" ;;
esac
```

- [ ] **Step 2: Keep the helper low-fork**

Use these constraints in the implementation:

```bash
# one tmux RPC for pane path + client tty
pane_info="$(tmux display-message -p -t "$pane_id" '#{pane_current_path}\t#{client_tty}')"

# read pane-local explicit state directly from tmux option values once
worktree_path="$(tmux show-options -pv -t "$pane_id" @agent_worktree_path 2>/dev/null || true)"
worktree_pid="$(tmux show-options -pv -t "$pane_id" @agent_worktree_pid 2>/dev/null || true)"

# only fall back to ps when a stored pid exists and must be validated
```

- [ ] **Step 3: Install the new helper**

Add a copy task in `roles/common/tasks/main.yml`:

```yaml
- name: Install tmux-remote-title script
  copy:
    backup: yes
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin/tmux-remote-title'
    src: '{{ playbook_dir }}/roles/common/files/bin/tmux-remote-title'
    mode: 0755
```

- [ ] **Step 4: Run the targeted tests**

Run:

```bash
bash roles/common/files/bin/tmux-remote-title.test
```

Expected: PASS for clean linked worktree, dirty linked worktree, fallback path, and publish mode.

- [ ] **Step 5: Commit the green helper**

```bash
git add roles/common/files/bin/tmux-remote-title roles/common/tasks/main.yml roles/common/files/bin/tmux-remote-title.test
git -c commit.gpgsign=false commit -m "Add tmux remote title publisher"
```

### Task 3: Implement the local filtered sync helper

**Files:**
- Create: `roles/common/files/bin/tmux-sync-remote-title`
- Modify: `roles/common/tasks/main.yml`
- Test: `roles/common/files/bin/tmux-sync-remote-title.test`

- [ ] **Step 1: Write the helper**

Create `roles/common/files/bin/tmux-sync-remote-title` with one tmux query and early exits:

```bash
#!/usr/bin/env bash
set -euo pipefail

pane_id="${1:-${TMUX_PANE:-}}"
pane_info="$(tmux display-message -p -t "$pane_id" '#{window_id}\t#{pane_active}\t#{pane_current_command}\t#{pane_tty}\t#{pane_title}\t#{session_id}\t#{session_name}\t#{window_name}')"
IFS=$'\t' read -r window_id pane_active pane_current_command pane_tty pane_title session_id session_name window_name <<< "$pane_info"

[ "$pane_active" = "1" ] || exit 0
case "$pane_current_command" in ssh|gh|ruby) ;; *) exit 0 ;; esac
case "$pane_title" in *" | "*) ;; *) exit 0 ;; esac
[ "$pane_title" != "$session_name" ] && tmux rename-session -t "$session_id" "$pane_title" 2>/dev/null || true
[ "$pane_title" != "$window_name" ] && tmux rename-window -t "$window_id" "$pane_title" 2>/dev/null || true
```

- [ ] **Step 2: Install the helper**

Add:

```yaml
- name: Install tmux-sync-remote-title script
  copy:
    backup: yes
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin/tmux-sync-remote-title'
    src: '{{ playbook_dir }}/roles/common/files/bin/tmux-sync-remote-title'
    mode: 0755
```

- [ ] **Step 3: Run the targeted tests**

Run:

```bash
bash roles/common/files/bin/tmux-sync-remote-title.test
```

Expected: PASS for active remote rename, spinner/noise ignore, and inactive ignore.

- [ ] **Step 4: Commit the helper**

```bash
git add roles/common/files/bin/tmux-sync-remote-title roles/common/tasks/main.yml roles/common/files/bin/tmux-sync-remote-title.test
git -c commit.gpgsign=false commit -m "Add local tmux remote title sync helper"
```

### Task 4: Wire the helpers into explicit worktree state and tmux hooks

**Files:**
- Modify: `roles/common/files/bin/tmux-agent-worktree`
- Modify: `roles/macos/templates/dotfiles/tmux.conf`
- Modify: `roles/linux/files/dotfiles/tmux.conf`
- Modify: `roles/common/files/bin/tmux-agent-worktree.test`
- Modify: `roles/common/files/bin/tmux-window-bar-config.test`
- Modify: `roles/common/files/bin/terminal-restore-config.test`

- [ ] **Step 1: Trigger title publish from explicit state changes**

Update `roles/common/files/bin/tmux-agent-worktree` to publish after every state mutation:

```bash
publish_title() {
  command -v tmux-remote-title >/dev/null 2>&1 || return 0
  tmux-remote-title publish >/dev/null 2>&1 || true
}

cmd_set() { ... write_pane_option ...; publish_title; }
cmd_clear() { ... clear_pane_option ...; publish_title; }
cmd_sync_current() {
  if ! is_git_worktree_path "$PWD" || ! is_linked_worktree "$PWD" || ! on_named_branch "$PWD"; then
    cmd_clear
    return 0
  fi
  ...write state...
  publish_title
}
```

- [ ] **Step 2: Add tmux hooks**

Update both tmux config files so:

```tmux
set-hook -g pane-focus-in 'run-shell -b "$HOME/.local/bin/tmux-remote-title publish"; run-shell -b "$HOME/.local/bin/tmux-session-name #{pane_id}"; run-shell -b "$HOME/.local/bin/tmux-window-label #{pane_id}"'
set-hook -g client-session-changed 'run-shell -b "$HOME/.local/bin/tmux-remote-title publish"; run-shell -b "$HOME/.local/bin/tmux-session-name #{pane_id}"; run-shell -b "$HOME/.local/bin/tmux-window-label #{pane_id}"'
set-hook -g pane-title-changed 'run-shell -b "$HOME/.local/bin/tmux-sync-remote-title #{pane_id}"'
```

The new `pane-title-changed` hook should only call the filtered helper.

- [ ] **Step 3: Run the wiring tests**

Run:

```bash
bash roles/common/files/bin/tmux-agent-worktree.test
bash roles/common/files/bin/tmux-window-bar-config.test
bash roles/common/files/bin/terminal-restore-config.test
```

Expected: PASS, including the new publish-trigger and hook assertions.

- [ ] **Step 4: Commit the wiring**

```bash
git add \
  roles/common/files/bin/tmux-agent-worktree \
  roles/macos/templates/dotfiles/tmux.conf \
  roles/linux/files/dotfiles/tmux.conf \
  roles/common/files/bin/tmux-agent-worktree.test \
  roles/common/files/bin/tmux-window-bar-config.test \
  roles/common/files/bin/terminal-restore-config.test
git -c commit.gpgsign=false commit -m "Wire tmux remote title sync hooks"
```

### Task 5: End-to-end verification and PR handoff

**Files:**
- Verify only

- [ ] **Step 1: Run the focused regression suite**

Run:

```bash
bash roles/common/files/bin/tmux-remote-title.test
bash roles/common/files/bin/tmux-sync-remote-title.test
bash roles/common/files/bin/tmux-agent-worktree.test
bash roles/common/files/bin/tmux-window-label.test
bash roles/common/files/bin/tmux-pane-label.test
bash roles/common/files/bin/tmux-window-bar-config.test
bash roles/common/files/bin/terminal-restore-config.test
bash roles/common/files/bin/worktree-start.test
```

Expected: all pass.

- [ ] **Step 2: Provision and reload tmux**

Run:

```bash
bin/provision
tmux source-file "$HOME/.tmux.conf"
```

Expected: provision succeeds and tmux reloads without config errors.

- [ ] **Step 3: Manual verification**

Check:

```bash
ssh <remote>
cd ~/projects/new-machine-bootstrap
worktree-start feature/title-sync-demo
tmux-agent-worktree clear
```

Expected:

- local terminal title immediately becomes `(<branch>) <repo> | <host>` after `worktree-start`
- local tmux session and window names match the same string
- dirtying the linked worktree and refocusing shows `(*<branch>) <repo> | <host>`
- `tmux-agent-worktree clear` falls back to `<directory> | <host>`
- background remote panes do not rename the local client until focused

- [ ] **Step 4: Open the pull request**

Run the repository’s PR flow after verification passes:

```bash
create-pull-request
```

Expected: PR created from the implementation branch with the verified changes.
