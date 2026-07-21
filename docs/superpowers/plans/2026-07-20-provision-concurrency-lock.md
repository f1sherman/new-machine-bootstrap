# Provision Concurrency Lock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Serialize concurrent `bin/provision` runs automatically and stop routine provisioning coordination over the agent mesh.

**Architecture:** A focused Bash helper owns portable atomic-directory locking, metadata, stale-owner recovery, waiting, and release. `bin/provision` sources the helper and installs one cleanup trap before any shared provisioning state is touched; managed Pi and Claude base fragments tell agents to rely on that lock instead of mesh announcements.

**Tech Stack:** Bash 3.2-compatible shell, atomic `mkdir`, POSIX process tools, shell regression tests, Ansible-managed prompt fragments.

## Global Constraints

- Serialize every `bin/provision` invocation, including `--check` and `--diff`.
- Wait indefinitely for an active provisioner unless interrupted.
- Work on stock macOS and Debian before provisioned dependencies such as `flock` are available.
- Keep the lock per-user, host-local, and shared across repository worktrees.
- Recover stale ownership without allowing a waiter to remove another process's active lock.
- Do not announce routine provision start, completion, holds, or releases over the mesh.
- Remote-pi relay and generic message-delivery behavior remain out of scope.

---

### Task 1: Portable Provision Lock

**Files:**
- Create: `bin/provision-lock`
- Create: `tests/provision-concurrency-lock.sh`
- Modify: `bin/provision:1-25`
- Modify: `.github/workflows/integration-test.yml`

**Interfaces:**
- Produces: `provision_lock_path`, `provision_lock_acquire`, and `provision_lock_release` Bash functions.
- Consumes: optional `PROVISION_LOCK_DIR` for isolated testing; otherwise `/tmp/new-machine-bootstrap-provision-$(id -u).lock`.
- Maintains: `PROVISION_LOCK_OWNED`, true only after this process creates the lock directory.

- [ ] **Step 1: Write the failing concurrency regression**

Create `tests/provision-concurrency-lock.sh` with a temporary directory and subprocess helpers that source `bin/provision-lock`. Cover these synchronized cases without overlapping real Ansible runs:

```bash
#!/bin/bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$REPO_ROOT/bin/provision-lock"
TMP_ROOT=$(mktemp -d)
OWNER_PID=""
WAITER_PID=""
trap '[[ -n "$WAITER_PID" ]] && kill "$WAITER_PID" 2>/dev/null || true; [[ -n "$OWNER_PID" ]] && kill "$OWNER_PID" 2>/dev/null || true; rm -rf "$TMP_ROOT"' EXIT

pass_count=0
fail_count=0
pass() { printf 'PASS  %s\n' "$1"; pass_count=$((pass_count + 1)); }
fail() { printf 'FAIL  %s\n' "$1" >&2; fail_count=$((fail_count + 1)); }
wait_for_file() {
  local path=$1 attempt=0
  while [[ ! -e "$path" && $attempt -lt 100 ]]; do sleep 0.05; attempt=$((attempt + 1)); done
  [[ -e "$path" ]]
}

run_owner() {
  PROVISION_LOCK_DIR="$TMP_ROOT/lock" OWNER_READY="$TMP_ROOT/owner-ready" RELEASE_OWNER="$TMP_ROOT/release-owner" \
    bash -c 'source "$1"; trap provision_lock_release EXIT; provision_lock_acquire; touch "$OWNER_READY"; while [[ ! -e "$RELEASE_OWNER" ]]; do sleep 0.05; done' _ "$HELPER"
}
run_waiter() {
  PROVISION_LOCK_DIR="$TMP_ROOT/lock" WAITER_READY="$TMP_ROOT/waiter-ready" \
    bash -c 'source "$1"; trap provision_lock_release EXIT; provision_lock_acquire; touch "$WAITER_READY"' _ "$HELPER"
}
```

Complete the test with assertions that:

- the owner creates `owner-ready` and the lock;
- the waiter output contains `Another provision is running` while `waiter-ready` remains absent;
- releasing the owner lets the waiter create `waiter-ready` and both processes exit cleanly;
- a directory whose `owner` file contains a non-live PID is quarantined and replaced;
- terminating a waiting process leaves the owner's lock intact;
- a process exiting nonzero after acquisition removes its own lock through the `EXIT` trap;
- different working directories and `TMPDIR` values calculate the same default lock path for the same UID;
- `bin/provision` sources the helper, acquires before creating `/tmp/provision-latest.log`, and has one cleanup path that releases the lock and retains the final log-location messages.

Finish with:

```bash
printf '\n%d passed, %d failed\n' "$pass_count" "$fail_count"
[[ $fail_count -eq 0 ]]
```

Add `bash tests/provision-concurrency-lock.sh` to `.github/workflows/integration-test.yml` so `tests/ci-test-inventory.sh` recognizes the new test.

- [ ] **Step 2: Run the regression to verify it fails**

Run:

```bash
bash tests/provision-concurrency-lock.sh
```

Expected: nonzero because `bin/provision-lock` and its functions do not exist.

- [ ] **Step 3: Implement the Bash 3.2-compatible lock helper**

Create executable `bin/provision-lock` with no top-level side effects:

```bash
#!/bin/bash

PROVISION_LOCK_OWNED=false
PROVISION_LOCK_WAIT_STARTED=""

provision_lock_path() {
  printf '%s\n' "${PROVISION_LOCK_DIR:-/tmp/new-machine-bootstrap-provision-$(id -u).lock}"
}

provision_lock_process_start() {
  ps -p "$1" -o lstart= 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

provision_lock_owner_value() {
  local key=$1 lock_dir=$2
  [[ -f "$lock_dir/owner" ]] || return 1
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$lock_dir/owner"
}

provision_lock_owner_is_alive() {
  local lock_dir=$1 pid expected_start actual_start
  pid=$(provision_lock_owner_value pid "$lock_dir") || return 1
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  expected_start=$(provision_lock_owner_value process_start "$lock_dir") || return 1
  actual_start=$(provision_lock_process_start "$pid")
  [[ -n "$actual_start" && "$actual_start" == "$expected_start" ]]
}

provision_lock_write_owner() {
  local lock_dir=$1 owner_tmp="$lock_dir/owner.$$"
  {
    printf 'pid=%s\n' "$$"
    printf 'process_start=%s\n' "$(provision_lock_process_start "$$")"
    printf 'started_at=%s\n' "$(date -Iseconds)"
    printf 'working_directory=%s\n' "$PWD"
    printf 'command=%s\n' "$0 $*"
  } > "$owner_tmp"
  mv "$owner_tmp" "$lock_dir/owner"
}
```

Add acquisition logic that:

- loops on atomic `mkdir "$lock_dir"`;
- marks ownership and writes metadata immediately after success;
- prints owner PID, working directory, and command once when blocked;
- waits two seconds between attempts and reminds every 30 seconds;
- treats missing/incomplete metadata as active for a short bounded grace period;
- identifies stale metadata with both `kill -0` and `ps` start-time comparison;
- atomically renames a stale directory to `"$lock_dir.stale.$$"` before deleting the quarantine, then retries;
- reports elapsed waiting time after acquisition.

Add release logic that returns unless `PROVISION_LOCK_OWNED` is true, verifies the current owner PID is `$$` when metadata exists, removes the owned directory, and resets the ownership flag.

- [ ] **Step 4: Wire locking into `bin/provision`**

Immediately after `set -eo pipefail`, resolve and source the helper from the script directory, initialize an empty `LOGFILE_PATH`, and install a single cleanup function:

```bash
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/provision-lock"

LOGFILE_PATH=""
cleanup() {
  provision_lock_release
  if [[ -n "$LOGFILE_PATH" ]]; then
    echo ""
    echo "==> Provisioning log: $LOGFILE_PATH"
    echo "==> Or: cat /tmp/provision-latest.log"
  fi
}
trap cleanup EXIT

provision_lock_acquire "$@"
PROVISIONING_START=$(date +%s)
LOGFILE_PATH="/tmp/provision-$(date +%Y%m%d-%H%M%S).log"
```

