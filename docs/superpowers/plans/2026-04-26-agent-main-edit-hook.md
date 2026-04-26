# Agent Main-Branch Edit Hook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Claude and Codex `PreToolUse` edit hooks that block main-branch edits for tracked or unignored files, wire them into provisioning, and verify the live machine setup.

**Architecture:** Follow the repository's existing hook pattern: dedicated Bash helpers beside helper-local shell regressions, plus repo-level provisioning regressions that execute the Ansible shell snippets directly. Keep Claude and Codex blockers separate because their hook payloads differ: Claude receives `tool_input.file_path`, while Codex exposes `apply_patch` text that must be parsed for `*** Add/Update/Delete File:` headers.

**Tech Stack:** Bash, jq, git, Ansible, yq, Claude Code hooks, Codex hooks.

---

## File Structure

### New files

- `roles/common/files/claude/hooks/block-main-branch-edits.sh`
  Claude `PreToolUse` helper for `Edit|MultiEdit|Write`.
- `roles/common/files/claude/hooks/block-main-branch-edits.sh.test`
  Shell regression harness for the Claude helper.
- `roles/common/files/bin/codex-block-main-branch-edits`
  Codex `PreToolUse` helper for `apply_patch|Edit|Write`.
- `roles/common/files/bin/codex-block-main-branch-edits.test`
  Shell regression harness for the Codex helper.
- `tests/claude-main-edit-hook-provisioning.sh`
  Repo-level regression for Claude hook registration and `0600` enforcement.
- `tests/codex-main-edit-hook-provisioning.sh`
  Repo-level regression for Codex install/merge behavior and `0600` enforcement.

### Modified files

- `roles/common/tasks/main.yml`
  Register the new Claude hook, enforce `0600` on `~/.claude/settings.json`, install the new Codex helper, and merge the new Codex hook entry into `~/.codex/hooks.json`.

## Task 1: Add The Claude Helper And Its Red/Green Regression

**Files:**
- Create: `roles/common/files/claude/hooks/block-main-branch-edits.sh`
- Create: `roles/common/files/claude/hooks/block-main-branch-edits.sh.test`

- [ ] **Step 1: Write the failing Claude helper regression**

Create `roles/common/files/claude/hooks/block-main-branch-edits.sh.test` with this content:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/block-main-branch-edits.sh"
REASON='File edit blocked on main. Move to a non-main branch/worktree per repo instructions, then retry.'

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
  local path="$1"
  local branch="$2"

  git init -q "$path" >/dev/null
  git -C "$path" commit -q --allow-empty -m init
  git -C "$path" branch -M main

  printf '*.log\n' > "$path/.gitignore"
  printf 'tracked\n' > "$path/tracked.txt"
  git -C "$path" add .gitignore tracked.txt
  git -C "$path" commit -q -m seed

  if [ "$branch" != "main" ]; then
    git -C "$path" checkout -q -b "$branch" >/dev/null
  fi
}

run_block_case() {
  local name="$1"
  local tool_name="$2"
  local file_path="$3"
  local payload
  local output

  payload="$(jq -n --arg tool_name "$tool_name" --arg file_path "$file_path" '{
    tool_name: $tool_name,
    tool_input: {
      file_path: $file_path,
      content: "replacement",
      old_string: "tracked",
      new_string: "replacement"
    }
  }')"
  output="$(printf '%s' "$payload" | "$SCRIPT")"

  if printf '%s' "$output" | jq -e --arg reason "$REASON" '. == {hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}' >/dev/null; then
    printf 'PASS  %s\n' "$name"
  else
    printf 'FAIL  %s\n' "$name" >&2
    printf '      output: %s\n' "$output" >&2
    exit 1
  fi
}

run_allow_case() {
  local name="$1"
  local tool_name="$2"
  local file_path="$3"
  local payload
  local output

  payload="$(jq -n --arg tool_name "$tool_name" --arg file_path "$file_path" '{
    tool_name: $tool_name,
    tool_input: {
      file_path: $file_path,
      content: "replacement",
      old_string: "tracked",
      new_string: "replacement"
    }
  }')"
  output="$(printf '%s' "$payload" | "$SCRIPT")"

  [ -z "$output" ] || {
    printf 'FAIL  %s\n' "$name" >&2
    printf '      output: %s\n' "$output" >&2
    exit 1
  }
  printf 'PASS  %s\n' "$name"
}

run_payload_allow_case() {
  local name="$1"
  local payload="$2"
  local output

  output="$(printf '%s' "$payload" | "$SCRIPT")"
  [ -z "$output" ] || {
    printf 'FAIL  %s\n' "$name" >&2
    printf '      output: %s\n' "$output" >&2
    exit 1
  }
  printf 'PASS  %s\n' "$name"
}

