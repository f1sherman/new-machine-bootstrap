# Ghostty Native Tab Session Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore Ghostty's regular saved tabs to the exact previously visible tmux session set while excluding quick-terminal and unrelated detached sessions.

**Architecture:** Ghostty native save state recreates surfaces. A periodic AppleScript saver records exact regular-tab session names and the Ghostty PID; helpers sharing a new Ghostty PID consume those names from a lock-protected JSON queue before using ordinary unattached-session selection.

**Tech Stack:** Bash, Ruby/Minitest, AppleScript, jq, tmux, launchd, Ansible

## Global Constraints

- All implementation and provisioning changes remain inside this worktree until `bin/provision` applies them.
- `window-save-state = always` delegates surface count and placement to Ghostty.
- Quick-terminal exclusion is structural: only `tabs of window` enter the manifest.
- Exact session set is required; exact tab order is best-effort.
- Every target is reserved with the helper PID before the coordination lock is released.
- Missing or invalid manifest/queue state falls back to normal selection while still respecting the lock.
- Diagnostics remain nonblocking, synchronized, single-line, and size-bounded.
- Production behavior changes follow red-green-refactor.

---

## File map

- Create `roles/macos/files/bin/ghostty-session-manifest-save`: collect, validate, and atomically save regular Ghostty tab sessions.
- Create `roles/macos/templates/launchd/com.user.ghostty-session-manifest-save.plist`: run the saver every 60 seconds.
- Modify `roles/common/files/bin/tmux-attach-or-new`: initialize and consume the per-Ghostty-process restore queue under the startup lock.
- Modify `roles/common/files/bin/tmux-restore-debug-report`: print manifest and queue state.
- Modify `roles/macos/tasks/main.yml`: enable native save state and provision/load the saver LaunchAgent.
- Modify `tests/tmux-restore-startup.rb`: exercise queue selection with the existing fake tmux implementation.
- Create `tests/ghostty-session-manifest.rb`: exercise saver validation and atomic preservation using fake `osascript`, `pgrep`, and `tmux` commands.
- Modify `tests/tmux-restore-diagnostics.sh`: assert the two new report sections.
- Modify `tests/ci-test-inventory.sh`: include the new Ruby test when required by the inventory convention.

---

### Task 1: Save an exact regular-tab session manifest

**Files:**
- Create: `roles/macos/files/bin/ghostty-session-manifest-save`
- Create: `tests/ghostty-session-manifest.rb`

**Interfaces:**
- Produces JSON at `${TMUX_GHOSTTY_MANIFEST:-$HOME/.local/state/tmux/ghostty-session-manifest.json}`.
- Accepts `GHOSTTY_APP_PID` as an explicit operational/test override; otherwise uses `pgrep -nf '/Ghostty.app/Contents/MacOS/ghostty$'`.
- Consumes AppleScript rows with fields `window_ordinal`, `selected_tab_index`, `tab_index`, and `session_name` separated by literal tabs.

- [ ] **Step 1: Write the failing saver tests**

Create a Minitest harness that places fake commands first in `PATH`, invokes the real saver, and asserts:

```ruby
def test_saves_regular_tabs_in_window_and_tab_order
  rows = [
    [1, 2, 2, "hnp"],
    [1, 2, 1, "journal"],
    [2, 1, 1, "nmb"]
  ]
  result = run_saver(rows:, sessions: %w[journal hnp nmb], ghostty_pid: 4321)
  manifest = JSON.parse(File.read(@manifest))

  assert result.success?
  assert_equal 4321, manifest.fetch("ghostty_pid")
  assert_equal %w[journal hnp nmb], manifest.fetch("windows").flat_map { |window|
    window.fetch("tabs").map { |tab| tab.fetch("session_name") }
  }
end

def test_rejects_unknown_or_duplicate_sessions_without_replacing_last_good
  File.write(@manifest, JSON.generate("version" => 1, "ghostty_pid" => 1, "windows" => []))
  original = File.read(@manifest)

  refute run_saver(rows: [[1, 1, 1, "missing"]], sessions: ["journal"], ghostty_pid: 4321).success?
  assert_equal original, File.read(@manifest)
end
```

Also assert the embedded AppleScript reads `name of focused terminal of t`, uses a window ordinal counter, and never requests `index of w`.

- [ ] **Step 2: Run the saver tests and verify RED**

Run:

```bash
ruby tests/ghostty-session-manifest.rb
```

Expected: failures because `roles/macos/files/bin/ghostty-session-manifest-save` does not exist.

- [ ] **Step 3: Implement the minimal saver**