Remove the old standalone `EXIT` trap. Keep creation of `/tmp/provision-latest.log` after lock acquisition.

- [ ] **Step 5: Run focused tests and syntax checks**

Run:

```bash
bash -n bin/provision bin/provision-lock tests/provision-concurrency-lock.sh
bash tests/provision-concurrency-lock.sh
bash tests/ci-test-inventory.sh
```

Expected: syntax checks exit 0; all concurrency assertions pass; CI inventory reports `0 failed`.

- [ ] **Step 6: Commit the lock**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Serialize concurrent provision runs" \
  bin/provision bin/provision-lock tests/provision-concurrency-lock.sh .github/workflows/integration-test.yml
```

---

### Task 2: Managed Agent Provisioning Guidance

**Files:**
- Modify: `roles/common/files/pi/AGENTS.md.d/00-base.md`
- Modify: `roles/common/files/claude/CLAUDE.md.d/00-base.md`
- Modify: `tests/provision-concurrency-lock.sh`

**Interfaces:**
- Consumes: the automatic serialization implemented by `bin/provision` in Task 1.
- Produces: the same concise provisioning coordination rule in the managed Pi and Claude base fragments.

- [ ] **Step 1: Add failing managed-guidance assertions**

Extend `tests/provision-concurrency-lock.sh` with a helper:

```bash
assert_contains() {
  local file=$1 expected=$2 description=$3
  if grep -Fq "$expected" "$file"; then pass "$description"; else fail "$description"; fi
}
```

Assert both base fragments contain this user-facing contract:

```text
Provisioning coordination: run `bin/provision` directly and rely on its built-in lock. Do not send routine provision start, completion, hold, or release messages over the agent mesh, and do not reply to informational provisioning status messages.
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run:

```bash
bash tests/provision-concurrency-lock.sh
```

Expected: lock checks pass, but both managed-guidance checks fail.

- [ ] **Step 3: Add the managed rule**

Add the exact contract line as a bullet near the existing action/verification workflow guidance in:

- `roles/common/files/pi/AGENTS.md.d/00-base.md`
- `roles/common/files/claude/CLAUDE.md.d/00-base.md`

Do not change remote-pi configuration or its installed `agent-network` skill.

- [ ] **Step 4: Run focused managed-output tests**

Run:

```bash
bash tests/provision-concurrency-lock.sh
bash tests/pi-agent-assemble-agents.sh
```

Expected: all checks pass; Pi assembly remains sorted, mode `0600`, and downstream-neutral.

- [ ] **Step 5: Commit the guidance**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Rely on provision locking for agent coordination" \
  roles/common/files/pi/AGENTS.md.d/00-base.md \
  roles/common/files/claude/CLAUDE.md.d/00-base.md \
  tests/provision-concurrency-lock.sh
```

---

### Task 3: End-to-End Verification

**Files:**
- Verify only; modify earlier files only if a regression is found.

**Interfaces:**
- Consumes: Tasks 1 and 2.
- Produces: empirical evidence that locking, managed guidance, provisioning dry-run behavior, and repository tests pass together.

- [ ] **Step 1: Run the focused suite from a clean shell**

```bash
bash -n bin/provision bin/provision-lock tests/provision-concurrency-lock.sh
bash tests/provision-concurrency-lock.sh
bash tests/pi-agent-assemble-agents.sh
bash tests/ci-test-inventory.sh
```

Expected: every command exits 0.

- [ ] **Step 2: Run the complete CI command inventory**

Run every command listed under `.github/workflows/integration-test.yml` in workflow order.

Expected: every command exits 0. If an environment-only test cannot run locally, record its exact command and error rather than claiming it passed.

- [ ] **Step 3: Exercise the real provisioning entry point**

Run:

```bash
bin/provision --check
```

Expected: the lock is acquired before the provisioning log link is created, Ansible check mode exits 0, the final log location is printed, and the lock directory no longer exists afterward.

- [ ] **Step 4: Verify repository state**

```bash
git diff --check
git status --short
git log --oneline origin/main..HEAD
```

Expected: no whitespace errors; only intentional committed changes; design, implementation plan, lock, tests, workflow wiring, and guidance commits appear.
