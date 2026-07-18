#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
BIN_DIR="$REPO_ROOT/roles/common/files/bin"
STATE="$BIN_DIR/tmux-agent-state"
SUBJECT="$BIN_DIR/tmux-agent-subject"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

pass_case() { printf 'PASS  %s\n' "$1"; }
fail_case() { printf 'FAIL  %s\n%s\n' "$1" "$2" >&2; exit 1; }

assert_eq() {
  local expected="$1" actual="$2" name="$3"
  [[ "$actual" == "$expected" ]] || fail_case "$name" "expected '$expected', got '$actual'"
  pass_case "$name"
}

assert_file_eq() {
  local path="$1" expected="$2" name="$3" actual
  [[ -f "$path" ]] || fail_case "$name" "missing file: $path"
  actual="$(cat "$path")"
  [[ "$actual" == "$expected" ]] || fail_case "$name" "expected '$expected', got '$actual'"
  pass_case "$name"
}

assert_file_contains() {
  local path="$1" needle="$2" name="$3"
  [[ -f "$path" ]] || fail_case "$name" "missing file: $path"
  grep -Fq -- "$needle" "$path" || fail_case "$name" "missing '$needle' in $path"
  pass_case "$name"
}

display_width() {
  TMUX_TASK_LABEL="$1" python3 - <<'PY'
import os
import unicodedata
text = os.environ["TMUX_TASK_LABEL"]
print(sum(0 if unicodedata.combining(c) or unicodedata.category(c) in {"Cf", "Me", "Mn"} else 2 if unicodedata.east_asian_width(c) in {"F", "W"} else 1 for c in text))
PY
}

assert_file_not_contains() {
  local path="$1" needle="$2" name="$3"
  [[ -f "$path" ]] || fail_case "$name" "missing file: $path"
  ! grep -Fq -- "$needle" "$path" || fail_case "$name" "found disallowed bytes in $path"
  pass_case "$name"
}

assert_no_file() {
  local path="$1" name="$2"
  [[ ! -e "$path" ]] || fail_case "$name" "expected absent: $path"
  pass_case "$name"
}

stub_bin="$TMPROOT/bin"
state_dir="$TMPROOT/state"
repo="$TMPROOT/repo"
mkdir -p "$stub_bin" "$state_dir" "$repo"

cat >"$stub_bin/tmux-window-label" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TMUX_AGENT_STATE_WINDOW_LOG"
STUB
cat >"$stub_bin/tmux-remote-title" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TMUX_AGENT_STATE_TITLE_LOG"
STUB
cat >"$stub_bin/tmux-label-format" <<'STUB'
#!/usr/bin/env bash
path="$2"
branch="$(git -C "$path" branch --show-current)"
printf '(%s) repo | host-a\n' "$branch"
STUB
chmod +x "$stub_bin/tmux-window-label" "$stub_bin/tmux-remote-title" "$stub_bin/tmux-label-format"

git -c init.defaultBranch=main -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name Test
printf 'base\n' >"$repo/file"
git -C "$repo" add file
git -C "$repo" commit -qm base
git -C "$repo" update-ref refs/remotes/origin/main HEAD
git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git -C "$repo" checkout -qb feature/durable-label

export TMUX=1
export TMUX_PANE="%1"
export TMUX_AGENT_STATE_DIR="$state_dir"
export TMUX_AGENT_STATE_WINDOW_LOG="$TMPROOT/window.log"
export TMUX_AGENT_STATE_TITLE_LOG="$TMPROOT/title.log"
export TMUX_AGENT_STATE_LABEL_FORMAT_BIN="$stub_bin/tmux-label-format"
export TMUX_AGENT_STATE_CURRENT_PATH="$repo"
export PATH="$stub_bin:$PATH"

for key in @agent_subject @agent_subject_stale @agent_subject_done @agent_completed_window_label; do
  printf old >"$state_dir/%1.$key"
done
printf '(main) repo | host-a' >"$state_dir/%1.@pane-label"

"$SUBJECT" set "tmux label persistence"
assert_file_eq "$state_dir/%1.@task_label" "tmux label persistence" "stores provisional label"
assert_file_eq "$state_dir/%1.@task_source" "agent" "stores provisional source"
assert_file_eq "$state_dir/%1.@task_state" "provisional" "stores provisional state"
assert_file_eq "$state_dir/%1.@window-label" "~ tmux label persistence" "renders provisional top label"
assert_file_eq "$state_dir/%1.@pane-label" "~ tmux label persistence · repo | host-a" "renders provisional contextual bottom label"
for key in @agent_subject @agent_subject_stale @agent_subject_done @agent_completed_window_label; do
  assert_no_file "$state_dir/%1.$key" "set removes obsolete $key"
done
assert_file_contains "$TMPROOT/window.log" "%1" "provisional refresh invokes tmux-window-label"
assert_file_contains "$TMPROOT/title.log" "publish" "provisional refresh publishes remote title"

"$STATE" activate-branch "$repo"
assert_file_eq "$state_dir/%1.@task_label" "feature/durable-label" "captures branch"
assert_file_eq "$state_dir/%1.@task_source" "branch" "stores branch source"
assert_file_eq "$state_dir/%1.@task_state" "active" "activates branch"
assert_file_eq "$state_dir/%1.@window-label" "feature/durable-label" "branch replaces subject"
assert_file_eq "$state_dir/%1.@pane-label" "(feature/durable-label) repo | host-a" "active bottom retains full branch and context"

"$SUBJECT" set "must not replace active branch"
assert_file_eq "$state_dir/%1.@task_label" "feature/durable-label" "provisional cannot replace active branch"
assert_file_eq "$state_dir/%1.@task_source" "branch" "active branch keeps source"
assert_file_eq "$state_dir/%1.@task_state" "active" "active branch keeps state"

