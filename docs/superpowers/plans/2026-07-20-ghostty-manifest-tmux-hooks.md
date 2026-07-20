# Ghostty Manifest tmux Hooks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the periodic Ghostty manifest LaunchAgent with serialized, event-driven macOS tmux hooks and actively remove the old plist.

**Architecture:** Four indexed macOS tmux hooks invoke the existing manifest saver asynchronously after a short settle delay. The saver serializes concurrent invocations with a bounded state-directory lock, while Ansible unloads and deletes the obsolete LaunchAgent plist.

**Tech Stack:** Bash, tmux configuration, AppleScript, Ansible YAML, Ruby/Minitest, ShellCheck

## Global Constraints

- Never add cron or another persistent scheduler.
- Hooks are macOS-only and use stable hook index `95`.
- Hook commands run in the background and wait `0.2` seconds before saving.
- Saver lock waits at most five seconds by default and lock failure must not disrupt tmux.
- Existing manifest schema, validation, atomic replacement, and last-good protections remain unchanged.
- Provisioning actively unloads and deletes `~/Library/LaunchAgents/com.user.ghostty-session-manifest-save.plist`.
- Selected-tab capture through `client-focus-in` remains best-effort.

---

### Task 1: Synchronize the Feature Branch

**Files:**
- Merge only; resolve existing PR files if required.

**Interfaces:**
- Consumes: latest `origin/main`, including merged status reconciliation work.
- Produces: PR #340 branch based on current main without unrelated delegate PR #343 commits.

- [ ] **Step 1: Fetch and inspect divergence**

Run:

```bash
git fetch origin main
git status --short
git log --oneline --left-right HEAD...origin/main
```

Expected: clean worktree and current main commits listed on the right.

- [ ] **Step 2: Merge current main**

Run:

```bash
git merge origin/main
```

Expected: clean merge or conflicts limited to files already changed by PR #340.

- [ ] **Step 3: Verify existing focused suites after the merge**

Run:

```bash
ruby tests/tmux-restore-startup.rb
ruby tests/ghostty-session-manifest.rb
ruby tests/ghostty-session-tabs-restore.rb
```

Expected: all existing tests pass before new behavior is introduced.

### Task 2: Serialize Manifest Saver Invocations

**Files:**
- Modify: `tests/ghostty-session-manifest.rb`
- Modify: `roles/macos/files/bin/ghostty-session-manifest-save`

**Interfaces:**
- Consumes: `TMUX_GHOSTTY_MANIFEST`, existing optional restore logger, and the system `flock` command.
- Produces: `TMUX_GHOSTTY_MANIFEST_LOCK` path override and `TMUX_GHOSTTY_MANIFEST_LOCK_TIMEOUT` seconds override; default lock is beside the manifest and default timeout is `5`.

- [ ] **Step 1: Write failing serialization tests**

Extend the fake `osascript` so an invocation may create a marker and sleep through environment variables. Add a test that launches one saver, waits for its marker, launches a second saver with different rows, and asserts both succeed and the second invocation produces the final manifest. Pass a unique `TMUX_GHOSTTY_MANIFEST_LOCK` from `run_saver`.

Add a lock-timeout test that holds the configured lock externally, invokes the saver with `TMUX_GHOSTTY_MANIFEST_LOCK_TIMEOUT=0`, and asserts success, unchanged last-good manifest, and no AppleScript-created candidate.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
ruby tests/ghostty-session-manifest.rb
```

Expected: failures because the saver does not yet acquire the configured lock or honor lock timeout.

- [ ] **Step 3: Add bounded locking before Ghostty lookup**

Add configuration near the manifest path:

```bash
manifest_lock="${TMUX_GHOSTTY_MANIFEST_LOCK:-${manifest}.lock}"
manifest_lock_timeout="${TMUX_GHOSTTY_MANIFEST_LOCK_TIMEOUT:-5}"
```

Validate the timeout as a nonnegative integer, create the lock directory, open a dedicated descriptor, and run `flock -w "$manifest_lock_timeout"` before `pgrep` or AppleScript. On failure:

```bash
tmux_restore_log_event manifest_rejected "reason=lock_timeout"
exit 0
```

Keep the descriptor open for the complete saver execution.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run:

```bash
ruby tests/ghostty-session-manifest.rb
```

Expected: all manifest tests pass, including deterministic serialization and timeout preservation.

- [ ] **Step 5: Commit saver serialization**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Serialize Ghostty manifest saves" \
  tests/ghostty-session-manifest.rb \
  roles/macos/files/bin/ghostty-session-manifest-save
```

