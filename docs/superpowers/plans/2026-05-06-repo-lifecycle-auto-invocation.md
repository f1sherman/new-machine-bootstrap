# Repo Lifecycle Auto-Invocation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `repo-start` and `repo-end` actually fire — nudge agents toward `repo-start` from initiation skills, hard-block alternative branch creation, and route `_clean-up` through `repo-end` first.

**Architecture:** Three independent components: (A) PostToolUse soft-reminder hook on `Skill` invocations, (B) extended PreToolUse hook on `Bash` to deny `git checkout -b` / `switch -c` / `branch <new>`, (C) `repo-end` gains an "already-merged" idempotency branch and `_clean-up` skill calls it before `git-clean-up`. Test approach mirrors existing patterns: `*.sh.test` files for hooks, real-temp-repo helpers for `repo-end.test`, naming-check additions to `tests/repo-lifecycle-provisioning.sh`.

**Tech Stack:** Bash 5+, jq, real `git` for hook tests, Ansible for hook registration in `~/.claude/settings.json`. No Ruby/Python.

**Spec:** `docs/superpowers/specs/2026-05-06-repo-lifecycle-auto-invocation-design.md`

---

## File Structure

**Created:**
- `roles/common/files/claude/hooks/block-initiation-skill-on-main.sh` — PostToolUse hook script.
- `roles/common/files/claude/hooks/block-initiation-skill-on-main.sh.test` — unit tests for the new hook.

**Modified:**
- `roles/common/files/claude/hooks/block-worktree-commands.sh` — add branch-creation regex matchers.
- `roles/common/files/claude/hooks/block-worktree-commands.sh.test` — new cases for the branch-creation matchers.
- `roles/common/files/bin/repo-end` — add already-merged short-circuit before rebase/merge/push.
- `roles/common/files/bin/repo-end.test` — new cases for the already-merged paths.
- `roles/common/files/config/skills/common/_clean-up/SKILL.md` — call `repo-end` before `git-clean-up` for the in-worktree path.
- `roles/common/tasks/main.yml` — register the new PostToolUse hook in `~/.claude/settings.json`.
- `tests/repo-lifecycle-provisioning.sh` — add naming/wiring checks for the new pieces.

**Out of scope (deferred to follow-up):** Codex-side mirrors (`codex-block-worktree-commands` etc.). The Claude-side wins do not depend on Codex parity.

---

## Task 1: New PostToolUse hook — `block-initiation-skill-on-main.sh`

Creates the soft-reminder hook. Test first (TDD), then implementation, then provisioning wiring (Task 2).

**Files:**
- Create: `roles/common/files/claude/hooks/block-initiation-skill-on-main.sh`
- Create: `roles/common/files/claude/hooks/block-initiation-skill-on-main.sh.test`

- [ ] **Step 1.1: Write the failing test**

Create `roles/common/files/claude/hooks/block-initiation-skill-on-main.sh.test`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/block-initiation-skill-on-main.sh"

if [ ! -x "$SCRIPT" ]; then
  printf 'ERROR: %s is not executable (or does not exist)\n' "$SCRIPT" >&2
  exit 2
fi

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

GIT_AUTHOR_NAME=test
GIT_AUTHOR_EMAIL=test@example.com
GIT_COMMITTER_NAME=test
GIT_COMMITTER_EMAIL=test@example.com
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

make_repo() {
  local path="$1" branch="$2"
  git -c init.templateDir= init -qb main "$path" >/dev/null
  git -C "$path" commit -q --allow-empty -m init
  if [ "$branch" != "main" ]; then
    git -C "$path" checkout -q -b "$branch"
  fi
}

REMINDER_NEEDLE='repo-start'

run_reminder_case() {
  local name="$1" skill="$2" branch="$3"
  local repo="$TMPROOT/$name"
  make_repo "$repo" "$branch"
  local payload output
  payload="$(jq -n --arg skill "$skill" '{tool_name:"Skill", tool_input:{skill:$skill}}')"
  output="$(cd "$repo" && printf '%s' "$payload" | "$SCRIPT")"
  if printf '%s' "$output" | jq -e --arg needle "$REMINDER_NEEDLE" \
      '.hookSpecificOutput.hookEventName == "PostToolUse"
       and .hookSpecificOutput.additionalContext
       | test($needle)' >/dev/null 2>&1; then
    printf 'PASS  %s\n' "$name"
  else
    printf 'FAIL  %s\n' "$name" >&2
    printf '      output: %s\n' "$output" >&2
    exit 1
  fi
}

