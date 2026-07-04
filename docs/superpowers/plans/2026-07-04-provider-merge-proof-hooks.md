# Provider Merge-Proof Hooks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `repo-end` provider-neutral by replacing built-in Forgejo proof with a phased `repo-end.d` merge-proof callback contract.

**Architecture:** `repo-end` keeps built-in Git and GitHub proof. When those fail, it runs executable `~/.local/bin/repo-end.d` callbacks with `--phase merge-proof`; successful callbacks allow cleanup, no-proof callbacks fall through, and hard failures abort cleanup. Existing callbacks continue as `--phase post-cleanup` callbacks after successful cleanup.

**Tech Stack:** Bash, Git, Ruby one-liners already used by `repo-end`, existing shell integration tests.

## Global Constraints

- NMB must not hard-code Brian's internal Forgejo hostnames or aliases.
- Keep GitHub support in NMB.
- Use behavior tests, not static greps, for safety-critical cleanup behavior.
- Work only inside `/home/brian/projects/new-machine-bootstrap/.worktrees/provider-merge-proof-hooks`.
- Commit every completed task.

---

## File Structure

- `roles/common/files/bin/repo-end`: owns cleanup sequencing, built-in proof, merge-proof callback execution, and post-cleanup callback execution.
- `tests/repo-end-callbacks.sh`: focused callback contract tests, including phase arguments and exit semantics.
- `tests/repo-lifecycle.sh`: end-to-end repo lifecycle tests; remove the built-in Forgejo proof case and keep GitHub behavior.
- `AGENTS.md`: contributor guidance that provider-specific internal forge behavior belongs in consumer repos through `repo-end.d`.

---

### Task 1: Add failing tests for phased `repo-end.d` callback behavior

**Files:**
- Modify: `tests/repo-end-callbacks.sh`

**Interfaces:**
- Consumes: existing `repo-end` CLI: `repo-end --print-path`.
- Produces: expected callback contract for Task 2:
  - callbacks receive `--phase merge-proof` before cleanup when built-in proof fails;
  - callbacks receive `--phase post-cleanup` after successful cleanup;
  - merge-proof exit `0` allows cleanup;
  - merge-proof exit `1` falls through;
  - merge-proof exit `2` aborts cleanup.

- [ ] **Step 1: Add a helper for squash-merged worktree fixtures**

Add this function after `forbid_origin_main_pushes()` in `tests/repo-end-callbacks.sh`:

```bash
create_squash_merged_worktree() {
  local name="$1"
  local branch="$2"
  local file="$3"
  local repo feature_path

  repo="$(create_repo "$name")"
  feature_path="$TMPROOT/${name}-feature"
  git -C "$repo" worktree add -q -b "$branch" "$feature_path" main
  printf '%s\n' "feature content" >"$feature_path/$file"
  git -C "$feature_path" add "$file"
  git -C "$feature_path" commit -q -m "feature work"

  git -C "$repo" checkout -q main
  printf '%s\n' "squash merged content" >"$repo/$file"
  git -C "$repo" add "$file"
  git -C "$repo" commit -q -m "squash merge feature"
  git -C "$repo" push -q origin main

  CREATED_REPO="$repo"
  CREATED_WORKTREE="$feature_path"
}
```

- [ ] **Step 2: Add test for post-cleanup phase arguments**

Update the expected ordered callback strings in the existing ordered callback case so they include `--phase post-cleanup` before `--repo-dir`:

```bash
expected_first="$(
  printf 'callback-first --phase post-cleanup --repo-dir %s --branch feature/ordered --main-branch main --main-path %s' \
    "$ordered_callbacks_repo" "$ordered_callbacks_repo"
)"
expected_second="$(
  printf 'callback-second --phase post-cleanup --repo-dir %s --branch feature/ordered --main-branch main --main-path %s' \
    "$ordered_callbacks_repo" "$ordered_callbacks_repo"
)"
```

- [ ] **Step 3: Add merge-proof fall-through/success test**