### Task 3: Replace LaunchAgent Scheduling with tmux Hooks

**Files:**
- Modify: `tests/ghostty-session-manifest.rb`
- Modify: `roles/macos/templates/dotfiles/tmux.conf`
- Modify: `roles/macos/tasks/main.yml`
- Delete: `roles/macos/templates/launchd/com.user.ghostty-session-manifest-save.plist`

**Interfaces:**
- Consumes: installed `$HOME/.local/bin/ghostty-session-manifest-save`.
- Produces: hook index `95` on `client-attached`, `client-detached`, `client-session-changed`, and `client-focus-in`.

- [ ] **Step 1: Replace the LaunchAgent contract test with failing hook/removal contracts**

Update the provisioning test to assert:

- `window-save-state = never` remains managed.
- tasks stat, unload, and remove `com.user.ghostty-session-manifest-save.plist`.
- tasks contain no template-install or launchctl-load task for that plist.
- the plist template does not exist.

Add a config contract that reads macOS and Linux tmux configs and asserts the macOS file contains exactly one hook at index `95` for each required event, each invoking:

```text
run-shell -b "sleep 0.2; $HOME/.local/bin/ghostty-session-manifest-save"
```

Assert the Linux config does not mention `ghostty-session-manifest-save`.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
ruby tests/ghostty-session-manifest.rb
```

Expected: failures because the plist is still installed and tmux hooks do not exist.

- [ ] **Step 3: Add the four macOS hooks**

Add documented stable hooks to `roles/macos/templates/dotfiles/tmux.conf`:

```tmux
set-hook -g client-attached[95] 'run-shell -b "sleep 0.2; $HOME/.local/bin/ghostty-session-manifest-save"'
set-hook -g client-detached[95] 'run-shell -b "sleep 0.2; $HOME/.local/bin/ghostty-session-manifest-save"'
set-hook -g client-session-changed[95] 'run-shell -b "sleep 0.2; $HOME/.local/bin/ghostty-session-manifest-save"'
set-hook -g client-focus-in[95] 'run-shell -b "sleep 0.2; $HOME/.local/bin/ghostty-session-manifest-save"'
```

Do not add these hooks to the Linux config.

- [ ] **Step 4: Replace installation tasks with cleanup tasks and delete the template**

Use the existing obsolete-plist pattern:

```yaml
- name: Stat obsolete Ghostty session manifest LaunchAgent plist
  stat:
    path: '{{ ansible_facts["user_dir"] }}/Library/LaunchAgents/com.user.ghostty-session-manifest-save.plist'
  register: ghostty_session_manifest_plist

- name: Unload obsolete Ghostty session manifest launchd job
  command: launchctl unload {{ ansible_facts["user_dir"] }}/Library/LaunchAgents/com.user.ghostty-session-manifest-save.plist
  when: ghostty_session_manifest_plist.stat.exists
  changed_when: false
  failed_when: false

- name: Remove obsolete Ghostty session manifest LaunchAgent plist
  file:
    path: '{{ ansible_facts["user_dir"] }}/Library/LaunchAgents/com.user.ghostty-session-manifest-save.plist'
    state: absent
