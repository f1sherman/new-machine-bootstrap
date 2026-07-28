# Tmux Restore Resilience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make restart restoration automatically recover a dangling latest snapshot, restore Ghostty tabs after tmux sessions exist, and resume configured pane processes without one handler blocking all others.

**Architecture:** Add two narrow state guards at existing lifecycle boundaries: the post-save hook prevents tmux-resurrect's same-path comparison from deleting its active target, and the startup helper explicitly repoints a dangling `last` to `last.safe` while holding its startup lock. Change the existing sidecar dispatcher to launch each handler in an isolated background subshell so core restoration and tab reconstruction can complete independently.

**Tech Stack:** Bash 3.2-compatible shell, Ruby 4/minitest, tmux-resurrect state files, existing structured restore logging.

## Global Constraints

- Do not reconstruct arbitrary interactive shell history or unregistered process state.
- Do not replace tmux-resurrect or tmux-continuum.
- Do not add filename heuristics, legacy-layout inference, or migration behavior.
- Do not change process-specific restore handler semantics.
- Keep all public repository content free of private organization, repository, ticket, employee, and tooling references.
- Follow test-driven development: observe each regression test fail before production edits.

---

### Task 1: Preserve same-target autosaves

**Files:**
- Create: `tests/tmux-resurrect-save-extra.rb`
- Modify: `roles/common/files/bin/tmux-resurrect-save-extra`

**Interfaces:**
- Consumes: tmux-resurrect's `post-save-layout` argument, the absolute new state-file path.
- Produces: `last.safe`, `last.safe.meta.json`, and removal of `last` only when its resolved symlink target equals the new state-file path.

- [ ] **Step 1: Write the failing same-target regression test**

Create a minitest fixture with a temporary `HOME`, a fake `tmux` executable that returns no persisted pane options, and a substantial state file containing at least 1 KiB and three `pane\t` records. Point `last` at that same state file, execute `tmux-resurrect-save-extra`, and assert:

```ruby
assert File.file?(File.join(@resurrect_dir, "last.safe"))
refute File.exist?(@last)
refute File.symlink?(@last)
```

Also add a control test where `last` targets a different state file and remains unchanged.

- [ ] **Step 2: Run the new test and verify RED**

Run: `ruby tests/tmux-resurrect-save-extra.rb`

Expected: the same-target test fails because `last` remains a symlink.

- [ ] **Step 3: Add the exact collision guard**

After successful safe rotation, resolve `last` only when it is a symlink. If `File.expand_path(File.readlink(last), dir) == File.expand_path(state_file)`, unlink `last`. Do not inspect timestamps, filename patterns, or snapshot sizes beyond the existing safe-rotation checks.

- [ ] **Step 4: Verify GREEN**

Run: `ruby tests/tmux-resurrect-save-extra.rb`

Expected: both same-target and different-target cases pass.

- [ ] **Step 5: Commit the save guard**

```bash
git add tests/tmux-resurrect-save-extra.rb roles/common/files/bin/tmux-resurrect-save-extra
git commit -m "Preserve colliding tmux snapshots"
```

### Task 2: Fall back before startup restoration

**Files:**
- Modify: `tests/tmux-restore-startup.rb`
- Modify: `roles/common/files/bin/tmux-attach-or-new`

**Interfaces:**
- Consumes: `TMUX_RESURRECT_DIR`, `<dir>/last`, and `<dir>/last.safe` while startup fd 9 holds `TMUX_ATTACH_LOCK_FILE`.
- Produces: an atomically replaced `last -> last.safe` symlink and structured event `restore_snapshot_fallback` with the failed and selected paths.

- [ ] **Step 1: Write failing startup fallback tests**

Extend test setup with a temporary resurrect directory and include `TMUX_RESURRECT_DIR` in `helper_env`. Add these cases:

```ruby
def test_dangling_last_falls_back_before_restore
  File.write(File.join(@resurrect_dir, "last.safe"), "safe snapshot\n")
  File.symlink("missing.txt", File.join(@resurrect_dir, "last"))

  _out, _err, status = Open3.capture3(helper_env("FAKE_RESTORE_SESSIONS" => "journal"), HELPER)

  assert status.success?
  assert_equal "last.safe", File.readlink(File.join(@resurrect_dir, "last"))
  assert_event(/event=restore_snapshot_fallback\tmissing=.*\tselected=.*last\.safe/)
end
```

