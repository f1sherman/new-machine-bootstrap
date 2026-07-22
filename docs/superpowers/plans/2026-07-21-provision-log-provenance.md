# Provision Log Provenance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record source provenance in every provisioning log and tell managed agents how to inspect that history when they decide it is useful.

**Architecture:** `bin/provision` will write a compact, non-fatal provenance header before prerequisite checks and Ansible execution. A configurable log directory keeps behavioral tests isolated while retaining `/tmp` as the production default. Managed Pi and Claude fragments will describe how to find and interpret logs without prescribing inspection triggers.

**Tech Stack:** Bash 3.2, Git CLI, Ansible entrypoint stubs, shell integration tests, Ansible-managed Markdown fragments.

## Global Constraints

- Remain compatible with stock macOS Bash 3.2 and Debian Bash.
- Git provenance lookup failures must not prevent provisioning.
- Do not weaken or delay acquisition of the existing provision lock.
- Keep agent-mesh behavior unchanged.
- Leave the decision to inspect provisioning history to the agent.
- Tests must verify behavior rather than exact managed-guidance prose.

---

### Task 1: Add Provision Log Provenance

**Files:**
- Modify: `bin/provision`
- Create: `tests/provision-log-provenance.sh`
- Modify: `.github/workflows/integration-test.yml`

**Interfaces:**
- Consumes: existing `bin/provision`, `PROVISION_LOCK_DIR`, Git CLI, and the `ansible-playbook` command.
- Produces: `provision_log_dir`, `provision_source_context`, and `log_provision_context` shell functions; optional `PROVISION_LOG_DIR` override; provenance lines in every provision log.

- [ ] **Step 1: Write the failing integration test**

Create `tests/provision-log-provenance.sh`. The test must create an isolated fake command directory containing:

```bash
#!/bin/bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_ROOT=$(mktemp -d)
cleanup() { rm -rf "$TMP_ROOT"; }
trap cleanup EXIT
mkdir -p "$TMP_ROOT/bin" "$TMP_ROOT/home" "$TMP_ROOT/logs" "$TMP_ROOT/state"

cat > "$TMP_ROOT/bin/ansible-playbook" <<'EOF'
#!/bin/bash
printf 'PLAY RECAP *********************************************************************\n'
printf 'localhost                  : ok=1 changed=0 unreachable=0 failed=0 skipped=0 rescued=0 ignored=0\n'
EOF
cat > "$TMP_ROOT/bin/brew" <<EOF
#!/bin/bash
[[ "\${1:-}" == --prefix ]] && printf '%s\n' '$TMP_ROOT/homebrew'
EOF
cat > "$TMP_ROOT/bin/dscl" <<EOF
#!/bin/bash
printf 'UserShell: %s\n' '$TMP_ROOT/homebrew/bin/zsh'
EOF
cat > "$TMP_ROOT/bin/say" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$TMP_ROOT/bin/"*

expected_root=$(cd "$REPO_ROOT" && pwd -P)
expected_branch=$(git -C "$REPO_ROOT" symbolic-ref --short -q HEAD || printf 'detached')
expected_commit=$(git -C "$REPO_ROOT" rev-parse HEAD)
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=normal)" ]]; then
  expected_state=dirty
else
  expected_state=clean
fi

(
  cd "$REPO_ROOT"
  PATH="$TMP_ROOT/bin:$PATH" \
  HOME="$TMP_ROOT/home" \
  XDG_STATE_HOME="$TMP_ROOT/state" \
  PROVISION_LOG_DIR="$TMP_ROOT/logs" \
  PROVISION_LOCK_DIR="$TMP_ROOT/lock" \
  bin/provision --check
) > "$TMP_ROOT/output" 2>&1

log_path=$(readlink "$TMP_ROOT/logs/provision-latest.log")
[[ -f "$log_path" ]]
grep -Fq "Provision source worktree: $expected_root" "$log_path"
grep -Fq "Provision source branch: $expected_branch" "$log_path"
grep -Fq "Provision source commit: $expected_commit" "$log_path"
grep -Fq "Provision source repository state: $expected_state" "$log_path"
grep -Fq 'Provision invocation arguments: --check' "$log_path"
grep -Eq 'Provision started at: [0-9]{4}-[0-9]{2}-[0-9]{2}T' "$log_path"
grep -Fq 'localhost                  : ok=1 changed=0 unreachable=0 failed=0' "$log_path"
printf 'PASS  provision log records source provenance and Ansible result\n'
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
bash tests/provision-log-provenance.sh
```

