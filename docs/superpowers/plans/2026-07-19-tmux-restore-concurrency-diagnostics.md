# Tmux Restore Concurrency and Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make simultaneous Ghostty surfaces attach to distinct restored tmux sessions and produce bounded, actionable diagnostics instead of blank tabs.

**Architecture:** `tmux-attach-or-new` serializes restore and selection with one flock, reserves a selected session with its live helper PID before unlocking, and retains that reservation while the tmux client runs. A shared shell logging library writes bounded one-line events for the attach helper and resurrect wrapper; a report command summarizes logs, tmux state, reservations, and the latest snapshot.

**Tech Stack:** Bash 3.2-compatible shell, tmux, flock, Ruby standard library test harness, Ansible, GitHub Actions.

## Global Constraints

- All managed changes remain inside this repository; deployed files are never edited directly.
- `__bootstrap__` is never an ordinary attachment candidate.
- A lock deadline must fall back to a visible usable login shell, never unlocked tmux startup.
- Runtime reservations contain helper PIDs and are reclaimable only when the owner PID is dead.
- Logs retain only current and previous bounded files and contain no multi-line process dumps.
- Exact Ghostty tab order and window placement remain out of scope.

---

### Task 1: Reproduce concurrent session selection and failure paths

**Files:**
- Create: `tests/tmux-restore-startup.rb`
- Modify: `.github/workflows/integration-test.yml`

**Interfaces:**
- Consumes: `roles/common/files/bin/tmux-attach-or-new`; environment seams `TMUX_ATTACH_LOCK_FILE`, `TMUX_ATTACH_LOCK_TIMEOUT`, `TMUX_RESTORE_LOG_LIB`, `TMUX_RESURRECT_RESTORE_WRAPPER`, and `TMUX_ATTACH_FALLBACK_SHELL`.
- Produces: a stateful fake `tmux` executable and regression scenarios that later tasks make pass.

- [ ] **Step 1: Write the stateful fake and duplicate-selection regression**

Create a Ruby standard-library test harness that builds an isolated HOME/PATH, writes a fake `tmux`, and stores sessions/options/attachment records in JSON guarded by `File#flock`. The core concurrent assertion must launch four helper processes and require four distinct targets:

```ruby
results = 4.times.map do
  Thread.new { Open3.capture3(env, helper) }
end.map(&:value)

attachments = JSON.parse(File.read(attachments_path))
assert_equal 4, attachments.length
assert_equal 4, attachments.map { |entry| entry.fetch("session_id") }.uniq.length
results.each { |_out, _err, status| assert status.success? }
```

The fake `attach` command must deliberately pause before marking its target attached so the current unlock-before-attach implementation deterministically selects the same session twice.

- [ ] **Step 2: Add slow restore, stale reservation, attach failure, and empty-state cases**

Add focused cases asserting:

```ruby
assert_equal 1, restore_invocations
assert_equal [], unlocked_bootstrap_attempts
assert_includes fallback_output, "tmux-restore-debug-report"
assert_nil session_options.fetch("@ghostty_attach_owner", nil)
refute_equal "__bootstrap__", attachments.first.fetch("session_name")
```

The slow-restore case must exceed the configured test lock deadline and prove the waiter uses the shell fallback rather than running tmux without the lock. Reservation cases must distinguish a live owner PID from a definitely dead PID.

- [ ] **Step 3: Run the new test and confirm the intended failures**

Run:

```bash
ruby tests/tmux-restore-startup.rb
```

Expected: duplicate-target and unlocked-timeout assertions fail against the current helper; test harness setup itself succeeds.

- [ ] **Step 4: Add the test to CI**

Add after the CI inventory step:

```yaml
      - name: Verify tmux restore startup coordination
        run: ruby tests/tmux-restore-startup.rb
```

- [ ] **Step 5: Verify inventory remains satisfied**

Run:

```bash
bash tests/ci-test-inventory.sh
```

Expected: `1 passed, 0 failed`.

- [ ] **Step 6: Commit the red tests**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Test concurrent tmux restore startup" \
  tests/tmux-restore-startup.rb \
  .github/workflows/integration-test.yml
