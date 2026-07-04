# repo-end Merged PR Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Teach `repo-end` to clean up squash-merged or remotely-updated PR branches only after local proof, remote-branch proof, or strict merged-PR API proof succeeds.

**Architecture:** Extend `roles/common/files/bin/repo-end` in place. Keep the existing Git proof logic as the primary path, add remote branch reconciliation as a second proof path, and add a platform API fallback only when Git proof cannot establish the branch is merged. Cover the behavior in `tests/repo-lifecycle.sh` with fake platform CLIs/HTTP helpers so CI does not depend on real network services.

**Tech Stack:** Bash, Git, `gh`/Forgejo API via curl when available, existing shell integration tests.

## Global Constraints

- Existing CLI remains `repo-end [--print-path]`.
- Current worktree clean, main checkout clean, and successful `git fetch --prune origin` remain required before cleanup.
- Existing local Git proof must run before remote branch reconciliation.
- Remote branch reconciliation must run before platform API lookup.
- Missing `origin/<current_branch>` is non-fatal and may fall through to API lookup.
- Diverged local/remote feature branches are a hard stop.
- API fallback accepts cleanup only for exactly one merged PR whose head branch matches the current branch and whose base matches the main branch.
- No API lookup may occur when local or remote-branch Git proof succeeds.

---

## File Structure

- Modify `roles/common/files/bin/repo-end`: add proof-source selection helpers, remote-branch reconciliation, platform detection, GitHub/Forgejo merged PR lookup, and route cleanup through the selected proof ref.
- Modify `tests/repo-lifecycle.sh`: add regression fixtures for remote proof, API fallback success, API ambiguity/refusal cases, and no-API-on-Git-proof behavior.

---

### Task 1: Add remote-branch proof selection before API fallback

**Files:**
- Modify: `roles/common/files/bin/repo-end`
- Modify: `tests/repo-lifecycle.sh`

**Interfaces:**
- Consumes: existing `already_merged(work_dir, ref)` function.
- Produces: new `select_merge_proof_ref()` function that prints a ref (`HEAD` or `refs/remotes/origin/<branch>`) and returns success, or returns nonzero with a clear error when no Git proof succeeds.

- [ ] **Step 1: Add failing test for stale local branch with merged remote branch**

Add a test case near the existing `repo-end worktree mode` merged/unmerged cases in `tests/repo-lifecycle.sh`:

```bash
# --- repo-end worktree mode: stale local branch uses remote branch proof ---
remote_proof_repo="$(create_repo end-worktree-remote-proof)"
remote_proof_origin="$CREATED_ORIGIN"
remote_proof_main="$CREATED_REPO"
remote_proof_feature="$TMPROOT/end-worktree-remote-proof-feature"
git -C "$remote_proof_main" worktree add -q -b feature/remote-proof "$remote_proof_feature" main
printf 'local stale content\n' >"$remote_proof_feature/remote-proof.txt"
git -C "$remote_proof_feature" add remote-proof.txt
git -C "$remote_proof_feature" commit -q -m "local stale feature commit"
git -C "$remote_proof_feature" push -q -u origin feature/remote-proof
# Simulate another worker updating the PR branch and merging that final state.
remote_proof_peer="$TMPROOT/end-worktree-remote-proof-peer"
git clone -q "$remote_proof_origin" "$remote_proof_peer"
git -C "$remote_proof_peer" checkout -q feature/remote-proof
printf 'remote final content\n' >"$remote_proof_peer/remote-proof.txt"
git -C "$remote_proof_peer" add remote-proof.txt
git -C "$remote_proof_peer" commit -q -m "remote final feature commit"
git -C "$remote_proof_peer" push -q origin feature/remote-proof
git -C "$remote_proof_peer" checkout -q main
git -C "$remote_proof_peer" merge -q --ff-only feature/remote-proof
git -C "$remote_proof_peer" push -q origin main
remote_proof_home="$TMPROOT/end-worktree-remote-proof-home"
mkdir -p "$remote_proof_home"
HOME="$remote_proof_home" \
  PATH="$BIN_DIR:$PATH" \
  GIT_CONFIG_GLOBAL=/dev/null \
  "$REPO_END_SCRIPT" --print-path \
  >"$TMPROOT/end-worktree-remote-proof.out" \
  2>"$TMPROOT/end-worktree-remote-proof.err"
assert_file_contains "$TMPROOT/end-worktree-remote-proof.out" "$remote_proof_main" "repo-end remote proof prints main path"
assert_file_contains "$TMPROOT/end-worktree-remote-proof.err" "Using origin/feature/remote-proof as merge proof" "repo-end announces remote branch proof"
if [[ -d "$remote_proof_feature" ]]; then
  fail_case "repo-end remote proof removes linked worktree" "worktree remains at $remote_proof_feature"
fi
pass_case "repo-end remote proof removes linked worktree"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/repo-lifecycle.sh`

