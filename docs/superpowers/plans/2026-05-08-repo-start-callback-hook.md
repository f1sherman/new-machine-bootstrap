# `repo-start.d` Callback Hook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `~/.local/bin/repo-start.d/*` callback hook to `repo-start`, mirroring the existing `repo-end.d` mechanism in `repo-end`.

**Architecture:** Add `run_repo_start_callbacks` to `roles/common/files/bin/repo-start`, invoked near the end of `main` (after tmux state publish, before final path output). Strict semantics: non-zero callback → non-zero `repo-start`. New `tests/repo-start-callbacks.sh` mirrors `tests/repo-end-callbacks.sh`. CI workflow gets a new step.

**Tech Stack:** Bash 3.2+, git, the existing `repo-lib.sh` helpers.

**Reference files:**
- Existing implementation to mirror: `roles/common/files/bin/repo-end:36-53,221-224`
- Existing test to mirror: `tests/repo-end-callbacks.sh`
- CI workflow to extend: `.github/workflows/integration-test.yml:30-31`

---

### Task 1: Write the failing callback test (Red)

**Files:**
- Create: `tests/repo-start-callbacks.sh`

The test mirrors `tests/repo-end-callbacks.sh` in structure (helper functions to spin up a fresh git repo with an origin, run the command in a temp `HOME`, assert log contents and stdout/stderr split). Each test case follows the same pattern as `repo-end-callbacks.sh`.

- [ ] **Step 1: Create the test file**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_START_SCRIPT="$(cd "$SCRIPT_DIR/../roles/common/files/bin" && pwd)/repo-start"

if [ ! -x "$REPO_START_SCRIPT" ]; then
  printf 'ERROR: %s is not executable (or does not exist)\n' "$REPO_START_SCRIPT" >&2
  exit 2
fi

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

export GIT_AUTHOR_NAME=test
export GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test
export GIT_COMMITTER_EMAIL=test@example.com

create_repo() {
  local name="$1"
  local origin="$TMPROOT/${name}-origin.git"
  local repo="$TMPROOT/${name}-repo"

  git init -q --bare "$origin"
  git init -qb main "$repo"
  git -C "$repo" remote add origin "$origin"
  git -C "$repo" commit -q --allow-empty -m init
  git -C "$repo" push -q -u origin main
  realpath "$repo"
}

run_case() {
  local name="$1" repo="$2" home_dir="$3" out="$4" err="$5" expect_success="${6:-true}"

  if (
    cd "$repo" &&
    HOME="$home_dir" "$REPO_START_SCRIPT" \
      --no-worktrees --ephemeral feature/cb \
      --print-path >"$out" 2>"$err"
  ); then
    if [[ "$expect_success" == "false" ]]; then
      printf 'FAIL  %s\nexpected repo-start to fail\n' "$name" >&2
      return 1
    fi
  else
    if [[ "$expect_success" == "true" ]]; then
      printf 'FAIL  %s\nrepo-start failed unexpectedly\nstderr: %s\n' "$name" "$(cat "$err")" >&2
      return 1
    fi
  fi
  printf 'PASS  %s\n' "$name"
}

assert_file_contains() {
  local path="$1" needle="$2" name="$3"
  local content
  content="$(cat "$path")"
  if [[ "$content" != *"$needle"* ]]; then
    printf 'FAIL  %s\nmissing %q in %s\n' "$name" "$needle" "$path" >&2
    return 1
  fi
  printf 'PASS  %s\n' "$name"
}

assert_file_equals() {
  local path="$1" expected="$2" name="$3"
  local content
  content="$(cat "$path")"
  if [[ "$content" != "$expected" ]]; then
    printf 'FAIL  %s\nexpected:\n%s\ngot:\n%s\n' "$name" "$expected" "$content" >&2
    return 1
  fi
  printf 'PASS  %s\n' "$name"
}

assert_ordered_output() {
  local log="$1" name="$2" first="$3" second="$4"
  local first_line second_line
  first_line="$(sed -n '1p' "$log")"
  second_line="$(sed -n '2p' "$log")"
  if [[ "$first_line" != "$first" || "$second_line" != "$second" ]]; then
    printf 'FAIL  %s\nexpected:\n%s\n%s\ngot:\n%s\n%s\n' \
      "$name" "$first" "$second" "$first_line" "$second_line" >&2
    return 1
  fi
  printf 'PASS  %s\n' "$name"
}

# Case 1: no callback dir is a successful no-op
no_callbacks_repo="$(create_repo no-callbacks)"
tmp_home_no_callbacks="$TMPROOT/no-callback-home"
mkdir -p "$tmp_home_no_callbacks"
run_case "no hooks is a successful no-op" \
  "$no_callbacks_repo" "$tmp_home_no_callbacks" \
  "$TMPROOT/no-callbacks.out" "$TMPROOT/no-callbacks.err"

# Case 2: ordered execution with expected args
ordered_repo="$(create_repo ordered)"
tmp_home_ordered="$TMPROOT/ordered-callback-home"
callback_dir="$tmp_home_ordered/.local/bin/repo-start.d"
mkdir -p "$callback_dir"
ordered_log="$tmp_home_ordered/.local/state/repo-start-callback-args.log"
mkdir -p "$(dirname "$ordered_log")"

