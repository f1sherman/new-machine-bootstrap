#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
MAIN_YML="$REPO_ROOT/roles/common/tasks/main.yml"
TASK="Set Codex CLI model defaults in ~/.codex/config.toml"
CONFIG_MODE_TASK="Enforce 0600 on ~/.codex/config.toml"

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

  actual="$(ruby -e 'mode = File.stat(ARGV[0]).mode & 0o777; puts "0o#{mode.to_s(8)}"' "$path")"
  assert_eq "$actual" "0o600" "$name"
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

assert_line_before_first_table() {
  local path="$1" pattern="$2" name="$3"
  local line_number first_table_line

  line_number="$(grep -En -- "$pattern" "$path" | head -n 1 | cut -d: -f1 || true)"
  first_table_line="$(grep -En '^\[[^]]+\]' "$path" | head -n 1 | cut -d: -f1 || true)"

  if [ -n "$line_number" ] && { [ -z "$first_table_line" ] || [ "$line_number" -lt "$first_table_line" ]; }; then
    pass_case "$name"
  else
    fail_case "$name" "line matching '$pattern' is not before the first table in $path"
  fi
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

assert_task_env "$TASK" 'CONFIG_FILE' '{{ ansible_facts["user_dir"] }}/.codex/config.toml' 'model defaults task wires CONFIG_FILE'
assert_task_mode "$CONFIG_MODE_TASK" '0600' 'config mode task uses 0600'

CONFIG_SNIPPET="$(extract_task_shell "$TASK")"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

config_script="$tmpdir/codex-model-defaults-task.sh"

missing_config="$tmpdir/missing.toml"
run_task_snippet "$CONFIG_SNIPPET" "$config_script" env CONFIG_FILE="$missing_config" bash
assert_eq "$TASK_STATUS" "0" 'model defaults task exits cleanly for missing config'
assert_contains "$TASK_OUTPUT" 'changed' 'model defaults task reports change for missing config'
assert_regex_count "$missing_config" '^model = "gpt-5\.5"$' 1 'model defaults task creates one model line'
assert_regex_count "$missing_config" '^model_reasoning_effort = "xhigh"$' 1 'model defaults task creates one reasoning line'
assert_mode_0600 "$missing_config" 'model defaults task writes 0600 for missing config'

config_file="$tmpdir/config.toml"
printf 'approval_policy = "never"\n\n[projects."/tmp/example"]\ntrust_level = "trusted"\n' > "$config_file"
run_task_snippet "$CONFIG_SNIPPET" "$config_script" env CONFIG_FILE="$config_file" bash
assert_eq "$TASK_STATUS" "0" 'model defaults task exits cleanly with existing root keys'
assert_contains "$TASK_OUTPUT" 'changed' 'model defaults task reports change with existing root keys'
assert_regex_count "$config_file" '^model = "gpt-5\.5"$' 1 'model defaults task keeps one model line'
assert_regex_count "$config_file" '^model_reasoning_effort = "xhigh"$' 1 'model defaults task keeps one reasoning line'
assert_file_contains "$config_file" 'approval_policy = "never"' 'model defaults task preserves unrelated root keys'
assert_file_contains "$config_file" '[projects."/tmp/example"]' 'model defaults task preserves existing tables'
assert_line_before_first_table "$config_file" '^model = "gpt-5\.5"$' 'model defaults task writes model before first table'
assert_line_before_first_table "$config_file" '^model_reasoning_effort = "xhigh"$' 'model defaults task writes reasoning before first table'
assert_mode_0600 "$config_file" 'model defaults task writes 0600 with existing root keys'

config_existing="$tmpdir/config-existing.toml"
printf '# header\n\nmodel = "gpt-5.4"\nmodel_reasoning_effort = "medium"\ncheck_for_update_on_startup = false\n\n[features]\ncodex_hooks = true\n' > "$config_existing"
run_task_snippet "$CONFIG_SNIPPET" "$config_script" env CONFIG_FILE="$config_existing" bash
assert_eq "$TASK_STATUS" "0" 'model defaults task exits cleanly with previous defaults'
assert_contains "$TASK_OUTPUT" 'changed' 'model defaults task reports change with previous defaults'
assert_regex_count "$config_existing" '^model = "gpt-5\.5"$' 1 'model defaults task replaces legacy model value'
assert_regex_count "$config_existing" '^model_reasoning_effort = "xhigh"$' 1 'model defaults task replaces legacy reasoning value'
assert_file_contains "$config_existing" '# header' 'model defaults task preserves leading comments'
assert_file_contains "$config_existing" 'check_for_update_on_startup = false' 'model defaults task preserves unrelated config'
assert_file_contains "$config_existing" '[features]' 'model defaults task preserves later tables'
config_existing_snapshot="$tmpdir/config-existing.snapshot"
cp "$config_existing" "$config_existing_snapshot"
chmod 0644 "$config_existing"
run_task_snippet "$CONFIG_SNIPPET" "$config_script" env CONFIG_FILE="$config_existing" bash
assert_eq "$TASK_STATUS" "0" 'model defaults task exits cleanly on second run'
assert_contains "$TASK_OUTPUT" 'unchanged' 'model defaults task reports unchanged on second run'
cmp -s "$config_existing_snapshot" "$config_existing" \
  && pass_case 'model defaults task is idempotent on second run' \
  || fail_case 'model defaults task is idempotent on second run' 'content changed on second run'
enforce_mode_0600 "$config_existing"
assert_eq "$MODE_STATUS" "0" 'config mode task runs successfully after drift'
assert_mode_0600 "$config_existing" 'config mode task restores 0600 after drift'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