run_silent_case() {
  local name="$1" skill="$2" branch="$3"
  local repo="$TMPROOT/$name"
  make_repo "$repo" "$branch"
  local payload output
  payload="$(jq -n --arg skill "$skill" '{tool_name:"Skill", tool_input:{skill:$skill}}')"
  output="$(cd "$repo" && printf '%s' "$payload" | "$SCRIPT")"
  if [ -z "$output" ]; then
    printf 'PASS  %s\n' "$name"
  else
    printf 'FAIL  %s\n' "$name" >&2
    printf '      output: %s\n' "$output" >&2
    exit 1
  fi
}

run_silent_no_repo() {
  local name="$1" skill="$2"
  local payload output
  payload="$(jq -n --arg skill "$skill" '{tool_name:"Skill", tool_input:{skill:$skill}}')"
  output="$(cd "$TMPROOT" && printf '%s' "$payload" | "$SCRIPT")"
  if [ -z "$output" ]; then
    printf 'PASS  %s\n' "$name"
  else
    printf 'FAIL  %s\n' "$name" >&2
    printf '      output: %s\n' "$output" >&2
    exit 1
  fi
}

run_silent_empty() {
  local name="$1" payload="$2"
  local output
  output="$(printf '%s' "$payload" | "$SCRIPT")"
  if [ -z "$output" ]; then
    printf 'PASS  %s\n' "$name"
  else
    printf 'FAIL  %s\n' "$name" >&2
    printf '      output: %s\n' "$output" >&2
    exit 1
  fi
}

run_reminder_case "reminds for brainstorming on main" "superpowers:brainstorming" "main"
run_reminder_case "reminds for _spec-first on main" "_spec-first" "main"
run_reminder_case "reminds for _spec-to-pr on main" "_spec-to-pr" "main"
run_silent_case "silent for brainstorming on feature branch" "superpowers:brainstorming" "feature/foo"
run_silent_case "silent for _spec-first on feature branch" "_spec-first" "feature/foo"
run_silent_case "silent for _spec-to-pr on feature branch" "_spec-to-pr" "feature/foo"
run_silent_case "silent for unrelated skill on main" "_commit" "main"
run_silent_case "silent for unrelated skill on feature" "_commit" "feature/bar"
run_silent_no_repo "silent when cwd is not a git repo" "superpowers:brainstorming"
run_silent_empty "silent for empty payload" '{}'
run_silent_empty "silent for missing skill field" '{"tool_input":{}}'
run_silent_empty "silent for non-Skill tool_name" '{"tool_name":"Bash","tool_input":{"skill":"superpowers:brainstorming"}}'

printf 'PASS  block-initiation-skill-on-main test suite\n'
```

Make it executable:

```bash
chmod +x roles/common/files/claude/hooks/block-initiation-skill-on-main.sh.test
```

- [ ] **Step 1.2: Run test to verify it fails**

```bash
bash roles/common/files/claude/hooks/block-initiation-skill-on-main.sh.test
```

Expected: `ERROR: <path>/block-initiation-skill-on-main.sh is not executable (or does not exist)` and exit 2.

- [ ] **Step 1.3: Implement the hook**

Create `roles/common/files/claude/hooks/block-initiation-skill-on-main.sh`:

```bash
#!/usr/bin/env bash
# Soft-reminder hook: when an initiating design skill runs while the cwd is
# on `main`, emit additionalContext nudging toward `repo-start <branch>`.
# Never blocks.
set -euo pipefail

input="$(cat)"

tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
if [[ "$tool_name" != "Skill" ]]; then
  exit 0
fi

skill="$(printf '%s' "$input" | jq -r '.tool_input.skill // empty' 2>/dev/null || true)"
case "$skill" in
  superpowers:brainstorming|_spec-first|_spec-to-pr) ;;
  *) exit 0 ;;
esac

branch="$(git -C "$PWD" branch --show-current 2>/dev/null || true)"
if [[ "$branch" != "main" ]]; then
  exit 0
fi