Append this case before the final success message:

```bash
merge_proof_home="$TMPROOT/merge-proof-home"
mkdir -p "$merge_proof_home/.local/bin/repo-end.d" "$merge_proof_home/.local/state"
create_squash_merged_worktree merge-proof-callbacks feature/provider-proof provider-proof.txt
merge_proof_main="$CREATED_REPO"
merge_proof_worktree="$CREATED_WORKTREE"

cat >"$merge_proof_home/.local/bin/repo-end.d/10-no-proof" <<'EOF'
#!/usr/bin/env bash
printf 'no-proof %s\n' "$*" >>"$HOME/.local/state/merge-proof.log"
case " $* " in
  *' --phase merge-proof '*) exit 1 ;;
  *' --phase post-cleanup '*) exit 0 ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$merge_proof_home/.local/bin/repo-end.d/10-no-proof"

cat >"$merge_proof_home/.local/bin/repo-end.d/20-proof" <<'EOF'
#!/usr/bin/env bash
printf 'proof %s\n' "$*" >>"$HOME/.local/state/merge-proof.log"
case " $* " in
  *' --phase merge-proof '*) printf 'Using provider callback proof\n' >&2; exit 0 ;;
  *' --phase post-cleanup '*) exit 0 ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$merge_proof_home/.local/bin/repo-end.d/20-proof"

run_case "merge-proof callback success allows cleanup" \
  "$merge_proof_worktree" \
  "$merge_proof_home" \
  "$TMPROOT/merge-proof.out" \
  "$TMPROOT/merge-proof.err"
assert_file_contains "$TMPROOT/merge-proof.err" "Using provider callback proof" \
  "merge-proof callback proof message is visible"
assert_file_contains "$merge_proof_home/.local/state/merge-proof.log" \
  "no-proof --phase merge-proof --repo-dir $merge_proof_worktree --branch feature/provider-proof --main-branch main --main-path $merge_proof_main" \
  "first merge-proof callback receives context"
assert_file_contains "$merge_proof_home/.local/state/merge-proof.log" \
  "proof --phase merge-proof --repo-dir $merge_proof_worktree --branch feature/provider-proof --main-branch main --main-path $merge_proof_main" \
  "second merge-proof callback receives context after fallthrough"
if [[ -d "$merge_proof_worktree" ]]; then
  printf 'FAIL  merge-proof callback removes worktree\nworktree remains at %s\n' "$merge_proof_worktree" >&2
  exit 1
fi
printf 'PASS  merge-proof callback removes worktree\n'
```

- [ ] **Step 4: Add merge-proof hard-failure test**

Append this case after the success test:

```bash
hard_fail_home="$TMPROOT/merge-proof-hard-fail-home"
mkdir -p "$hard_fail_home/.local/bin/repo-end.d" "$hard_fail_home/.local/state"
create_squash_merged_worktree merge-proof-hard-fail feature/provider-ambiguous provider-ambiguous.txt
hard_fail_worktree="$CREATED_WORKTREE"

cat >"$hard_fail_home/.local/bin/repo-end.d/10-hard-fail" <<'EOF'
#!/usr/bin/env bash
printf 'hard-fail %s\n' "$*" >>"$HOME/.local/state/merge-proof-hard-fail.log"
case " $* " in
  *' --phase merge-proof '*) printf 'provider proof ambiguous\n' >&2; exit 2 ;;
  *' --phase post-cleanup '*) exit 0 ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$hard_fail_home/.local/bin/repo-end.d/10-hard-fail"

run_case "merge-proof callback hard failure aborts cleanup" \
  "$hard_fail_worktree" \
  "$hard_fail_home" \
  "$TMPROOT/merge-proof-hard-fail.out" \
  "$TMPROOT/merge-proof-hard-fail.err" \
  false
assert_file_contains "$TMPROOT/merge-proof-hard-fail.err" "provider proof ambiguous" \
  "merge-proof hard failure is surfaced"
if [[ ! -d "$hard_fail_worktree" ]]; then
  printf 'FAIL  merge-proof hard failure preserves worktree\nworktree was removed\n' >&2
  exit 1
fi
printf 'PASS  merge-proof hard failure preserves worktree\n'
```