main_repo="$TMPROOT/main-repo"
feature_repo="$TMPROOT/feature-repo"
outside_dir="$TMPROOT/outside"
mkdir -p "$outside_dir"

make_repo "$main_repo" main
make_repo "$feature_repo" feature/claude-main-edit-hook

run_block_case "blocks tracked write on main" "Write" "$main_repo/tracked.txt"
run_block_case "blocks tracked edit on main" "Edit" "$main_repo/tracked.txt"
run_block_case "blocks tracked multiedit on main" "MultiEdit" "$main_repo/tracked.txt"
run_block_case "blocks untracked non-ignored write on main" "Write" "$main_repo/new.txt"
run_allow_case "allows ignored file on main" "Write" "$main_repo/ignored.log"
run_allow_case "allows tracked file on feature branch" "Edit" "$feature_repo/tracked.txt"
run_allow_case "allows file outside git repo" "Write" "$outside_dir/outside.txt"
run_payload_allow_case "allows missing file path" '{"tool_name":"Write","tool_input":{"content":"replacement"}}'
run_payload_allow_case "allows malformed payload" '{}'

printf 'PASS  Claude main-branch edit helper test suite\n'
```

- [ ] **Step 2: Run the Claude helper test to verify it fails**

Run:

```bash
bash roles/common/files/claude/hooks/block-main-branch-edits.sh.test
```

Expected:

- exits non-zero
- prints `ERROR: .../block-main-branch-edits.sh is not executable (or does not exist)`

- [ ] **Step 3: Write the minimal Claude helper implementation**

Create `roles/common/files/claude/hooks/block-main-branch-edits.sh` with this content:

```bash
#!/usr/bin/env bash
set -euo pipefail

reason='File edit blocked on main. Move to a non-main branch/worktree per repo instructions, then retry.'
file_path="$(jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"

emit_deny() {
  jq -n --arg reason "$reason" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": $reason
    }
  }'
}

find_probe_dir() {
  local path="$1"
  local probe

  if [ -d "$path" ]; then
    probe="$path"
  else
    probe="$(dirname "$path")"
  fi

  while [ ! -d "$probe" ] && [ "$probe" != "/" ] && [ "$probe" != "." ]; do
    probe="$(dirname "$probe")"
  done

  [ -d "$probe" ] || return 1
  printf '%s\n' "$probe"
}