reminder='You invoked '"$skill"' while on main. Before committing any spec, plan, or other artifact, run `repo-start <branch>` to land in a feature worktree. (You may already have planned to do this; ignore this reminder if so.)'

jq -n --arg ctx "$reminder" '{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $ctx
  }
}'
```

Make it executable:

```bash
chmod +x roles/common/files/claude/hooks/block-initiation-skill-on-main.sh
```

- [ ] **Step 1.4: Run test to verify it passes**

```bash
bash roles/common/files/claude/hooks/block-initiation-skill-on-main.sh.test
```

Expected: 12 PASS lines + final `PASS  block-initiation-skill-on-main test suite`.

- [ ] **Step 1.5: Commit**

Invoke the `_commit` skill via the Skill tool with arguments:
> Commit the new hook + its test as one commit. Files: `roles/common/files/claude/hooks/block-initiation-skill-on-main.sh` and `.test`. Message focus: introduces the soft-reminder PostToolUse hook for initiating skills on main.

---

## Task 2: Register the new hook in Ansible

The hook script is useless without a registration in `~/.claude/settings.json`. Mirror the existing pattern.

**Files:**
- Modify: `roles/common/tasks/main.yml`

- [ ] **Step 2.1: Write the failing provisioning test**

Append to `tests/repo-lifecycle-provisioning.sh` (just before the final `printf 'PASS  repo lifecycle provisioning checks\n'`):

```bash
require_contains roles/common/tasks/main.yml 'block-initiation-skill-on-main.sh' \
  'main.yml registers initiation-skill PostToolUse hook'
require_contains roles/common/tasks/main.yml 'PostToolUse' \
  'main.yml mentions PostToolUse event'
require_contains roles/common/files/claude/hooks/block-initiation-skill-on-main.sh 'repo-start' \
  'initiation-skill hook names repo-start'
```

- [ ] **Step 2.2: Run test to verify it fails**

```bash
bash tests/repo-lifecycle-provisioning.sh
```

Expected: `FAIL  main.yml registers initiation-skill PostToolUse hook` and exit 1.

- [ ] **Step 2.3: Add the Ansible task**

In `roles/common/tasks/main.yml`, locate the existing block titled
`Register PreToolUse Edit|MultiEdit|Write hook for blocking main-branch file edits` (around line 720). Immediately after it (and before the next non-hook task), insert:

```yaml
- name: Register PostToolUse Skill hook for initiation-skill main-branch reminder
  shell: |
    set -euo pipefail

    settings_file="${SETTINGS_FILE:?}"
    hook_cmd='~/.claude/hooks/block-initiation-skill-on-main.sh'

    if [ ! -f "$settings_file" ]; then
      echo '{}' > "$settings_file"
    fi

    if jq -e --arg cmd "$hook_cmd" '
      .hooks.PostToolUse // []
      | any(.matcher == "Skill" and any(.hooks[]?; .type == "command" and .command == $cmd))
    ' "$settings_file" > /dev/null 2>&1; then
      echo "already registered"
      exit 0
    fi

    HOOK_ENTRY='{"matcher":"Skill","hooks":[{"type":"command","command":"'"$hook_cmd"'"}]}'
    jq --argjson entry "$HOOK_ENTRY" \
      '.hooks //= {} | .hooks.PostToolUse = ((.hooks.PostToolUse // []) + [$entry])' \
      "$settings_file" > "${settings_file}.tmp" \
      && mv "${settings_file}.tmp" "$settings_file"
  args:
    executable: /bin/bash
  environment:
    SETTINGS_FILE: '{{ ansible_facts["user_dir"] }}/.claude/settings.json'
  register: block_initiation_skill_hook_result
  changed_when: "'already registered' not in block_initiation_skill_hook_result.stdout"