```

---

### Task 2: Add bounded shared diagnostics and report command

**Files:**
- Create: `roles/common/files/bin/tmux-restore-log.sh`
- Create: `roles/common/files/bin/tmux-restore-debug-report`
- Create: `tests/tmux-restore-diagnostics.sh`
- Modify: `roles/common/files/bin/tmux-resurrect-restore-wrapper`
- Modify: `roles/common/tasks/main.yml`
- Modify: `.github/workflows/integration-test.yml`

**Interfaces:**
- Consumes: optional `TMUX_RESTORE_STATE_DIR`, `TMUX_RESTORE_LOG`, `TMUX_RESTORE_LOG_LIMIT`, and `TMUX_RESURRECT_RESTORE_SCRIPT` test/runtime overrides.
- Produces: sourceable functions `tmux_restore_log_event EVENT [key=value ...]` and `tmux_restore_rotate_log`; executable `tmux-restore-debug-report`.

- [ ] **Step 1: Write failing diagnostics contract tests**

Create a shell test that sources the future library in an isolated state directory, emits events containing tabs/newlines, forces rotation with a small byte limit, and asserts only current/previous logs remain. It must also invoke the report command with a fake tmux and assert these headings:

```text
Tmux restore diagnostics
Recent restore events
Current sessions
Current clients
Reservations
Latest resurrect snapshot
```

Run:

```bash
bash tests/tmux-restore-diagnostics.sh
```

Expected: FAIL because the library and report command do not exist.

- [ ] **Step 2: Implement the logging library**

Implement Bash 3.2-compatible helpers with one sanitized line per append:

```bash
TMUX_RESTORE_STATE_DIR="${TMUX_RESTORE_STATE_DIR:-$HOME/.local/state/tmux}"
TMUX_RESTORE_LOG="${TMUX_RESTORE_LOG:-$TMUX_RESTORE_STATE_DIR/restore.log}"
TMUX_RESTORE_LOG_LIMIT="${TMUX_RESTORE_LOG_LIMIT:-262144}"
TMUX_RESTORE_LOG_SEQUENCE=0

tmux_restore_log_event() {
  event="$1"; shift
  TMUX_RESTORE_LOG_SEQUENCE=$((TMUX_RESTORE_LOG_SEQUENCE + 1))
  mkdir -p "$TMUX_RESTORE_STATE_DIR" 2>/dev/null || return 0
  printf 'timestamp=%s\tseq=%s\tpid=%s\tppid=%s\tevent=%s' \
    "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$TMUX_RESTORE_LOG_SEQUENCE" "$$" "$PPID" "$event"
  printf '\t%s' "$@"
  printf '\n'
}
```

Sanitize carriage returns, newlines, and tabs before the atomic append. `tmux_restore_rotate_log` moves current to `.previous` only when the configured byte limit is exceeded.

- [ ] **Step 3: Instrument the resurrect wrapper with completion status**

Replace the `ps` dump and `exec` with shared start/end events:

```bash
source "${TMUX_RESTORE_LOG_LIB:-$HOME/.local/bin/tmux-restore-log.sh}"
restore_script="${TMUX_RESURRECT_RESTORE_SCRIPT:-$HOME/.tmux/plugins/tmux-resurrect/scripts/restore.sh}"
tmux_restore_log_event restore_start "script=$restore_script"
set +e
"$restore_script" "$@"
status=$?
set -e
tmux_restore_log_event restore_end "status=$status"
exit "$status"
```

- [ ] **Step 4: Implement the read-only report command**

Print the fixed headings, tail bounded portions of `.previous` and current logs, and query tmux with failure-tolerant commands:

```bash
tmux list-sessions -F '#{session_id}\t#{session_name}\tattached=#{session_attached}\towner=#{@ghostty_attach_owner}'
tmux list-clients -F '#{client_tty}\t#{session_id}\t#{session_name}'
tmux show-options -gqv @ghostty_restore_state
```

For each nonempty reservation owner, report `alive=yes|no` using `kill -0`. Resolve the latest resurrect symlink without failing when absent.

- [ ] **Step 5: Provision both diagnostics files**

Add to `Install tmux attach/session helpers`:

```yaml
    - { name: tmux-restore-log.sh, mode: '0644' }
    - { name: tmux-restore-debug-report, mode: '0755' }
```

- [ ] **Step 6: Add diagnostics test to CI and verify**

Run:

```bash
bash tests/tmux-restore-diagnostics.sh
bash tests/ci-test-inventory.sh
bash -n roles/common/files/bin/tmux-restore-log.sh \
  roles/common/files/bin/tmux-restore-debug-report \
  roles/common/files/bin/tmux-resurrect-restore-wrapper
```

Expected: all commands exit zero.

- [ ] **Step 7: Commit diagnostics**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Add bounded tmux restore diagnostics" \
  roles/common/files/bin/tmux-restore-log.sh \
  roles/common/files/bin/tmux-restore-debug-report \
  roles/common/files/bin/tmux-resurrect-restore-wrapper \
  roles/common/tasks/main.yml \
  tests/tmux-restore-diagnostics.sh \
  .github/workflows/integration-test.yml
```

---

### Task 3: Reserve sessions across the selection-to-attachment boundary

**Files:**
- Modify: `roles/common/files/bin/tmux-attach-or-new`
- Modify: `tests/tmux-restore-startup.rb`

**Interfaces:**
- Consumes: `tmux_restore_log_event`, `tmux_restore_rotate_log`, tmux option `@ghostty_attach_owner`, and server option `@ghostty_restore_state`.
- Produces: exclusive PID-owned session reservations retained for the tmux client lifetime.

- [ ] **Step 1: Load diagnostics and replace startup process dumps**

Source the managed library after PATH normalization and log `helper_invoked`. Remove all process-table scans. Add a fallback function that logs, prints a visible message naming `tmux-restore-debug-report`, and executes `${TMUX_ATTACH_FALLBACK_SHELL:-${SHELL:-/bin/zsh}} -l`.