The script must:

```bash
state_dir="${TMUX_GHOSTTY_STATE_DIR:-$HOME/.local/state/tmux}"
manifest="${TMUX_GHOSTTY_MANIFEST:-$state_dir/ghostty-session-manifest.json}"
mkdir -p "$state_dir"
ghostty_pid="${GHOSTTY_APP_PID:-$(pgrep -nf '/Ghostty.app/Contents/MacOS/ghostty$' 2>/dev/null || true)}"
```

Collect rows with positional window counters and supported tab indices:

```applescript
tell application "Ghostty"
  set output to ""
  set windowOrdinal to 0
  repeat with w in windows
    set windowOrdinal to windowOrdinal + 1
    set selectedIndex to index of selected tab of w
    repeat with t in tabs of w
      set termRef to focused terminal of t
      set output to output & windowOrdinal & tab & selectedIndex & tab & (index of t) & tab & (name of termRef) & linefeed
    end repeat
  end repeat
  return output
end tell
```

Use `jq -Rn` to group rows by window ordinal, sort tabs by tab index, set `version`, `ghostty_pid`, and `saved_at`, then validate that the flattened names are nonempty and unique. Validate every name with exact tmux targeting:

```bash
while IFS= read -r session_name; do
  tmux has-session -t "=$session_name" 2>/dev/null || exit 1
done < <(jq -r '.windows[].tabs[].session_name' "$candidate")
```

Write to a `mktemp` candidate in the destination directory, `chmod 0600`, and `mv` only after all validation passes. Exit nonzero for malformed candidates so launchd records failure while the last good file remains unchanged; exit zero when Ghostty is not running or exposes no windows.

- [ ] **Step 4: Run saver tests and verify GREEN**

Run:

```bash
ruby tests/ghostty-session-manifest.rb
bash -n roles/macos/files/bin/ghostty-session-manifest-save
shellcheck roles/macos/files/bin/ghostty-session-manifest-save
```

Expected: all pass with no ShellCheck findings.

- [ ] **Step 5: Commit the saver unit**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Save Ghostty regular tab sessions" \
  roles/macos/files/bin/ghostty-session-manifest-save \
  tests/ghostty-session-manifest.rb
```

---

### Task 2: Consume saved sessions under the startup lock

**Files:**
- Modify: `roles/common/files/bin/tmux-attach-or-new`
- Modify: `tests/tmux-restore-startup.rb`

**Interfaces:**
- Consumes `${TMUX_GHOSTTY_MANIFEST:-$HOME/.local/state/tmux/ghostty-session-manifest.json}`.
- Reads/writes `${TMUX_GHOSTTY_RESTORE_QUEUE:-$HOME/.local/state/tmux/ghostty-restore-queue.json}` only while file descriptor 9 holds the startup lock.
- `ghostty_app_pid` comes from `TMUX_GHOSTTY_APP_PID` or the helper's Ghostty grandparent process.
- Produces a session ID in `target`; ordinary selection remains the fallback.

- [ ] **Step 1: Write failing concurrent queue tests**

Extend test setup with manifest and queue paths, add them to `helper_env`, and add:

```ruby
def test_new_ghostty_process_claims_exact_manifest_set
  set_sessions(%w[17 19 journal hnp nmb command-proxy misc])
  write_manifest(pid: 100, sessions: %w[journal hnp nmb command-proxy misc])
  env = helper_env("TMUX_GHOSTTY_APP_PID" => "200", "FAKE_TMUX_ATTACH_DELAY" => "0.25")

  results = 5.times.map { Thread.new { Open3.capture3(env, HELPER) } }.map(&:value)
  names = read_attachments.map { |entry| entry.fetch("session_name") }

  assert_equal %w[command-proxy hnp journal misc nmb], names.sort
  refute_includes names, "17"
  refute_includes names, "19"
  results.each { |_out, _err, status| assert status.success? }