```

The exact insertion point: directly after the existing main-branch-edits registration block ends (the line containing `changed_when:` for that task), before the next `- name:` task.

- [ ] **Step 2.4: Run provisioning test to verify it passes**

```bash
bash tests/repo-lifecycle-provisioning.sh
```

Expected: all PASS lines including the three new ones.

- [ ] **Step 2.5: Apply provisioning locally and verify settings.json**

```bash
bin/provision --tags claude
```

(Use whatever tag is wired; if tags aren't used, plain `bin/provision` is fine.) Then:

```bash
jq '.hooks.PostToolUse // [] | map(select(.matcher == "Skill")) | length' ~/.claude/settings.json
```

Expected: `1` (or higher if there were already Skill PostToolUse hooks). Re-run `bin/provision` once more and verify the count does not increase (idempotency check).

- [ ] **Step 2.6: Commit**

Invoke the `_commit` skill with arguments:
> Commit `roles/common/tasks/main.yml` and `tests/repo-lifecycle-provisioning.sh`. Message focus: register the new PostToolUse skill hook in settings.json via Ansible.

---

## Task 3: Extend `block-worktree-commands.sh` to block branch creation

Add denials for `git checkout -b`, `git switch -c`, `git switch --create`, and `git branch <new>`.

**Files:**
- Modify: `roles/common/files/claude/hooks/block-worktree-commands.sh`
- Modify: `roles/common/files/claude/hooks/block-worktree-commands.sh.test`

- [ ] **Step 3.1: Write the failing test cases**

Append to `roles/common/files/claude/hooks/block-worktree-commands.sh.test`, just before the final `printf 'PASS  blocker helper test suite\n'` line:

```bash
DENY_REASON='Do not create branches directly. Use repo-start <branch> instead.'

run_block_case "blocks git checkout -b" 'git checkout -b foo' "$DENY_REASON"
run_block_case "blocks git switch -c" 'git switch -c foo' "$DENY_REASON"
run_block_case "blocks git switch --create" 'git switch --create foo' "$DENY_REASON"
run_block_case "blocks git branch <name>" 'git branch foo' "$DENY_REASON"
run_block_case "blocks git -C path checkout -b" 'git -C repo checkout -b foo' "$DENY_REASON"
run_block_case "blocks command git checkout -b" 'command git checkout -b foo' "$DENY_REASON"
run_block_case "blocks chained git checkout -b" 'cd repo && git checkout -b foo' "$DENY_REASON"
run_allow_case "allows git branch (no args)" 'git branch'
run_allow_case "allows git branch --show-current" 'git branch --show-current'
run_allow_case "allows git branch --list" 'git branch --list'
run_allow_case "allows git branch -d foo" 'git branch -d foo'
run_allow_case "allows git branch -D foo" 'git branch -D foo'
run_allow_case "allows git branch -v" 'git branch -v'
run_allow_case "allows git branch --merged" 'git branch --merged'
run_allow_case "allows git checkout main" 'git checkout main'
run_allow_case "allows git switch main" 'git switch main'
```

- [ ] **Step 3.2: Run test to verify the new cases fail**

```bash
bash roles/common/files/claude/hooks/block-worktree-commands.sh.test
```

Expected: First failure on `blocks git checkout -b` (or whichever new block-case runs first after the existing tests).

- [ ] **Step 3.3: Update the hook**

Edit `roles/common/files/claude/hooks/block-worktree-commands.sh`. Replace the existing body (everything after `set -euo pipefail` and the empty-command guard) with:

```bash
matches_worktree_command() {
  local action="$1"
  local pattern='(^|[;&|()])[[:space:]]*((([[:alnum:]_]+)=[^[:space:]]+[[:space:]]+|command[[:space:]]+|env[[:space:]]+)*)git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]]+)*)*[[:space:]]+worktree[[:space:]]+'"$action"'([[:space:]]|$)'
  printf '%s\n' "$command" | grep -Eq "$pattern"
}

# Matches the leading "git ..." preamble: optional env-var prefixes, optional
# `command ` / `env ` builtin wrapper, optional global git flags like `-C path`.
GIT_PREAMBLE='(^|[;&|()])[[:space:]]*((([[:alnum:]_]+)=[^[:space:]]+[[:space:]]+|command[[:space:]]+|env[[:space:]]+)*)git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]]+)*)*[[:space:]]+'

