#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
MAIN_YML="$REPO_ROOT/roles/common/tasks/main.yml"
HOOK_TASK="Merge managed Codex pane session hook into ~/.codex/hooks.json"
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

assert_mode_0600() {
  local path="$1" name="$2" mode

  case "$(uname -s)" in
    Darwin) mode="$(stat -f '%Lp' "$path")" ;;
    *) mode="$(stat -c '%a' "$path")" ;;
  esac

  assert_eq "$mode" "600" "$name"
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

assert_task_loop_member "Install worktree helpers" "codex-bind-tmux-pane" "1" 'worktree helper install loop includes codex-bind-tmux-pane'
assert_task_env "$HOOK_TASK" 'HOOKS_FILE' '{{ ansible_facts["user_dir"] }}/.codex/hooks.json' 'pane session hook task wires HOOKS_FILE'
assert_task_mode "$HOOKS_MODE_TASK" '0600' 'hooks mode task uses 0600'

HOOK_SNIPPET="$(extract_task_shell "$HOOK_TASK")"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

hooks_script="$tmpdir/codex-pane-hooks-task.sh"
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
            "command": "keep-bash"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "clear",
        "hooks": [
          {
            "type": "command",
            "command": "keep-clear"
          }
        ]
      }
    ]
  }
}
JSON

run_task_snippet "$HOOK_SNIPPET" "$hooks_script" env HOOKS_FILE="$hooks_file" bash
assert_eq "$TASK_STATUS" "0" 'pane session hook task exits cleanly on first run'
assert_contains "$TASK_OUTPUT" 'changed' 'pane session hook task reports change on first run'
assert_eq "$(jq -r '.kept' "$hooks_file")" 'true' 'pane session hook task preserves top-level content'
assert_eq "$(jq -r '.hooks.SessionStart | length' "$hooks_file")" '2' 'pane session hook task merges one SessionStart entry'
assert_eq "$(jq -r '[.hooks.SessionStart[] | select(.matcher == "startup|resume" and any(.hooks[]?; .type == "command" and .command == "~/.local/bin/codex-bind-tmux-pane" and .timeout == 5))] | length' "$hooks_file")" '1' 'pane session hook task installs the managed command once'
assert_eq "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$hooks_file")" 'keep-bash' 'pane session hook task preserves unrelated hook groups'
assert_mode_0600 "$hooks_file" 'pane session hook task writes 0600 on creation'

hooks_snapshot="$tmpdir/hooks.snapshot"
cp "$hooks_file" "$hooks_snapshot"
chmod 0644 "$hooks_file"

run_task_snippet "$HOOK_SNIPPET" "$hooks_script" env HOOKS_FILE="$hooks_file" bash
assert_eq "$TASK_STATUS" "0" 'pane session hook task exits cleanly on second run'
assert_contains "$TASK_OUTPUT" 'unchanged' 'pane session hook task reports unchanged on second run'
cmp -s "$hooks_snapshot" "$hooks_file" \
  && pass_case 'pane session hook task is idempotent on second run' \
  || fail_case 'pane session hook task is idempotent on second run' 'content changed on second run'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