cat >"$callback_dir/20-second.sh" <<'EOF'
#!/usr/bin/env bash
printf 'callback-second %s\n' "$*" >> "$HOME/.local/state/repo-start-callback-args.log"
EOF
chmod +x "$callback_dir/20-second.sh"

cat >"$callback_dir/10-first.sh" <<'EOF'
#!/usr/bin/env bash
printf 'callback-first %s\n' "$*" >> "$HOME/.local/state/repo-start-callback-args.log"
EOF
chmod +x "$callback_dir/10-first.sh"

run_case "ordered callbacks run lexicographically" \
  "$ordered_repo" "$tmp_home_ordered" \
  "$TMPROOT/ordered.out" "$TMPROOT/ordered.err"

expected_first="callback-first --repo-dir $ordered_repo --branch feature/cb --main-branch main --status created"
expected_second="callback-second --repo-dir $ordered_repo --branch feature/cb --main-branch main --status created"
assert_ordered_output "$ordered_log" \
  "ordered callbacks are lexicographically sorted" \
  "$expected_first" "$expected_second"

# Case 3: callback stdout is redirected in print-path mode
stdout_repo="$(create_repo stdout-callback)"
tmp_home_stdout="$TMPROOT/stdout-callback-home"
stdout_dir="$tmp_home_stdout/.local/bin/repo-start.d"
mkdir -p "$stdout_dir"
cat >"$stdout_dir/10-progress.sh" <<'EOF'
#!/usr/bin/env bash
printf 'callback progress\n'
EOF
chmod +x "$stdout_dir/10-progress.sh"

run_case "callback stdout is redirected in print-path mode" \
  "$stdout_repo" "$tmp_home_stdout" \
  "$TMPROOT/stdout.out" "$TMPROOT/stdout.err"

assert_file_equals "$TMPROOT/stdout.out" "$stdout_repo" \
  "print-path stdout contains only the final path"
assert_file_contains "$TMPROOT/stdout.err" "callback progress" \
  "callback progress is still visible on stderr"

# Case 4: failing callback fails repo-start
fail_repo="$(create_repo callback-fails)"
tmp_home_fail="$TMPROOT/fail-callback-home"
fail_dir="$tmp_home_fail/.local/bin/repo-start.d"
mkdir -p "$fail_dir"
fail_log="$tmp_home_fail/.local/state/repo-start-fail-callback.log"
mkdir -p "$(dirname "$fail_log")"
cat >"$fail_dir/10-fail.sh" <<'EOF'
#!/usr/bin/env bash
printf 'callback-failed %s\n' "$*" >> "$HOME/.local/state/repo-start-fail-callback.log"
exit 3
EOF
chmod +x "$fail_dir/10-fail.sh"

run_case "callback failure makes repo-start fail" \
  "$fail_repo" "$tmp_home_fail" \
  "$TMPROOT/fail.out" "$TMPROOT/fail.err" \
  false

assert_file_contains "$tmp_home_fail/.local/state/repo-start-fail-callback.log" \
  "callback-failed --repo-dir $fail_repo --branch feature/cb --main-branch main --status created" \
  "failing callback receives expected args"
assert_file_contains "$TMPROOT/fail.err" "repo-start callback failed" \
  "callback failure is surfaced"