matches_branch_create_command() {
  # `git ... checkout ... -b/-B <name>`
  local checkout_b="${GIT_PREAMBLE}checkout[[:space:]].*[[:space:]]-[bB]([[:space:]]|$)"
  # `git ... switch ... -c/-C/--create <name>`
  local switch_c="${GIT_PREAMBLE}switch[[:space:]].*(-c|--create|-C)([[:space:]]|$)"
  # `git ... branch <name>` where <name> is a positional (non-flag) argument.
  # Read-only and management forms (-d/-D/-m/-M/-l/--list/--show-current/-v/-a/-r/--merged/--no-merged/--contains) are allowed because they begin with `-`.
  local branch_create="${GIT_PREAMBLE}branch[[:space:]]+[^-[:space:]][^[:space:]]*([[:space:]]|$)"

  printf '%s\n' "$command" | grep -Eq "$checkout_b" && return 0
  printf '%s\n' "$command" | grep -Eq "$switch_c" && return 0
  printf '%s\n' "$command" | grep -Eq "$branch_create" && return 0
  return 1
}

emit_deny() {
  local reason="$1"
  jq -n --arg reason "$reason" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": $reason
    }
  }'
}

if matches_worktree_command add; then
  emit_deny "Do not run git worktree add directly. Use repo-start instead."
  exit 0
fi

if matches_worktree_command remove; then
  emit_deny "Do not run git worktree remove directly. Use repo-end to finish work, or cleanup-branches --branch <branch> for cleanup only."
  exit 0
fi

if matches_branch_create_command; then
  emit_deny "Do not create branches directly. Use repo-start <branch> instead."
  exit 0
fi

exit 0
```

Note: the regex for `git branch <name>` uses negative-lookahead-by-character-class — only matches when the first positional argument does NOT start with `-`. This allows `git branch -d`, `--list`, etc. through.

- [ ] **Step 3.4: Run test to verify it passes**

```bash
bash roles/common/files/claude/hooks/block-worktree-commands.sh.test
```

Expected: all PASS lines (existing + new) + final `PASS  blocker helper test suite`.

- [ ] **Step 3.5: Commit**

Invoke the `_commit` skill with arguments:
> Commit `roles/common/files/claude/hooks/block-worktree-commands.sh` and its `.test`. Message focus: also block direct branch creation and redirect to repo-start.

---

## Task 4: Add already-merged idempotency to `repo-end`

Make `repo-end` safe to call when the branch is already integrated into `origin/main` (direct ancestor or squash-merged), so `_clean-up` can run it post-PR-merge without harm.

**Files:**
- Modify: `roles/common/files/bin/repo-end`
- Modify: `roles/common/files/bin/repo-end.test`

- [ ] **Step 4.1: Write the failing test cases**

Append to `roles/common/files/bin/repo-end.test`, just before the final `printf 'PASS  ...\n'` (or final exit). The existing test scaffolding (`create_remote_repo`, `assert_file_contains`, the cleanup-branches stub, the `CLEANUP_LOG`/`CLEANUP_STATUS`/`CLEANUP_STDOUT` env vars) is already available.

```bash
# Already-merged direct-ancestor: feature commits are present in origin/main,
# repo-end should skip rebase/merge/push and run cleanup-branches.
ancestor_repo="$(create_remote_repo already-ancestor)"
git -C "$ancestor_repo" checkout -q -b feature/already-ancestor
printf 'ancestor work\n' >"$ancestor_repo/work.txt"
git -C "$ancestor_repo" add work.txt
git -C "$ancestor_repo" commit -q -m work
# Push the feature branch's commits to origin/main directly to simulate a
# fast-forward merge that already happened upstream.
ancestor_origin="$TMPROOT/already-ancestor-origin.git"
ancestor_tip="$(git -C "$ancestor_repo" rev-parse HEAD)"
git --git-dir="$ancestor_origin" update-ref refs/heads/main "$ancestor_tip"
CLEANUP_LOG="$TMPROOT/already-ancestor-cleanup.log" CLEANUP_STATUS=0 \
  bash -c 'cd "$1" && "$2" --print-path' bash "$ancestor_repo" "$SCRIPT" >"$TMPROOT/already-ancestor.out" 2>"$TMPROOT/already-ancestor.err"
assert_file_contains "$TMPROOT/already-ancestor-cleanup.log" \
  '--branch feature/already-ancestor' \
  'repo-end runs cleanup when feature is direct ancestor of origin/main'