```

Delete `roles/macos/templates/launchd/com.user.ghostty-session-manifest-save.plist`.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run:

```bash
ruby tests/ghostty-session-manifest.rb
bash tests/tmux-managed-bars-contract.sh
```

Expected: all tests pass and existing hook inventory remains valid.

- [ ] **Step 6: Commit event-driven manifest saving**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Save Ghostty manifests from tmux hooks" \
  tests/ghostty-session-manifest.rb \
  roles/macos/templates/dotfiles/tmux.conf \
  roles/macos/tasks/main.yml \
  roles/macos/templates/launchd/com.user.ghostty-session-manifest-save.plist
```

### Task 4: Verify, Provision, and Prove Live Behavior

**Files:**
- Modify only if verification reveals a reproducible defect.

**Interfaces:**
- Consumes: completed hook and saver changes.
- Produces: deployed plist-free event-driven manifest saving and updated PR proof.

- [ ] **Step 1: Run complete focused automation**

Run:

```bash
ruby tests/tmux-restore-startup.rb
ruby tests/ghostty-session-manifest.rb
ruby tests/ghostty-session-tabs-restore.rb
bash tests/tmux-restore-diagnostics.sh
bash tests/tmux-managed-bars-contract.sh
bash tests/ghostty-quick-terminal.sh
bash tests/ci-test-inventory.sh
shellcheck roles/macos/files/bin/ghostty-session-manifest-save \
  roles/macos/files/bin/ghostty-session-tabs-restore \
  roles/common/files/bin/tmux-attach-or-new \
  roles/common/files/bin/tmux-resurrect-restore-wrapper \
  roles/common/files/bin/tmux-restore-debug-report
bash -n roles/macos/files/bin/ghostty-session-manifest-save \
  roles/macos/files/bin/ghostty-session-tabs-restore
git diff --check origin/main...HEAD
ansible-playbook playbook.yml --syntax-check
```

Expected: all commands pass with no lint, syntax, or whitespace failures.

- [ ] **Step 2: Review the branch**

Use the repository review workflow against `origin/main`. Reproduce and fix only valid findings through a new failing test.

- [ ] **Step 3: Coordinate and run a combined provision**

Broadcast an nmb provisioning hold. Build a temporary worktree combining the latest accepted `origin/main`, the current PR #340 head, and any still-unmerged accepted provisioning branch required for the shared live state. Run:

```bash
bin/provision
```

Expected: Ansible reports `failed=0`.

- [ ] **Step 4: Verify deployed cleanup and exact files**

Confirm:

```bash
! test -e "$HOME/Library/LaunchAgents/com.user.ghostty-session-manifest-save.plist"
! launchctl print "gui/$(id -u)/com.user.ghostty-session-manifest-save"
cmp roles/macos/files/bin/ghostty-session-manifest-save "$HOME/.local/bin/ghostty-session-manifest-save"
cmp roles/common/files/bin/tmux-attach-or-new "$HOME/.local/bin/tmux-attach-or-new"
grep -x 'window-save-state = never' "$HOME/Library/Application Support/com.mitchellh.ghostty/config"
```

Inspect `tmux show-hooks -g` and confirm exactly one index-95 saver hook for all four events.

- [ ] **Step 5: Exercise event-driven saving**

Save the initial manifest checksum, open or focus a regular Ghostty tab, wait one second, and confirm the manifest timestamp/checksum changes and its session list matches the visible regular tabs. Close the test tab if one was created and confirm the manifest updates again without manual saver invocation.

- [ ] **Step 6: Repeat deterministic restart acceptance**

With the intended five-tab manifest current, quit and reopen Ghostty without manual tab intervention. Confirm five intended distinct clients, an empty queue, and `tab_builder_complete` in the bounded restore log.

- [ ] **Step 7: Update and push PR #340**

Update the PR description and live proof to explain plist-free tmux-hook saving, push all commits, and rearm PR monitoring.