Add controls proving a valid `last` is retained and a dangling `last` without `last.safe` keeps existing empty-start behavior.

- [ ] **Step 2: Run focused tests and verify RED**

Run: `ruby tests/tmux-restore-startup.rb --name '/dangling_last|valid_last/'`

Expected: fallback case fails because `last` still targets the missing file and no fallback event exists.

- [ ] **Step 3: Implement locked explicit fallback**

Add a helper before `resurrect_snapshot` that:

1. Reads `TMUX_RESURRECT_DIR` or the existing default.
2. Returns unless `last` is a symlink and its resolved target is not a regular file.
3. Returns unless `last.safe` is a regular file.
4. Creates a temporary symlink in the same directory, renames it over `last`, and logs `restore_snapshot_fallback`.
5. Calls existing fallback-shell handling if atomic replacement fails.

Invoke it after detecting no server and before logging `restore_start`, while the startup lock remains held.

- [ ] **Step 4: Verify startup and Ghostty ordering**

Run:

```bash
ruby tests/tmux-restore-startup.rb
ruby tests/ghostty-session-tabs-restore.rb
ruby tests/ghostty-session-manifest.rb
```

Expected: all tests pass; existing tab-builder-after-unlock coverage remains green.

- [ ] **Step 5: Commit startup fallback**

```bash
git add tests/tmux-restore-startup.rb roles/common/files/bin/tmux-attach-or-new
git commit -m "Fall back from dangling tmux snapshots"
```

### Task 3: Isolate post-restore handlers

**Files:**
- Create: `tests/tmux-resurrect-restore-extra.rb`
- Modify: `roles/common/files/bin/tmux-resurrect-restore-extra`

**Interfaces:**
- Consumes: `<resolved-last>.meta.json`, live tmux pane coordinates, and executables named `tmux-restore-handler-<persist-key>` on `PATH`.
- Produces: one independent background handler process per recognized sidecar value plus `handler-complete` or `handler-failed` lines in `restore-extra.log`.

- [ ] **Step 1: Write the failing nonblocking dispatcher test**

Create a minitest fixture with two sidecar entries and a fake `tmux` coordinate map. Put two handlers on `PATH`: the first writes a started marker, sleeps for two seconds, then writes a completed marker; the second writes its marker immediately. Execute the dispatcher with a one-second Ruby timeout and assert it returns successfully, then poll briefly for both started markers.

```ruby
Timeout.timeout(1) { system(@env, RESTORE_EXTRA, exception: true) }
wait_for(@slow_started)
wait_for(@fast_started)
```

Add a failure handler case and poll `restore-extra.log` for its independent `handler-failed` record.

- [ ] **Step 2: Run the new test and verify RED**

Run: `ruby tests/tmux-resurrect-restore-extra.rb`

Expected: timeout occurs because the current dispatcher waits for the slow handler before starting the next one.

- [ ] **Step 3: Dispatch each handler independently**

Replace the synchronous handler call with a background subshell:

```bash
(
  if "$handler" "$pid" "$val"; then
    echo "$(date) handler-complete: $key for $coord"
  else
    echo "$(date) handler-failed: $key for $coord"
  fi
) >>"$log" 2>&1 &
```

Keep missing-handler and missing-pane behavior synchronous and unchanged. Do not wait for background jobs.

- [ ] **Step 4: Verify dispatcher and integration suites**

Run:

```bash
ruby tests/tmux-resurrect-restore-extra.rb
ruby tests/tmux-resurrect-save-extra.rb
ruby tests/tmux-restore-startup.rb
tests/tmux-restore-diagnostics.sh
ruby tests/ghostty-session-tabs-restore.rb
ruby tests/ghostty-session-manifest.rb
```

Expected: all tests pass without timeout or leaked foreground jobs.

- [ ] **Step 5: Commit handler isolation**

```bash
git add tests/tmux-resurrect-restore-extra.rb roles/common/files/bin/tmux-resurrect-restore-extra
git commit -m "Isolate tmux restore handlers"
```

