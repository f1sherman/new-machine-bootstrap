#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
MAIN_YML="$REPO_ROOT/roles/common/tasks/main.yml"
CONFIG_TASK="Enable Codex hooks in ~/.codex/config.toml"
HOOKS_TASK="Merge managed Codex worktree hook into ~/.codex/hooks.json"
CONFIG_MODE_TASK="Enforce 0600 on ~/.codex/config.toml"
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

assert_file_contains() {
  local path="$1" needle="$2" name="$3"

  if grep -Fq -- "$needle" "$path"; then
    pass_case "$name"
  else
    fail_case "$name" "missing '$needle' in $path"
  fi
}

assert_regex_count() {
  local path="$1" pattern="$2" expected="$3" name="$4"
  local actual

  actual="$(grep -Ec -- "$pattern" "$path" || true)"
  assert_eq "$actual" "$expected" "$name"
}

assert_mode_0600() {
  local path="$1" name="$2" actual

  actual="$(python3 - "$path" <<'PY'
import os
import stat
import sys

print(oct(os.stat(sys.argv[1]).st_mode & 0o777))
PY
)"
  assert_eq "$actual" "0o600" "$name"
}

assert_task_mode() {
  local task_name="$1" expected="$2" name="$3"
  local actual

  actual="$(yq -r ".[] | select(.name == \"$task_name\") | .file.mode // \"\"" "$MAIN_YML" || true)"
  assert_eq "$actual" "$expected" "$name"
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

assert_task_mode "$CONFIG_MODE_TASK" '0600' 'config mode task uses 0600'
assert_task_mode "$HOOKS_MODE_TASK" '0600' 'hooks mode task uses 0600'
assert_task_env "$CONFIG_TASK" 'CONFIG_FILE' '{{ ansible_facts["user_dir"] }}/.codex/config.toml' 'config task wires CONFIG_FILE'
assert_task_env "$HOOKS_TASK" 'HOOKS_FILE' '{{ ansible_facts["user_dir"] }}/.codex/hooks.json' 'hooks task wires HOOKS_FILE'

CONFIG_SNIPPET="$(extract_task_shell "$CONFIG_TASK")"
HOOKS_SNIPPET="$(extract_task_shell "$HOOKS_TASK")"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

config_script="$tmpdir/codex-config-task.sh"
hooks_script="$tmpdir/codex-hooks-task.sh"

config_file="$tmpdir/config.toml"
printf '[core]\nfoo = true\n' > "$config_file"
run_task_snippet "$CONFIG_SNIPPET" "$config_script" env CONFIG_FILE="$config_file" bash
assert_eq "$TASK_STATUS" "0" 'config task exits cleanly without features section'
assert_contains "$TASK_OUTPUT" 'changed' 'config task reports change without features section'
assert_regex_count "$config_file" '^\[features\]([[:space:]]*[#;].*)?$' 1 'config task creates one features table'
assert_regex_count "$config_file" '^codex_hooks = true$' 1 'config task inserts codex_hooks once'
assert_file_contains "$config_file" '[core]' 'config task preserves existing content'
assert_file_contains "$config_file" 'foo = true' 'config task preserves existing keys'
assert_mode_0600 "$config_file" 'config task writes 0600 on creation'

config_file_comment="$tmpdir/config-comment.toml"
printf '[features] # comment\ncodex_hooks = false\nother = true\n' > "$config_file_comment"
run_task_snippet "$CONFIG_SNIPPET" "$config_script" env CONFIG_FILE="$config_file_comment" bash
assert_eq "$TASK_STATUS" "0" 'config task exits cleanly with commented features header'
assert_contains "$TASK_OUTPUT" 'changed' 'config task updates commented features header'
assert_regex_count "$config_file_comment" '^\[features\]([[:space:]]*[#;].*)?$' 1 'config task keeps one commented features table'
assert_file_contains "$config_file_comment" '[features] # comment' 'config task preserves inline comment on features header'
assert_regex_count "$config_file_comment" '^codex_hooks = true$' 1 'config task normalizes codex_hooks to true'
assert_file_contains "$config_file_comment" 'other = true' 'config task preserves section body'

config_file_false="$tmpdir/config-false.toml"
printf '[features]\ncodex_hooks = false\nother = 1\n' > "$config_file_false"
run_task_snippet "$CONFIG_SNIPPET" "$config_script" env CONFIG_FILE="$config_file_false" bash
assert_eq "$TASK_STATUS" "0" 'config task exits cleanly with false feature value'
assert_contains "$TASK_OUTPUT" 'changed' 'config task updates false feature value'
assert_regex_count "$config_file_false" '^\[features\]([[:space:]]*[#;].*)?$' 1 'config task keeps one plain features table'
assert_regex_count "$config_file_false" '^codex_hooks = true$' 1 'config task replaces false value'
assert_file_contains "$config_file_false" 'other = 1' 'config task preserves other settings'
config_false_snapshot="$tmpdir/config-false.snapshot"
cp "$config_file_false" "$config_false_snapshot"
chmod 0644 "$config_file_false"
run_task_snippet "$CONFIG_SNIPPET" "$config_script" env CONFIG_FILE="$config_file_false" bash
assert_eq "$TASK_STATUS" "0" 'config task exits cleanly on second run'
assert_contains "$TASK_OUTPUT" 'unchanged' 'config task reports unchanged on second run'
cmp -s "$config_false_snapshot" "$config_file_false" \
  && pass_case 'config task is idempotent on second run' \
  || fail_case 'config task is idempotent on second run' 'content changed on second run'
enforce_mode_0600 "$config_file_false"
assert_eq "$MODE_STATUS" "0" 'config mode task runs successfully after drift'
assert_mode_0600 "$config_file_false" 'config mode task restores 0600 after drift'

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
            "command": "keep-this"
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
assert_eq "$TASK_STATUS" "0" 'hooks task exits cleanly on first run'
assert_contains "$TASK_OUTPUT" 'changed' 'hooks task reports change on first run'
assert_eq "$(jq -r '.kept' "$hooks_file")" 'true' 'hooks task preserves top-level content'
assert_eq "$(jq -r '.hooks.PreToolUse | length' "$hooks_file")" '2' 'hooks task merges one managed entry'
assert_eq "$(jq -r '[.hooks.PreToolUse[] | select(.matcher == "Bash")] | length' "$hooks_file")" '1' 'hooks task adds one Bash matcher entry'
assert_eq "$(jq -r '[.hooks.PreToolUse[] | select(.matcher == "Bash" and any(.hooks[]?; .type == "command" and .command == "~/.local/bin/codex-block-worktree-commands"))] | length' "$hooks_file")" '1' 'hooks task installs the managed command once'
assert_eq "$(jq -r '.hooks.Notification[0].hooks[0].command' "$hooks_file")" 'notify' 'hooks task preserves unrelated hook groups'
assert_mode_0600 "$hooks_file" 'hooks task writes 0600 on creation'
hooks_snapshot="$tmpdir/hooks.snapshot"
cp "$hooks_file" "$hooks_snapshot"
chmod 0644 "$hooks_file"
run_task_snippet "$HOOKS_SNIPPET" "$hooks_script" env HOOKS_FILE="$hooks_file" bash
assert_eq "$TASK_STATUS" "0" 'hooks task exits cleanly on second run'
assert_contains "$TASK_OUTPUT" 'unchanged' 'hooks task reports unchanged on second run'
cmp -s "$hooks_snapshot" "$hooks_file" \
  && pass_case 'hooks task is idempotent on second run' \
  || fail_case 'hooks task is idempotent on second run' 'content changed on second run'
enforce_mode_0600 "$hooks_file"
assert_eq "$MODE_STATUS" "0" 'hooks mode task runs successfully after drift'
assert_mode_0600 "$hooks_file" 'hooks mode task restores 0600 after drift'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