end
```

Add separate tests proving:

```ruby
# Missing saved names are skipped and the next valid saved session is claimed.
# Once pending is empty, another helper with the same app PID uses ordinary selection.
# A manifest whose ghostty_pid equals the helper app PID does not initialize restore mode.
# No Ghostty PID or no manifest preserves Linux/current behavior.
```

- [ ] **Step 2: Run startup tests and verify RED**

Run:

```bash
ruby tests/tmux-restore-startup.rb
```

Expected: exact-manifest assertions fail because the helper selects sessions `17` and `19`.

- [ ] **Step 3: Implement PID and queue helpers**

Add paths after lock configuration:

```bash
GHOSTTY_MANIFEST="${TMUX_GHOSTTY_MANIFEST:-$HOME/.local/state/tmux/ghostty-session-manifest.json}"
GHOSTTY_RESTORE_QUEUE="${TMUX_GHOSTTY_RESTORE_QUEUE:-$HOME/.local/state/tmux/ghostty-restore-queue.json}"
```

Resolve the application PID explicitly in tests or from the known Ghostty → login → helper chain:

```bash
ghostty_app_pid="${TMUX_GHOSTTY_APP_PID:-}"
if [ -z "$ghostty_app_pid" ]; then
  login_pid="$(ps -o ppid= -p "$$" 2>/dev/null | tr -d ' ')"
  ghostty_app_pid="$(ps -o ppid= -p "$login_pid" 2>/dev/null | tr -d ' ')"
fi
case "$ghostty_app_pid" in ''|*[!0-9]*) ghostty_app_pid="" ;; esac
```

While holding descriptor 9, initialize queue JSON when its PID differs. Only seed manifest names when `.ghostty_pid != current_pid`; otherwise write an empty pending array. Use a temp file plus rename in the queue directory.

Consume pending names in order. For each name:

```bash
candidate_id="$(tmux display-message -p -t "=$candidate_name" '#{session_id}' 2>/dev/null || true)"
```

Match the ID against `sessions_output`; skip bootstrap, attached, missing, or live-reserved candidates. Reclaim dead owners using the existing behavior. Remove every inspected candidate from pending, reserve the first valid target with the current helper PID, and emit queue lifecycle events. If queue processing returns no target, enter the existing ordinary loop unchanged.

- [ ] **Step 4: Run startup tests and verify GREEN**

Run:

```bash
ruby tests/tmux-restore-startup.rb
bash -n roles/common/files/bin/tmux-attach-or-new
shellcheck roles/common/files/bin/tmux-attach-or-new
```

Expected: all startup tests pass, including existing delayed restore and reservation cases.

- [ ] **Step 5: Commit queue selection**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Restore saved Ghostty tab sessions" \
  roles/common/files/bin/tmux-attach-or-new \
  tests/tmux-restore-startup.rb
```

---

### Task 3: Provision native state and expose queue diagnostics

**Files:**
- Create: `roles/macos/templates/launchd/com.user.ghostty-session-manifest-save.plist`
- Modify: `roles/macos/tasks/main.yml`
- Modify: `roles/common/files/bin/tmux-restore-debug-report`
- Modify: `tests/tmux-restore-diagnostics.sh`
- Modify: `tests/ci-test-inventory.sh`

**Interfaces:**
- LaunchAgent label: `com.user.ghostty-session-manifest-save`.
- LaunchAgent executes `~/.local/bin/ghostty-session-manifest-save` every 60 seconds and at load.
- Debug report headings: `Ghostty session manifest` and `Ghostty restore queue`.

- [ ] **Step 1: Write failing provisioning and report assertions**

Add repository assertions to `tests/ghostty-session-manifest.rb`:

```ruby
assert_match(/line: 'window-save-state = always'/, File.read(MACOS_TASKS))
refute_match(/Remove ghostty window-save-state setting/, File.read(MACOS_TASKS))
assert_match(/com\.user\.ghostty-session-manifest-save\.plist/, File.read(MACOS_TASKS))
```

Extend diagnostics test setup with manifest and queue fixtures, run the report with path overrides, and assert:

```bash
grep -F '=== Ghostty session manifest ===' "$report"
grep -F '=== Ghostty restore queue ===' "$report"
grep -F '"session_name": "journal"' "$report"
```

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
ruby tests/ghostty-session-manifest.rb
bash tests/tmux-restore-diagnostics.sh
```

Expected: missing configuration/LaunchAgent assertions and missing report headings fail.

- [ ] **Step 3: Add provisioning and diagnostics**

Create the plist with:

```xml
<key>Label</key>
<string>com.user.ghostty-session-manifest-save</string>
<key>ProgramArguments</key>
<array>
  <string>{{ ansible_facts["user_dir"] }}/.local/bin/ghostty-session-manifest-save</string>
</array>
<key>RunAtLoad</key><true/>
<key>StartInterval</key><integer>60</integer>
```

Replace the removal task with:

```yaml
- name: Configure ghostty native window state restoration
  lineinfile:
    path: '{{ ansible_facts["user_dir"] }}/Library/Application Support/com.mitchellh.ghostty/config'
    regexp: '^window-save-state\s*='
    line: 'window-save-state = always'
    create: yes
    mode: 0644