### Task 4: Full verification and deployment

**Files:**
- Verify all modified files and committed docs.

**Interfaces:**
- Consumes: completed Tasks 1-3.
- Produces: provisioned local configuration and PR-ready branch.

- [ ] **Step 1: Run syntax and focused behavioral checks**

```bash
bash -n roles/common/files/bin/tmux-attach-or-new
bash -n roles/common/files/bin/tmux-resurrect-restore-extra
ruby -c roles/common/files/bin/tmux-resurrect-save-extra
ruby tests/tmux-resurrect-save-extra.rb
ruby tests/tmux-resurrect-restore-extra.rb
ruby tests/tmux-restore-startup.rb
tests/tmux-restore-diagnostics.sh
ruby tests/ghostty-session-tabs-restore.rb
ruby tests/ghostty-session-manifest.rb
```

Expected: syntax checks report success and every test passes.

- [ ] **Step 2: Run repository integration tests that cover managed files**

Run the repository's integration test entry points discovered from `.github/workflows/integration-test.yml`, including shellcheck/Ansible syntax checks applicable on macOS.

Expected: all locally applicable checks pass; document any platform-only checks delegated to CI.

- [ ] **Step 3: Provision from this worktree**

Run: `bin/provision`

Expected: changed helper files deploy successfully under the provision lock.

- [ ] **Step 4: Verify deployed parity without altering runtime sessions**

Compare hashes for each changed managed helper against its deployed `~/.local/bin` counterpart and source the managed tmux config only if provisioning did not already reload it.

Expected: source and deployed hashes match. Do not restart or destroy the recovered tmux server.

- [ ] **Step 5: Independent review, push, and PR**

Request a fresh-context code review, apply any verified fixes as the sole writer, rerun affected checks, push `fix/tmux-restore-resilience`, and open a public PR describing only generic macOS/Ghostty/tmux behavior.

### Task 5: Restore autosaving after interrupted manual recovery

**Files:**
- Create: `tests/tmux-resurrect-recover.rb`
- Modify: `roles/common/files/bin/tmux-resurrect-recover`
- Modify: `.github/workflows/integration-test.yml`

**Interfaces:**
- Consumes: the current `@continuum-save-interval` and catchable process signals while manual recovery owns the temporary pause.
- Produces: idempotent restoration of the prior nonzero interval on normal completion, ordinary failure, `HUP`, `INT`, or `TERM`.

- [ ] **Step 1: Write the failing interruption regression**

Create a minitest fixture with a fake `tmux` executable backed by an interval state file and a blocking fake restore script. Spawn `tmux-resurrect-recover` in its own process group with an explicit substantial source snapshot and nonempty `TMUX`; wait until the restore marker exists, send `TERM` to the process group, and assert the fake tmux interval returns from `0` to `5` before the process exits.

- [ ] **Step 2: Run the test and verify RED**

Run: `ruby tests/tmux-resurrect-recover.rb`

Expected: the interval remains `0` after interruption.

- [ ] **Step 3: Add interruption-safe cleanup**

After pausing continuum, install catchable signal handlers that exit with conventional `128 + signal` status. Wrap the recovery body in `begin`/`ensure`, restoring the prior interval exactly once from the ensure path. Restore prior signal handlers after ordinary completion. Preserve existing snapshot selection, fd-pressure handling, tmux config sourcing, and summary behavior.

- [ ] **Step 4: Add CI coverage and verify GREEN**

Add `ruby tests/tmux-resurrect-recover.rb` beside the other tmux restore workflow steps. Run:

```bash
ruby tests/tmux-resurrect-recover.rb
bash tests/ci-test-inventory.sh
ruby tests/tmux-restore-startup.rb
ruby tests/tmux-resurrect-save-extra.rb
ruby tests/tmux-resurrect-restore-extra.rb
git diff --check
```

Expected: all tests pass and CI inventory references the new test.

- [ ] **Step 5: Commit interrupted-recovery safety**

