#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
BIN_DIR="$REPO_ROOT/roles/common/files/bin"
PANE_LABEL="$BIN_DIR/tmux-pane-label"
AGENT_WORKTREE="$BIN_DIR/tmux-agent-worktree"
WINDOW_LABEL="$BIN_DIR/tmux-window-label"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

export GIT_AUTHOR_NAME=test
export GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test
export GIT_COMMITTER_EMAIL=test@example.com

pass_case() {
  printf 'PASS  %s\n' "$1"
}

fail_case() {
  printf 'FAIL  %s\n%s\n' "$1" "$2" >&2
  exit 1
}

assert_equals() {
  local actual="$1" expected="$2" name="$3"
  if [ "$actual" != "$expected" ]; then
    fail_case "$name" "expected '$expected', got '$actual'"
  fi
  pass_case "$name"
}

assert_file_contains() {
  local path="$1" needle="$2" name="$3"
  if [ ! -f "$path" ]; then
    fail_case "$name" "missing file: $path"
  fi
  if ! grep -Fq -- "$needle" "$path"; then
    fail_case "$name" "missing '$needle' in $path"
  fi
  pass_case "$name"
}

assert_no_file() {
  local path="$1" name="$2"
  if [ -e "$path" ]; then
    fail_case "$name" "expected absent: $path"
  fi
  pass_case "$name"
}

create_repo() {
  local name="$1" repo
  repo="$TMPROOT/$name"
  git init -qb main "$repo"
  git -C "$repo" commit -q --allow-empty -m init
  git -C "$repo" checkout -q -b feature/label
  realpath "$repo"
}

plain_path="$TMPROOT/plain-dir"
mkdir -p "$plain_path"
plain_label="$(TMUX_PANE_LABEL_HOST_TAG=host-a "$PANE_LABEL" /dev/null "$plain_path" zsh)"
assert_equals "$plain_label" "plain-dir | host-a" "fallback pane label is cwd basename plus host"

repo_path="$(create_repo label-repo)"
fallback_repo_label="$(TMUX_PANE_LABEL_HOST_TAG=host-a "$PANE_LABEL" /dev/null "$repo_path" zsh)"
assert_equals "$fallback_repo_label" "label-repo | host-a" "fallback pane label does not infer repo branch"

stub_bin="$TMPROOT/stub-bin"
mkdir -p "$stub_bin"
cat >"$stub_bin/tmux-window-label" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
cat >"$stub_bin/tmux-remote-title" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$stub_bin/tmux-window-label" "$stub_bin/tmux-remote-title"

state_dir="$TMPROOT/state"
TMUX=1 \
TMUX_PANE="%1" \
TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
TMUX_AGENT_WORKTREE_PANE_TTY=/dev/null \
TMUX_PANE_LABEL_HOST_TAG=host-a \
PATH="$stub_bin:$PATH" \
  "$AGENT_WORKTREE" set "$repo_path"

assert_file_contains "$state_dir/%1.@agent_worktree_path" "$repo_path" "repo-start tmux writer stores explicit repo path"
assert_file_contains "$state_dir/%1.@pane-label" "label-repo feature/label | host-a" "repo-start tmux writer stores repo branch pane label"

TMUX=1 \
TMUX_PANE="%1" \
TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
PATH="$stub_bin:$PATH" \
  "$AGENT_WORKTREE" clear

assert_no_file "$state_dir/%1.@agent_worktree_path" "repo-end tmux clearer removes explicit repo path"
assert_no_file "$state_dir/%1.@agent_worktree_pid" "repo-end tmux clearer removes explicit repo pid"
assert_no_file "$state_dir/%1.@pane-label" "repo-end tmux clearer removes cached pane label"

fake_tmux_dir="$TMPROOT/fake-tmux-bin"
window_log="$TMPROOT/window-label.log"
mkdir -p "$fake_tmux_dir"
cat >"$fake_tmux_dir/tmux" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "display-message" ]; then
  printf '@1\t1\told-window\t/dev/null\t/tmp/project\tssh\tproject feature/remote | remote-host\t%%1\n'
  exit 0
fi
if [ "$1" = "rename-window" ]; then
  printf '%s\n' "$*" >> "$TMUX_WINDOW_LABEL_LOG"
  exit 0
fi
exit 0
STUB
chmod +x "$fake_tmux_dir/tmux"

TMUX_WINDOW_LABEL_LOG="$window_log" PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" "%1"
assert_file_contains "$window_log" "rename-window -t @1 project feature/remote" "window labels strip hostname from structured labels"

printf 'tmux label contract checks complete\n'