- [ ] **Step 2: Make lock failure safe**

Try immediate acquisition first; print a restore-wait message only when contention exists. A bounded failure calls fallback rather than continuing:

```bash
if flock -n 9; then
  tmux_restore_log_event lock_acquired "waited=0"
else
  printf '%s\n' '[tmux] Waiting for saved sessions to restore...'
  if ! flock -w "$LOCK_TIMEOUT" 9; then
    fallback_shell lock_timeout
  fi
fi
```

- [ ] **Step 3: Make restore state explicit**

When no server exists, create `__bootstrap__`, set global `@ghostty_restore_state` to `running`, and call `${TMUX_RESURRECT_RESTORE_WRAPPER:-$HOME/.local/bin/tmux-resurrect-restore-wrapper}` with the synthetic TMUX socket. On success set `ok`; on failure set `failed` and use fallback. Existing servers with state `failed` also use fallback instead of competing restore.

- [ ] **Step 4: Reclaim dead reservations and select a candidate**

List sessions with IDs, names, attachment counts, and owners. For each owner, use `kill -0`; unset dead owners under the lock. Select only a non-bootstrap row with attached count zero and no live owner.

If no candidate exists, create it detached under the lock:

```bash
target="$(tmux new-session -d -P -F '#{session_id}' 2>/dev/null)" || fallback_shell session_create_failed
```

After successful restore, ensure a normal target exists before killing `__bootstrap__`.

- [ ] **Step 5: Reserve before unlock and retain ownership while attached**

Set the session option before unlocking:

```bash
tmux set-option -q -t "$target" @ghostty_attach_owner "$$"
reserved_target="$target"
```

Install cleanup that reacquires the global lock briefly, verifies the option still equals `$$`, unsets it, and unlocks. Run `tmux attach -t "$target"` without `exec`; cleanup on return or signal. Attach failure uses visible fallback after cleanup.

- [ ] **Step 6: Run focused startup tests**

Run:

```bash
ruby tests/tmux-restore-startup.rb
bash -n roles/common/files/bin/tmux-attach-or-new
```

Expected: all concurrency and failure scenarios pass; syntax check exits zero.

- [ ] **Step 7: Commit coordination fix**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Serialize tmux restore session assignment" \
  roles/common/files/bin/tmux-attach-or-new \
  tests/tmux-restore-startup.rb
```

---

### Task 4: Simplify managed hooks and verify deployment

**Files:**
- Modify: `roles/macos/templates/dotfiles/tmux.conf`
- Modify: `roles/linux/files/dotfiles/tmux.conf`
- Modify: `tests/tmux-restore-diagnostics.sh`

**Interfaces:**
- Consumes: managed `tmux-resurrect-restore-wrapper` and the shared restore log.
- Produces: lightweight configuration hooks without process-table scans and consistent manual restore instrumentation.

- [ ] **Step 1: Add failing configuration assertions**

Extend the diagnostics contract to assert both managed tmux configs:

- retain `@resurrect-restore-script-path` pointing to the wrapper
- do not contain `tmux-debug.log`
- do not contain `/bin/ps -axo`
- log session/client events through the new one-line logger or omit redundant hooks already covered by helper events

Run the test and confirm it fails against the old debug block.

- [ ] **Step 2: Replace obsolete debug blocks**

Remove the May 2026 interim instrumentation and process snapshots. Keep the restore wrapper setting because manual resurrect invokes it. Retain only lightweight session/client events when they add correlation not already supplied by the synchronous helper.

- [ ] **Step 3: Run full focused verification**

Run:

```bash
ruby tests/tmux-restore-startup.rb
bash tests/tmux-restore-diagnostics.sh
bash tests/ci-test-inventory.sh
bash tests/ghostty-quick-terminal.sh
bash -n roles/common/files/bin/tmux-attach-or-new \
  roles/common/files/bin/tmux-restore-log.sh \
  roles/common/files/bin/tmux-restore-debug-report \
  roles/common/files/bin/tmux-resurrect-restore-wrapper
ansible-playbook playbook.yml --syntax-check
```

Expected: every command exits zero.

- [ ] **Step 4: Apply managed configuration**

Run:

```bash
bin/provision
```

Expected: provisioning exits zero and installs the managed helper/library/report/configuration. Do not manually edit deployed files.

- [ ] **Step 5: Verify idempotence and installed behavior**

Run:

```bash
bin/provision --check
~/.local/bin/tmux-restore-debug-report
```

Expected: check mode reports no unexpected changes; report exits zero and contains all fixed headings.

- [ ] **Step 6: Commit managed-hook cleanup**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Use structured tmux restore events" \
  roles/macos/templates/dotfiles/tmux.conf \
  roles/linux/files/dotfiles/tmux.conf \
  tests/tmux-restore-diagnostics.sh
```

- [ ] **Step 7: Review the complete branch**

Inspect:

```bash
git diff main...HEAD
git status --short
git log --oneline main..HEAD
```

Expected: only approved design, plan, coordination, diagnostics, tests, CI, and provisioning changes; clean worktree.