```

Install the plist, unload it only when changed, and load it with the same idempotent launchctl pattern as other user LaunchAgents. Add explicit cleanup for the known obsolete `com.user.ghostty-layout-save.plist` and unloaded label.

In the debug report, print each JSON file with `jq .` when valid and raw `cat` otherwise; print `none` when absent. Respect `TMUX_GHOSTTY_MANIFEST` and `TMUX_GHOSTTY_RESTORE_QUEUE` overrides.

Add the new test to CI inventory if the inventory script enumerates tests explicitly.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
ruby tests/ghostty-session-manifest.rb
bash tests/tmux-restore-diagnostics.sh
bash tests/ci-test-inventory.sh
```

Expected: all pass.

- [ ] **Step 5: Commit provisioning and diagnostics**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Enable Ghostty native workspace restore" \
  roles/macos/templates/launchd/com.user.ghostty-session-manifest-save.plist \
  roles/macos/tasks/main.yml \
  roles/common/files/bin/tmux-restore-debug-report \
  tests/tmux-restore-diagnostics.sh \
  tests/ci-test-inventory.sh \
  tests/ghostty-session-manifest.rb
```

---

### Task 4: Full verification, provisioning, and PR update

**Files:**
- Modify only if verification exposes a test-backed defect.

**Interfaces:**
- Installed manifest saver matches the repository copy.
- Installed Ghostty config contains exactly one `window-save-state = always` line.
- PR #340 head matches the local branch.

- [ ] **Step 1: Run complete automated verification**

```bash
ruby tests/tmux-restore-startup.rb
ruby tests/ghostty-session-manifest.rb
bash tests/tmux-restore-diagnostics.sh
bash tests/ci-test-inventory.sh
bash tests/ghostty-quick-terminal.sh
bash -n roles/common/files/bin/tmux-attach-or-new \
  roles/common/files/bin/tmux-restore-debug-report \
  roles/macos/files/bin/ghostty-session-manifest-save
shellcheck roles/common/files/bin/tmux-attach-or-new \
  roles/common/files/bin/tmux-restore-debug-report \
  roles/macos/files/bin/ghostty-session-manifest-save
ansible-playbook playbook.yml --syntax-check
git diff --check
```

Expected: every command exits zero.

- [ ] **Step 2: Provision this branch**

```bash
bin/provision
```

Expected: successful play recap with zero failed hosts. This step is mandatory because a separate branch provision reinstalled old tmux instrumentation during development.

- [ ] **Step 3: Verify installed state**

```bash
cmp roles/macos/files/bin/ghostty-session-manifest-save ~/.local/bin/ghostty-session-manifest-save
cmp roles/common/files/bin/tmux-attach-or-new ~/.local/bin/tmux-attach-or-new
grep -x 'window-save-state = always' "$HOME/Library/Application Support/com.mitchellh.ghostty/config"
launchctl print "gui/$(id -u)/com.user.ghostty-session-manifest-save"
~/.local/bin/ghostty-session-manifest-save
jq . ~/.local/state/tmux/ghostty-session-manifest.json
tmux-restore-debug-report
```

Expected: copies match, launchd job exists, manifest lists the five current regular sessions once each, and the report includes both JSON sections.

- [ ] **Step 4: Review and commit any verification-only correction**

If a verification command exposes a defect, first add a failing automated reproduction, confirm RED, make the minimal fix, confirm GREEN, then commit only the affected files with `z-commit/commit.sh`. If no defect appears, do not create an empty commit.

- [ ] **Step 5: Push and update PR #340**

```bash
git push origin fix/tmux-restore-concurrency-diagnostics
gh pr edit 340 --body-file /tmp/tmux-restore-pr-body.md
```

Update the PR body first so it describes native surface restoration, manifest targeting, the observed failed restart, and the new verification evidence. Confirm `gh pr view 340 --json headRefOid` matches `git rev-parse HEAD`, then arm the PR monitor.

- [ ] **Step 6: Perform the real restart acceptance test**

Before quitting, capture regular Ghostty tabs and tmux clients. Fully quit Ghostty with `Cmd-Q`, reopen it, then verify:

```text
regular tabs = journal, hnp, nmb, command-proxy, misc (each exactly once)
quick-terminal session 17 = not a regular tab
unrelated session 19 = not a regular tab
blank tabs = 0
```

Ordering is recorded but is not a blocker. On failure, do not restart again; immediately capture `tmux-restore-debug-report`, Ghostty AppleScript tab inventory, and `tmux list-clients`.