Expected: FAIL because `PROVISION_LOG_DIR` is ignored and the isolated latest-log symlink does not exist.

- [ ] **Step 3: Implement isolated log paths and provenance logging**

In `bin/provision`, preserve lock acquisition before log publication, then replace hard-coded log creation with:

```bash
provision_log_dir() {
  printf '%s\n' "${PROVISION_LOG_DIR:-/tmp}"
}

PROVISION_LOG_DIR_PATH=$(provision_log_dir)
mkdir -p "$PROVISION_LOG_DIR_PATH"
LOGFILE_PATH="$PROVISION_LOG_DIR_PATH/provision-$(date +%Y%m%d-%H%M%S).log"
ln -sf "$LOGFILE_PATH" "$PROVISION_LOG_DIR_PATH/provision-latest.log"
```

Update cleanup and startup messages to print `$PROVISION_LOG_DIR_PATH/provision-latest.log` instead of a hard-coded `/tmp/provision-latest.log`.

After `log_info` and `log_error`, add Bash 3.2-compatible helpers:

```bash
provision_source_context() {
  local source_root branch commit repository_state
  source_root=$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -z "$source_root" ]]; then
    printf '%s\n' 'unknown' 'unknown' 'unknown' 'unknown'
    return 0
  fi
  source_root=$(cd "$source_root" 2>/dev/null && pwd -P || printf 'unknown')
  branch=$(git -C "$source_root" symbolic-ref --short -q HEAD 2>/dev/null || printf 'detached')
  commit=$(git -C "$source_root" rev-parse HEAD 2>/dev/null || printf 'unknown')
  if git -C "$source_root" status --porcelain --untracked-files=normal >/dev/null 2>&1; then
    if [[ -n "$(git -C "$source_root" status --porcelain --untracked-files=normal 2>/dev/null)" ]]; then
      repository_state=dirty
    else
      repository_state=clean
    fi
  else
    repository_state=unknown
  fi
  printf '%s\n' "$source_root" "$branch" "$commit" "$repository_state"
}

log_provision_context() {
  local context source_root branch commit repository_state invocation_arguments
  context=$(provision_source_context)
  source_root=$(printf '%s\n' "$context" | sed -n '1p')
  branch=$(printf '%s\n' "$context" | sed -n '2p')
  commit=$(printf '%s\n' "$context" | sed -n '3p')
  repository_state=$(printf '%s\n' "$context" | sed -n '4p')
  invocation_arguments="$*"
  [[ -n "$invocation_arguments" ]] || invocation_arguments='(none)'
  log_info "Provision started at: $(timestamp)"
  log_info "Provision source worktree: $source_root"
  log_info "Provision source branch: $branch"
  log_info "Provision source commit: $commit"
  log_info "Provision source repository state: $repository_state"
  log_info "Provision invocation arguments: $invocation_arguments"
}

log_provision_context "$@"
```

Keep these lookups non-fatal under `set -e`. Do not move `provision_lock_acquire` later.

- [ ] **Step 4: Run targeted verification**

Run:

```bash
bash -n bin/provision tests/provision-log-provenance.sh
bash tests/provision-log-provenance.sh
bash tests/provision-concurrency-lock.sh
```

Expected: syntax passes; provenance integration test passes; concurrency suite passes.

- [ ] **Step 5: Add the test to CI and verify inventory**

Add this command alongside the other shell integration tests in `.github/workflows/integration-test.yml`:

```yaml
      - name: Test provision log provenance
        run: bash tests/provision-log-provenance.sh
```

Run:

```bash
bash tests/ci-test-inventory.sh
git diff --check
```

Expected: all tracked test-like files are referenced by CI; no whitespace errors.

- [ ] **Step 6: Commit**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Record provision source provenance" \
  bin/provision tests/provision-log-provenance.sh .github/workflows/integration-test.yml
```

### Task 2: Teach Managed Agents to Inspect Provisioning History

**Files:**
- Modify: `roles/common/files/pi/AGENTS.md.d/00-base.md`
- Modify: `roles/common/files/claude/CLAUDE.md.d/00-base.md`

**Interfaces:**
- Consumes: provenance fields and default `/tmp/provision-*.log` location from Task 1.
- Produces: matching Pi and Claude instructions for voluntary provisioning-history inspection.

- [ ] **Step 1: Add concise matching guidance**

Append this paragraph to both managed base fragments near the existing provisioning-coordination rule:

```markdown
Provisioning history: when useful, inspect `/tmp/provision-*.log`; `ls -t /tmp/provision-*.log` lists runs newest first. Each log records its source worktree, branch, commit, repository state, invocation arguments, changed-task output, and completion status. Compare that provenance with your current worktree before deciding whether deployed state may have affected your work. Do not assume unexpected deployed state is a source-code regression.
```

Do not add a mandatory inspection trigger, receipt flow, confirmation command, or mesh message.

- [ ] **Step 2: Verify managed fragment assembly and repository policy**

Run:

```bash
bash tests/pi-agent-assemble-agents.sh
bash tests/ci-test-inventory.sh
git diff --check
```

Expected: Pi assembly and CI inventory pass; no exact guidance-prose test is added; no whitespace errors.

- [ ] **Step 3: Commit**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Document provision history inspection" \
  roles/common/files/pi/AGENTS.md.d/00-base.md \
  roles/common/files/claude/CLAUDE.md.d/00-base.md
```

### Task 3: End-to-End Verification and Deployment

**Files:**
- No new source files.
- Provisioned outputs are generated from repository-managed sources and are not edited directly.

**Interfaces:**
- Consumes: Tasks 1 and 2.
- Produces: verified branch and deployed managed guidance.

- [ ] **Step 1: Run focused verification from committed HEAD**

```bash
bash -n bin/provision bin/provision-lock tests/provision-concurrency-lock.sh tests/provision-log-provenance.sh
bash tests/provision-log-provenance.sh
bash tests/provision-concurrency-lock.sh
bash tests/pi-agent-assemble-agents.sh
bash tests/ci-test-inventory.sh
git diff --check
git status --short
```

Expected: every command succeeds and the worktree is clean.

- [ ] **Step 2: Apply the managed configuration**

Run:

```bash
bin/provision
```

Expected: Ansible exits successfully, the generated log begins with correct worktree provenance, the managed Pi and Claude base fragments are deployed, and the canonical provision lock is absent afterward.

- [ ] **Step 3: Confirm deployed behavior**

Inspect the generated log and deployed assembled guidance without editing deployed files:

```bash
log_path=$(readlink /tmp/provision-latest.log)
grep -F 'Provision source worktree:' "$log_path"
grep -F 'Provision source branch:' "$log_path"
grep -F 'Provision source commit:' "$log_path"
grep -F 'Provision source repository state:' "$log_path"
grep -F 'Provisioning history:' ~/.pi/agent/AGENTS.md ~/.claude/CLAUDE.md.d/00-base.md
lock_path=$(bash -c 'source bin/provision-lock; provision_lock_path')
test ! -e "$lock_path"
```

Expected: provenance and guidance are present, and the lock was cleaned up.

- [ ] **Step 4: Push the updated branch and refresh PR #345**

Follow the existing PR update workflow: push `HEAD`, verify the remote head SHA matches local `HEAD`, update the PR description for provenance logging and managed guidance, check CI status, reply to relevant review threads if needed, and rearm the Pi PR monitor.