# Verify the bare origin's main was NOT updated by an extra push (it should
# still point at ancestor_tip, not at some merge commit on top of it).
post_origin_tip="$(git --git-dir="$ancestor_origin" rev-parse refs/heads/main)"
[ "$post_origin_tip" = "$ancestor_tip" ] || {
  printf 'FAIL  repo-end did not push when already ancestor\n' >&2
  printf '      expected %s, origin now %s\n' "$ancestor_tip" "$post_origin_tip" >&2
  exit 1
}
printf 'PASS  repo-end skips push when feature is direct ancestor\n'

# Squash-merged: feature's tree is in origin/main as a single squash commit
# whose individual commit hashes do not appear on main. repo-end should
# detect via patch-id (`git cherry`) that the work is already upstream and
# skip rebase/merge/push.
squash_repo="$(create_remote_repo squash-merged)"
git -C "$squash_repo" checkout -q -b feature/squash-merged
printf 'squash work\n' >"$squash_repo/squash.txt"
git -C "$squash_repo" add squash.txt
git -C "$squash_repo" commit -q -m 'squash work part 1'
printf 'more squash work\n' >>"$squash_repo/squash.txt"
git -C "$squash_repo" add squash.txt
git -C "$squash_repo" commit -q -m 'squash work part 2'
# Build a squash commit on origin/main containing the same tree changes.
squash_tree="$(git -C "$squash_repo" rev-parse HEAD^{tree})"
squash_parent="$(git -C "$squash_repo" rev-parse 'HEAD~2')"
squash_origin="$TMPROOT/squash-merged-origin.git"
squash_commit="$(git -C "$squash_repo" commit-tree "$squash_tree" -p "$squash_parent" -m 'squash merge of feature/squash-merged')"
git --git-dir="$squash_origin" update-ref refs/heads/main "$squash_commit"
CLEANUP_LOG="$TMPROOT/squash-cleanup.log" CLEANUP_STATUS=0 \
  bash -c 'cd "$1" && "$2" --print-path' bash "$squash_repo" "$SCRIPT" >"$TMPROOT/squash.out" 2>"$TMPROOT/squash.err"
assert_file_contains "$TMPROOT/squash-cleanup.log" \
  '--branch feature/squash-merged' \
  'repo-end runs cleanup when feature is squash-merged into origin/main'
post_squash_tip="$(git --git-dir="$squash_origin" rev-parse refs/heads/main)"
[ "$post_squash_tip" = "$squash_commit" ] || {
  printf 'FAIL  repo-end pushed beyond squash commit\n' >&2
  printf '      expected %s, origin now %s\n' "$squash_commit" "$post_squash_tip" >&2
  exit 1
}
printf 'PASS  repo-end skips push when feature is squash-merged\n'
```

- [ ] **Step 4.2: Run test to verify the new cases fail**

```bash
bash roles/common/files/bin/repo-end.test
```

Expected: existing tests pass; first new case (`repo-end skips push when feature is direct ancestor`) fails because the current `repo-end` will rebase + merge + push even though it's already upstream.

- [ ] **Step 4.3: Add the idempotency check to `repo-end`**

Edit `roles/common/files/bin/repo-end`. Find the block:

```bash
"$(_worktree_cmd git)" -C "$repo_root" fetch -q origin || true
if ! "$(_worktree_cmd git)" -C "$repo_root" rebase --quiet "origin/${main_branch}"; then
  printf 'Error: rebase has conflicts; resolve them in %s and run repo-end again\n' "$repo_root" >&2
  exit 1
fi
```

Replace it with:

```bash
"$(_worktree_cmd git)" -C "$repo_root" fetch -q origin || true

already_merged() {
  # Direct ancestor: every commit on HEAD is already in origin/<main>.
  if "$(_worktree_cmd git)" -C "$repo_root" merge-base --is-ancestor HEAD "origin/${main_branch}" 2>/dev/null; then
    return 0
  fi
  # Squash equivalence: every unique commit on HEAD has a patch-id match
  # on origin/<main>. `git cherry` marks already-upstream commits with `-`
  # and unique commits with `+`. If grep finds no `+` lines, the branch is
  # fully represented upstream.
  local cherry
  cherry="$("$(_worktree_cmd git)" -C "$repo_root" cherry "origin/${main_branch}" HEAD 2>/dev/null || true)"
  [[ -n "$cherry" ]] || return 1
  if printf '%s\n' "$cherry" | grep -Eq '^\+'; then
    return 1
  fi
  return 0
}

if already_merged; then
  skip_integration=true
