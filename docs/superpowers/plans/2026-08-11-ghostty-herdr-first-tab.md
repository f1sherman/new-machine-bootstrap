# Ghostty Herdr First Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Start Herdr in the first tab of each Ghostty app process and use the existing tmux launcher for all later tabs until Herdr exits.

**Architecture:** Ghostty runs a new `ghostty-tab-launch` dispatcher for every surface. The dispatcher identifies its Ghostty ancestor and uses a locked, per-Ghostty-PID live-owner marker to select either `herdr-launch` or `tmux-attach-or-new` without changing either command's behavior.

**Tech Stack:** Bash, macOS `ps`, `mkdir` locking, Ansible, Ghostty configuration

## Global Constraints

- Scope one Herdr owner across all windows in one Ghostty app process.
- Give separate Ghostty app processes independent Herdr owners.
- Preserve `tmux-attach-or-new` restore and session-selection behavior.
- Store coordination state in `$HOME/.local/state/ghostty-tab-launch` with user-only directory permissions.
- Reclaim invalid or stale markers.
- Clear the owned marker when Herdr exits or fails.
- Do not add a permanent automated test unless it meets the repository's test-value requirements.

---

### Task 1: Add and Deploy the Ghostty Tab Dispatcher

**Files:**
- Create: `roles/macos/files/bin/ghostty-tab-launch`
- Modify: `roles/macos/tasks/main.yml:201-207`

**Interfaces:**
- Consumes: `herdr-launch` and `tmux-attach-or-new`, both executable commands in `$HOME/.local/bin`; `GHOSTTY_TAB_LAUNCH_STATE_DIR` as an optional verification-only state-directory override; `GHOSTTY_TAB_LAUNCH_APP_PID` as an optional verification-only numeric Ghostty PID override.
- Produces: `ghostty-tab-launch`, a no-argument Ghostty surface command that exits with the selected child command's status.

- [ ] **Step 1: Build a failing disposable behavior harness**

Create a temporary fixture outside the repository. Copy the planned production
path into the fixture only after implementation. Stub `herdr-launch` so it
records `herdr`, waits on a release file, and exits with a configured status.
Stub `tmux-attach-or-new` so it records `tmux`. Invoke the production dispatcher
with isolated values for `HOME`, `GHOSTTY_TAB_LAUNCH_STATE_DIR`, and
`GHOSTTY_TAB_LAUNCH_APP_PID`.

Before the production file exists, confirm:

```bash
test -x roles/macos/files/bin/ghostty-tab-launch
```

Expected: FAIL because the dispatcher does not exist.

The finished harness must assert these observable cases:

```text
first live invocation                         -> herdr
second invocation while first is waiting     -> tmux
invocation after first exits                  -> herdr
invalid marker contents                       -> herdr
marker naming a dead PID                      -> herdr
two simultaneous first invocations            -> one herdr and one tmux
two distinct overridden Ghostty app PIDs      -> two herdr invocations
Herdr nonzero exit                            -> same exit status and no marker
```

- [ ] **Step 2: Implement the dispatcher**

Create `roles/macos/files/bin/ghostty-tab-launch` with Bash strict mode. Implement
these focused functions:

```bash
find_ghostty_pid()       # print numeric Ghostty ancestor PID or fail
read_live_owner()        # print a validated live launcher PID or fail
remove_owned_marker()    # remove marker only when it still contains $$
release_lock()           # remove the atomic mkdir lock when held
cleanup()                # release lock and remove this process's marker
```

Use `GHOSTTY_TAB_LAUNCH_APP_PID` when set; otherwise walk from `$PPID` through
`ps -p "$pid" -o command=` and `ps -p "$pid" -o ppid=` until the command
matches `*/Ghostty.app/Contents/MacOS/ghostty*`. Reject a nonnumeric PID or a
walk that reaches PID 1 without finding Ghostty.

Create the state directory with `umask 077` and `mkdir -p`. Acquire one
coordination lock with atomic `mkdir`, retry briefly when another dispatcher
owns it, and reclaim the lock only when its recorded owner PID is dead. Store
the lock owner PID inside the lock directory.

Use marker `$state_dir/herdr-$ghostty_pid.pid`. A live marker must be numeric,
respond to `kill -0`, and have a `ps -p "$owner" -o command=` value ending in
`ghostty-tab-launch`. Remove any marker that fails validation.

When a live marker exists, release the lock and run:

```bash
exec "$HOME/.local/bin/tmux-attach-or-new"
```

Otherwise, write `$$` to a temporary marker, atomically rename it to the final
marker, release the lock, and run `herdr-launch` as a child. Preserve its exit
status. Install EXIT, HUP, INT, and TERM handling that removes the marker only
when it is still owned by `$$`.

- [ ] **Step 3: Configure Ghostty to use the dispatcher**

Change the managed line in `roles/macos/tasks/main.yml` to:

```yaml
line: 'command = {{ ansible_facts["user_dir"] }}/.local/bin/ghostty-tab-launch'
```

The existing `Install macOS-specific scripts` fileglob installs the new helper
with mode `0755`; do not add a second copy task.

- [ ] **Step 4: Run focused verification**

Run the disposable behavior harness from Step 1 against the production script.
Expected: all eight cases pass.

Run:

```bash
bash -n roles/macos/files/bin/ghostty-tab-launch
shellcheck roles/macos/files/bin/ghostty-tab-launch
ansible-playbook playbook.yml --syntax-check
```

Expected: all commands exit zero.

- [ ] **Step 5: Commit the implementation**

Commit these exact paths with an imperative message:

```text
roles/macos/files/bin/ghostty-tab-launch
roles/macos/tasks/main.yml
```

Suggested message: `Start Herdr in the first Ghostty tab`

### Task 2: Provision and Verify the Managed Behavior

**Files:**
- Verify deployed copies only; do not edit files outside the repository.

**Interfaces:**
- Consumes: the committed dispatcher and managed Ghostty command from Task 1.
- Produces: empirical proof that provisioning deploys the command and that live Ghostty tabs follow the required lifecycle.

- [ ] **Step 1: Provision from the feature worktree**

Run `bin/provision` from the worktree and rely on its built-in lock. Expected:
the macOS-specific script task deploys `ghostty-tab-launch`, and the Ghostty
configuration task changes its command without failures.

- [ ] **Step 2: Verify deployed configuration and file identity**

Compare the deployed script with the repository source and inspect the managed
Ghostty command. Expected: the files match and the command points to
`$HOME/.local/bin/ghostty-tab-launch`.

- [ ] **Step 3: Verify the live Ghostty lifecycle**

After reloading Ghostty configuration, open a new Ghostty app process. Confirm:

```text
first tab across all windows          -> Herdr
later tab while Herdr remains open    -> existing tmux attach command
new window while Herdr remains open   -> existing tmux attach command
next tab after the Herdr tab exits    -> Herdr
```

If interactive automation cannot safely close the user's existing surfaces,
use a separate Ghostty app process and report the exact parts verified by
process inspection and the disposable production-script harness.

- [ ] **Step 4: Run final repository checks**

Run `git diff --check`, confirm the worktree is clean after commits, and inspect
the final commit range. Expected: no whitespace errors, no uncommitted changes,
and only the spec, plan, dispatcher, and Ghostty task change are present.
