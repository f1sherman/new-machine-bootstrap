# Codex Push-to-Main Hook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Codex `PreToolUse` hook helper plus provisioning so Codex denies direct pushes to `main` and tells the agent to open a PR instead.

**Architecture:** Follow the existing Codex worktree-hook pattern already in this repo: a dedicated helper executable under `roles/common/files/bin/`, a helper-local shell test beside it, and a repo-level provisioning regression under `tests/`. Keep the push-to-`main` policy separate from the worktree blocker, then install and merge it into `~/.codex/hooks.json` with a second Ansible task in `roles/common/tasks/main.yml`.

**Tech Stack:** Bash, jq, git, Ansible, yq, Codex CLI hooks.

---

## File Structure

### New files

- `roles/common/files/bin/codex-block-git-push-main`
  Codex hook helper that denies direct pushes to `main`.
- `roles/common/files/bin/codex-block-git-push-main.test`
  Shell regression harness for helper input/output behavior, including real git branch-state checks.
- `tests/codex-push-main-hook-provisioning.sh`
  Repo-level regression for Ansible install/merge behavior and `hooks.json` idempotence.

### Modified files

- `roles/common/tasks/main.yml`
  Install the new helper into `~/.local/bin/` and merge the managed Codex hook entry into `~/.codex/hooks.json`.

## Task 1: Add The Hook Helper And Its Red/Green Regression

**Files:**
- Create: `roles/common/files/bin/codex-block-git-push-main`
- Create: `roles/common/files/bin/codex-block-git-push-main.test`

- [ ] **Step 1: Write the failing helper regression**

Create `roles/common/files/bin/codex-block-git-push-main.test` with this content:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/codex-block-git-push-main"
REASON='Do not push to main directly. Open a PR.'

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

  git init -qb main "$path" >/dev/null
  git -C "$path" commit -q --allow-empty -m init
  if [ "$branch" != "main" ]; then
    git -C "$path" checkout -qb "$branch" >/dev/null
  fi
}

run_block_case() {
  local name="$1"
  local repo="$2"
  local command="$3"
  local output

  output="$(cd "$repo" && jq -n --arg command "$command" '{tool_input:{command:$command}}' | "$SCRIPT")"
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

  output="$(cd "$repo" && jq -n --arg command "$command" '{tool_input:{command:$command}}' | "$SCRIPT")"
  [ -z "$output" ] || {
    printf 'FAIL  %s\n' "$name" >&2
    printf '      output: %s\n' "$output" >&2
    exit 1
  }
  printf 'PASS  %s\n' "$name"
}

run_empty_case() {
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
make_repo "$main_repo" main
make_repo "$feature_repo" feature/push-guard

run_block_case "blocks explicit origin main" "$feature_repo" 'git push origin main'
run_block_case "blocks explicit HEAD:main" "$feature_repo" 'git push upstream HEAD:main'
run_block_case "blocks explicit refs/heads/main destination" "$feature_repo" 'git push origin HEAD:refs/heads/main'
run_block_case "blocks bare push on local main" "$main_repo" 'git push'
run_block_case "blocks remote-only push on local main" "$main_repo" 'git push origin'
run_block_case "blocks chained push segment" "$feature_repo" 'cd repo && git push origin main'
run_allow_case "allows feature branch remote push" "$feature_repo" 'git push origin'
run_allow_case "allows explicit feature refspec from main" "$main_repo" 'git push origin feature/push-guard'
run_allow_case "allows non-push commands" "$main_repo" 'git status --short'
run_allow_case "allows plain text mention of push" "$main_repo" 'echo git push origin main'
run_empty_case "allows missing command" '{}'
run_empty_case "allows empty command" '{"tool_input":{"command":""}}'

printf 'PASS  push-to-main helper test suite\n'
```

- [ ] **Step 2: Run the helper test to verify it fails**

Run:

```bash
bash roles/common/files/bin/codex-block-git-push-main.test
```

Expected:

- exits non-zero
- prints `ERROR: .../codex-block-git-push-main is not executable (or does not exist)`

- [ ] **Step 3: Write the minimal helper implementation**

Create `roles/common/files/bin/codex-block-git-push-main` with this content:

```bash
#!/usr/bin/env bash
set -euo pipefail

reason='Do not push to main directly. Open a PR.'
command="$(jq -r '.tool_input.command // empty' 2>/dev/null || true)"

if [[ -z "$command" ]]; then
  exit 0
fi

emit_deny() {
  jq -n --arg reason "$reason" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": $reason
    }
  }'
}

tokenize_command() {
  COMMAND="$command" python3 - <<'PY'
import os
import shlex
import sys

lexer = shlex.shlex(
    os.environ["COMMAND"],
    posix=True,
    punctuation_chars=';&|()',
)
lexer.whitespace_split = True

for token in lexer:
    sys.stdout.buffer.write(token.encode())
    sys.stdout.buffer.write(b"\0")
PY
}