to_repo_path() {
  local path="$1"

  if [[ "$path" == "$repo_root"/* ]]; then
    printf '%s\n' "${path#$repo_root/}"
  else
    printf '%s\n' "$path"
  fi
}

if [[ -z "$file_path" ]]; then
  exit 0
fi

probe_dir="$(find_probe_dir "$file_path" 2>/dev/null || true)"
if [[ -z "$probe_dir" ]]; then
  exit 0
fi

repo_root="$(git -C "$probe_dir" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
  exit 0
fi

branch="$(git -C "$repo_root" branch --show-current 2>/dev/null || true)"
if [[ "$branch" != "main" ]]; then
  exit 0
fi

repo_path="$(to_repo_path "$file_path")"

if git -C "$repo_root" ls-files --error-unmatch -- "$repo_path" >/dev/null 2>&1; then
  emit_deny
  exit 0
fi

if git -C "$repo_root" check-ignore -q -- "$repo_path" >/dev/null 2>&1; then
  exit 0
fi

emit_deny
```

- [ ] **Step 4: Run the Claude helper test to verify it passes**

Run:

```bash
bash roles/common/files/claude/hooks/block-main-branch-edits.sh.test
```

Expected:

- exits `0`
- prints `PASS  Claude main-branch edit helper test suite`

- [ ] **Step 5: Commit the Claude helper**

Run:

```bash
git add roles/common/files/claude/hooks/block-main-branch-edits.sh roles/common/files/claude/hooks/block-main-branch-edits.sh.test
git -c commit.gpgsign=false commit -m "Add Claude main-branch edit hook"
```

Expected:

- one commit containing only the Claude helper and its regression

## Task 2: Add The Codex Helper And Its Red/Green Regression

**Files:**
- Create: `roles/common/files/bin/codex-block-main-branch-edits`
- Create: `roles/common/files/bin/codex-block-main-branch-edits.test`

- [ ] **Step 1: Write the failing Codex helper regression**

Create `roles/common/files/bin/codex-block-main-branch-edits.test` with this content:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/codex-block-main-branch-edits"
REASON='File edit blocked on main. Move to a non-main branch/worktree per repo instructions, then retry.'

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
  local path="$1"
  local branch="$2"

  git init -q "$path" >/dev/null
  git -C "$path" commit -q --allow-empty -m init
  git -C "$path" branch -M main

  printf '*.log\n' > "$path/.gitignore"
  printf 'tracked\n' > "$path/tracked.txt"
  git -C "$path" add .gitignore tracked.txt
  git -C "$path" commit -q -m seed

  if [ "$branch" != "main" ]; then
    git -C "$path" checkout -q -b "$branch" >/dev/null
  fi
}

run_block_case() {
  local name="$1"
  local repo="$2"
  local command="$3"
  local output

  output="$(cd "$repo" && jq -n --arg command "$command" '{tool_name:"apply_patch",tool_input:{command:$command}}' | "$SCRIPT")"

  if printf '%s' "$output" | jq -e --arg reason "$REASON" '. == {hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}' >/dev/null; then
    printf 'PASS  %s\n' "$name"
  else
    printf 'FAIL  %s\n' "$name" >&2
    printf '      output: %s\n' "$output" >&2
    exit 1
  fi
}

run_allow_case() {
  local name="$1"
  local repo="$2"
  local command="$3"
  local output

  output="$(cd "$repo" && jq -n --arg command "$command" '{tool_name:"apply_patch",tool_input:{command:$command}}' | "$SCRIPT")"

  [ -z "$output" ] || {
    printf 'FAIL  %s\n' "$name" >&2
    printf '      output: %s\n' "$output" >&2
    exit 1
  }
  printf 'PASS  %s\n' "$name"
}

run_payload_allow_case() {
  local name="$1"
  local payload="$2"
  local output

  output="$(printf '%s' "$payload" | "$SCRIPT")"
  [ -z "$output" ] || {
    printf 'FAIL  %s\n' "$name" >&2
    printf '      output: %s\n' "$output" >&2
    exit 1
  }
  printf 'PASS  %s\n' "$name"
}

main_repo="$TMPROOT/main-repo"
feature_repo="$TMPROOT/feature-repo"
outside_dir="$TMPROOT/outside"
mkdir -p "$outside_dir"

make_repo "$main_repo" main
make_repo "$feature_repo" feature/codex-main-edit-hook

tracked_patch='*** Begin Patch
*** Update File: tracked.txt
@@
-tracked
+updated
*** End Patch
'

new_patch='*** Begin Patch
*** Add File: new.txt
+created
*** End Patch
'

ignored_patch='*** Begin Patch
*** Add File: ignored.log
+created
*** End Patch
'

mixed_patch='*** Begin Patch
*** Add File: ignored.log
+created
*** Update File: tracked.txt
@@
-tracked
+updated
*** End Patch
'

empty_patch='*** Begin Patch
*** End Patch
'

run_block_case "blocks tracked patch on main" "$main_repo" "$tracked_patch"
run_block_case "blocks untracked non-ignored patch on main" "$main_repo" "$new_patch"
run_block_case "blocks mixed patch when one path is blocked" "$main_repo" "$mixed_patch"
run_allow_case "allows ignored add-file patch on main" "$main_repo" "$ignored_patch"
run_allow_case "allows tracked patch on feature branch" "$feature_repo" "$tracked_patch"
run_allow_case "allows patch with no recognized file headers" "$main_repo" "$empty_patch"
run_allow_case "allows patch outside a git repo" "$outside_dir" "$tracked_patch"
run_payload_allow_case "allows missing command" '{}'
run_payload_allow_case "allows empty command" '{"tool_name":"apply_patch","tool_input":{"command":""}}'

printf 'PASS  Codex main-branch edit helper test suite\n'
```

- [ ] **Step 2: Run the Codex helper test to verify it fails**

Run:

```bash
bash roles/common/files/bin/codex-block-main-branch-edits.test
```

Expected:

- exits non-zero
- prints `ERROR: .../codex-block-main-branch-edits is not executable (or does not exist)`

- [ ] **Step 3: Write the minimal Codex helper implementation**

Create `roles/common/files/bin/codex-block-main-branch-edits` with this content:

```bash
#!/usr/bin/env bash
set -euo pipefail

reason='File edit blocked on main. Move to a non-main branch/worktree per repo instructions, then retry.'
command="$(jq -r '.tool_input.command // empty' 2>/dev/null || true)"

emit_deny() {
  jq -n --arg reason "$reason" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": $reason
    }
  }'
}

extract_paths() {
  printf '%s\n' "$command" | sed -n -E 's/^\*\*\* (Add|Update|Delete) File: //p' | awk 'length && !seen[$0]++'
}

to_repo_path() {
  local path="$1"

  if [[ "$path" == "$repo_root"/* ]]; then
    printf '%s\n' "${path#$repo_root/}"
  else
    printf '%s\n' "$path"
  fi
}

if [[ -z "$command" ]]; then
  exit 0
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
  exit 0
fi

branch="$(git -C "$repo_root" branch --show-current 2>/dev/null || true)"
if [[ "$branch" != "main" ]]; then
  exit 0
fi

mapfile -t paths < <(extract_paths)
if [ "${#paths[@]}" -eq 0 ]; then
  exit 0
fi

for path in "${paths[@]}"; do
  repo_path="$(to_repo_path "$path")"

  if git -C "$repo_root" ls-files --error-unmatch -- "$repo_path" >/dev/null 2>&1; then
    emit_deny
    exit 0
  fi

  if git -C "$repo_root" check-ignore -q -- "$repo_path" >/dev/null 2>&1; then
    continue
  fi

  emit_deny
  exit 0
done
```

- [ ] **Step 4: Run the Codex helper test to verify it passes**

Run:

```bash
bash roles/common/files/bin/codex-block-main-branch-edits.test
```

Expected:

- exits `0`
- prints `PASS  Codex main-branch edit helper test suite`

- [ ] **Step 5: Commit the Codex helper**

Run:

```bash
git add roles/common/files/bin/codex-block-main-branch-edits roles/common/files/bin/codex-block-main-branch-edits.test
git -c commit.gpgsign=false commit -m "Add Codex main-branch edit hook"
```

Expected:

- one commit containing only the Codex helper and its regression

## Task 3: Wire The Claude Hook Into Provisioning

**Files:**
- Create: `tests/claude-main-edit-hook-provisioning.sh`
- Modify: `roles/common/tasks/main.yml`

- [ ] **Step 1: Write the failing Claude provisioning regression**

Create `tests/claude-main-edit-hook-provisioning.sh` with this content:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
MAIN_YML="$REPO_ROOT/roles/common/tasks/main.yml"
HOOK_FILE="$REPO_ROOT/roles/common/files/claude/hooks/block-main-branch-edits.sh"
HOOK_TASK="Register PreToolUse Edit|MultiEdit|Write hook for blocking main-branch file edits"
MODE_TASK="Enforce 0600 on ~/.claude/settings.json"

pass=0
fail=0

pass_case() {
  pass=$((pass + 1))
  printf 'PASS  %s\n' "$1"
}

fail_case() {
  fail=$((fail + 1))
  printf 'FAIL  %s\n' "$1"
  printf '      %s\n' "$2"
}

assert_eq() {
  local actual="$1" expected="$2" name="$3"

  if [ "$actual" = "$expected" ]; then
    pass_case "$name"
  else
    fail_case "$name" "expected '$expected' but got '$actual'"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" name="$3"

  if printf '%s' "$haystack" | grep -Fq -- "$needle"; then
    pass_case "$name"
  else
    fail_case "$name" "missing '$needle'"
  fi
}

assert_file_exists() {
  local path="$1" name="$2"

  if [ -f "$path" ]; then
    pass_case "$name"
  else
    fail_case "$name" "missing file $path"
  fi
}

assert_task_env() {
  local task_name="$1" key="$2" expected="$3" name="$4"
  local actual

  actual="$(yq -r ".[] | select(.name == \"$task_name\") | .environment.$key // \"\"" "$MAIN_YML" || true)"
  assert_eq "$actual" "$expected" "$name"
}

assert_task_mode() {
  local task_name="$1" expected="$2" name="$3"
  local actual

  actual="$(yq -r ".[] | select(.name == \"$task_name\") | .file.mode // \"\"" "$MAIN_YML" || true)"
  assert_eq "$actual" "$expected" "$name"
}

extract_task_shell() {
  local task_name="$1"

  yq -r ".[] | select(.name == \"$task_name\") | .shell" "$MAIN_YML"
}

run_task_snippet() {
  local snippet="$1" script_path="$2"
  shift 2

  printf '%s\n' "$snippet" > "$script_path"
  chmod 0700 "$script_path"

  set +e
  TASK_OUTPUT="$("$@" "$script_path" 2>&1)"
  TASK_STATUS=$?
  set -e
}

enforce_mode_0600() {
  local path="$1"

  set +e
  MODE_OUTPUT="$(ansible localhost -c local -i localhost, -m file -a "path=$path mode=0600" 2>&1)"
  MODE_STATUS=$?
  set -e
}

assert_mode_0600() {
  local path="$1" name="$2"
  local mode

  case "$(uname -s)" in
    Darwin) mode="$(stat -f '%Lp' "$path")" ;;
    *) mode="$(stat -c '%a' "$path")" ;;
  esac

  assert_eq "$mode" "600" "$name"
}

assert_file_exists "$HOOK_FILE" 'Claude hook helper file exists in repo'
assert_task_env "$HOOK_TASK" 'SETTINGS_FILE' '{{ ansible_facts["user_dir"] }}/.claude/settings.json' 'Claude hook task wires SETTINGS_FILE'
assert_task_mode "$MODE_TASK" '0600' 'Claude settings mode task uses 0600'

HOOK_SNIPPET="$(extract_task_shell "$HOOK_TASK")"
assert_contains "$HOOK_SNIPPET" '~/.claude/hooks/block-main-branch-edits.sh' 'Claude hook task targets the managed helper'
assert_contains "$HOOK_SNIPPET" 'Edit|MultiEdit|Write' 'Claude hook task registers the edit matcher'

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

settings_file="$tmpdir/settings.json"
hook_script="$tmpdir/claude-main-edit-hook-task.sh"

cat > "$settings_file" <<'JSON'
{
  "kept": true,
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "keep-bash"
          }
        ]
      }
    ],
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "notify"
          }
        ]
      }
    ]
  }
}
JSON

run_task_snippet "$HOOK_SNIPPET" "$hook_script" env SETTINGS_FILE="$settings_file" bash
assert_eq "$TASK_STATUS" "0" 'Claude hook task exits cleanly on first run'
assert_contains "$TASK_OUTPUT" 'changed' 'Claude hook task reports change on first run'
assert_eq "$(jq -r '.kept' "$settings_file")" 'true' 'Claude hook task preserves top-level content'
assert_eq "$(jq -r '.hooks.PreToolUse | length' "$settings_file")" '2' 'Claude hook task merges one managed entry'
assert_eq "$(jq -r '[.hooks.PreToolUse[] | select(.matcher == "Edit|MultiEdit|Write" and any(.hooks[]?; .type == "command" and .command == "~/.claude/hooks/block-main-branch-edits.sh"))] | length' "$settings_file")" '1' 'Claude hook task installs the managed command once'
assert_eq "$(jq -r '.hooks.Notification[0].hooks[0].command' "$settings_file")" 'notify' 'Claude hook task preserves unrelated hook groups'

settings_snapshot="$tmpdir/settings.snapshot"
cp "$settings_file" "$settings_snapshot"
chmod 0644 "$settings_file"

run_task_snippet "$HOOK_SNIPPET" "$hook_script" env SETTINGS_FILE="$settings_file" bash
assert_eq "$TASK_STATUS" "0" 'Claude hook task exits cleanly on second run'
assert_contains "$TASK_OUTPUT" 'unchanged' 'Claude hook task reports unchanged on second run'
cmp -s "$settings_snapshot" "$settings_file" \
  && pass_case 'Claude hook task is idempotent on second run' \
  || fail_case 'Claude hook task is idempotent on second run' 'content changed on second run'

enforce_mode_0600 "$settings_file"
assert_eq "$MODE_STATUS" "0" 'Claude settings mode task runs successfully after drift'
assert_mode_0600 "$settings_file" 'Claude settings mode task restores 0600 after drift'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the Claude provisioning test to verify it fails**

Run:

```bash
bash tests/claude-main-edit-hook-provisioning.sh
```

Expected:

- exits non-zero
- reports the missing hook file, missing task env wiring, or missing mode task

- [ ] **Step 3: Update `roles/common/tasks/main.yml` for the Claude hook**

In `roles/common/tasks/main.yml`, insert this task after `Register PreToolUse Bash hook for blocking raw git worktree commands`:

```yaml
- name: Register PreToolUse Edit|MultiEdit|Write hook for blocking main-branch file edits
  shell: |
    set -euo pipefail

    settings_file="${SETTINGS_FILE:?}"
    hook_cmd='~/.claude/hooks/block-main-branch-edits.sh'

    if [ ! -f "$settings_file" ]; then
      echo '{}' > "$settings_file"
    fi

    if jq -e --arg cmd "$hook_cmd" '
      .hooks.PreToolUse // []
      | any(.matcher == "Edit|MultiEdit|Write" and any(.hooks[]?; .type == "command" and .command == $cmd))
    ' "$settings_file" >/dev/null 2>&1; then
      echo "unchanged"
      exit 0
    fi

    managed_entry="$(
      jq -n --arg cmd "$hook_cmd" '{
        matcher: "Edit|MultiEdit|Write",
        hooks: [
          {
            type: "command",
            command: $cmd
          }
        ]
      }'
    )"
    tmp_file="$(mktemp)"

    if [ -f "$settings_file" ] && [ -s "$settings_file" ]; then
      jq --argjson entry "$managed_entry" '
        .hooks //= {} |
        .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [$entry])
      ' "$settings_file" > "$tmp_file"
    else
      jq -n --argjson entry "$managed_entry" '
        {hooks: {PreToolUse: [$entry]}}
      ' > "$tmp_file"
    fi

    mv "$tmp_file" "$settings_file"
    echo "changed"
  args:
    executable: /bin/bash
  environment:
    SETTINGS_FILE: '{{ ansible_facts["user_dir"] }}/.claude/settings.json'
  register: claude_main_edit_hook_result
  changed_when: claude_main_edit_hook_result.stdout.strip() == 'changed'
```

Then add this task after `Register Stop and PermissionRequest hooks to clear working indicator`:

```yaml
- name: Enforce 0600 on ~/.claude/settings.json
  file:
    path: '{{ ansible_facts["user_dir"] }}/.claude/settings.json'
    mode: '0600'
```

- [ ] **Step 4: Run the Claude provisioning regression and helper test**

Run:

```bash
bash roles/common/files/claude/hooks/block-main-branch-edits.sh.test
bash tests/claude-main-edit-hook-provisioning.sh
```

Expected:

- both commands exit `0`
- the helper test prints `PASS  Claude main-branch edit helper test suite`
- the provisioning test ends with `0 failed`

- [ ] **Step 5: Commit the Claude provisioning wiring**

Run:

```bash
git add roles/common/tasks/main.yml tests/claude-main-edit-hook-provisioning.sh
git -c commit.gpgsign=false commit -m "Wire Claude main-branch edit hook"
```

Expected:

- one commit containing only the Claude provisioning changes

## Task 4: Wire The Codex Hook Into Provisioning

**Files:**
- Create: `tests/codex-main-edit-hook-provisioning.sh`
- Modify: `roles/common/tasks/main.yml`

- [ ] **Step 1: Write the failing Codex provisioning regression**

Create `tests/codex-main-edit-hook-provisioning.sh` with this content:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
MAIN_YML="$REPO_ROOT/roles/common/tasks/main.yml"
HOOK_TASK="Merge managed Codex main-branch edit hook into ~/.codex/hooks.json"
HOOKS_MODE_TASK="Enforce 0600 on ~/.codex/hooks.json"

pass=0
fail=0

pass_case() {
  pass=$((pass + 1))
  printf 'PASS  %s\n' "$1"
}

fail_case() {
  fail=$((fail + 1))
  printf 'FAIL  %s\n' "$1"
  printf '      %s\n' "$2"
}

assert_eq() {
  local actual="$1" expected="$2" name="$3"

  if [ "$actual" = "$expected" ]; then
    pass_case "$name"
  else
    fail_case "$name" "expected '$expected' but got '$actual'"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" name="$3"

  if printf '%s' "$haystack" | grep -Fq -- "$needle"; then
    pass_case "$name"
  else
    fail_case "$name" "missing '$needle'"
  fi
}

assert_task_env() {
  local task_name="$1" key="$2" expected="$3" name="$4"
  local actual

  actual="$(yq -r ".[] | select(.name == \"$task_name\") | .environment.$key // \"\"" "$MAIN_YML" || true)"
  assert_eq "$actual" "$expected" "$name"
}

assert_task_mode() {
  local task_name="$1" expected="$2" name="$3"
  local actual

  actual="$(yq -r ".[] | select(.name == \"$task_name\") | .file.mode // \"\"" "$MAIN_YML" || true)"
  assert_eq "$actual" "$expected" "$name"
}

assert_task_loop_member() {
  local task_name="$1" member="$2" expected="$3" name="$4"
  local actual

  actual="$(yq -r ".[] | select(.name == \"$task_name\") | .loop[]?.name" "$MAIN_YML" | awk -v member="$member" '$0 == member {count++} END {print count + 0}')"
  assert_eq "$actual" "$expected" "$name"
}

extract_task_shell() {
  local task_name="$1"

  yq -r ".[] | select(.name == \"$task_name\") | .shell" "$MAIN_YML"
}

run_task_snippet() {
  local snippet="$1" script_path="$2"
  shift 2

  printf '%s\n' "$snippet" > "$script_path"
  chmod 0700 "$script_path"

  set +e
  TASK_OUTPUT="$("$@" "$script_path" 2>&1)"
  TASK_STATUS=$?
  set -e
}

enforce_mode_0600() {
  local path="$1"

  set +e
  MODE_OUTPUT="$(ansible localhost -c local -i localhost, -m file -a "path=$path mode=0600" 2>&1)"
  MODE_STATUS=$?
  set -e
}

assert_mode_0600() {
  local path="$1" name="$2"
  local mode

  case "$(uname -s)" in
    Darwin) mode="$(stat -f '%Lp' "$path")" ;;
    *) mode="$(stat -c '%a' "$path")" ;;
  esac

  assert_eq "$mode" "600" "$name"
}

assert_task_loop_member "Install worktree helpers" "codex-block-main-branch-edits" "1" 'worktree helper install loop includes codex-block-main-branch-edits'
assert_task_env "$HOOK_TASK" 'HOOKS_FILE' '{{ ansible_facts["user_dir"] }}/.codex/hooks.json' 'Codex hook task wires HOOKS_FILE'
assert_task_mode "$HOOKS_MODE_TASK" '0600' 'Codex hooks mode task uses 0600'

HOOK_SNIPPET="$(extract_task_shell "$HOOK_TASK")"
assert_contains "$HOOK_SNIPPET" '~/.local/bin/codex-block-main-branch-edits' 'Codex hook task targets the managed helper'
assert_contains "$HOOK_SNIPPET" 'apply_patch|Edit|Write' 'Codex hook task registers the native edit matcher'

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

hooks_script="$tmpdir/codex-main-edit-hook-task.sh"
hooks_file="$tmpdir/hooks.json"

cat > "$hooks_file" <<'JSON'
{
  "kept": true,
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Python",
        "hooks": [
          {
            "type": "command",
            "command": "keep-python"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "keep-bash"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "notify"
          }
        ]
      }
    ]
  }
}
JSON

run_task_snippet "$HOOK_SNIPPET" "$hooks_script" env HOOKS_FILE="$hooks_file" bash
assert_eq "$TASK_STATUS" "0" 'Codex hook task exits cleanly on first run'
assert_contains "$TASK_OUTPUT" 'changed' 'Codex hook task reports change on first run'
assert_eq "$(jq -r '.kept' "$hooks_file")" 'true' 'Codex hook task preserves top-level content'
assert_eq "$(jq -r '.hooks.PreToolUse | length' "$hooks_file")" '3' 'Codex hook task merges one managed entry'
assert_eq "$(jq -r '[.hooks.PreToolUse[] | select(.matcher == "apply_patch|Edit|Write" and any(.hooks[]?; .type == "command" and .command == "~/.local/bin/codex-block-main-branch-edits"))] | length' "$hooks_file")" '1' 'Codex hook task installs the managed command once'
assert_eq "$(jq -r '.hooks.Notification[0].hooks[0].command' "$hooks_file")" 'notify' 'Codex hook task preserves unrelated hook groups'
assert_mode_0600 "$hooks_file" 'Codex hook task writes 0600 on creation'

hooks_snapshot="$tmpdir/hooks.snapshot"
cp "$hooks_file" "$hooks_snapshot"
chmod 0644 "$hooks_file"

run_task_snippet "$HOOK_SNIPPET" "$hooks_script" env HOOKS_FILE="$hooks_file" bash
assert_eq "$TASK_STATUS" "0" 'Codex hook task exits cleanly on second run'
assert_contains "$TASK_OUTPUT" 'unchanged' 'Codex hook task reports unchanged on second run'
cmp -s "$hooks_snapshot" "$hooks_file" \
  && pass_case 'Codex hook task is idempotent on second run' \
  || fail_case 'Codex hook task is idempotent on second run' 'content changed on second run'

enforce_mode_0600 "$hooks_file"
assert_eq "$MODE_STATUS" "0" 'Codex hooks mode task runs successfully after drift'
assert_mode_0600 "$hooks_file" 'Codex hooks mode task restores 0600 after drift'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the Codex provisioning test to verify it fails**

Run:

```bash
bash tests/codex-main-edit-hook-provisioning.sh
```

Expected:

- exits non-zero
- reports the missing install-loop member or missing hook merge task

- [ ] **Step 3: Update `roles/common/tasks/main.yml` for the Codex hook**

In the `Install worktree helpers` loop, add this item:

```yaml
    - { name: codex-block-main-branch-edits, mode: '0755' }
```

Then insert this task after `Merge managed Codex push-to-main hook into ~/.codex/hooks.json`:

```yaml
- name: Merge managed Codex main-branch edit hook into ~/.codex/hooks.json
  shell: |
    set -euo pipefail

    hooks_file="${HOOKS_FILE:?}"
    managed_command='~/.local/bin/codex-block-main-branch-edits'

    if [ -f "$hooks_file" ] && jq -e --arg cmd "$managed_command" '
      .hooks.PreToolUse // []
      | any(.matcher == "apply_patch|Edit|Write" and any(.hooks[]?; .type == "command" and .command == $cmd))
    ' "$hooks_file" >/dev/null 2>&1; then
      echo "unchanged"
      exit 0
    fi

    managed_entry="$(
      jq -n --arg cmd "$managed_command" '{
        matcher: "apply_patch|Edit|Write",
        hooks: [
          {
            type: "command",
            command: $cmd
          }
        ]
      }'
    )"
    tmp_file="$(mktemp)"

    if [ -f "$hooks_file" ] && [ -s "$hooks_file" ]; then
      jq --argjson entry "$managed_entry" '
        .hooks //= {} |
        .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [$entry])
      ' "$hooks_file" > "$tmp_file"
    else
      jq -n --argjson entry "$managed_entry" '
        {hooks: {PreToolUse: [$entry]}}
      ' > "$tmp_file"
    fi

    mv "$tmp_file" "$hooks_file"
    chmod 600 "$hooks_file"
    echo "changed"
  args:
    executable: /bin/bash
  environment:
    HOOKS_FILE: '{{ ansible_facts["user_dir"] }}/.codex/hooks.json'
  register: codex_main_edit_hooks_json_result
  changed_when: codex_main_edit_hooks_json_result.stdout.strip() == 'changed'
```

- [ ] **Step 4: Run the Codex provisioning regression and helper test**

Run:

```bash
bash roles/common/files/bin/codex-block-main-branch-edits.test
bash tests/codex-main-edit-hook-provisioning.sh
```

Expected:

- both commands exit `0`
- the helper test prints `PASS  Codex main-branch edit helper test suite`
- the provisioning test ends with `0 failed`

- [ ] **Step 5: Commit the Codex provisioning wiring**

Run:

```bash
git add roles/common/tasks/main.yml tests/codex-main-edit-hook-provisioning.sh
git -c commit.gpgsign=false commit -m "Wire Codex main-branch edit hook"
```

Expected:

- one commit containing only the Codex provisioning changes

## Task 5: Full Verification And Live Provision Smoke

**Files:**
- Modify: none

- [ ] **Step 1: Run the full regression set**

Run:

```bash
bash roles/common/files/claude/hooks/block-main-branch-edits.sh.test
bash roles/common/files/bin/codex-block-main-branch-edits.test
bash tests/claude-main-edit-hook-provisioning.sh
bash tests/codex-main-edit-hook-provisioning.sh
```

Expected:

- all four commands exit `0`
- each test suite prints its final `PASS ... suite` line or `0 failed`

- [ ] **Step 2: Provision the live machine config**

Run:

```bash
bin/provision
```

Expected:

- exits `0`
- installs the new helpers into `~/.claude/hooks/` and `~/.local/bin/`
- updates `~/.claude/settings.json` and `~/.codex/hooks.json`

- [ ] **Step 3: Verify the live hook registrations**

Run:

```bash
jq '[.hooks.PreToolUse[] | select(.matcher == "Edit|MultiEdit|Write")] | length' ~/.claude/settings.json
jq '[.hooks.PreToolUse[] | select(.matcher == "apply_patch|Edit|Write")] | length' ~/.codex/hooks.json
```

Expected:

- first command prints `1`
- second command prints `1`

- [ ] **Step 4: Smoke-test the installed Claude helper on a tracked file**

Run:

```bash
jq -n --arg file "$PWD/CLAUDE.md" '{
  tool_name: "Write",
  tool_input: {
    file_path: $file,
    content: "blocked"
  }
}' | ~/.claude/hooks/block-main-branch-edits.sh | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
```

Expected:

- exits `0`
- `jq` confirms the installed hook returns a deny decision on `main`

- [ ] **Step 5: Smoke-test the installed Codex helper on blocked and allowed paths**

Run:

```bash
jq -n --arg command "$(cat <<'EOF'
*** Begin Patch
*** Update File: CLAUDE.md
@@
-old
+new
*** End Patch
EOF
)" '{tool_name:"apply_patch",tool_input:{command:$command}}' | ~/.local/bin/codex-block-main-branch-edits | jq -e '.hookSpecificOutput.permissionDecision == "deny"'

jq -n --arg command "$(cat <<'EOF'
*** Begin Patch
*** Add File: tmp/main-edit-hook-smoke.log
+ok
*** End Patch
EOF
)" '{tool_name:"apply_patch",tool_input:{command:$command}}' | ~/.local/bin/codex-block-main-branch-edits > /tmp/codex-main-edit-hook-allow.out
[ ! -s /tmp/codex-main-edit-hook-allow.out ]
```

Expected:

- first command exits `0` and confirms a deny decision
- second command exits `0` and confirms the ignored-file case is allowed

## Self-Review Checklist

- Spec coverage: Claude helper, Codex helper, tracked/unignored deny rules, ignored-file allow rule, payload-shape handling, provisioning wiring, `0600` enforcement, and live verification all map to explicit tasks above.
- Placeholder scan: no `TODO`, `TBD`, or implicit "write tests later" steps remain.
- Type consistency: Claude uses `tool_input.file_path`; Codex uses `tool_input.command` plus `*** Add/Update/Delete File:` headers; matcher strings stay consistent across tests and YAML snippets.