```bash
git add tests/tmux-resurrect-recover.rb roles/common/files/bin/tmux-resurrect-recover .github/workflows/integration-test.yml docs/superpowers/specs/2026-07-27-tmux-restore-resilience-design.md docs/superpowers/plans/2026-07-27-tmux-restore-resilience.md
git commit -m "Resume tmux autosaves after interrupted recovery"
```

### Task 6: Close final save and signal safety gaps

**Files:**
- Create: `roles/common/files/bin/tmux-resurrect-save-wrapper`
- Create: `tests/tmux-resurrect-save-wrapper.rb`
- Modify: `roles/common/tasks/main.yml`
- Modify: `roles/macos/templates/dotfiles/tmux.conf`
- Modify: `roles/linux/files/dotfiles/tmux.conf`
- Modify: `roles/common/files/bin/tmux-resurrect-save-extra`
- Modify: `roles/common/files/bin/tmux-resurrect-restore-extra`
- Modify: `tests/tmux-resurrect-save-extra.rb`
- Modify: `tests/tmux-resurrect-restore-extra.rb`
- Modify: `roles/common/files/bin/tmux-resurrect-recover`
- Modify: `tests/tmux-resurrect-recover.rb`
- Modify: `.github/workflows/integration-test.yml`

**Interfaces:**
- Produces: `tmux-resurrect-save-wrapper`, which consumes `TMUX_RESURRECT_SAVE_SCRIPT` and `TMUX_RESURRECT_SAVE_LOCK` overrides and serializes the complete upstream save command.
- Produces: sidecar field `state_sha256`, verified against the selected state file before any process handler dispatch.
- Produces: recovery-owned restore child process group, terminated when the parent receives `HUP`, `INT`, or `TERM` directly.

- [ ] **Step 1: Write three failing boundary regressions**

Add tests proving: two concurrent wrapper invocations never overlap inside a blocking fake save script; restore-extra skips all handlers when `state_sha256` does not match the selected state file; and `TERM` sent only to the recovery PID terminates the blocking restore child, restores interval `5`, and exits `143`.

- [ ] **Step 2: Run each focused test and verify RED**

```bash
ruby tests/tmux-resurrect-save-wrapper.rb
ruby tests/tmux-resurrect-restore-extra.rb
ruby tests/tmux-resurrect-recover.rb
```

Expected: overlap is observed without the wrapper, mismatched metadata still dispatches handlers, and direct-PID TERM leaves recovery blocked.

- [ ] **Step 3: Implement save-wide serialization**

Install the wrapper from `roles/common/tasks/main.yml`. It opens the lock path, acquires `flock`, and executes the upstream save script with all arguments. Set `@resurrect-save-script-path` to the wrapper after TPM initialization in both managed tmux configs, then explicitly rebind tmux-resurrect's manual save key to the wrapper because the plugin's existing binding bypasses the option.

- [ ] **Step 4: Bind and validate state generations**

Use Ruby's standard `Digest::SHA256` in `tmux-resurrect-save-extra` to store `state_sha256`. Before reading pane entries, `tmux-resurrect-restore-extra` computes the selected state digest with an available system tool and exits after logging a generation mismatch when the digest differs or is absent. Update existing fixtures to include valid digests.

- [ ] **Step 5: Own and terminate the restore child**

Replace the blocking `system(opts[:restore_script])` call with an explicitly spawned child in a new process group. Record its PID before waiting. Deferred catchable-signal handling terminates that child process group so direct-PID signals promptly unwind into existing interval cleanup and preserve first-signal exit status.

- [ ] **Step 6: Verify and commit**

```bash
ruby tests/tmux-resurrect-save-wrapper.rb
ruby tests/tmux-resurrect-save-extra.rb
ruby tests/tmux-resurrect-restore-extra.rb
ruby tests/tmux-resurrect-recover.rb
ruby tests/tmux-restore-startup.rb
bash tests/ci-test-inventory.sh
bash -n roles/common/files/bin/tmux-resurrect-save-wrapper
bash -n roles/common/files/bin/tmux-resurrect-restore-extra
ruby -c roles/common/files/bin/tmux-resurrect-save-extra
ruby -c roles/common/files/bin/tmux-resurrect-recover
git diff --check
```

Commit with message `Close tmux restore concurrency gaps` and no AI attribution.