else
  skip_integration=false
  if ! "$(_worktree_cmd git)" -C "$repo_root" rebase --quiet "origin/${main_branch}"; then
    printf 'Error: rebase has conflicts; resolve them in %s and run repo-end again\n' "$repo_root" >&2
    exit 1
  fi
fi
```

Then find the block that does the merge+push:

```bash
"$(_worktree_cmd git)" -C "$main_path" checkout -q "$main_branch"
"$(_worktree_cmd git)" -C "$main_path" merge --quiet "$current_branch"
"$(_worktree_cmd git)" -C "$main_path" push --quiet
```

Replace with:

```bash
if [[ "$skip_integration" != "true" ]]; then
  "$(_worktree_cmd git)" -C "$main_path" checkout -q "$main_branch"
  "$(_worktree_cmd git)" -C "$main_path" merge --quiet "$current_branch"
  "$(_worktree_cmd git)" -C "$main_path" push --quiet
fi
```

Leave the cleanup invocation and the final `printf '%s\n' "$main_path"` untouched — they should run in both branches.

- [ ] **Step 4.4: Run test to verify it passes**

```bash
bash roles/common/files/bin/repo-end.test
```

Expected: all existing + new PASS lines.

- [ ] **Step 4.5: Commit**

Invoke the `_commit` skill with arguments:
> Commit `roles/common/files/bin/repo-end` and its `.test`. Message focus: skip integration in repo-end when the feature branch is already merged upstream (direct ancestor or squash equivalence), so it can be called safely post-PR-merge.

---

## Task 5: Update `_clean-up` skill to call `repo-end` first

The in-worktree path becomes "`repo-end` then `git-clean-up`." The monitor-driven path (with `--repo-dir`) stays as-is — it always runs after a remote PR merge and from a context where the working directory may already be the to-be-removed worktree.

**Files:**
- Modify: `roles/common/files/config/skills/common/_clean-up/SKILL.md`
- Modify: `tests/_clean-up-skill.sh` (add a check for the new content)

- [ ] **Step 5.1: Write the failing skill-content test**

Edit `tests/_clean-up-skill.sh`. The file already defines an `assert_contains <path> <needle> <name>` helper that uses `rg`. Find the existing block of `assert_contains "$COMMON_SKILL" ...` calls (around line 65–67) and add these two lines immediately after them:

```bash
assert_contains "$COMMON_SKILL" 'repo-end' "skill invokes repo-end"
assert_contains "$COMMON_SKILL" 'main_path="$(repo-end --print-path)"' "skill captures repo-end main path"
```

- [ ] **Step 5.2: Run test to verify it fails**

```bash
bash tests/_clean-up-skill.sh
```

Expected: `FAIL  _clean-up SKILL.md names repo-end`.

- [ ] **Step 5.3: Update the skill**

Edit `roles/common/files/config/skills/common/_clean-up/SKILL.md`. Replace the in-worktree `git-clean-up` invocation block:

```markdown
Run the shared cleanup helper from the repository that should be cleaned:

```bash
git-clean-up
```
```

with:

```markdown
Run the lifecycle close helper first, then the shared cleanup sweep, from
the repository that should be cleaned:

```bash
main_path="$(repo-end --print-path)"
cd "$main_path"
git-clean-up
```

`repo-end` integrates the feature branch into main and tears down the
worktree. It is safe to invoke when the branch was already merged upstream
(direct or squash) — it will skip the integration phase and proceed to
cleanup. After it returns, `cd` to the printed main path before running
`git-clean-up` so the wider cleanup runs from a valid cwd.
```

Leave the second invocation block (the monitor path with `--repo-dir`/`--branch`) unchanged — that path runs post-PR-merge from a possibly-already-defunct cwd and should keep its current shape.

- [ ] **Step 5.4: Run skill test to verify it passes**

```bash
bash tests/_clean-up-skill.sh
```

Expected: all PASS lines including the two new ones.

- [ ] **Step 5.5: Commit**

Invoke the `_commit` skill with arguments:
> Commit `roles/common/files/config/skills/common/_clean-up/SKILL.md` and `tests/_clean-up-skill.sh`. Message focus: route the in-worktree clean-up flow through repo-end before git-clean-up.

---

## Task 6: End-to-end verification

Apply all changes locally and walk through each surface manually. No new commits expected unless the verification surfaces a real bug.

- [ ] **Step 6.1: Apply provisioning**

```bash
bin/provision
```

Expected: clean run, no errors.

- [ ] **Step 6.2: Verify hook deployment**

```bash
ls -la ~/.claude/hooks/block-initiation-skill-on-main.sh
jq '.hooks.PostToolUse | map(select(.matcher == "Skill"))' ~/.claude/settings.json
```

Expected: file exists and is executable; jq output shows the new entry.

- [ ] **Step 6.3: Verify the soft-reminder hook end-to-end**

From the **main** checkout (not this worktree), run:

```bash
cd /Users/brianjohn/projects/new-machine-bootstrap
git -c init.defaultBranch=main branch --show-current   # confirm: main
echo '{"tool_name":"Skill","tool_input":{"skill":"superpowers:brainstorming"}}' \
  | ~/.claude/hooks/block-initiation-skill-on-main.sh