- [ ] **Step 5: Run test to verify failure**

Run: `bash tests/repo-end-callbacks.sh`

Expected: FAIL before implementation. The ordered callback assertion should still expect old arguments, or the merge-proof callback cases should fail because `repo-end` does not invoke `--phase merge-proof`.

- [ ] **Step 6: Commit failing tests**

```bash
~/.pi/agent/skills/commit/commit.sh -m "Test repo-end provider proof callbacks" tests/repo-end-callbacks.sh
```

---

### Task 2: Implement phased callbacks in `repo-end`

**Files:**
- Modify: `roles/common/files/bin/repo-end`
- Modify: `tests/repo-end-callbacks.sh` only if small expectation fixes are needed

**Interfaces:**
- Consumes: Task 1 callback expectations.
- Produces:
  - `run_repo_end_callbacks PHASE` for post-cleanup phases;
  - `run_repo_end_merge_proof_callbacks` returning success/no-proof/hard-failure according to callback exits.

- [ ] **Step 1: Change post-cleanup callback invocation**

In `run_repo_end_callbacks`, add a phase parameter and pass it to callbacks:

```bash
run_repo_end_callbacks() {
  local phase="$1"
  local callback_dir="$HOME/.local/bin/repo-end.d"
  local callback
  local callback_timeout_seconds

  [[ -d "$callback_dir" ]] || return 0

  callback_timeout_seconds="$(repo_end_callback_timeout_seconds)" || return 1
  for callback in "$callback_dir"/*; do
    [[ -f "$callback" && -x "$callback" ]] || continue
    if ! run_repo_end_callback "$callback" "$callback_timeout_seconds" "$phase"; then
      printf 'repo-end callback failed: %s\n' "$callback" >&2
      return 1
    fi
  done
}
```

Update `run_repo_end_callback` signature and command:

```bash
run_repo_end_callback() {
  local callback="$1"
  local timeout_seconds="$2"
  local phase="$3"
  local timeout_marker callback_pid watchdog_pid status

  timeout_marker="$("$(_worktree_cmd mktemp)" "${TMPDIR:-/tmp}/repo-end-callback-timeout.XXXXXX")" || return 1

  repo_end_start_background_group "$callback" \
    --phase "$phase" \
    --repo-dir "$repo_root" \
    --branch "$current_branch" \
    --main-branch "$main_branch" \
    --main-path "$main_path"
```

- [ ] **Step 2: Add merge-proof callback runner**

Add after `run_repo_end_callback()`:

```bash
run_repo_end_merge_proof_callbacks() {
  local callback_dir="$HOME/.local/bin/repo-end.d"
  local callback callback_timeout_seconds status

  [[ -d "$callback_dir" ]] || return 1
  callback_timeout_seconds="$(repo_end_callback_timeout_seconds)" || return 2

  for callback in "$callback_dir"/*; do
    [[ -f "$callback" && -x "$callback" ]] || continue
    set +e
    run_repo_end_callback "$callback" "$callback_timeout_seconds" "merge-proof"
    status=$?
    set -e
    case "$status" in
      0) return 0 ;;
      1) ;;
      *)
        printf 'repo-end merge-proof callback failed: %s\n' "$callback" >&2
        return "$status"
        ;;
    esac
  done

  return 1
}
```

- [ ] **Step 3: Route no built-in proof through provider callbacks**

Replace the no-proof block with:

```bash
merge_proof_ref="$(select_git_merge_proof_ref || true)"
if [[ -z "$merge_proof_ref" ]]; then
  if platform_merged_pr_proof; then
    merge_proof_ref="origin/$main_branch"
  else
    set +e
    run_repo_end_merge_proof_callbacks
    merge_proof_status=$?
    set -e
    if [[ "$merge_proof_status" -eq 0 ]]; then
      merge_proof_ref="origin/$main_branch"
    elif [[ "$merge_proof_status" -eq 1 ]]; then
      printf 'Error: branch %s is not merged into origin/%s; merge the PR first, then run repo-end again\n' "$current_branch" "$main_branch" >&2
      exit 1
    else
      exit "$merge_proof_status"
    fi
  fi
fi
```

- [ ] **Step 4: Update post-cleanup call sites**

Replace every `run_repo_end_callbacks` call with `run_repo_end_callbacks post-cleanup`.

- [ ] **Step 5: Run callback tests**

Run: `bash tests/repo-end-callbacks.sh`

Expected: PASS with final line `repo-end callback behavior checks complete`.

- [ ] **Step 6: Run lifecycle tests**

Run: `bash tests/repo-lifecycle.sh`

Expected: may still PASS before Forgejo removal; note any failures caused by phase argument changes and fix them without weakening safety semantics.

- [ ] **Step 7: Commit implementation**

```bash
~/.pi/agent/skills/commit/commit.sh -m "Add provider proof callbacks to repo-end" roles/common/files/bin/repo-end tests/repo-end-callbacks.sh
```

---

### Task 3: Remove built-in Forgejo proof from NMB

**Files:**
- Modify: `roles/common/files/bin/repo-end`
- Modify: `tests/repo-lifecycle.sh`

**Interfaces:**
- Consumes: Task 2 `run_repo_end_merge_proof_callbacks`.
- Produces: NMB without Forgejo host/API assumptions.

- [ ] **Step 1: Remove Forgejo helpers from `repo-end`**

Delete these functions entirely:

```bash
forgejo_repo_parts() { ... }
forgejo_base_url() { ... }
forgejo_merged_pr_proof() { ... }
```

Change `platform_merged_pr_proof` to:

```bash
platform_merged_pr_proof() {
  github_merged_pr_proof
}
```

- [ ] **Step 2: Remove Forgejo lifecycle fixture**

Delete the `# --- repo-end worktree mode: deleted remote branch uses merged Forgejo PR proof ---` block from `tests/repo-lifecycle.sh`.

- [ ] **Step 3: Run lifecycle and callback tests**

Run:

```bash
bash tests/repo-lifecycle.sh
bash tests/repo-end-callbacks.sh
```

Expected: both PASS.

- [ ] **Step 4: Commit Forgejo removal**

```bash
~/.pi/agent/skills/commit/commit.sh -m "Remove Forgejo proof from repo-end" roles/common/files/bin/repo-end tests/repo-lifecycle.sh
```

---

### Task 4: Update NMB guidance and verification

**Files:**
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: final hook contract from Tasks 2-3.
- Produces: repo guidance telling future agents where provider-specific behavior belongs.

- [ ] **Step 1: Add guidance section**

Add this section near the repository architecture or agent behavior guidance in `AGENTS.md`:

```markdown
## Repo Lifecycle Provider Hooks

NMB owns generic `repo-start`/`repo-end` lifecycle helpers. Provider-specific internal forge behavior does not belong in this repo. If a consuming environment needs extra merge proof for a private Git provider, install an executable callback from that consuming repo under `~/.local/bin/repo-end.d`.

`repo-end` calls callbacks with `--phase merge-proof` before cleanup only when built-in proof fails. Exit `0` means the callback proved the branch was merged, exit `1` means no proof and lets `repo-end` try the next callback, and exit `2+` aborts cleanup. After successful cleanup, callbacks run with `--phase post-cleanup` for notification or sweep behavior.
```

- [ ] **Step 2: Run targeted tests**

Run:

```bash
bash tests/repo-lifecycle.sh
bash tests/repo-end-callbacks.sh
bash tests/ci-test-inventory.sh
```

Expected: all PASS.

- [ ] **Step 3: Commit guidance**

```bash
~/.pi/agent/skills/commit/commit.sh -m "Document repo-end provider hooks" AGENTS.md
```