Expected: fails because `repo-end` rejects the stale local branch before trying `origin/feature/remote-proof`.

- [ ] **Step 3: Implement remote proof selection**

In `roles/common/files/bin/repo-end`, add these helpers after `prune_merged_local_branches()` or before the main non-main cleanup block:

```bash
remote_branch_ref() {
  printf 'refs/remotes/origin/%s\n' "$current_branch"
}

remote_branch_exists() {
  "$(_worktree_cmd git)" -C "$repo_root" show-ref --verify --quiet "$(remote_branch_ref)"
}

local_branch_is_ancestor_of_remote() {
  "$(_worktree_cmd git)" -C "$repo_root" merge-base --is-ancestor HEAD "$(remote_branch_ref)"
}

remote_branch_is_ancestor_of_local() {
  "$(_worktree_cmd git)" -C "$repo_root" merge-base --is-ancestor "$(remote_branch_ref)" HEAD
}

select_git_merge_proof_ref() {
  if already_merged "$repo_root" HEAD; then
    printf 'HEAD\n'
    return 0
  fi

  if ! remote_branch_exists; then
    return 1
  fi

  if local_branch_is_ancestor_of_remote; then
    if already_merged "$repo_root" "$(remote_branch_ref)"; then
      printf 'Using origin/%s as merge proof\n' "$current_branch" >&2
      remote_branch_ref
      return 0
    fi
    return 1
  fi

  if ! remote_branch_is_ancestor_of_local; then
    printf 'Error: local branch %s diverged from origin/%s; resolve manually before re-running repo-end\n' "$current_branch" "$current_branch" >&2
    exit 1
  fi

  return 1
}
```

Then replace the current non-main check:

```bash
if ! already_merged; then
  printf 'Error: branch %s is not merged into origin/%s; merge the PR first, then run repo-end again\n' "$current_branch" "$main_branch" >&2
  exit 1
fi
```

with:

```bash
merge_proof_ref="$(select_git_merge_proof_ref || true)"
if [[ -z "$merge_proof_ref" ]]; then
  printf 'Error: branch %s is not merged into origin/%s; merge the PR first, then run repo-end again\n' "$current_branch" "$main_branch" >&2
  exit 1
fi
```

- [ ] **Step 4: Run test to verify remote proof passes**

Run: `bash tests/repo-lifecycle.sh`

Expected: all existing repo lifecycle checks pass, including the new remote proof case.

- [ ] **Step 5: Commit Task 1**

Run:

```bash
~/.pi/agent/skills/commit/commit.sh -m "Use remote branch proof in repo-end" roles/common/files/bin/repo-end tests/repo-lifecycle.sh
```

---

### Task 2: Add strict platform API fallback after Git proof fails

**Files:**
- Modify: `roles/common/files/bin/repo-end`
- Modify: `tests/repo-lifecycle.sh`

**Interfaces:**
- Consumes: `select_git_merge_proof_ref()` from Task 1.
- Produces: new `platform_merged_pr_proof()` function returning success only when exactly one merged PR for current branch/base exists.

- [ ] **Step 1: Add fake GitHub API success test after remote branch deletion**

Add this test near the Task 1 remote proof case in `tests/repo-lifecycle.sh`:

```bash
# --- repo-end worktree mode: deleted remote branch uses merged GitHub PR proof ---
github_proof_repo="$(create_repo end-worktree-github-proof)"
github_proof_origin="$CREATED_ORIGIN"
github_proof_main="$CREATED_REPO"
github_proof_feature="$TMPROOT/end-worktree-github-proof-feature"
git -C "$github_proof_main" remote set-url origin git@github.com:example/end-worktree-github-proof.git
git -C "$github_proof_main" worktree add -q -b feature/github-proof "$github_proof_feature" main
printf 'github stale content\n' >"$github_proof_feature/github-proof.txt"
git -C "$github_proof_feature" add github-proof.txt
git -C "$github_proof_feature" commit -q -m "github stale feature commit"
# Merge equivalent content directly to main as a squash and delete the remote feature ref.
git -C "$github_proof_main" checkout -q main
printf 'github merged content\n' >"$github_proof_main/github-proof.txt"
git -C "$github_proof_main" add github-proof.txt
git -C "$github_proof_main" commit -q -m "squash github proof"
git -C "$github_proof_main" push -q origin main
stub_api_bin="$TMPROOT/github-proof-bin"
mkdir -p "$stub_api_bin"
cat >"$stub_api_bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "gh $*" >>"$GH_STUB_LOG"
cat <<'JSON'
[{"number":298,"merged_at":"2026-07-04T02:41:51Z","base":{"ref":"main"},"head":{"ref":"feature/github-proof"}}]
JSON
EOF
chmod +x "$stub_api_bin/gh"
github_proof_home="$TMPROOT/end-worktree-github-proof-home"
mkdir -p "$github_proof_home"
GH_STUB_LOG="$TMPROOT/github-proof-gh.log" \
HOME="$github_proof_home" \
PATH="$stub_api_bin:$BIN_DIR:$PATH" \
GIT_CONFIG_GLOBAL=/dev/null \
"$REPO_END_SCRIPT" --print-path \
  >"$TMPROOT/end-worktree-github-proof.out" \
  2>"$TMPROOT/end-worktree-github-proof.err"
assert_file_contains "$TMPROOT/end-worktree-github-proof.out" "$github_proof_main" "repo-end GitHub proof prints main path"
assert_file_contains "$TMPROOT/end-worktree-github-proof.err" "Using merged GitHub PR #298 as merge proof" "repo-end announces GitHub PR proof"
assert_file_contains "$TMPROOT/github-proof-gh.log" "repos/example/end-worktree-github-proof/pulls" "repo-end queries GitHub pulls API"
if [[ -d "$github_proof_feature" ]]; then
  fail_case "repo-end GitHub proof removes linked worktree" "worktree remains at $github_proof_feature"
fi
pass_case "repo-end GitHub proof removes linked worktree"
```

- [ ] **Step 2: Add refusal test for multiple API matches**

Add a second fixture that stubs `gh` to return two merged PR objects and asserts `repo-end` fails with `multiple merged PRs` while keeping the worktree.

```bash
# --- repo-end API fallback refuses ambiguous merged PRs ---
api_ambiguous_repo="$(create_repo end-worktree-api-ambiguous)"
api_ambiguous_main="$CREATED_REPO"
api_ambiguous_feature="$TMPROOT/end-worktree-api-ambiguous-feature"
git -C "$api_ambiguous_main" remote set-url origin git@github.com:example/end-worktree-api-ambiguous.git
git -C "$api_ambiguous_main" worktree add -q -b feature/api-ambiguous "$api_ambiguous_feature" main
printf 'ambiguous local\n' >"$api_ambiguous_feature/ambiguous.txt"
git -C "$api_ambiguous_feature" add ambiguous.txt
git -C "$api_ambiguous_feature" commit -q -m "ambiguous local"
stub_ambiguous_bin="$TMPROOT/api-ambiguous-bin"
mkdir -p "$stub_ambiguous_bin"
cat >"$stub_ambiguous_bin/gh" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[
  {"number":10,"merged_at":"2026-07-04T02:00:00Z","base":{"ref":"main"},"head":{"ref":"feature/api-ambiguous"}},
  {"number":11,"merged_at":"2026-07-04T03:00:00Z","base":{"ref":"main"},"head":{"ref":"feature/api-ambiguous"}}
]
JSON
EOF
chmod +x "$stub_ambiguous_bin/gh"
if HOME="$TMPROOT/api-ambiguous-home" PATH="$stub_ambiguous_bin:$BIN_DIR:$PATH" GIT_CONFIG_GLOBAL=/dev/null \
  "$REPO_END_SCRIPT" >"$TMPROOT/api-ambiguous.out" 2>"$TMPROOT/api-ambiguous.err"; then
  fail_case "repo-end refuses ambiguous API PR proof" "repo-end unexpectedly succeeded"
fi
assert_file_contains "$TMPROOT/api-ambiguous.err" "multiple merged PRs" "repo-end explains ambiguous API proof"
if [[ ! -d "$api_ambiguous_feature" ]]; then
  fail_case "repo-end ambiguous API proof keeps worktree" "worktree was removed"
fi
pass_case "repo-end ambiguous API proof keeps worktree"
```

- [ ] **Step 3: Run tests to verify API cases fail**

Run: `bash tests/repo-lifecycle.sh`

Expected: new GitHub API proof test fails because no API fallback exists.