```

Expected: JSON containing `additionalContext` with the word `repo-start`.

From this worktree (`.worktrees/repo-lifecycle-auto-invocation`), the same input should produce no output.

- [ ] **Step 6.4: Verify the branch-creation block end-to-end**

```bash
echo '{"tool_input":{"command":"git checkout -b throwaway"}}' \
  | ~/.claude/hooks/block-worktree-commands.sh
```

Expected: JSON with `permissionDecision: "deny"` and `permissionDecisionReason` mentioning `repo-start`.

```bash
echo '{"tool_input":{"command":"git branch --show-current"}}' \
  | ~/.claude/hooks/block-worktree-commands.sh
```

Expected: empty output (allowed).

- [ ] **Step 6.5: Verify `repo-end` idempotency on a real already-merged branch**

(Optional smoke test. Skip if no convenient already-merged branch is available — the unit tests cover the same logic.)

Find a local branch whose tip is already in `origin/main`:

```bash
git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads/ \
  | grep -E '\[gone\]|^main' | head -5
```

If a candidate exists, check it out in a throwaway worktree:

```bash
git worktree add /tmp/throwaway-verify <branch>
cd /tmp/throwaway-verify
repo-end --print-path
```

Expected: prints the main path, runs cleanup, no errors. This intentionally bypasses the new branch-creation hook by running outside the agent harness.

- [ ] **Step 6.6: Run all relevant tests once more**

```bash
bash roles/common/files/claude/hooks/block-initiation-skill-on-main.sh.test
bash roles/common/files/claude/hooks/block-worktree-commands.sh.test
bash roles/common/files/claude/hooks/block-main-branch-edits.sh.test
bash roles/common/files/bin/repo-end.test
bash tests/repo-lifecycle-provisioning.sh
bash tests/_clean-up-skill.sh
```

Expected: all green.

- [ ] **Step 6.7: Open the PR**

Invoke the `_pull-request` skill via the Skill tool. The PR description should summarize the three components (skill reminder, branch-create block, `_clean-up` → `repo-end`) and note the `repo-end` behavior change (already-merged short-circuit) as the most reviewable bit.

---

## Self-Review Notes

**Spec coverage:**
- Component A (PostToolUse reminder hook): Tasks 1, 2, 6.3.
- Component B (branch creation block): Tasks 3, 6.4.
- Component C (`_clean-up` → `repo-end`, with `repo-end` idempotency): Tasks 4, 5, 6.5.
- Spec's "Files Affected" list: all touched (deferring Codex parity per spec).
- Spec's "Open Questions" — `repo-end` idempotency picked option 1 (bake into `repo-end`), reflected in Task 4. Plan introduces a new wrinkle the spec didn't anticipate: the in-worktree `_clean-up` path needs `cd "$main_path"` after `repo-end` to keep `git-clean-up`'s cwd valid. Captured in Task 5.

**Type/name consistency:**
- Hook script name `block-initiation-skill-on-main.sh` used uniformly.
- Skill matcher value `Skill` used in both the hook (`tool_name == "Skill"`) and Ansible (`matcher: "Skill"`).
- Deny reason for branch-create matches between hook and tests (`Do not create branches directly. Use repo-start <branch> instead.`).
- `skip_integration` flag introduced in Task 4 is a one-task local; no naming clash elsewhere.