printf 'repo-start callback behavior checks complete\n'
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x tests/repo-start-callbacks.sh
```

- [ ] **Step 3: Run it to verify it fails**

Run: `bash tests/repo-start-callbacks.sh`
Expected: FAIL — Case 2 fails because no callbacks run (no `repo-start.d` mechanism yet).

- [ ] **Step 4: Commit**

```bash
git add tests/repo-start-callbacks.sh
git commit -m "test: add failing repo-start callback hook tests"
```

---

### Task 2: Implement the callback hook (Green)

**Files:**
- Modify: `roles/common/files/bin/repo-start`

Add `run_repo_start_callbacks` modeled after `run_repo_end_callbacks` in `roles/common/files/bin/repo-end:36-53`. Call it near the end of `main`, after tmux state publish and before the final `printf '%s\n' "$path"`. Redirect callback stdout to stderr in `--print-path` and `--json` modes so the machine-readable output stays clean.

- [ ] **Step 1: Add the callback runner function**

Insert this function near the top of `roles/common/files/bin/repo-start`, after the `source "$SCRIPT_DIR/repo-lib.sh"` line:

```bash
run_repo_start_callbacks() {
  local callback_dir="$HOME/.local/bin/repo-start.d"
  local callback
  local repo_dir="$1"
  local branch="$2"
  local main_branch="$3"
  local status="$4"

  [[ -d "$callback_dir" ]] || return 0

  for callback in "$callback_dir"/*; do
    [[ -f "$callback" && -x "$callback" ]] || continue
    if ! "$callback" \
      --repo-dir "$repo_dir" \
      --branch "$branch" \
      --main-branch "$main_branch" \
      --status "$status"; then
      printf 'repo-start callback failed: %s\n' "$callback" >&2
      return 1
    fi
  done
}
```

- [ ] **Step 2: Resolve `main_branch` inside `main`**

Just before `_worktree_publish_tmux_state` near line 306, add:

```bash
  local main_branch
  main_branch="$(_worktree_main_branch)"
```

- [ ] **Step 3: Invoke the callback runner before final output**

Replace the final stdout block (currently `if [[ "$json_output" == "true" ]]; ... printf '%s\n' "$path"` near lines 314–328) with logic that runs callbacks first, redirecting their stdout to stderr in print-path / JSON modes:

```bash
  if [[ "$json_output" == "true" || "$print_path" == "true" ]]; then
    run_repo_start_callbacks "$path" "$branch" "$main_branch" "$status" >&2 || return 1
  else
    run_repo_start_callbacks "$path" "$branch" "$main_branch" "$status" || return 1
  fi

  if [[ "$json_output" == "true" ]]; then
    jq -nc \
      --arg status "$status" \
      --arg mode "$mode" \
      --arg branch "$branch" \
      --arg path "$path" \
      --argjson repaired "$repaired" \
      '{status:$status, mode:$mode, branch:$branch, path:$path, repaired:$repaired}'
    return 0
  fi

  if [[ "$print_path" == "true" ]]; then
    :
  fi
  printf '%s\n' "$path"
```

(The existing `if [[ "$print_path" == "true" ]]; then :; fi` is intentional in the current file — preserve it.)

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/repo-start-callbacks.sh`
Expected: All four cases PASS, ending with `repo-start callback behavior checks complete`.

- [ ] **Step 5: Run existing repo-lifecycle tests for regressions**

Run: `bash tests/repo-lifecycle.sh && bash tests/repo-end-callbacks.sh`
Expected: PASS in both — the change should not break existing repo-start use sites or the repo-end callback contract.

- [ ] **Step 6: Commit**

```bash
git add roles/common/files/bin/repo-start
git commit -m "feat: add repo-start.d callback hook"
```

---

### Task 3: Wire the new test into CI

**Files:**
- Modify: `.github/workflows/integration-test.yml`

`tests/ci-test-inventory.sh` asserts every tracked test file is referenced by some workflow step. Without this addition that test fails.

- [ ] **Step 1: Add the workflow step**

In `.github/workflows/integration-test.yml`, after the existing "Verify repo-end callback behavior" step (line 30–31), add:

```yaml
      - name: Verify repo-start callback behavior
        run: bash tests/repo-start-callbacks.sh
```

- [ ] **Step 2: Verify the inventory test passes**

Run: `bash tests/ci-test-inventory.sh`
Expected: `1 passed, 0 failed`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/integration-test.yml
git commit -m "ci: run repo-start callback test in integration workflow"
```

---

### Task 4: Open the PR

- [ ] **Step 1: Push**

```bash
git push -u origin repo-start-callback-hook
```

- [ ] **Step 2: Open draft PR**

Title: `feat: add repo-start.d callback hook`

Body — copy from spec summary, three bullets:

```
## Summary

- Adds `~/.local/bin/repo-start.d/*` callback mechanism mirroring the existing
  `repo-end.d` hook in `repo-end`.
- Each callback runs after `repo-start` finishes its core work and receives
  `--repo-dir`, `--branch`, `--main-branch`, `--status`.
- Strict failure semantics match `repo-end.d`: non-zero callback fails
  `repo-start`. Stdout from callbacks is redirected to stderr in
  `--print-path` / `--json` modes.

## Test plan

- [x] `bash tests/repo-start-callbacks.sh` passes locally
- [x] `bash tests/repo-end-callbacks.sh` still passes (no regressions)
- [x] `bash tests/repo-lifecycle.sh` still passes
- [x] `bash tests/ci-test-inventory.sh` passes (workflow references the new test)
```

Use the standard PR-creation tooling for this repo (e.g., `gh pr create --draft` or the `_pull-request` skill if available).

---

## Self-Review

### Spec coverage
- Behavior: callback args ✓ Task 2 step 1; lexical order ✓ Task 1 case 2; print-path stdout-redirect ✓ Task 2 step 3 + Task 1 case 3; non-zero callback fails ✓ Task 2 step 1 + Task 1 case 4; missing dir is no-op ✓ Task 2 step 1 (`[[ -d ]] || return 0`) + Task 1 case 1.
- Architecture: function placement ✓ Task 2 step 1; invocation point ✓ Task 2 step 3.
- Testing: mirror of `repo-end-callbacks.sh` ✓ Task 1.
- CI wiring: ✓ Task 3.

### Placeholders
None.

### Type / signature consistency
`run_repo_start_callbacks` arity matches its invocations in Task 2 step 3 (4 positional args: `repo_dir`, `branch`, `main_branch`, `status`). Args passed to callbacks (`--repo-dir`, `--branch`, `--main-branch`, `--status`) match what the test asserts in Task 1 cases 2 and 4.