- [ ] **Step 4: Implement platform detection and GitHub API lookup**

Add helpers to `roles/common/files/bin/repo-end`:

```bash
origin_url() {
  "$(_worktree_cmd git)" -C "$repo_root" remote get-url origin 2>/dev/null || true
}

github_repo_slug() {
  local url="$1"
  case "$url" in
    git@github.com:*) printf '%s\n' "${url#git@github.com:}" | sed 's/[.]git$//' ;;
    https://github.com/*) printf '%s\n' "${url#https://github.com/}" | sed 's/[.]git$//' ;;
    ssh://git@github.com/*) printf '%s\n' "${url#ssh://git@github.com/}" | sed 's/[.]git$//' ;;
    *) return 1 ;;
  esac
}

github_merged_pr_proof() {
  command -v gh >/dev/null 2>&1 || return 1
  local slug json count number
  slug="$(github_repo_slug "$(origin_url)")" || return 1
  [[ -n "$slug" ]] || return 1
  json="$(gh api "repos/${slug}/pulls" -f state=closed -f head="${slug%%/*}:${current_branch}" -f base="$main_branch" 2>/dev/null)" || return 1
  count="$(printf '%s\n' "$json" | ruby -rjson -e '
    prs = JSON.parse(STDIN.read)
    matches = prs.select { |pr| pr["merged_at"].to_s != "" && pr.dig("base", "ref") == ARGV[0] && pr.dig("head", "ref") == ARGV[1] }
    puts matches.length
  ' "$main_branch" "$current_branch")" || return 1
  if [[ "$count" == "1" ]]; then
    number="$(printf '%s\n' "$json" | ruby -rjson -e '
      prs = JSON.parse(STDIN.read)
      matches = prs.select { |pr| pr["merged_at"].to_s != "" && pr.dig("base", "ref") == ARGV[0] && pr.dig("head", "ref") == ARGV[1] }
      puts matches.fetch(0).fetch("number")
    ' "$main_branch" "$current_branch")"
    printf 'Using merged GitHub PR #%s as merge proof\n' "$number" >&2
    return 0
  fi
  if [[ "$count" -gt 1 ]]; then
    printf 'Error: multiple merged PRs found for branch %s targeting %s; refusing cleanup\n' "$current_branch" "$main_branch" >&2
    exit 1
  fi
  return 1
}
```

Update the non-main proof block:

```bash
merge_proof_ref="$(select_git_merge_proof_ref || true)"
if [[ -z "$merge_proof_ref" ]]; then
  if platform_merged_pr_proof; then
    merge_proof_ref="platform-api"
  else
    printf 'Error: branch %s is not merged into origin/%s; merge the PR first, then run repo-end again\n' "$current_branch" "$main_branch" >&2
    exit 1
  fi
fi
```

where `platform_merged_pr_proof` initially delegates to `github_merged_pr_proof`.

- [ ] **Step 5: Run tests to verify GitHub API fallback passes**

Run: `bash tests/repo-lifecycle.sh`

Expected: all lifecycle tests pass.

- [ ] **Step 6: Commit Task 2**

Run:

```bash
~/.pi/agent/skills/commit/commit.sh -m "Use merged GitHub PR proof in repo-end" roles/common/files/bin/repo-end tests/repo-lifecycle.sh
```

---

### Task 3: Add Forgejo API fallback and full verification

**Files:**
- Modify: `roles/common/files/bin/repo-end`
- Modify: `tests/repo-lifecycle.sh`

**Interfaces:**
- Consumes: `platform_merged_pr_proof()` from Task 2.
- Produces: Forgejo merged PR proof via `curl` when `origin` points at a Forgejo remote and a token is available.

- [ ] **Step 1: Add fake Forgejo API success test**

Add a fixture like the GitHub one, but set origin URL to `ssh://git@forgejo.example:2222/example/end-worktree-forgejo-proof.git`, stub `curl`, set `FORGEJO_TOKEN=test-token`, and return:

```json
[
  {"number":42,"merged":true,"base":{"ref":"main"},"head":{"ref":"feature/forgejo-proof"}}
]
```

Assert stderr contains `Using merged Forgejo PR #42 as merge proof` and the worktree is removed.

- [ ] **Step 2: Run test to verify Forgejo case fails**

Run: `bash tests/repo-lifecycle.sh`

Expected: fails because Forgejo lookup is not implemented.

- [ ] **Step 3: Implement Forgejo lookup**

Add helpers:

```bash
forgejo_repo_parts() {
  local url="$1" path
  case "$url" in
    ssh://git@*/*) path="${url#ssh://git@*/}" ;;
    git@*:*) path="${url#git@*:}" ;;
    https://*/*) path="${url#https://*/}" ;;
    *) return 1 ;;
  esac
  printf '%s\n' "$path" | sed 's/[.]git$//'
}

forgejo_base_url() {
  local url="$1" host
  case "$url" in
    ssh://git@*) host="${url#ssh://git@}"; host="${host%%/*}"; host="${host%%:*}" ;;
    git@*:*) host="${url#git@}"; host="${host%%:*}" ;;
    https://*) host="${url#https://}"; host="${host%%/*}" ;;
    *) return 1 ;;
  esac
  case "$host" in
    forgejo|forgejo-git) printf 'https://forgejo.brianjohn.com\n' ;;
    *) printf 'https://%s\n' "$host" ;;
  esac
}

forgejo_merged_pr_proof() {
  command -v curl >/dev/null 2>&1 || return 1
  local token="${FORGEJO_TOKEN:-${GITEA_TOKEN:-}}"
  [[ -n "$token" ]] || return 1
  local remote base_url repo_path encoded json count number
  remote="$(origin_url)"
  repo_path="$(forgejo_repo_parts "$remote")" || return 1
  base_url="$(forgejo_base_url "$remote")" || return 1
  [[ -n "$repo_path" && -n "$base_url" ]] || return 1
  encoded="$(printf '%s' "$repo_path" | sed 's#/#%2F#g')"
  json="$(curl -sf -H "Authorization: token ${token}" "${base_url}/api/v1/repos/${repo_path}/pulls?state=closed" 2>/dev/null)" || return 1
  count="$(printf '%s\n' "$json" | ruby -rjson -e '
    prs = JSON.parse(STDIN.read)
    matches = prs.select { |pr| (pr["merged"] == true || pr["merged_at"].to_s != "") && pr.dig("base", "ref") == ARGV[0] && pr.dig("head", "ref") == ARGV[1] }
    puts matches.length
  ' "$main_branch" "$current_branch")" || return 1
  if [[ "$count" == "1" ]]; then
    number="$(printf '%s\n' "$json" | ruby -rjson -e '
      prs = JSON.parse(STDIN.read)
      matches = prs.select { |pr| (pr["merged"] == true || pr["merged_at"].to_s != "") && pr.dig("base", "ref") == ARGV[0] && pr.dig("head", "ref") == ARGV[1] }
      puts matches.fetch(0).fetch("number")
    ' "$main_branch" "$current_branch")"
    printf 'Using merged Forgejo PR #%s as merge proof\n' "$number" >&2
    return 0
  fi
  if [[ "$count" -gt 1 ]]; then
    printf 'Error: multiple merged PRs found for branch %s targeting %s; refusing cleanup\n' "$current_branch" "$main_branch" >&2
    exit 1
  fi
  return 1
}
```

Update `platform_merged_pr_proof`:

```bash
platform_merged_pr_proof() {
  github_merged_pr_proof || forgejo_merged_pr_proof
}
```

- [ ] **Step 4: Run full verification**

Run:

```bash
bash tests/repo-lifecycle.sh
bash tests/repo-end-callbacks.sh
bash tests/ci-test-inventory.sh
ansible-playbook --syntax-check playbook.yml
```

Expected: all pass.

- [ ] **Step 5: Commit Task 3**

Run:

```bash
~/.pi/agent/skills/commit/commit.sh -m "Use merged Forgejo PR proof in repo-end" roles/common/files/bin/repo-end tests/repo-lifecycle.sh
```

---

### Task 4: Open PR and monitor

**Files:**
- No code changes expected beyond prior tasks.

**Interfaces:**
- Consumes: committed implementation and verification output.
- Produces: GitHub PR for NMB.

- [ ] **Step 1: Check clean status**

Run: `git status --short`

Expected: no output.

- [ ] **Step 2: Push branch**

Run: `git push -u origin repo-end-merged-pr-fallback`

Expected: branch pushed.

- [ ] **Step 3: Open PR through the pull-request skill workflow**

Use the installed `pull-request` skill or shared PR helper. PR body must mention:

- Local Git proof remains primary.
- Remote branch proof runs before API fallback.
- API fallback only accepts exactly one merged PR targeting main.
- Verification commands from Task 3.

- [ ] **Step 4: Monitor PR**

Use `monitor-pr` or check GitHub review/check status. Address any actionable feedback with `receiving-code-review`.