is_separator() {
  case "$1" in
    ';'|'&&'|'||'|'|'|'('|')') return 0 ;;
    *) return 1 ;;
  esac
}

segment_targets_main() {
  local token count

  count="${#positionals[@]}"
  if (( count >= 2 )); then
    case "${positionals[1]}" in
      main|refs/heads/main) return 0 ;;
    esac
  fi

  for token in "${positionals[@]}"; do
    case "$token" in
      :main|:refs/heads/main|*:main|*:refs/heads/main) return 0 ;;
    esac
  done

  return 1
}

current_branch_is_main() {
  [[ "$(git branch --show-current 2>/dev/null || true)" == "main" ]]
}

mapfile -d '' -t tokens < <(tokenize_command)

i=0
while (( i < ${#tokens[@]} )); do
  if is_separator "${tokens[i]}"; then
    ((i += 1))
    continue
  fi

  while (( i < ${#tokens[@]} )); do
    case "${tokens[i]}" in
      *=*|command|env) ((i += 1)) ;;
      *) break ;;
    esac
  done

  [[ "${tokens[i]:-}" == "git" ]] || {
    while (( i < ${#tokens[@]} )) && ! is_separator "${tokens[i]}"; do
      ((i += 1))
    done
    continue
  }
  ((i += 1))

  while (( i < ${#tokens[@]} )) && [[ "${tokens[i]}" == -* ]]; do
    case "${tokens[i]}" in
      -C|-c|--git-dir|--work-tree)
        ((i += 2))
        ;;
      *)
        ((i += 1))
        ;;
    esac
  done

  [[ "${tokens[i]:-}" == "push" ]] || {
    while (( i < ${#tokens[@]} )) && ! is_separator "${tokens[i]}"; do
      ((i += 1))
    done
    continue
  }
  ((i += 1))

  positionals=()
  while (( i < ${#tokens[@]} )) && ! is_separator "${tokens[i]}"; do
    if [[ "${tokens[i]}" != -* ]]; then
      positionals+=("${tokens[i]}")
    fi
    ((i += 1))
  done

  if segment_targets_main; then
    emit_deny
    exit 0
  fi

  if current_branch_is_main && (( ${#positionals[@]} <= 1 )); then
    emit_deny
    exit 0
  fi
done

exit 0
```

- [ ] **Step 4: Run the helper regression to verify it passes**

Run:

```bash
bash roles/common/files/bin/codex-block-git-push-main.test
```

Expected:

- every case prints `PASS`
- final line is `PASS  push-to-main helper test suite`

- [ ] **Step 5: Commit the helper change**

Run:

```bash
git add roles/common/files/bin/codex-block-git-push-main roles/common/files/bin/codex-block-git-push-main.test
git commit -m "feat: add Codex push-to-main hook helper"
```

Expected:

- one commit containing only the new helper and its test

## Task 2: Provision The Helper And Lock In Hook Merge Behavior

**Files:**
- Modify: `roles/common/tasks/main.yml`
- Create: `tests/codex-push-main-hook-provisioning.sh`
- Test: `roles/common/files/bin/codex-block-git-push-main.test`

- [ ] **Step 1: Write the failing provisioning regression**

Create `tests/codex-push-main-hook-provisioning.sh` with this content:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
MAIN_YML="$REPO_ROOT/roles/common/tasks/main.yml"
HOOKS_TASK="Merge managed Codex push-to-main hook into ~/.codex/hooks.json"
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

assert_mode_0600() {
  local path="$1" name="$2" actual

  actual="$(python3 - "$path" <<'PY'
import os
import sys

print(oct(os.stat(sys.argv[1]).st_mode & 0o777))
PY
)"
  assert_eq "$actual" "0o600" "$name"
}

assert_task_env() {
  local task_name="$1" key="$2" expected="$3" name="$4"
  local actual

  actual="$(yq -r ".[] | select(.name == \"$task_name\") | .environment.$key // \"\"" "$MAIN_YML" || true)"
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

assert_contains "$(sed -n '120,145p' "$MAIN_YML")" 'codex-block-git-push-main' 'install loop includes push-to-main helper'
assert_task_env "$HOOKS_TASK" 'HOOKS_FILE' '{{ ansible_facts["user_dir"] }}/.codex/hooks.json' 'push hook task wires HOOKS_FILE'

HOOKS_SNIPPET="$(extract_task_shell "$HOOKS_TASK")"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
hooks_script="$tmpdir/codex-push-main-hooks-task.sh"
hooks_file="$tmpdir/hooks.json"

cat > "$hooks_file" <<'JSON'
{
  "kept": true,
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.local/bin/codex-block-worktree-commands"
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

run_task_snippet "$HOOKS_SNIPPET" "$hooks_script" env HOOKS_FILE="$hooks_file" bash
assert_eq "$TASK_STATUS" "0" 'push hook task exits cleanly on first run'
assert_contains "$TASK_OUTPUT" 'changed' 'push hook task reports change on first run'
assert_eq "$(jq -r '.kept' "$hooks_file")" 'true' 'push hook task preserves top-level content'
assert_eq "$(jq -r '.hooks.PreToolUse | length' "$hooks_file")" '2' 'push hook task appends one managed entry'
assert_eq "$(jq -r '[.hooks.PreToolUse[] | select(.matcher == "Bash" and any(.hooks[]?; .type == "command" and .command == "~/.local/bin/codex-block-git-push-main"))] | length' "$hooks_file")" '1' 'push hook task installs managed command once'
assert_eq "$(jq -r '.hooks.Notification[0].hooks[0].command' "$hooks_file")" 'notify' 'push hook task preserves unrelated hook groups'
assert_mode_0600 "$hooks_file" 'push hook task writes 0600 on create'

hooks_snapshot="$tmpdir/hooks.snapshot"
cp "$hooks_file" "$hooks_snapshot"
chmod 0644 "$hooks_file"
run_task_snippet "$HOOKS_SNIPPET" "$hooks_script" env HOOKS_FILE="$hooks_file" bash
assert_eq "$TASK_STATUS" "0" 'push hook task exits cleanly on second run'
assert_contains "$TASK_OUTPUT" 'unchanged' 'push hook task reports unchanged on second run'
cmp -s "$hooks_snapshot" "$hooks_file" \
  && pass_case 'push hook task is idempotent on second run' \
  || fail_case 'push hook task is idempotent on second run' 'content changed on second run'

enforce_mode_0600 "$hooks_file"
assert_eq "$MODE_STATUS" "0" 'hooks mode task runs successfully after drift'
assert_mode_0600 "$hooks_file" 'hooks mode task restores 0600 after drift'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the provisioning regression to verify it fails**

Run:

```bash
bash tests/codex-push-main-hook-provisioning.sh
```

Expected:

- exits non-zero
- fails on the missing helper install entry and missing `Merge managed Codex push-to-main hook into ~/.codex/hooks.json` task

- [ ] **Step 3: Update Ansible installation and hook merge**

Modify `roles/common/tasks/main.yml`.

In the `Install worktree helpers` loop, add the new helper:

```yaml
  loop:
    - { name: worktree-lib.sh, mode: '0644' }
    - { name: worktree-start, mode: '0755' }
    - { name: worktree-delete, mode: '0755' }
    - { name: worktree-merge, mode: '0755' }
    - { name: worktree-done, mode: '0755' }
    - { name: codex-block-worktree-commands, mode: '0755' }
    - { name: codex-block-git-push-main, mode: '0755' }
```

After `Merge managed Codex worktree hook into ~/.codex/hooks.json`, add this task:

```yaml
- name: Merge managed Codex push-to-main hook into ~/.codex/hooks.json
  shell: |
    set -euo pipefail

    hooks_file="${HOOKS_FILE:?}"
    managed_command='~/.local/bin/codex-block-git-push-main'

    if [ -f "$hooks_file" ] && jq -e --arg cmd "$managed_command" '
      .hooks.PreToolUse // []
      | any(.matcher == "Bash" and any(.hooks[]?; .type == "command" and .command == $cmd))
    ' "$hooks_file" >/dev/null 2>&1; then
      echo "unchanged"
      exit 0
    fi

    managed_entry="$(
      jq -n --arg cmd "$managed_command" '{
        matcher: "Bash",
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
  register: codex_push_main_hooks_json_result
  changed_when: codex_push_main_hooks_json_result.stdout.strip() == 'changed'
```

- [ ] **Step 4: Run helper, provisioning, and smoke checks to verify green behavior**

Run:

```bash
bash roles/common/files/bin/codex-block-git-push-main.test
bash tests/codex-push-main-hook-provisioning.sh
REPO_ROOT="$(git rev-parse --show-toplevel)"
tmpdir="$(mktemp -d)"
git init -qb main "$tmpdir/repo"
git -C "$tmpdir/repo" -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m init
(
  cd "$tmpdir/repo"
  jq -n --arg command 'git push' '{tool_input:{command:$command}}' \
    | "$REPO_ROOT/roles/common/files/bin/codex-block-git-push-main"
) | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
rm -rf "$tmpdir"
```

Expected:

- both shell test suites print only `PASS` lines
- the smoke check exits `0`
- the final `jq -e` command prints `true`

- [ ] **Step 5: Commit the provisioning integration**

Run:

```bash
git add roles/common/tasks/main.yml tests/codex-push-main-hook-provisioning.sh
git commit -m "feat: provision Codex push-to-main hook"
```

Expected:

- one commit containing the Ansible integration and provisioning regression