# A default branch must not replace an existing useful task identity.
git -C "$repo" checkout -q main
"$STATE" activate-branch "$repo"
assert_file_eq "$state_dir/%1.@task_label" "feature/durable-label" "default branch retains task identity"
assert_file_eq "$state_dir/%1.@task_state" "active" "default branch retains active state"

# With an explicit develop default, main is a valid non-default branch.
git -C "$repo" branch develop
git -C "$repo" update-ref refs/remotes/origin/develop refs/heads/develop
git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop
"$STATE" activate-branch "$repo"
assert_file_eq "$state_dir/%1.@task_label" "main" "main is valid when origin default is develop"
assert_file_eq "$state_dir/%1.@task_state" "active" "non-default main becomes active"

git -C "$repo" symbolic-ref --delete refs/remotes/origin/HEAD
git -C "$repo" checkout -q feature/durable-label
"$STATE" activate-branch "$repo"
git -C "$repo" checkout -q main
"$STATE" activate-branch "$repo"
assert_file_eq "$state_dir/%1.@task_label" "feature/durable-label" "main is rejected when origin default is unknown"
git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

# Failed Git lookup must not erase captured identity.
"$STATE" activate-branch "$TMPROOT/missing"
assert_file_eq "$state_dir/%1.@task_label" "feature/durable-label" "Git lookup failure retains identity"

# Restore the contextual active label before completion.
git -C "$repo" checkout -q feature/durable-label
"$STATE" activate-branch "$repo"
printf 999 >"$state_dir/%1.@agent_worktree_pid"
printf link >"$state_dir/%1.@pane-link"
printf source >"$state_dir/%1.@pane-link-source"
"$STATE" complete-worktree
assert_file_eq "$state_dir/%1.@task_state" "completed" "completion stores completed state"
assert_file_eq "$state_dir/%1.@window-label" "✓ feature/durable-label" "renders completed branch"
assert_file_eq "$state_dir/%1.@pane-label" "✓ (feature/durable-label) repo | host-a" "completed bottom retains full context"
assert_no_file "$state_dir/%1.@agent_worktree_path" "completion clears worktree path"
assert_no_file "$state_dir/%1.@agent_worktree_pid" "completion clears worktree pid"
assert_no_file "$state_dir/%1.@pane-link" "completion clears pane link"
assert_no_file "$state_dir/%1.@pane-link-source" "completion clears pane link source"
assert_eq $'completed\tbranch\tfeature/durable-label' "$("$STATE" status)" "status contract"

"$STATE" complete-worktree
assert_file_eq "$state_dir/%1.@window-label" "✓ feature/durable-label" "completion is idempotent"
assert_file_not_contains "$state_dir/%1.@window-label" "✓ ✓" "completion does not duplicate marker"

"$SUBJECT" set "next provisional task"
assert_file_eq "$state_dir/%1.@task_label" "next provisional task" "provisional replaces completed branch"
assert_file_eq "$state_dir/%1.@task_source" "agent" "replacement changes source to agent"
assert_file_eq "$state_dir/%1.@task_state" "provisional" "replacement changes state to provisional"

"$STATE" clear-task
assert_no_file "$state_dir/%1.@task_label" "clear-task removes label"
assert_no_file "$state_dir/%1.@task_source" "clear-task removes source"
assert_no_file "$state_dir/%1.@task_state" "clear-task removes state"
assert_eq "" "$("$STATE" status)" "empty status emits nothing"

printf old >"$state_dir/%1.@agent_subject_done"
"$STATE" set-kind pi
assert_no_file "$state_dir/%1.@agent_subject_done" "session kind clears obsolete completion state"
assert_file_eq "$state_dir/%1.@window-label" "repo" "fallback top omits agent kind"

"$SUBJECT" set "$(printf ' \033\a\001 ')"
assert_no_file "$state_dir/%1.@task_label" "empty sanitized subject leaves identity empty"

control_subject="$(printf 'bad \033chars\a\001 subject')"
"$SUBJECT" set "$control_subject"
assert_file_eq "$state_dir/%1.@task_label" "bad chars subject" "subject removes control bytes"
assert_file_not_contains "$state_dir/%1.@task_label" "$(printf '\033')" "stored subject removes escape byte"
assert_file_not_contains "$state_dir/%1.@window-label" "$(printf '\a')" "window label removes bell byte"

long_subject="$(printf 'a%.0s' {1..120})"
"$SUBJECT" set "$long_subject"
long_label="$(cat "$state_dir/%1.@window-label")"
assert_eq "40" "$(display_width "$long_label")" "ASCII top label is exactly 40 cells"
assert_eq "…" "${long_label: -1}" "long top label ends with ellipsis"
assert_file_eq "$state_dir/%1.@task_label" "$long_subject" "stored subject is not capped at 80 characters"
assert_file_eq "$state_dir/%1.@pane-label" "~ $long_subject · repo | host-a" "bottom label retains full subject"

wide_subject="$(printf '界%.0s' {1..30})"
"$SUBJECT" set "$wide_subject"
wide_label="$(cat "$state_dir/%1.@window-label")"
assert_eq "39" "$(display_width "$wide_label")" "wide-glyph top label stays within 40 cells"
assert_eq "~ $(printf '界%.0s' {1..18})…" "$wide_label" "wide-glyph truncation is exact"
assert_file_eq "$state_dir/%1.@task_label" "$wide_subject" "wide subject remains full in storage"

printf 'tmux-agent-state checks complete\n'
