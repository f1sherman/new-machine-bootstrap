#!/usr/bin/env bash
set -euo pipefail

unset TMUX TMUX_PANE

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
BIN_DIR="$REPO_ROOT/roles/common/files/bin"
PANE_LABEL="$BIN_DIR/tmux-pane-label"
PANE_TITLE_CHANGED="$BIN_DIR/tmux-pane-title-changed"
AGENT_WORKTREE="$BIN_DIR/tmux-agent-worktree"
WINDOW_LABEL="$BIN_DIR/tmux-window-label"
TITLE_TRANSITION="$BIN_DIR/tmux-title-transition"
PANE_LINK="$BIN_DIR/tmux-pane-link"
REMOTE_TITLE="$BIN_DIR/tmux-remote-title"
SYNC_REMOTE_TITLE="$BIN_DIR/tmux-sync-remote-title"
UPDATE_PANE_LABEL="$BIN_DIR/tmux-update-pane-label"
TASK_LABEL="$BIN_DIR/tmux-task-label"
GLYPHS="$BIN_DIR/tmux-indicator-glyphs"

TMPROOT="$(mktemp -d)"

# git-ai bootstraps a `git-ai bg run` daemon when its hooks fire under a
# throwaway HOME. This test runs git tooling under HOME dirs inside TMPROOT, so
# disable the hooks and reap any daemon that still managed to root itself there.
export GIT_AI_SKIP_ALL_HOOKS=1

tmproot_git_ai_daemon_pids() {
  # pgrep cannot match on the full executable path portably, and we filter on
  # the daemon's path being rooted under TMPROOT. No match is the normal,
  # successful case, so the grep chain must not abort the caller.
  # shellcheck disable=SC2009
  ps -axww -o pid=,args= 2>/dev/null \
    | { grep 'git-ai bg' || true; } \
    | { grep -F -- "$TMPROOT" || true; } \
    | awk '{ print $1 }'
}

reap_tmproot_git_ai_daemons() {
  local pid
  for pid in $(tmproot_git_ai_daemon_pids); do
    kill "$pid" 2>/dev/null || true
  done
}

trap 'reap_tmproot_git_ai_daemons; rm -rf "$TMPROOT"' EXIT

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

assert_less_than() {
  local actual="$1" limit="$2" name="$3"
  if [ "$actual" -ge "$limit" ]; then
    fail_case "$name" "expected $actual to be less than $limit"
  fi
  pass_case "$name"
}

assert_lexically_after() {
  local later="$1" earlier="$2" name="$3"
  if [[ ! "$later" > "$earlier" ]]; then
    fail_case "$name" "expected '$later' to sort after '$earlier'"
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

assert_file_not_contains() {
  local path="$1" needle="$2" name="$3"
  if [ ! -f "$path" ]; then
    fail_case "$name" "missing file: $path"
  fi
  if grep -Fq -- "$needle" "$path"; then
    fail_case "$name" "found '$needle' in $path"
  fi
  pass_case "$name"
}

assert_file_matches() {
  local path="$1" pattern="$2" name="$3"
  if [ ! -f "$path" ]; then
    fail_case "$name" "missing file: $path"
  fi
  if ! grep -Eq -- "$pattern" "$path"; then
    fail_case "$name" "missing pattern '$pattern' in $path"
  fi
  pass_case "$name"
}

assert_file_line() {
  local path="$1" line="$2" name="$3"
  if [ ! -f "$path" ]; then
    fail_case "$name" "missing file: $path"
  fi
  if ! grep -Fxq -- "$line" "$path"; then
    fail_case "$name" "missing exact line '$line' in $path"
  fi
  pass_case "$name"
}

assert_line_before() {
  local path="$1" before="$2" after="$3" name="$4" before_line after_line
  before_line="$(grep -nFx -- "$before" "$path" 2>/dev/null | head -n 1 | cut -d: -f1 || true)"
  after_line="$(grep -nFx -- "$after" "$path" 2>/dev/null | head -n 1 | cut -d: -f1 || true)"
  if [ -z "$before_line" ] || [ -z "$after_line" ] || [ "$before_line" -ge "$after_line" ]; then
    fail_case "$name" "'$before' does not appear before '$after' in $path"
  fi
  pass_case "$name"
}

wait_for_file_line() {
  local path="$1" line="$2" name="$3" attempts=0
  while [ "$attempts" -lt 100 ]; do
    if [ -f "$path" ] && grep -Fxq -- "$line" "$path"; then
      pass_case "$name"
      return 0
    fi
    sleep 0.02
    attempts=$((attempts + 1))
  done
  fail_case "$name" "missing exact line '$line' in $path after waiting"
}

wait_for_process_exit() {
  local pid="$1" name="$2" attempts=0 status
  while [ "$attempts" -lt 100 ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      if wait "$pid"; then
        pass_case "$name"
        return 0
      else
        status=$?
        fail_case "$name" "process $pid exited with status $status"
      fi
    fi
    sleep 0.02
    attempts=$((attempts + 1))
  done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  fail_case "$name" "process $pid did not exit after waiting"
}

assert_no_file() {
  local path="$1" name="$2"
  if [ -e "$path" ]; then
    fail_case "$name" "expected absent: $path"
  fi
  pass_case "$name"
}

assert_link_before_label() {
  local file="$1" name="$2" line before link_idx label_idx
  line="$(grep -F 'set -g pane-border-format' "$file")" || fail_case "$name" "no pane-border-format in $file"
  before="${line%%@pane-link*}"
  link_idx=${#before}
  before="${line%%@pane-label*}"
  label_idx=${#before}
  if [ "$link_idx" -ge "$label_idx" ]; then
    fail_case "$name" "@pane-link ($link_idx) is not before @pane-label ($label_idx) in $file"
  fi
  pass_case "$name"
}

create_repo() {
  local name="$1" repo
  repo="$TMPROOT/$name"
  git init -qb main "$repo"
  git -C "$repo" commit -q --allow-empty -m init
  git -C "$repo" remote add origin "https://example.com/org/${name}.git"
  git -C "$repo" checkout -q -b feature/label
  realpath "$repo"
}

write_pr_status_cache() {
  local home="$1" repo="$2" platform="$3" pr_number="$4" url="$5"
  local remote_url branch key cache_dir now expires display_ref

  remote_url="$(git -C "$repo" remote get-url origin)"
  branch="$(git -C "$repo" branch --show-current)"
  key="$(printf '%s\n%s\n' "$remote_url" "$branch" | shasum -a 256 | awk '{print $1}')"
  cache_dir="$home/.local/state/pr-status"
  now="$(date +%s)"
  expires="$((now + 3600))"

  case "$platform" in
    github) display_ref="gh#$pr_number" ;;
    forgejo) display_ref="fj#$pr_number" ;;
    *) fail_case "write PR status cache" "unsupported platform: $platform" ;;
  esac

  mkdir -p "$cache_dir"
  jq -n \
    --argjson schema_version 1 \
    --arg platform "$platform" \
    --arg repo_root "$repo" \
    --arg git_common_dir "$repo/.git" \
    --arg remote_url "$remote_url" \
    --arg branch "$branch" \
    --arg head_sha "abc123" \
    --argjson pr_number "$pr_number" \
    --arg display_ref "$display_ref" \
    --arg html_url "$url" \
    --arg state "open" \
    --arg source "test" \
    --argjson updated_at_epoch "$now" \
    --argjson expires_at_epoch "$expires" \
    '{schema_version:$schema_version,platform:$platform,repo_root:$repo_root,git_common_dir:$git_common_dir,remote_url:$remote_url,branch:$branch,head_sha:$head_sha,pr_number:$pr_number,display_ref:$display_ref,html_url:$html_url,state:$state,source:$source,updated_at_epoch:$updated_at_epoch,expires_at_epoch:$expires_at_epoch}' \
    > "$cache_dir/$key.json"
}

pane_link_state_dir="$TMPROOT/state-pane-link"
mkdir -p "$pane_link_state_dir"
direct_url="https://github.com/org/repo/pull/7"
TMUX=1 \
TMUX_AGENT_WORKTREE_STATE_DIR="$pane_link_state_dir" \
  "$PANE_LINK" --pane %20 "$direct_url"
assert_equals "$(cat "$pane_link_state_dir/%20.@pane-link")" "$direct_url" "tmux-pane-link stores bare URL with no label"

plain_path="$TMPROOT/plain-dir"
mkdir -p "$plain_path"
plain_label="$(TMUX_PANE_LABEL_HOST_TAG=host-a "$PANE_LABEL" /dev/null "$plain_path" zsh)"
assert_equals "$plain_label" "plain-dir | host-a" "fallback pane label is cwd basename plus host"

repo_path="$(create_repo label-repo)"
fallback_repo_label="$(TMUX_PANE_LABEL_HOST_TAG=host-a "$PANE_LABEL" /dev/null "$repo_path" zsh)"
assert_equals "$fallback_repo_label" "label-repo | host-a" "fallback pane label does not infer repo branch"

assert_equals "$("$GLYPHS" working approved)" '⏳#[fg=#b5bd68]● ' "indicator glyphs render working+approved"
assert_equals "$("$GLYPHS" waiting "")" "💬 " "indicator glyphs render waiting only"
assert_equals "$("$GLYPHS" "" draft)" '#[fg=#808080]● ' "draft indicator matches Pi muted"
assert_equals "$("$GLYPHS" "" checks-failing)" '#[fg=#cc6666]● ' "checks-failing indicator matches Pi error"
assert_equals "$("$GLYPHS" "" changes-requested)" '#[fg=#ffff00]● ' "changes-requested indicator matches Pi warning"
assert_equals "$("$GLYPHS" "" ready-for-review)" '#[fg=#8abeb7]● ' "ready indicator matches Pi accent"
assert_equals "$("$GLYPHS" "" approved)" '#[fg=#b5bd68]● ' "approved indicator matches Pi success"
assert_equals "$("$GLYPHS" "" merged)" '#[fg=#8957e5]● ' "merged indicator matches Pi purple"
assert_equals "$("$GLYPHS" "" closed)" '#[fg=#cf4f4f,dim]● ' "closed indicator matches Pi dim red"
assert_equals "$("$GLYPHS" "" "")" "" "indicator glyphs render nothing when empty"
assert_equals "$("$GLYPHS" bogus nonsense)" "" "indicator glyphs ignore unknown values"

remote_edge_title="$(TMUX_PANE= TMUX_REMOTE_TITLE_PANE_PATH="$repo_path" TMUX_REMOTE_TITLE_CLIENT_TTY=/dev/null TMUX_REMOTE_TITLE_PANE_TTY=/dev/null TMUX_REMOTE_TITLE_HOST_TAG=remote-host TMUX_REMOTE_TITLE_PANE_COMMAND=tmux TMUX_REMOTE_TITLE_EDGE_FLAGS=hj "$REMOTE_TITLE" print)"
assert_equals "$remote_edge_title" "label-repo | remote-host [nmb-edge=hj]" "remote title publishes tmux edge marker"

remote_vim_title="$(TMUX_PANE= TMUX_REMOTE_TITLE_PANE_PATH="$repo_path" TMUX_REMOTE_TITLE_CLIENT_TTY=/dev/null TMUX_REMOTE_TITLE_PANE_TTY=/dev/null TMUX_REMOTE_TITLE_HOST_TAG=remote-host TMUX_REMOTE_TITLE_PANE_COMMAND=nvim TMUX_REMOTE_TITLE_EDGE_FLAGS=hj "$REMOTE_TITLE" print)"
assert_equals "$remote_vim_title" "label-repo | remote-host" "remote title suppresses edge marker for vim panes"

remote_suppressed_title="$(TMUX_PANE= TMUX_REMOTE_TITLE_PANE_PATH="$repo_path" TMUX_REMOTE_TITLE_CLIENT_TTY=/dev/null TMUX_REMOTE_TITLE_PANE_TTY=/dev/null TMUX_REMOTE_TITLE_HOST_TAG=remote-host TMUX_REMOTE_TITLE_PANE_COMMAND=zsh TMUX_REMOTE_TITLE_EDGE_FLAGS=hj TMUX_REMOTE_TITLE_SUPPRESS_EDGE=1 "$REMOTE_TITLE" print)"
assert_equals "$remote_suppressed_title" "label-repo | remote-host" "remote title can suppress stale edge marker while commands run"

remote_ind_title="$(TMUX_PANE= TMUX_REMOTE_TITLE_PANE_PATH="$repo_path" TMUX_REMOTE_TITLE_CLIENT_TTY=/dev/null TMUX_REMOTE_TITLE_PANE_TTY=/dev/null TMUX_REMOTE_TITLE_HOST_TAG=remote-host TMUX_REMOTE_TITLE_PANE_COMMAND=zsh TMUX_REMOTE_TITLE_ACTIVITY=working TMUX_REMOTE_TITLE_PR_STATE=draft "$REMOTE_TITLE" print)"
assert_equals "$remote_ind_title" "label-repo | remote-host [nmb-ind=working,draft]" "remote title publishes indicator marker"

remote_ind_edge_title="$(TMUX_PANE= TMUX_REMOTE_TITLE_PANE_PATH="$repo_path" TMUX_REMOTE_TITLE_CLIENT_TTY=/dev/null TMUX_REMOTE_TITLE_PANE_TTY=/dev/null TMUX_REMOTE_TITLE_HOST_TAG=remote-host TMUX_REMOTE_TITLE_PANE_COMMAND=tmux TMUX_REMOTE_TITLE_EDGE_FLAGS=hj TMUX_REMOTE_TITLE_ACTIVITY=waiting "$REMOTE_TITLE" print)"
assert_equals "$remote_ind_edge_title" "label-repo | remote-host [nmb-ind=waiting,] [nmb-edge=hj]" "indicator marker precedes edge marker"

remote_task_tmux_dir="$TMPROOT/remote-task-tmux-bin"
mkdir -p "$remote_task_tmux_dir"
cat >"$remote_task_tmux_dir/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  display-message)
    printf '/tmp/project\t/dev/null\tzsh\t\t\t\t1\n'
    ;;
  show-options)
    case "${*: -1}" in
      @task_label) printf '%s' "$TMUX_TEST_TASK_LABEL" ;;
      @task_state) printf '%s' "$TMUX_TEST_TASK_STATE" ;;
      @task_source) printf '%s' "${TMUX_TEST_TASK_SOURCE:-}" ;;
      @task_context) printf '%s' "$TMUX_TEST_TASK_CONTEXT" ;;
      @window-label) printf '%s' "${TMUX_TEST_WINDOW_LABEL:-}" ;;
      @pane-label) printf '%s' "$TMUX_TEST_PANE_LABEL" ;;
    esac
    ;;
esac
STUB
chmod +x "$remote_task_tmux_dir/tmux"
remote_task_title="$(TMUX_PANE=%31 TMUX_REMOTE_TITLE_HOST_TAG=remote-host TMUX_TEST_TASK_LABEL=feature/durable-label TMUX_TEST_TASK_STATE=active TMUX_TEST_TASK_SOURCE=branch TMUX_TEST_TASK_CONTEXT=project TMUX_TEST_PANE_LABEL='(feature/durable-label fj#42) project | wrong-host' PATH="$remote_task_tmux_dir:$PATH" "$REMOTE_TITLE" print)"
assert_equals "$remote_task_title" "(feature/durable-label) project | remote-host" "remote title builds active label from canonical task fields"

remote_goal_title="$(TMUX_PANE=%31 TMUX_REMOTE_TITLE_HOST_TAG=remote-host TMUX_TEST_TASK_LABEL='A durable goal that is intentionally longer than forty characters' TMUX_TEST_TASK_STATE=active TMUX_TEST_TASK_SOURCE=goal TMUX_TEST_TASK_CONTEXT=project TMUX_TEST_WINDOW_LABEL='A durable goal that is intentionally lo…' TMUX_TEST_PANE_LABEL='(A durable goal that is intentionally longer than forty characters) project | remote-host' TMUX_REMOTE_TITLE_ACTIVITY=waiting TMUX_REMOTE_TITLE_PR_STATE=merged PATH="$remote_task_tmux_dir:$PATH" "$REMOTE_TITLE" print)"
assert_equals "$remote_goal_title" "A durable goal that is intentionally longer than forty characters · project | remote-host [nmb-task=goal] [nmb-ind=waiting,merged]" "remote active goal publishes explicit task identity"

remote_manual_title="$(TMUX_PANE=%31 TMUX_REMOTE_TITLE_HOST_TAG=remote-host TMUX_TEST_TASK_LABEL='Manual task identity' TMUX_TEST_TASK_STATE=active TMUX_TEST_TASK_SOURCE=manual TMUX_TEST_TASK_CONTEXT=project TMUX_TEST_WINDOW_LABEL='Manual task identity' TMUX_TEST_PANE_LABEL='(Manual task identity) project | remote-host' PATH="$remote_task_tmux_dir:$PATH" "$REMOTE_TITLE" print)"
assert_equals "$remote_manual_title" "Manual task identity · project | remote-host [nmb-task=manual]" "remote active manual publishes explicit task identity"

remote_goal_fallback_title="$(TMUX_PANE=%31 TMUX_REMOTE_TITLE_HOST_TAG=remote-host TMUX_TEST_TASK_LABEL='Missing cached goal' TMUX_TEST_TASK_STATE=active TMUX_TEST_TASK_SOURCE=goal TMUX_TEST_TASK_CONTEXT=project TMUX_TEST_WINDOW_LABEL='' TMUX_TEST_PANE_LABEL='(Missing cached goal) project | remote-host' PATH="$remote_task_tmux_dir:$PATH" "$REMOTE_TITLE" print)"
assert_equals "$remote_goal_fallback_title" "Missing cached goal · project | remote-host [nmb-task=goal]" "remote active goal publication does not require cached window label"

remote_pipe_title="$(TMUX_PANE=%31 TMUX_REMOTE_TITLE_HOST_TAG=remote-host TMUX_TEST_TASK_LABEL='auth | billing' TMUX_TEST_TASK_STATE=provisional TMUX_TEST_TASK_CONTEXT=project TMUX_TEST_PANE_LABEL='~ wrong rendered label | wrong-host' PATH="$remote_task_tmux_dir:$PATH" "$REMOTE_TITLE" print)"
assert_equals "$remote_pipe_title" "~ auth | billing · project | remote-host" "remote title preserves pipe in canonical provisional subject"

remote_dot_title="$(TMUX_PANE=%31 TMUX_REMOTE_TITLE_HOST_TAG=remote-host TMUX_TEST_TASK_LABEL='auth · billing' TMUX_TEST_TASK_STATE=provisional TMUX_TEST_TASK_CONTEXT='project | remote-host' TMUX_TEST_PANE_LABEL='~ wrong rendered label | wrong-host' PATH="$remote_task_tmux_dir:$PATH" "$REMOTE_TITLE" print)"
assert_equals "$remote_dot_title" "~ auth · billing · project | remote-host" "remote title preserves middle dot and avoids duplicate host"

remote_completed_title="$(TMUX_PANE=%31 TMUX_REMOTE_TITLE_HOST_TAG=remote-host TMUX_TEST_TASK_LABEL=feature/durable-label TMUX_TEST_TASK_STATE=completed TMUX_TEST_TASK_CONTEXT=project TMUX_TEST_PANE_LABEL='✓ wrong rendered label | wrong-host' PATH="$remote_task_tmux_dir:$PATH" "$REMOTE_TITLE" print)"
assert_equals "$remote_completed_title" "✓ (feature/durable-label) project | remote-host" "remote title builds completed label from canonical task fields"

remote_publish_tmux_dir="$TMPROOT/remote-publish-tmux-bin"
remote_publish_visible="$TMPROOT/remote-publish-visible"
remote_publish_other="$TMPROOT/remote-publish-other"
remote_publish_second="$TMPROOT/remote-publish-second"
mkdir -p "$remote_publish_tmux_dir"
: > "$remote_publish_visible"
: > "$remote_publish_other"
: > "$remote_publish_second"
cat >"$remote_publish_tmux_dir/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  display-message)
    printf '/tmp/project\t/dev/null\tzsh\t\t$source\t@source\t%s\n' "${TMUX_TEST_PANE_ACTIVE:-1}"
    ;;
  list-clients)
    printf '%b' "$TMUX_TEST_CLIENTS"
    ;;
  show-options)
    case "${*: -1}" in
      @task_label) printf 'status check' ;;
      @task_state) printf 'provisional' ;;
      @task_context) printf 'project' ;;
    esac
    ;;
esac
STUB
chmod +x "$remote_publish_tmux_dir/tmux"

TMUX_PANE=%31 \
TMUX_REMOTE_TITLE_HOST_TAG=remote-host \
TMUX_TEST_CLIENTS="$remote_publish_visible\t\$source\t@source\n$remote_publish_other\t\$other\t@other\n" \
PATH="$remote_publish_tmux_dir:$PATH" \
  "$REMOTE_TITLE" publish
assert_file_contains "$remote_publish_visible" '~ status check · project | remote-host' "remote title reaches client displaying source window"
assert_equals "$(wc -c < "$remote_publish_other" | tr -d ' ')" "0" "remote title does not leak to another session"

: > "$remote_publish_visible"
TMUX_PANE=%31 \
TMUX_REMOTE_TITLE_HOST_TAG=remote-host \
TMUX_TEST_CLIENTS="$remote_publish_visible\t\$source\t@different\n$remote_publish_other\t\$source\t@other\n" \
PATH="$remote_publish_tmux_dir:$PATH" \
  "$REMOTE_TITLE" publish
assert_equals "$(wc -c < "$remote_publish_visible" | tr -d ' ')" "0" "remote title skips client viewing another window"
assert_equals "$(wc -c < "$remote_publish_other" | tr -d ' ')" "0" "remote title skips all nonmatching windows"

: > "$remote_publish_visible"
: > "$remote_publish_second"
TMUX_PANE=%31 \
TMUX_REMOTE_TITLE_HOST_TAG=remote-host \
TMUX_TEST_CLIENTS="$remote_publish_visible\t\$source\t@source\n$remote_publish_second\t\$source\t@source\n" \
PATH="$remote_publish_tmux_dir:$PATH" \
  "$REMOTE_TITLE" publish
assert_file_contains "$remote_publish_visible" '~ status check · project | remote-host' "remote title reaches first client viewing source window"
assert_file_contains "$remote_publish_second" '~ status check · project | remote-host' "remote title reaches second client viewing source window"

: > "$remote_publish_visible"
TMUX_PANE=%31 \
TMUX_REMOTE_TITLE_HOST_TAG=remote-host \
TMUX_TEST_PANE_ACTIVE=0 \
TMUX_TEST_CLIENTS="$remote_publish_visible\t\$source\t@source\n" \
PATH="$remote_publish_tmux_dir:$PATH" \
  "$REMOTE_TITLE" publish
assert_equals "$(wc -c < "$remote_publish_visible" | tr -d ' ')" "0" "inactive source pane publishes no remote title"

transition_state="$TMPROOT/transition-state"
transition_log="$TMPROOT/transition.log"
transition_bin="$TMPROOT/transition-bin"
mkdir -p "$transition_bin"
cat >"$transition_bin/tmux-window-label" <<'STUB'
#!/usr/bin/env bash
printf 'label-start\t%s\n' "${2:-}" >> "$TMUX_TITLE_TRANSITION_LOG"
[ "${2:-}" != old ] || sleep 0.2
[ "${2:-}" != render-failure ] || exit 73
printf 'label-end\t%s\n' "${2:-}" >> "$TMUX_TITLE_TRANSITION_LOG"
STUB
cat >"$transition_bin/tmux-remote-title" <<'STUB'
#!/usr/bin/env bash
printf 'publish\t%s\t%s\n' "${TMUX_REMOTE_TITLE_SUPPRESS_EDGE:-0}" "${1:-}" >> "$TMUX_TITLE_TRANSITION_LOG"
STUB
chmod +x "$transition_bin/tmux-window-label" "$transition_bin/tmux-remote-title"
SSH_CONNECTION=test TMUX_TITLE_TRANSITION_STATE_DIR="$transition_state" \
TMUX_TITLE_TRANSITION_LOG="$transition_log" PATH="$transition_bin:$PATH" \
  "$TITLE_TRANSITION" %1 0001 old 0 &
old_transition_pid=$!
wait_for_file_line "$transition_log" $'label-start\told' "older transition renderer starts"
transition_lock="$transition_state/default._1/worker.lock"
assert_equals "$(cat "$transition_lock/owner")" "$old_transition_pid"$'\t'0001 "active transition records PID and request identity"
SSH_CONNECTION=test TMUX_TITLE_TRANSITION_STATE_DIR="$transition_state" \
TMUX_TITLE_TRANSITION_LOG="$transition_log" PATH="$transition_bin:$PATH" \
  "$TITLE_TRANSITION" %1 0002 new 1 &
new_transition_pid=$!
sleep 0.05
assert_equals "$(cat "$transition_lock/owner")" "$old_transition_pid"$'\t'0001 "waiting transition does not steal live-owner lock"
assert_file_not_contains "$transition_log" $'label-start\tnew' "waiting transition does not render under live-owner lock"
wait "$old_transition_pid" "$new_transition_pid"
assert_line_before "$transition_log" $'label-start\told' $'label-end\told' "transition keeps each render serialized"
assert_line_before "$transition_log" $'label-end\told' $'label-start\tnew' "newer transition waits for prior renderer"
assert_file_not_contains "$transition_log" $'publish\t0\tpublish' "stale transition does not publish after a newer request"
assert_file_line "$transition_log" $'publish\t1\tpublish' "newest transition publishes after its label"
assert_line_before "$transition_log" $'label-end\tnew' $'publish\t1\tpublish' "newest label completes before remote publication"
assert_no_file "$transition_lock" "completed live-owner transitions leave no lock"

terminated_waiter_state="$TMPROOT/terminated-waiter-state"
terminated_waiter_log="$TMPROOT/terminated-waiter.log"
terminated_waiter_lock="$terminated_waiter_state/default._11/worker.lock"
terminated_waiter_request="$terminated_waiter_state/default._11/requests/0001"
terminated_waiter_owner=terminated-waiter-live-owner
mkdir -p "$terminated_waiter_lock"
: > "$terminated_waiter_log"
bash -c 'sleep 3; :' "$terminated_waiter_owner" &
terminated_waiter_owner_pid=$!
printf '%s\t%s\n' "$terminated_waiter_owner_pid" "$terminated_waiter_owner" > "$terminated_waiter_lock/owner"
SSH_CONNECTION=test TMUX_TITLE_TRANSITION_STATE_DIR="$terminated_waiter_state" \
TMUX_TITLE_TRANSITION_LOG="$terminated_waiter_log" PATH="$transition_bin:$PATH" \
  "$TITLE_TRANSITION" %11 0001 canceled 0 &
terminated_waiter_pid=$!
for _ in {1..100}; do
  [ ! -f "$terminated_waiter_request" ] || break
  sleep 0.01
done
[ -f "$terminated_waiter_request" ] || fail_case "waiting transition creates its request" "missing $terminated_waiter_request"
pass_case "waiting transition creates its request"
assert_equals "$(cat "$terminated_waiter_lock/owner")" "$terminated_waiter_owner_pid"$'\t'"$terminated_waiter_owner" "cancel target waits on demonstrably live owner lock"
kill -TERM "$terminated_waiter_pid"
terminated_waiter_exited=0
for _ in {1..100}; do
  if ! kill -0 "$terminated_waiter_pid" 2>/dev/null; then
    terminated_waiter_exited=1
    break
  fi
  sleep 0.01
done
if [ "$terminated_waiter_exited" = "1" ]; then
  if wait "$terminated_waiter_pid"; then
    terminated_waiter_status=0
  else
    terminated_waiter_status=$?
  fi
else
  kill -KILL "$terminated_waiter_pid" 2>/dev/null || true
  wait "$terminated_waiter_pid" 2>/dev/null || true
  kill "$terminated_waiter_owner_pid" 2>/dev/null || true
  wait "$terminated_waiter_owner_pid" 2>/dev/null || true
  fail_case "TERM exits waiting transition promptly" "process $terminated_waiter_pid remained alive"
fi
pass_case "TERM exits waiting transition promptly"
assert_equals "$terminated_waiter_status" 0 "TERM exits waiting transition nonfatally"
assert_equals "$(cat "$terminated_waiter_lock/owner")" "$terminated_waiter_owner_pid"$'\t'"$terminated_waiter_owner" "terminated waiter preserves live owner metadata"
[ -d "$terminated_waiter_lock" ] || fail_case "terminated waiter preserves live owner lock" "missing $terminated_waiter_lock"
pass_case "terminated waiter preserves live owner lock"
assert_equals "$(wc -c < "$terminated_waiter_log" | tr -d ' ')" 0 "terminated waiter does not render or publish"
assert_no_file "$terminated_waiter_request" "terminated waiter removes its request"
kill "$terminated_waiter_owner_pid" 2>/dev/null || true
wait "$terminated_waiter_owner_pid" 2>/dev/null || true
rm -rf "$terminated_waiter_lock"

render_failure_state="$TMPROOT/render-failure-state"
render_failure_log="$TMPROOT/render-failure.log"
SSH_CONNECTION=test TMUX_TITLE_TRANSITION_STATE_DIR="$render_failure_state" \
TMUX_TITLE_TRANSITION_LOG="$render_failure_log" PATH="$transition_bin:$PATH" \
  "$TITLE_TRANSITION" %9 0001 render-failure 0
assert_file_line "$render_failure_log" $'label-start\trender-failure' "failed transition attempts window rendering"
assert_file_not_contains "$render_failure_log" $'publish\t0\tpublish' "failed window rendering suppresses remote publication"

abandoned_transition_state="$TMPROOT/abandoned-transition-state"
abandoned_transition_log="$TMPROOT/abandoned-transition.log"
abandoned_transition_lock="$abandoned_transition_state/default._2/worker.lock"
mkdir -p "$abandoned_transition_lock"
printf 'invalid-owner\n' > "$abandoned_transition_lock/owner"
SSH_CONNECTION=test TMUX_TITLE_TRANSITION_STATE_DIR="$abandoned_transition_state" \
TMUX_TITLE_TRANSITION_LOG="$abandoned_transition_log" PATH="$transition_bin:$PATH" \
  "$TITLE_TRANSITION" %2 0001 recovered 0 &
abandoned_transition_pid=$!
wait_for_process_exit "$abandoned_transition_pid" "transition exits after recovering abandoned lock"
assert_file_line "$abandoned_transition_log" $'label-end\trecovered' "recovered transition renders label"
assert_file_line "$abandoned_transition_log" $'publish\t0\tpublish' "recovered transition publishes remote title"
assert_line_before "$abandoned_transition_log" $'label-end\trecovered' $'publish\t0\tpublish' "recovered label completes before publication"
assert_no_file "$abandoned_transition_lock" "recovered transition leaves no lock"

reused_pid_state="$TMPROOT/reused-pid-state"
reused_pid_log="$TMPROOT/reused-pid.log"
reused_pid_lock="$reused_pid_state/default._8/worker.lock"
mkdir -p "$reused_pid_lock"
printf '%s\n' "$$" > "$reused_pid_lock/owner"
TMUX_TITLE_TRANSITION_STATE_DIR="$reused_pid_state" TMUX_TITLE_TRANSITION_LOG="$reused_pid_log" \
PATH="$transition_bin:$PATH" "$TITLE_TRANSITION" %8 0001 reused-pid 0 &
reused_pid_transition=$!
sleep 0.1
: > "$reused_pid_state/default._8/requests/0002"
wait_for_process_exit "$reused_pid_transition" "transition exits when unrelated live process reuses lock PID"
assert_file_line "$reused_pid_log" $'label-end\treused-pid' "live PID without owner identity recovers lock"
rm -f "$reused_pid_state/default._8/requests/0002"

reused_identity_state="$TMPROOT/reused-identity-state"
reused_identity_log="$TMPROOT/reused-identity.log"
reused_identity_lock="$reused_identity_state/default._10/worker.lock"
mkdir -p "$reused_identity_lock"
printf '%s\t%s\n' "$$" unrelated-reused-owner > "$reused_identity_lock/owner"
TMUX_TITLE_TRANSITION_STATE_DIR="$reused_identity_state" TMUX_TITLE_TRANSITION_LOG="$reused_identity_log" \
PATH="$transition_bin:$PATH" "$TITLE_TRANSITION" %10 0001 reused-identity 0
assert_file_line "$reused_identity_log" $'label-end\treused-identity' "PID reuse with mismatched process identity recovers lock"

owner_race_state="$TMPROOT/owner-race-state"
owner_race_log="$TMPROOT/owner-race.log"
owner_race_lock="$owner_race_state/default._5/worker.lock"
mkdir -p "$owner_race_lock" "$owner_race_state/default._5/requests"
: > "$owner_race_log"
owner_race_identity=owner-race-live-process
bash -c 'sleep 2; :' "$owner_race_identity" &
owner_race_live_pid=$!
TMUX_TITLE_TRANSITION_STATE_DIR="$owner_race_state" TMUX_TITLE_TRANSITION_LOG="$owner_race_log" \
PATH="$transition_bin:$PATH" "$TITLE_TRANSITION" %5 0001 owner-race 0 &
owner_race_pid=$!
sleep 0.02
printf '%s\t%s\n' "$owner_race_live_pid" "$owner_race_identity" > "$owner_race_lock/owner.tmp.test"
mv "$owner_race_lock/owner.tmp.test" "$owner_race_lock/owner"
sleep 0.06
: > "$owner_race_state/default._5/requests/0002"
wait_for_process_exit "$owner_race_pid" "contender exits stale after owner metadata race"
assert_equals "$(cat "$owner_race_lock/owner")" "$owner_race_live_pid"$'\t'"$owner_race_identity" "contender preserves atomically published live owner metadata"
assert_file_not_contains "$owner_race_log" $'label-start\towner-race' "stale contender does not render during metadata race"
kill "$owner_race_live_pid" 2>/dev/null || true
wait "$owner_race_live_pid" 2>/dev/null || true
rm -rf "$owner_race_lock" "$owner_race_state/default._5/requests/0002"

socket_state="$TMPROOT/socket-transition-state"
TMUX_TITLE_TRANSITION_STATE_DIR="$socket_state" TMUX="$TMPROOT/socket-a/shared,1,1" \
TMUX_TITLE_TRANSITION_LOG="$transition_log" PATH="$transition_bin:$PATH" \
  "$TITLE_TRANSITION" %7 0001 first-socket 0
TMUX_TITLE_TRANSITION_STATE_DIR="$socket_state" TMUX="$TMPROOT/socket-b/shared,1,1" \
TMUX_TITLE_TRANSITION_LOG="$transition_log" PATH="$transition_bin:$PATH" \
  "$TITLE_TRANSITION" %7 0001 second-socket 0
assert_equals "$(find "$socket_state" -name completed -type f | wc -l | tr -d ' ')" "2" "full tmux socket paths have distinct transition state keys"

transition_xdg="$TMPROOT/transition-xdg"
transition_private_tmp="$TMPROOT/transition-private-tmp"
transition_home="$TMPROOT/transition-home"
mkdir -p "$transition_xdg" "$transition_private_tmp" "$transition_home"
(
  unset TMUX_TITLE_TRANSITION_STATE_DIR
  XDG_RUNTIME_DIR="$transition_xdg" TMPDIR="$transition_private_tmp" HOME="$transition_home" \
  TMUX_TITLE_TRANSITION_LOG="$transition_log" PATH="$transition_bin:$PATH" \
    "$TITLE_TRANSITION" %3 0001 xdg 0
)
assert_file_line "$transition_xdg/tmux-title-transition/default._3/completed" 0001 "transition prefers XDG runtime state"
assert_no_file "$transition_private_tmp/tmux-title-transition-${UID:-$(id -u)}" "XDG runtime state wins over private TMPDIR"

(
  unset TMUX_TITLE_TRANSITION_STATE_DIR XDG_RUNTIME_DIR
  TMPDIR="$transition_private_tmp" HOME="$transition_home" \
  TMUX_TITLE_TRANSITION_LOG="$transition_log" PATH="$transition_bin:$PATH" \
    "$TITLE_TRANSITION" %6 0001 private-tmp 0
)
assert_file_line "$transition_private_tmp/tmux-title-transition-${UID:-$(id -u)}/default._6/completed" 0001 "transition preserves private TMPDIR fallback"

(
  unset TMUX_TITLE_TRANSITION_STATE_DIR XDG_RUNTIME_DIR TMPDIR
  HOME="$transition_home" TMUX_TITLE_TRANSITION_LOG="$transition_log" PATH="$transition_bin:$PATH" \
    "$TITLE_TRANSITION" %4 0001 home 0
)
transition_home_root="$transition_home/.local/state/tmux-title-transition"
assert_file_line "$transition_home_root/default._4/completed" 0001 "transition uses HOME state instead of shared tmp fallback"
if transition_home_mode="$(stat -c '%a' "$transition_home_root" 2>/dev/null)"; then
  :
else
  transition_home_mode="$(stat -f '%Lp' "$transition_home_root")"
fi
assert_equals "$transition_home_mode" 700 "transition state root is user-private"

zsh_hook_home="$TMPROOT/zsh-hook-home"
zsh_hook_log="$TMPROOT/zsh-hook.log"
zsh_hook_bin="$TMPROOT/zsh-hook-bin"
mkdir -p "$zsh_hook_home" "$zsh_hook_bin"
cat >"$zsh_hook_bin/tmux-title-transition" <<'STUB'
#!/usr/bin/env bash
sleep 2
printf 'transition\t%s\t%s\t%s\n' "${1:-}" "${3:-}" "${4:-}" >> "$TMUX_REMOTE_TITLE_HOOK_LOG"
printf 'request\t%s\n' "${2:-}" >> "$TMUX_REMOTE_TITLE_HOOK_LOG"
STUB
cat >"$zsh_hook_bin/tmux-sync-pane-border-status" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$zsh_hook_bin/tmux-title-transition" "$zsh_hook_bin/tmux-sync-pane-border-status"
SECONDS=0
HOME="$zsh_hook_home" \
TMUX=/tmp/tmux-test \
TMUX_PANE=%1 \
SSH_CONNECTION="127.0.0.1 1 127.0.0.1 2" \
TMUX_REMOTE_TITLE_HOOK_LOG="$zsh_hook_log" \
PATH="$zsh_hook_bin:$PATH" \
  zsh -fc "source '$REPO_ROOT/roles/common/templates/dotfiles/zshrc.d/10-common-shell.zsh'; _tmux_window_title_preexec 'nvim content/post.md'; _tmux_window_title_precmd"
hook_elapsed="$SECONDS"
assert_less_than "$hook_elapsed" 2 "zsh title hooks dispatch without waiting for slow renderer"
wait_for_file_line "$zsh_hook_log" $'transition\t%1\tnvim\t1' "zsh preexec dispatches vim-suppressed transition"
wait_for_file_line "$zsh_hook_log" $'transition\t%1\tzsh\t0' "zsh precmd dispatches shell transition"
assert_file_matches "$zsh_hook_log" $'^request\t[0-9]{16,}\.' "zsh transition requests include an ordered timestamp"

zsh_command_log="$TMPROOT/zsh-command-hook.log"
HOME="$zsh_hook_home" \
TMUX=/tmp/tmux-test \
TMUX_PANE=%1 \
TMUX_REMOTE_TITLE_HOOK_LOG="$zsh_command_log" \
PATH="$zsh_hook_bin:$PATH" \
  zsh -fc "source '$REPO_ROOT/roles/common/templates/dotfiles/zshrc.d/10-common-shell.zsh'; TMUX_PANE=%alias; _tmux_window_title_preexec 'v README.md' 'nvim README.md' 'nvim README.md'; TMUX_PANE=%alias-fallback; _tmux_window_title_preexec 'v README.md' 'nvim README.md'; TMUX_PANE=%assignment; _tmux_window_title_preexec 'FOO=bar nvim README.md'; TMUX_PANE=%command; _tmux_window_title_preexec 'command nvim README.md'; TMUX_PANE=%env; _tmux_window_title_preexec 'env FOO=bar nvim README.md'; TMUX_PANE=%sudo; _tmux_window_title_preexec 'sudo nvim README.md'; TMUX_PANE=%sudo-option; _tmux_window_title_preexec 'sudo -u root nvim README.md'; TMUX_PANE=%exec; _tmux_window_title_preexec 'exec nvim README.md'; TMUX_PANE=%exec-option; _tmux_window_title_preexec 'exec -a editor nvim README.md'; TMUX_PANE=%noglob; _tmux_window_title_preexec 'noglob nvim README.md'; TMUX_PANE=%nocorrect; _tmux_window_title_preexec 'nocorrect nvim README.md'; TMUX_PANE=%time; _tmux_window_title_preexec 'time nvim README.md'; TMUX_PANE=%time-option; _tmux_window_title_preexec 'time -p nvim README.md'; TMUX_PANE=%builtin; _tmux_window_title_preexec 'builtin nvim README.md'; TMUX_PANE=%nohup; _tmux_window_title_preexec 'nohup -- nvim README.md'; TMUX_PANE=%path; _tmux_window_title_preexec \"'/usr/bin/nvim' 'content/post draft.md'\""
wait_for_file_line "$zsh_command_log" $'transition\t%alias\tnvim\t1' "zsh preexec uses alias-expanded executed command"
wait_for_file_line "$zsh_command_log" $'transition\t%alias-fallback\tnvim\t1' "zsh preexec falls back to alias-expanded command argument"
wait_for_file_line "$zsh_command_log" $'transition\t%assignment\tnvim\t1' "zsh preexec skips leading environment assignments"
wait_for_file_line "$zsh_command_log" $'transition\t%command\tnvim\t1' "zsh preexec skips command wrapper"
wait_for_file_line "$zsh_command_log" $'transition\t%env\tnvim\t1' "zsh preexec skips env wrapper and assignments"
wait_for_file_line "$zsh_command_log" $'transition\t%sudo\tnvim\t1' "zsh preexec skips sudo wrapper"
wait_for_file_line "$zsh_command_log" $'transition\t%sudo-option\tnvim\t1' "zsh preexec skips sudo options with arguments"
wait_for_file_line "$zsh_command_log" $'transition\t%exec\tnvim\t1' "zsh preexec skips exec modifier"
wait_for_file_line "$zsh_command_log" $'transition\t%exec-option\tnvim\t1' "zsh preexec skips exec options"
wait_for_file_line "$zsh_command_log" $'transition\t%noglob\tnvim\t1' "zsh preexec skips noglob modifier"
wait_for_file_line "$zsh_command_log" $'transition\t%nocorrect\tnvim\t1' "zsh preexec skips nocorrect modifier"
wait_for_file_line "$zsh_command_log" $'transition\t%time\tnvim\t1' "zsh preexec skips time modifier"
wait_for_file_line "$zsh_command_log" $'transition\t%time-option\tnvim\t1' "zsh preexec skips time options"
wait_for_file_line "$zsh_command_log" $'transition\t%builtin\tnvim\t1' "zsh preexec skips builtin prefix"
wait_for_file_line "$zsh_command_log" $'transition\t%nohup\tnvim\t1' "zsh preexec skips nohup prefix and options"
wait_for_file_line "$zsh_command_log" $'transition\t%path\tnvim\t1' "zsh preexec preserves quoted path parsing and vim suppression"
assert_file_not_contains "$zsh_command_log" $'\tv\t' "zsh preexec does not title alias name"

rollback_hook_log="$TMPROOT/zsh-rollback-hook.log"
HOME="$zsh_hook_home" \
TMUX=/tmp/tmux-test \
TMUX_PANE=%1 \
TMUX_REMOTE_TITLE_HOOK_LOG="$rollback_hook_log" \
PATH="$zsh_hook_bin:$PATH" \
  zsh -fc "source '$REPO_ROOT/roles/common/templates/dotfiles/zshrc.d/10-common-shell.zsh'; TMUX_TITLE_TRANSITION_NOW=2000000000000000; _tmux_title_transition_dispatch before-rollback; TMUX_TITLE_TRANSITION_NOW=1000000000000000; _tmux_title_transition_dispatch after-rollback; sleep 2.2"
rollback_before="$(sed -n '/^request\t.*\.0000000001$/ { s/^request\t//; p; q; }' "$rollback_hook_log")"
rollback_after="$(sed -n '/^request\t.*\.0000000002$/ { s/^request\t//; p; q; }' "$rollback_hook_log")"
assert_file_matches "$rollback_hook_log" $'^request\t2000000000000000\.' "test timestamp source controls transition request clock"
assert_lexically_after "$rollback_after" "$rollback_before" "same-shell request IDs remain ordered after wall-clock rollback"

# Non-vim foreground commands (agents) must keep the edge marker live so the
# outer tmux can use C-h/j/k/l edge fallback while the agent runs.
zsh_agent_log="$TMPROOT/zsh-agent-hook.log"
HOME="$zsh_hook_home" \
TMUX=/tmp/tmux-test \
TMUX_PANE=%1 \
SSH_CONNECTION="127.0.0.1 1 127.0.0.1 2" \
TMUX_REMOTE_TITLE_HOOK_LOG="$zsh_agent_log" \
PATH="$zsh_hook_bin:$PATH" \
  zsh -fc "source '$REPO_ROOT/roles/common/templates/dotfiles/zshrc.d/10-common-shell.zsh'; _tmux_window_title_preexec 'claude --resume'"
wait_for_file_line "$zsh_agent_log" $'transition\t%1\tclaude\t0' "zsh preexec keeps remote edge marker for non-vim command"

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
cat >"$stub_bin/tmux-label-format" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
chmod +x "$stub_bin/tmux-window-label" "$stub_bin/tmux-remote-title" "$stub_bin/tmux-label-format"

state_dir="$TMPROOT/state"
TMUX=1 \
TMUX_PANE="%1" \
TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
TMUX_AGENT_WORKTREE_PANE_TTY=/dev/null \
TMUX_PANE_LABEL_HOST_TAG=host-a \
PATH="$stub_bin:$PATH" \
  "$AGENT_WORKTREE" set "$repo_path"

assert_file_contains "$state_dir/%1.@agent_worktree_path" "$repo_path" "repo-start tmux writer stores explicit repo path"
assert_file_contains "$state_dir/%1.@task_label" "feature/label" "repo-start tmux writer captures branch identity"
assert_file_contains "$state_dir/%1.@task_source" "branch" "repo-start tmux writer stores branch source"
assert_file_contains "$state_dir/%1.@task_state" "active" "repo-start tmux writer activates branch identity"
assert_file_contains "$state_dir/%1.@pane-label" "(feature/label) label-repo | host-a" "repo-start tmux writer stores repo branch pane label"

cat >"$stub_bin/tmux-label-format" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "local" ] && [ "$2" = "$TMUX_LABEL_FORMAT_REPO_PATH" ]; then
  printf '(feature/label fj#42) label-repo\n'
fi
STUB
chmod +x "$stub_bin/tmux-label-format"

TMUX=1 \
TMUX_PANE="%8" \
TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
TMUX_AGENT_WORKTREE_PANE_TTY=/dev/null \
TMUX_PANE_LABEL_HOST_TAG=host-a \
TMUX_LABEL_FORMAT_REPO_PATH="$repo_path" \
PATH="$stub_bin:$PATH" \
  "$AGENT_WORKTREE" set "$repo_path"

assert_file_contains "$state_dir/%8.@pane-label" "(feature/label fj#42) label-repo" "repo-start tmux writer prefers formatter pane label"

cache_home="$TMPROOT/cache-home"
cache_state_dir="$TMPROOT/state-cache-link"
pr_url="https://forgejo.example.com/org/label-repo/pulls/42"
write_pr_status_cache "$cache_home" "$repo_path" forgejo 42 "$pr_url"

TMUX=1 \
TMUX_PANE="%10" \
TMUX_AGENT_WORKTREE_STATE_DIR="$cache_state_dir" \
TMUX_AGENT_WORKTREE_PANE_TTY=/dev/null \
TMUX_PANE_LABEL_HOST_TAG=host-a \
TMUX_LABEL_FORMAT_REPO_PATH="$repo_path" \
HOME="$cache_home" \
PATH="$stub_bin:$BIN_DIR:$PATH" \
  "$AGENT_WORKTREE" set "$repo_path"

assert_equals "$(cat "$cache_state_dir/%10.@pane-link")" "$pr_url" "repo-start tmux writer publishes bare cached PR URL"
assert_file_contains "$cache_state_dir/%10.@pane-link-source" "pr-status-cache" "repo-start tmux writer marks cached PR URL source"

manual_link_state_dir="$TMPROOT/state-manual-link"
mkdir -p "$manual_link_state_dir"
printf 'manual https://example.com/manual' > "$manual_link_state_dir/%11.@pane-link"

TMUX=1 \
TMUX_PANE="%11" \
TMUX_AGENT_WORKTREE_STATE_DIR="$manual_link_state_dir" \
TMUX_AGENT_WORKTREE_PANE_TTY=/dev/null \
TMUX_PANE_LABEL_HOST_TAG=host-a \
TMUX_LABEL_FORMAT_REPO_PATH="$repo_path" \
HOME="$TMPROOT/no-pr-cache-home" \
PATH="$stub_bin:$BIN_DIR:$PATH" \
  "$AGENT_WORKTREE" set "$repo_path"

assert_file_contains "$manual_link_state_dir/%11.@pane-link" "manual https://example.com/manual" "repo-start tmux writer preserves manual pane link without cached PR"

(
  cd "$repo_path"
  TMUX=1 \
  TMUX_PANE="%9" \
  TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  TMUX_AGENT_WORKTREE_PANE_TTY=/dev/null \
  TMUX_PANE_LABEL_HOST_TAG=host-a \
  TMUX_LABEL_FORMAT_REPO_PATH="$repo_path" \
  PATH="$stub_bin:$PATH" \
    "$AGENT_WORKTREE" sync-current
)

assert_file_contains "$state_dir/%9.@pane-label" "(feature/label fj#42) label-repo" "sync-current tmux writer prefers formatter pane label"

TMUX=1 \
TMUX_PANE="%1" \
TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
PATH="$stub_bin:$PATH" \
  "$AGENT_WORKTREE" clear

assert_no_file "$state_dir/%1.@agent_worktree_path" "ordinary tmux clear removes explicit repo path"
assert_no_file "$state_dir/%1.@agent_worktree_pid" "ordinary tmux clear removes explicit repo pid"
assert_file_contains "$state_dir/%1.@task_state" "active" "ordinary tmux clear does not complete task identity"
assert_file_contains "$state_dir/%1.@window-label" "feature/label" "ordinary tmux clear preserves active branch label"

TMUX=1 \
TMUX_PANE="%1" \
TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
PATH="$stub_bin:$PATH" \
  "$AGENT_WORKTREE" complete

assert_file_contains "$state_dir/%1.@task_state" "completed" "explicit tmux completion marks task identity"
assert_file_contains "$state_dir/%1.@window-label" "✓ feature/label" "explicit tmux completion marks branch label"
assert_no_file "$state_dir/%1.@agent_worktree_path" "explicit tmux completion clears repo path"
assert_no_file "$state_dir/%1.@pane-link" "explicit tmux completion clears pane link"

fake_tmux_dir="$TMPROOT/fake-tmux-bin"
window_log="$TMPROOT/window-label.log"
mkdir -p "$fake_tmux_dir"
cat >"$fake_tmux_dir/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  display-message)
    printf '@1__NMB_TMUX_FIELD__1__NMB_TMUX_FIELD__%s__NMB_TMUX_FIELD__/dev/null__NMB_TMUX_FIELD__%s__NMB_TMUX_FIELD__%s__NMB_TMUX_FIELD__%s__NMB_TMUX_FIELD__%%1\n' \
      "${TMUX_TEST_WINDOW_NAME:-old-window}" "${TMUX_TEST_PATH:-/tmp/project}" \
      "${TMUX_TEST_COMMAND-ssh}" "${TMUX_TEST_TITLE:-}"
    ;;
  show-options)
    case "${*: -1}" in
      @window-label) printf '%s' "${TMUX_TEST_WINDOW_LABEL:-}" ;;
      @task_state) printf '%s' "${TMUX_TEST_TASK_STATE:-${TMUX_TEST_LOCAL_TASK:+active}}" ;;
      @task_source) printf '%s' "${TMUX_TEST_TASK_SOURCE:-${TMUX_TEST_LOCAL_TASK:+branch}}" ;;
      @task_label) printf '%s' "${TMUX_TEST_TASK_LABEL:-${TMUX_TEST_LOCAL_TASK:+feature/durable-label}}" ;;
      @agent_kind) printf '%s' "${TMUX_TEST_AGENT_KIND:-}" ;;
      @agent_activity) printf '%s' "${TMUX_TEST_ACTIVITY:-}" ;;
      @pr_state) printf '%s' "${TMUX_TEST_PR_STATE:-}" ;;
    esac
    ;;
  set-option)
    printf '%s\n' "$*" >> "$TMUX_WINDOW_LABEL_LOG"
    [ "${TMUX_TEST_FAIL_MUTATION:-}" != set-option ] || exit 71
    ;;
  rename-window)
    printf '%s\n' "$*" >> "$TMUX_WINDOW_LABEL_LOG"
    [ "${TMUX_TEST_FAIL_MUTATION:-}" != rename-window ] || exit 72
    ;;
esac
STUB
chmod +x "$fake_tmux_dir/tmux"

TMUX_TEST_TITLE='(feature/remote) project | remote-host [nmb-edge=hjl]' \
TMUX_WINDOW_LABEL_LOG="$window_log" PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" "%1"
assert_file_contains "$window_log" "rename-window -t @1 feature/remote" "outer window extracts active remote branch"

: > "$window_log"
TMUX_TEST_TITLE='(feature) repo) foo | remote-host' \
TMUX_WINDOW_LABEL_LOG="$window_log" PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" "%1"
assert_file_contains "$window_log" "rename-window -t @1 feature" "outer window ignores closing-parenthesis text in repo context"

: > "$window_log"
TMUX_TEST_TITLE='✓ (feature/remote) project | remote-host' \
TMUX_WINDOW_LABEL_LOG="$window_log" PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" "%1"
assert_file_contains "$window_log" "rename-window -t @1 ✓ feature/remote" "outer window extracts completed remote branch"

: > "$window_log"
TMUX_TEST_TITLE='~ tmux label persistence · project | remote-host' \
TMUX_WINDOW_LABEL_LOG="$window_log" PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" "%1"
assert_file_contains "$window_log" "rename-window -t @1 ~ tmux label persistence" "outer window extracts provisional remote subject"

for separator_case in \
  '~ auth · billing · project | remote-host' \
  '~ auth | billing · project | remote-host'; do
  expected="${separator_case% · project | remote-host}"
  : > "$window_log"
  TMUX_TEST_TITLE="$separator_case" TMUX_WINDOW_LABEL_LOG="$window_log" \
    PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" "%1"
  assert_file_contains "$window_log" "rename-window -t @1 $expected" "outer window preserves provisional separators: $expected"
done

degraded_goal_wire='Fix stale tmux feedback indicator · new-machine-bootstrap | dev [nmb-task=goal] [nmb-ind=working,merged] [nmb-edge=hjkl]'
: > "$window_log"
TMUX_TEST_TITLE=dev TMUX_TEST_WINDOW_NAME="$degraded_goal_wire" \
TMUX_WINDOW_LABEL_LOG="$window_log" PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" "%1"
assert_file_contains "$window_log" \
  'rename-window -t @1 Fix stale tmux feedback indicator' \
  'host-only pane title extracts concise marked goal from window name'
assert_file_contains "$window_log" \
  'set-option -wq -t @1 @window-indicators ⏳#[fg=#8957e5]● ' \
  'host-only marked goal fallback captures formatted indicators'
assert_file_not_contains "$window_log" '[nmb-' \
  'host-only marked goal fallback leaks no transport metadata'

: > "$window_log"
TMUX_TEST_TITLE=dev \
TMUX_TEST_WINDOW_NAME='Untrusted goal · new-machine-bootstrap | dev [nmb-task=agent]' \
TMUX_WINDOW_LABEL_LOG="$window_log" PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" "%1"
assert_file_not_contains "$window_log" 'rename-window -t @1 Untrusted goal' \
  'host-only malformed marked window name fails closed'
assert_file_not_contains "$window_log" '[nmb-' \
  'host-only malformed marked window name leaks no transport metadata'

for degraded_fallback_case in \
  'remote-host^(feature/fallback) project | remote-host^feature/fallback^branch' \
  'remote-host^~ fallback goal · project | remote-host^~ fallback goal^provisional' \
  'remote-host^0: (feature/numeric) project | remote-host^feature/numeric^numeric nested'; do
  pane_host="${degraded_fallback_case%%^*}"
  remainder="${degraded_fallback_case#*^}"
  fallback_wire="${remainder%%^*}"
  remainder="${remainder#*^}"
  fallback_expected="${remainder%%^*}"
  fallback_name="${remainder#*^}"
  : > "$window_log"
  TMUX_TEST_TITLE="$pane_host" TMUX_TEST_WINDOW_NAME="$fallback_wire" \
  TMUX_WINDOW_LABEL_LOG="$window_log" PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" "%1"
  assert_file_contains "$window_log" "rename-window -t @1 $fallback_expected" \
    "host-only pane title preserves $fallback_name window-name fallback"
done

for remote_case in \
  '(feature/a)b) project | remote-host' \
  "(feature/$(printf 'a%.0s' {1..60})) project | remote-host" \
  "(feature/$(printf '界%.0s' {1..30})) project | remote-host" \
  "~ $(printf 'p%.0s' {1..60}) · project | remote-host" \
  "✓ (feature/$(printf '👩‍💻%.0s' {1..20})) project | remote-host"; do
  expected="$($TASK_LABEL extract-remote "$remote_case")"
  : > "$window_log"
  TMUX_TEST_TITLE="$remote_case" TMUX_WINDOW_LABEL_LOG="$window_log" \
    PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" "%1"
  assert_file_contains "$window_log" "rename-window -t @1 $expected" "outer window applies exact remote task contract: $expected"
done
assert_equals "$($TASK_LABEL extract-remote '(feature/a)b) project | remote-host')" 'feature/a)b' "remote parser preserves branch closing parenthesis"
assert_equals "$($TASK_LABEL extract-remote '(feature/x) project | remote-host [nmb-ind=working,draft] [nmb-edge=hj]')" 'feature/x' "remote parser strips indicator marker"
assert_equals "$($TASK_LABEL extract-remote 'Fix stale tmux feedback indicator · new-machine-bootstrap | dev [nmb-task=goal] [nmb-ind=working,merged] [nmb-edge=hjkl]')" "Fix stale tmux feedback indicator" "remote parser extracts explicit goal identity"
assert_equals "$($TASK_LABEL render-remote 'Fix stale tmux feedback indicator · new-machine-bootstrap | dev [nmb-task=goal] [nmb-ind=working,merged] [nmb-edge=hjkl]')" "(Fix stale tmux feedback indicator) new-machine-bootstrap | dev" "remote renderer hides task transport metadata"
assert_equals \
  "$($TASK_LABEL render-remote '0: repo | dev')" \
  'repo | dev' \
  'remote renderer normalizes numeric nested repository prefix'
for rejected_task_title in \
  'Unmarked bare goal · new-machine-bootstrap | dev' \
  'Invalid task source · new-machine-bootstrap | dev [nmb-task=agent]' \
  'Missing context ·  | dev [nmb-task=goal]' \
  'Unknown marker · new-machine-bootstrap | dev [nmb-task=goal] [nmb-unknown=value]'; do
  if "$TASK_LABEL" extract-remote "$rejected_task_title" >/dev/null 2>&1; then
    fail_case "remote parser rejects invalid task wire: $rejected_task_title" 'unexpected successful extraction'
  fi
  pass_case "remote parser rejects invalid task wire: $rejected_task_title"
done
branch_shaped_task_wire='(feature/x) project | remote-host [nmb-task=goal]'
for task_label_mode in extract-remote render-remote; do
  if "$TASK_LABEL" "$task_label_mode" "$branch_shaped_task_wire" >/dev/null 2>&1; then
    fail_case "$task_label_mode rejects task marker with invalid marked grammar" 'unexpected legacy branch fallback'
  fi
  pass_case "$task_label_mode rejects task marker with invalid marked grammar"
done
opaque_provisional_task_wire='~ explicit goal · project | remote-host [nmb-task=manual]'
assert_equals \
  "$($TASK_LABEL extract-remote "$opaque_provisional_task_wire")" \
  '~ explicit goal' \
  'marked task extraction preserves provisional-looking opaque subject'
assert_equals \
  "$($TASK_LABEL render-remote "$opaque_provisional_task_wire")" \
  '(~ explicit goal) project | remote-host' \
  'marked task rendering preserves provisional-looking opaque subject'
if "$TASK_LABEL" extract-remote-provisional "$opaque_provisional_task_wire" >/dev/null 2>&1; then
  fail_case 'provisional extractor rejects authoritative task marker' 'unexpected provisional adoption candidate'
fi
pass_case 'provisional extractor rejects authoritative task marker'
opaque_numeric_task_wire='12: explicit goal · project | remote-host [nmb-task=goal]'
assert_equals \
  "$($TASK_LABEL extract-remote "$opaque_numeric_task_wire")" \
  '12: explicit goal' \
  'marked task extraction preserves numeric opaque subject prefix'
assert_equals \
  "$($TASK_LABEL render-remote "$opaque_numeric_task_wire")" \
  '(12: explicit goal) project | remote-host' \
  'marked task rendering preserves numeric opaque subject prefix'
long_marked_goal="$(printf '👩‍💻%.0s' {1..21})"
long_marked_goal_top="$(printf '👩‍💻%.0s' {1..19})…"
long_marked_goal_wire="$long_marked_goal · project | remote-host [nmb-task=goal]"
assert_equals \
  "$($TASK_LABEL extract-remote "$long_marked_goal_wire")" \
  "$long_marked_goal_top" \
  'marked task extraction truncates top label by grapheme cell width'
assert_equals \
  "$($TASK_LABEL render-remote "$long_marked_goal_wire")" \
  "($long_marked_goal) project | remote-host" \
  'marked task rendering preserves full long detailed identity'
for malformed_edge in hh kh lh; do
  malformed_edge_title="Explicit goal · project | remote-host [nmb-task=goal] [nmb-edge=$malformed_edge]"
  for task_label_mode in extract-remote render-remote; do
    if "$TASK_LABEL" "$task_label_mode" "$malformed_edge_title" >/dev/null 2>&1; then
      fail_case "$task_label_mode rejects malformed edge marker: $malformed_edge" 'unexpected successful parsing'
    fi
    pass_case "$task_label_mode rejects malformed edge marker: $malformed_edge"
  done
done
assert_equals \
  "$($TASK_LABEL extract-remote-provisional '~ investigate title race · project | remote-host [nmb-ind=waiting,] [nmb-edge=hj]')" \
  'investigate title race' \
  'remote parser extracts raw provisional subject'
assert_equals \
  "$($TASK_LABEL extract-remote-provisional '~ auth · billing | migration · project | remote-host')" \
  'auth · billing | migration' \
  'remote parser preserves subject separators'
assert_equals \
  "$($TASK_LABEL extract-remote-provisional '~ preserve: ~ literal marker · project | remote-host')" \
  'preserve: ~ literal marker' \
  'remote parser preserves literal provisional syntax after subject colon'
assert_equals \
  "$($TASK_LABEL extract-remote-provisional '~ preserve: (literal) punctuation · project | remote-host')" \
  'preserve: (literal) punctuation' \
  'remote parser preserves literal branch syntax after subject colon'
assert_equals \
  "$($TASK_LABEL extract-remote-provisional '0: ~ nested task · project | remote-host')" \
  'nested task' \
  'remote parser normalizes numeric nested tmux prefix'
assert_equals \
  "$($TASK_LABEL extract-remote-provisional 'remote-session: ~ nested task · project | remote-host')" \
  'nested task' \
  'remote parser normalizes named nested tmux prefix'
assert_equals \
  "$($TASK_LABEL extract-remote 'remote-session: (feature/nested) project | remote-host')" \
  'feature/nested' \
  'remote parser normalizes named nested active title prefix'
long_remote_subject="$(printf '界%.0s' {1..60})"
assert_equals \
  "$($TASK_LABEL extract-remote-provisional "~ $long_remote_subject · project | remote-host")" \
  "$long_remote_subject" \
  'remote parser keeps canonical subject untruncated'
if "$TASK_LABEL" extract-remote-provisional 'plain project | remote-host' >/dev/null 2>&1; then
  fail_case 'remote parser rejects non-provisional title' 'unexpected successful extraction'
fi
pass_case 'remote parser rejects non-provisional title'

for malformed_provisional in \
  '~  · project | remote-host' \
  '~     · project | remote-host' \
  '~ subject ·  | remote-host' \
  '~ subject ·     | remote-host' \
  '~ subject · project | ' \
  '~ subject · project |     ' \
  '~ subject | remote-host' \
  '~ subject · project' \
  '~ subject · project | remote-host [nmb-ind=waiting,' \
  '~ subject · project | remote-host [nmb-edge=hj' \
  '~ subject · project | remote-host [nmb-unknown=value]'; do
  if "$TASK_LABEL" extract-remote-provisional "$malformed_provisional" >/dev/null 2>&1; then
    fail_case "remote parser rejects malformed provisional: $malformed_provisional" 'unexpected successful extraction'
  fi
  pass_case "remote parser rejects malformed provisional: $malformed_provisional"
done
control_only="$(printf '\033\a\001')"
if "$TASK_LABEL" extract-remote-provisional "~ $control_only · project | remote-host" >/dev/null 2>&1; then
  fail_case 'remote parser rejects control-only provisional subject' 'unexpected successful extraction'
fi
pass_case 'remote parser rejects control-only provisional subject'

: > "$window_log"
TMUX_TEST_TITLE='(feature/remote) project | remote-host [nmb-ind=working,draft] [nmb-edge=hjl]' \
TMUX_WINDOW_LABEL_LOG="$window_log" PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" "%1"
assert_file_contains "$window_log" "set-option -wq -t @1 @window-indicators ⏳#[fg=#808080]● " "remote marker stores formatted indicators"
assert_file_contains "$window_log" "rename-window -t @1 feature/remote" "remote marker keeps window name plain"

: > "$window_log"
if TMUX_TEST_TITLE='(feature/remote) project | remote-host [nmb-ind=working,draft]' \
  TMUX_TEST_FAIL_MUTATION=set-option TMUX_WINDOW_LABEL_LOG="$window_log" \
  PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" %1; then
  fail_case "window label reports indicator set failure" "unexpected successful status"
fi
pass_case "window label reports indicator set failure"
assert_file_contains "$window_log" "rename-window -t @1 feature/remote" \
  "indicator set failure does not skip required rename"

: > "$window_log"
if TMUX_TEST_TITLE='(feature/remote) project | remote-host' \
  TMUX_TEST_FAIL_MUTATION=set-option TMUX_WINDOW_LABEL_LOG="$window_log" \
  PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" %1; then
  fail_case "window label reports indicator unset failure" "unexpected successful status"
fi
pass_case "window label reports indicator unset failure"
assert_file_contains "$window_log" "rename-window -t @1 feature/remote" \
  "indicator unset failure does not skip required rename"

: > "$window_log"
if TMUX_TEST_TITLE='(feature/remote) project | remote-host' \
  TMUX_TEST_FAIL_MUTATION=rename-window TMUX_WINDOW_LABEL_LOG="$window_log" \
  PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" %1; then
  fail_case "window label reports required rename failure" "unexpected successful status"
fi
pass_case "window label reports required rename failure"
assert_file_contains "$window_log" "set-option -wqu -t @1 @window-indicators" \
  "required rename failure does not skip indicator mutation"

production_render_failure_state="$TMPROOT/production-render-failure-state"
production_render_failure_log="$TMPROOT/production-render-failure.log"
if ! SSH_CONNECTION=test TMUX_TITLE_TRANSITION_STATE_DIR="$production_render_failure_state" \
  TMUX_TITLE_TRANSITION_WINDOW_LABEL_BIN="$WINDOW_LABEL" \
  TMUX_TITLE_TRANSITION_REMOTE_TITLE_BIN="$transition_bin/tmux-remote-title" \
  TMUX_TITLE_TRANSITION_LOG="$production_render_failure_log" \
  TMUX_WINDOW_LABEL_LOG="$production_render_failure_log" \
  TMUX_TEST_TITLE='(feature/remote) project | remote-host' \
  TMUX_TEST_FAIL_MUTATION=rename-window PATH="$fake_tmux_dir:$transition_bin:$PATH" \
  "$TITLE_TRANSITION" %1 0001 ssh 0; then
  fail_case "production renderer failure remains best effort for transition caller" \
    "transition returned nonzero"
fi
pass_case "production renderer failure remains best effort for transition caller"
assert_file_contains "$production_render_failure_log" "rename-window -t @1 feature/remote" \
  "production transition attempts required window rename"
assert_file_not_contains "$production_render_failure_log" $'publish\t0\tpublish' \
  "production renderer mutation failure suppresses remote publication"

: > "$window_log"
TMUX_TEST_AGENT_KIND=pi TMUX_TEST_COMMAND=pi TMUX_TEST_LOCAL_TASK=1 \
TMUX_TEST_WINDOW_LABEL='feature/durable-label' TMUX_TEST_ACTIVITY=waiting TMUX_TEST_PR_STATE=approved \
TMUX_WINDOW_LABEL_LOG="$window_log" PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" "%1"
assert_file_contains "$window_log" "set-option -wq -t @1 @window-indicators 💬#[fg=#b5bd68]● " "live local pane state stores formatted indicators"
assert_file_contains "$window_log" "rename-window -t @1 feature/durable-label" "live local pane state keeps window name plain"

node_ps="$TMPROOT/window-label-node.ps"
printf '123 S+ node /opt/pi-coding-agent/dist/cli.js --offline\n' > "$node_ps"
: > "$window_log"
TMUX_TEST_AGENT_KIND=pi TMUX_TEST_COMMAND=node TMUX_TEST_LOCAL_TASK=1 \
TMUX_TEST_WINDOW_LABEL='feature/durable-label' \
TMUX_TEST_TITLE='(feature/remote) project | remote-host [nmb-ind=working,draft]' TMUX_TEST_ACTIVITY=waiting \
TMUX_WINDOW_LABEL_PS_FILE="$node_ps" TMUX_WINDOW_LABEL_LOG="$window_log" \
PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" "%1"
assert_file_contains "$window_log" "set-option -wq -t @1 @window-indicators 💬 " "foreground Pi Node identity wins over stale remote marker"
assert_file_contains "$window_log" "rename-window -t @1 feature/durable-label" "foreground Pi Node identity keeps managed title"

printf '124 S+ pi pi\n' > "$node_ps"
: > "$window_log"
TMUX_TEST_AGENT_KIND=pi TMUX_TEST_COMMAND=node TMUX_TEST_LOCAL_TASK=1 \
TMUX_TEST_WINDOW_LABEL='feature/durable-label' TMUX_WINDOW_LABEL_PS_FILE="$node_ps" \
TMUX_WINDOW_LABEL_LOG="$window_log" PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" "%1"
assert_file_contains "$window_log" "rename-window -t @1 feature/durable-label" "foreground Pi process identity preserves title when tmux reports Node"

printf '125 S+ node node server.js\n' > "$node_ps"
: > "$window_log"
TMUX_TEST_AGENT_KIND=pi TMUX_TEST_COMMAND=node TMUX_TEST_LOCAL_TASK=1 \
TMUX_TEST_WINDOW_LABEL='feature/durable-label' TMUX_TEST_PATH="$repo_path" \
TMUX_WINDOW_LABEL_PS_FILE="$node_ps" TMUX_WINDOW_LABEL_LOG="$window_log" \
PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" "%1"
assert_file_contains "$window_log" "rename-window -t @1 node | label-repo" "ordinary Node ignores stale Pi title"

: > "$window_log"
TMUX_TEST_AGENT_KIND=claude TMUX_TEST_COMMAND=node TMUX_TEST_LOCAL_TASK=1 \
TMUX_TEST_WINDOW_LABEL='Claude direct title' TMUX_TEST_PATH="$repo_path" \
TMUX_WINDOW_LABEL_PS_FILE="$node_ps" TMUX_WINDOW_LABEL_LOG="$window_log" \
PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" "%1"
assert_file_contains "$window_log" "rename-window -t @1 node | label-repo" "ordinary Node ignores stale Claude title"

for stale_node_case in \
  'pi|node app.js pi|stale Pi argv word' \
  'claude|node app.js claude|stale Claude argv word'; do
  stale_kind="${stale_node_case%%|*}"
  stale_remainder="${stale_node_case#*|}"
  stale_argv="${stale_remainder%%|*}"
  stale_name="${stale_remainder#*|}"
  printf '126 S+ node %s\n' "$stale_argv" > "$node_ps"
  : > "$window_log"
  TMUX_TEST_AGENT_KIND="$stale_kind" TMUX_TEST_COMMAND=node TMUX_TEST_LOCAL_TASK=1 \
  TMUX_TEST_WINDOW_LABEL='stale managed title' TMUX_TEST_PATH="$repo_path" \
  TMUX_WINDOW_LABEL_PS_FILE="$node_ps" TMUX_WINDOW_LABEL_LOG="$window_log" \
  PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" %1
  assert_file_contains "$window_log" "rename-window -t @1 node | label-repo" "$stale_name does not prove a live agent"
done

printf '125 S+ node /opt/node_modules/@anthropic-ai/claude-code/cli.js --resume\n' > "$node_ps"
: > "$window_log"
TMUX_TEST_AGENT_KIND=claude TMUX_TEST_COMMAND=node TMUX_TEST_LOCAL_TASK=1 \
TMUX_TEST_WINDOW_LABEL='Claude direct title' TMUX_WINDOW_LABEL_PS_FILE="$node_ps" \
TMUX_WINDOW_LABEL_LOG="$window_log" PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" "%1"
assert_file_contains "$window_log" "rename-window -t @1 Claude direct title" "foreground Claude Node identity preserves direct title"

: > "$window_log"
TMUX_TEST_AGENT_KIND=claude TMUX_TEST_COMMAND=claude TMUX_TEST_LOCAL_TASK=1 \
TMUX_TEST_WINDOW_LABEL='Claude direct title' TMUX_WINDOW_LABEL_LOG="$window_log" \
PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" "%1"
assert_file_contains "$window_log" "rename-window -t @1 Claude direct title" "direct Claude command preserves direct title"

: > "$window_log"
TMUX_TEST_WINDOW_NAME='feature/remote' TMUX_TEST_TITLE='(feature/remote) project | remote-host' \
TMUX_WINDOW_LABEL_LOG="$window_log" PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" "%1"
assert_file_contains "$window_log" "set-option -wqu -t @1 @window-indicators" "missing state clears formatted indicators when plain label is unchanged"
assert_file_not_contains "$window_log" "rename-window" "unchanged plain label does not trigger a rename"

: > "$window_log"
TMUX_TEST_AGENT_KIND=pi TMUX_TEST_COMMAND=pi \
TMUX_TEST_WINDOW_LABEL='feature/durable-label' TMUX_TEST_LOCAL_TASK=1 \
TMUX_WINDOW_LABEL_LOG="$window_log" PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" "%1"
assert_file_contains "$window_log" "rename-window -t @1 feature/durable-label" "live local window uses task-only cached label unchanged"

nested_path="$repo_path/content/posts"
mkdir -p "$nested_path"
: > "$window_log"
TMUX_TEST_AGENT_KIND=pi TMUX_TEST_TASK_STATE=provisional \
TMUX_TEST_TASK_SOURCE=agent TMUX_TEST_TASK_LABEL='Summer 2027 award flights' \
TMUX_TEST_WINDOW_LABEL='~ Summer 2027 award flights' \
TMUX_TEST_PATH="$nested_path" TMUX_TEST_COMMAND=nvim \
TMUX_WINDOW_LABEL_LOG="$window_log" PATH="$fake_tmux_dir:$PATH" \
  "$WINDOW_LABEL" %1
assert_file_contains "$window_log" 'rename-window -t @1 nvim | label-repo' \
  'non-agent command ignores stale agent title and uses Git root'
assert_file_contains "$window_log" 'set-option -wqu -t @1 @window-indicators' \
  'non-agent command clears managed indicators'

: > "$window_log"
TMUX_TEST_AGENT_KIND=pi TMUX_TEST_TASK_STATE=provisional \
TMUX_TEST_TASK_SOURCE=agent TMUX_TEST_TASK_LABEL='Summer 2027 award flights' \
TMUX_TEST_WINDOW_LABEL='~ Summer 2027 award flights' \
TMUX_TEST_PATH="$nested_path" TMUX_TEST_COMMAND=pi \
TMUX_WINDOW_LABEL_LOG="$window_log" PATH="$fake_tmux_dir:$PATH" \
  "$WINDOW_LABEL" %1
assert_file_contains "$window_log" 'rename-window -t @1 ~ Summer 2027 award flights' \
  'live Pi command preserves cached agent title'

: > "$window_log"
TMUX_TEST_AGENT_KIND=pi TMUX_TEST_TASK_STATE=provisional \
TMUX_TEST_TASK_SOURCE=agent TMUX_TEST_TASK_LABEL='Summer 2027 award flights' \
TMUX_TEST_WINDOW_LABEL='~ Summer 2027 award flights' \
TMUX_TEST_PATH="$nested_path" TMUX_TEST_COMMAND=zsh \
TMUX_WINDOW_LABEL_LOG="$window_log" PATH="$fake_tmux_dir:$PATH" \
  "$WINDOW_LABEL" %1 nvim
assert_file_contains "$window_log" 'rename-window -t @1 nvim | label-repo' \
  'explicit command override controls non-agent title'

: > "$window_log"
TMUX_TEST_PATH="$plain_path" TMUX_TEST_COMMAND=nvim \
TMUX_WINDOW_LABEL_LOG="$window_log" PATH="$fake_tmux_dir:$PATH" \
  "$WINDOW_LABEL" %1
assert_file_contains "$window_log" 'rename-window -t @1 nvim | plain-dir' \
  'non-agent command uses current non-Git directory'

: > "$window_log"
TMUX_TEST_PATH="$plain_path" TMUX_TEST_COMMAND='' \
TMUX_WINDOW_LABEL_LOG="$window_log" PATH="$fake_tmux_dir:$PATH" \
  "$WINDOW_LABEL" %1
assert_file_contains "$window_log" 'rename-window -t @1 zsh | plain-dir' \
  'empty override and pane command use zsh fallback'

sync_remote_log="$TMPROOT/sync-remote-title.log"
sync_remote_tmux_dir="$TMPROOT/sync-remote-title-bin"
mkdir -p "$sync_remote_tmux_dir"
cat >"$sync_remote_tmux_dir/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  display-message)
    printf '@9__NMB_TMUX_FIELD__1__NMB_TMUX_FIELD__ssh__NMB_TMUX_FIELD__/dev/null__NMB_TMUX_FIELD__%s__NMB_TMUX_FIELD__%s\n' "$TMUX_TEST_TITLE" "${TMUX_TEST_WINDOW_NAME:-old-window}"
    ;;
  rename-window)
    printf '%s\n' "$*" >> "$TMUX_SYNC_REMOTE_LOG"
    ;;
esac
STUB
chmod +x "$sync_remote_tmux_dir/tmux"

for task_case in \
  'feature/remote|(feature/remote) project | remote-host' \
  '✓ feature/remote|✓ (feature/remote) project | remote-host' \
  '~ tmux label persistence|~ tmux label persistence · project | remote-host'; do
  expected="${task_case%%|*}"
  title="${task_case#*|}"
  : > "$sync_remote_log"
  TMUX_TEST_TITLE="$title" TMUX_SYNC_REMOTE_LOG="$sync_remote_log" \
    PATH="$sync_remote_tmux_dir:$PATH" "$SYNC_REMOTE_TITLE" %9
  assert_file_contains "$sync_remote_log" "rename-window -t @9 $expected" "remote sync extracts task-only label: $expected"
done

for separator_case in \
  '~ auth · billing · project | remote-host' \
  '~ auth | billing · project | remote-host'; do
  expected="${separator_case% · project | remote-host}"
  : > "$sync_remote_log"
  TMUX_TEST_TITLE="$separator_case" TMUX_SYNC_REMOTE_LOG="$sync_remote_log" \
    PATH="$sync_remote_tmux_dir:$PATH" "$SYNC_REMOTE_TITLE" %9
  assert_file_contains "$sync_remote_log" "rename-window -t @9 $expected" "remote sync preserves provisional separators: $expected"
done

for remote_case in \
  "(feature/$(printf 'a%.0s' {1..60})) project | remote-host" \
  "✓ (feature/$(printf '界%.0s' {1..30})) project | remote-host" \
  "~ $(printf '👩‍💻%.0s' {1..20}) · project | remote-host" \
  '(feature/a)b) project | remote-host'; do
  expected="$($TASK_LABEL extract-remote "$remote_case")"
  : > "$sync_remote_log"
  TMUX_TEST_TITLE="$remote_case" TMUX_SYNC_REMOTE_LOG="$sync_remote_log" \
    PATH="$sync_remote_tmux_dir:$PATH" "$SYNC_REMOTE_TITLE" %9
  assert_file_contains "$sync_remote_log" "rename-window -t @9 $expected" "remote sync applies exact capped task contract: $expected"
done

tmux_37_dir="$TMPROOT/tmux-37-bin"
tmux_37_hook_dir="$TMPROOT/tmux-37-hook-bin"
hook_log="$TMPROOT/tmux-37-hook.log"
sync_log="$TMPROOT/tmux-37-sync.log"
window_log="$TMPROOT/tmux-37-window.log"
mkdir -p "$tmux_37_dir" "$tmux_37_hook_dir"
: > "$hook_log"
: > "$sync_log"
: > "$window_log"
cat >"$tmux_37_dir/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  display-message)
    output="${*: -1}"
    output="${output//'#{window_id}'/@37}"
    output="${output//'#{pane_active}'/1}"
    output="${output//'#{window_name}'/}"
    output="${output//'#{pane_tty}'//dev/null}"
    output="${output//'#{pane_current_path}'//tmp/project}"
    output="${output//'#{pane_current_command}'/${TMUX_37_COMMAND:-ssh}}"
    output="${output//'#{pane_title}'/${TMUX_37_TITLE:-(feature/tmux-37) project | remote-host}}"
    output="${output//'#{pane_id}'/%37}"
    output="${output//$'\t'/_}"
    printf '%s\n' "$output"
    ;;
  show-options)
    if [ "${*: -1}" = '@pane-title-structured' ] && [ -n "${TMUX_37_STRUCTURED_STATE:-}" ]; then
      cat "$TMUX_37_STRUCTURED_STATE"
    fi
    ;;
  set-option)
    if [ -n "${TMUX_37_ACTIVITY_LOG:-}" ]; then
      printf 'tmux %s\n' "$*" >> "$TMUX_37_ACTIVITY_LOG"
    fi
    if [[ "$*" = *' -u '* ]] && [ "${*: -1}" = '@pane-title-structured' ] && [ -n "${TMUX_37_STRUCTURED_STATE:-}" ]; then
      rm -f "$TMUX_37_STRUCTURED_STATE"
    fi
    ;;
  rename-window)
    printf '%s\n' "$*" >> "$TMUX_37_RENAME_LOG"
    ;;
esac
STUB
cat >"$tmux_37_hook_dir/tmux-sync-remote-title" <<'STUB'
#!/usr/bin/env bash
if [ -n "${TMUX_37_HOOK_LOG:-}" ]; then
  printf 'tmux-sync-remote-title %s\n' "$*" >> "$TMUX_37_HOOK_LOG"
fi
if [ -n "${TMUX_37_ACTIVITY_LOG:-}" ]; then
  printf 'tmux-sync-remote-title %s\n' "$*" >> "$TMUX_37_ACTIVITY_LOG"
fi
STUB
for helper in tmux-sync-pane-border-status tmux-update-pane-label tmux-window-label; do
  cat >"$tmux_37_hook_dir/$helper" <<'STUB'
#!/usr/bin/env bash
if [ -n "${TMUX_37_ACTIVITY_LOG:-}" ]; then
  printf '%s %s\n' "${0##*/}" "$*" >> "$TMUX_37_ACTIVITY_LOG"
fi
STUB
done
chmod +x "$tmux_37_dir/tmux" "$tmux_37_hook_dir/"*

pane_label="$(PATH="$tmux_37_dir:$PATH" "$PANE_LABEL" /dev/null /tmp/project ssh %37)"
assert_equals "$pane_label" '(feature/tmux-37) project | remote-host' \
  'tmux 3.7 parsing preserves structured remote pane label'
explicit_goal_pane_label="$(TMUX_37_TITLE='Fix stale tmux feedback indicator · new-machine-bootstrap | dev [nmb-task=goal] [nmb-ind=working,merged] [nmb-edge=hjkl]' PATH="$tmux_37_dir:$PATH" "$PANE_LABEL" /dev/null /tmp/project ssh %37)"
assert_equals "$explicit_goal_pane_label" '(Fix stale tmux feedback indicator) new-machine-bootstrap | dev' \
  'pane label renders explicit remote goal without transport metadata'
numeric_repository_pane_label="$(TMUX_37_TITLE='0: repo | dev' PATH="$tmux_37_dir:$PATH" "$PANE_LABEL" /dev/null /tmp/project ssh %37)"
assert_equals "$numeric_repository_pane_label" 'repo | dev' \
  'pane label normalizes numeric nested repository prefix'
TMUX_37_HOOK_LOG="$hook_log" PATH="$tmux_37_dir:$tmux_37_hook_dir:$PATH" \
  "$PANE_TITLE_CHANGED" %37
assert_file_contains "$hook_log" 'tmux-sync-remote-title %37' \
  'tmux 3.7 parsing dispatches structured pane title synchronization'

sticky_state="$TMPROOT/tmux-37-sticky-structured"
sticky_activity_log="$TMPROOT/tmux-37-sticky-activity.log"
printf '1' > "$sticky_state"
: > "$sticky_activity_log"
TMUX_37_TITLE=remote-host TMUX_37_COMMAND=ssh \
  TMUX_37_STRUCTURED_STATE="$sticky_state" TMUX_37_ACTIVITY_LOG="$sticky_activity_log" \
  PATH="$tmux_37_dir:$tmux_37_hook_dir:$PATH" "$PANE_TITLE_CHANGED" %37
assert_file_contains "$sticky_state" '1' \
  'tmux 3.7 parsing keeps structured state for degraded remote title'
assert_equals "$(cat "$sticky_activity_log")" '' \
  'tmux 3.7 parsing exits sticky remote-title path before clear and update helpers'

TMUX_37_RENAME_LOG="$sync_log" PATH="$tmux_37_dir:$PATH" \
  "$SYNC_REMOTE_TITLE" %37
assert_file_contains "$sync_log" 'rename-window -t @37 feature/tmux-37' \
  'tmux 3.7 parsing synchronizes remote window title'
TMUX_37_RENAME_LOG="$window_log" PATH="$tmux_37_dir:$PATH" \
  "$WINDOW_LABEL" %37
assert_file_contains "$window_log" 'rename-window -t @37 feature/tmux-37' \
  'tmux 3.7 parsing renders remote window label'

task_focus_state="$TMPROOT/task-focus-state"
task_focus_bin="$TMPROOT/task-focus-bin"
task_focus_log="$TMPROOT/task-focus-refresh.log"
mkdir -p "$task_focus_state" "$task_focus_bin"
cat >"$task_focus_bin/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  show-options)
    case "${*: -1}" in
      @task_state) printf '%s' "$TMUX_TASK_FOCUS_STATE" ;;
      @agent_worktree_path) ;;
    esac
    ;;
  set-option) printf 'unexpected set-option: %s\n' "$*" >&2; exit 1 ;;
esac
STUB
cat >"$task_focus_bin/tmux-agent-state" <<'STUB'
#!/usr/bin/env bash
printf '%s %s\n' "$TMUX_PANE" "$*" >> "$TMUX_TASK_FOCUS_LOG"
STUB
chmod +x "$task_focus_bin/tmux" "$task_focus_bin/tmux-agent-state"

for task_case in \
  'provisional|~ pre-branch subject|~ pre-branch subject · repo | host-a' \
  'active|feature/focus-durable|(feature/focus-durable) repo | host-a' \
  'completed|✓ feature/focus-durable|✓ (feature/focus-durable) repo | host-a'; do
  state="${task_case%%|*}"
  remainder="${task_case#*|}"
  top="${remainder%%|*}"
  bottom="${remainder#*|}"
  printf '%s' "$top" > "$task_focus_state/window-label"
  printf '%s' "$bottom" > "$task_focus_state/pane-label"
  : > "$task_focus_log"
  TMUX=1 TMUX_TASK_FOCUS_STATE="$state" TMUX_TASK_FOCUS_LOG="$task_focus_log" \
    TMUX_AGENT_STATE_BIN="$task_focus_bin/tmux-agent-state" PATH="$task_focus_bin:$PATH" \
    "$UPDATE_PANE_LABEL" %44
  assert_equals "$(cat "$task_focus_state/window-label")" "$top" "focus preserves exact $state task top without worktree path"
  assert_equals "$(cat "$task_focus_state/pane-label")" "$bottom" "focus preserves exact $state task bottom without worktree path"
  assert_file_contains "$task_focus_log" '%44 refresh' "focus delegates $state task pane to shared renderer"
done

focus_state="$TMPROOT/focus-remote-state"
focus_tmux_dir="$TMPROOT/focus-remote-bin"
mkdir -p "$focus_state" "$focus_tmux_dir"
printf '%s' '(feature/remote) project | dev-host' > "$focus_state/pane-label"
printf '%s' '1' > "$focus_state/structured"
printf '%s' 'feature/remote' > "$focus_state/window-name"
printf '%s' 'dev-host' > "$focus_state/pane-title"
printf '%s' 'ssh' > "$focus_state/pane-command"
cat >"$focus_tmux_dir/tmux" <<'STUB'
#!/usr/bin/env bash
state="$TMUX_FOCUS_STATE"
case "$1" in
  display-message)
    format="${*: -1}"
    case "$format" in
      '#{window_id}__NMB_TMUX_FIELD__'*)
        printf '@12__NMB_TMUX_FIELD__1__NMB_TMUX_FIELD__%s__NMB_TMUX_FIELD__/dev/null__NMB_TMUX_FIELD__/tmp/local-project__NMB_TMUX_FIELD__%s__NMB_TMUX_FIELD__%s__NMB_TMUX_FIELD__%%12\n' \
          "$(cat "$state/window-name")" "$(cat "$state/pane-command")" "$(cat "$state/pane-title")"
        ;;
      '#{window_id}') printf '@12\n' ;;
      '#{pane_tty}|#{pane_current_path}|#{pane_current_command}|#{pane_title}')
        printf '/dev/null|/tmp/local-project|%s|%s\n' \
          "$(cat "$state/pane-command")" "$(cat "$state/pane-title")"
        ;;
      '#{pane_tty}|#{pane_current_path}|#{pane_current_command}')
        printf '/dev/null|/tmp/local-project|%s\n' "$(cat "$state/pane-command")"
        ;;
      *pane_title*window_name*)
        printf '%s__NMB_TMUX_FIELD__%s\n' "$(cat "$state/pane-title")" "$(cat "$state/window-name")"
        ;;
    esac
    ;;
  show-options)
    key="${*: -1}"
    case "$key" in
      @pane-title-structured) cat "$state/structured" ;;
      @pane-label) cat "$state/pane-label" ;;
      @window-label|@agent_worktree_path) ;;
    esac
    ;;
  set-option)
    case "$*" in
      *' -u '*)
        key="${*: -1}"
        [ "$key" != '@pane-title-structured' ] || rm -f "$state/structured"
        ;;
      *)
        key="${*: -2:1}"
        value="${*: -1}"
        case "$key" in
          @pane-label) printf '%s' "$value" > "$state/pane-label" ;;
          @pane-title-structured) printf '1' > "$state/structured" ;;
        esac
        ;;
    esac
    ;;
  rename-window)
    printf '%s' "${*: -1}" > "$state/window-name"
    ;;
esac
STUB
chmod +x "$focus_tmux_dir/tmux"

TMUX_FOCUS_STATE="$focus_state" PATH="$focus_tmux_dir:$PATH" "$WINDOW_LABEL" %12
TMUX_FOCUS_STATE="$focus_state" PATH="$focus_tmux_dir:$PATH" "$UPDATE_PANE_LABEL" %12
assert_equals "$(cat "$focus_state/pane-label")" '(feature/remote) project | dev-host' "focus refresh preserves contextual remote pane cache after degraded title"
assert_equals "$(cat "$focus_state/window-name")" 'feature/remote' "focus refresh preserves task-only top after degraded title"
assert_file_contains "$focus_state/structured" '1' "focus refresh keeps structured marker while pane remains remote"

printf '%s' '(feature/new-label) project | dev-host' > "$focus_state/pane-title"
TMUX_FOCUS_STATE="$focus_state" PATH="$focus_tmux_dir:$PATH" "$UPDATE_PANE_LABEL" %12
assert_equals "$(cat "$focus_state/pane-label")" '(feature/new-label) project | dev-host' "valid structured update replaces contextual pane cache"

printf '%s' 'zsh' > "$focus_state/pane-command"
printf '%s' 'shell' > "$focus_state/pane-title"
TMUX_FOCUS_STATE="$focus_state" PATH="$focus_tmux_dir:$PATH" "$UPDATE_PANE_LABEL" %12
assert_no_file "$focus_state/structured" "leaving remote command clears structured marker"
if [ "$(cat "$focus_state/pane-label")" = '(feature/new-label) project | dev-host' ]; then
  fail_case "leaving remote command replaces contextual pane cache" "stale remote pane label remained"
fi
pass_case "leaving remote command replaces contextual pane cache"

remote_window_label_log="$TMPROOT/window-label-remote-priority.log"
remote_window_label_tmux_dir="$TMPROOT/window-label-remote-priority-bin"
mkdir -p "$remote_window_label_tmux_dir"
cat >"$remote_window_label_tmux_dir/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  display-message)
    printf '@5__NMB_TMUX_FIELD__1__NMB_TMUX_FIELD__old-window__NMB_TMUX_FIELD__/dev/null__NMB_TMUX_FIELD__/tmp/current__NMB_TMUX_FIELD__ssh__NMB_TMUX_FIELD__%s__NMB_TMUX_FIELD__%%5\n' \
      "${TMUX_TEST_TITLE:-~ remote task · remote-repo | remote-host}"
    ;;
  show-options)
    case "${*: -1}" in
      @window-label) printf 'codex: tmux subject labels' ;;
      @task_state) [ -z "${TMUX_TEST_LOCAL_TASK:-}" ] || printf 'provisional' ;;
      @task_source) [ -z "${TMUX_TEST_LOCAL_TASK:-}" ] || printf 'agent' ;;
      @task_label) [ -z "${TMUX_TEST_LOCAL_TASK:-}" ] || printf 'tmux subject labels' ;;
      @agent_kind) printf '%s' "${TMUX_TEST_AGENT_KIND:-}" ;;
      @agent_worktree_path) printf '' ;;
      @pane-title-structured) printf '%s' "${TMUX_TEST_STRUCTURED:-}" ;;
      @pane-label) printf '%s' "${TMUX_TEST_PANE_LABEL:-(feature/label) label-repo | host-a}" ;;
    esac
    ;;
  rename-window)
    printf '%s\n' "$*" >> "$TMUX_WINDOW_LABEL_LOG"
    ;;
esac
STUB
chmod +x "$remote_window_label_tmux_dir/tmux"

TMUX_WINDOW_LABEL_LOG="$remote_window_label_log" PATH="$remote_window_label_tmux_dir:$PATH" "$WINDOW_LABEL" "%5"
assert_file_contains "$remote_window_label_log" "rename-window -t @5 ~ remote task" "structured provisional task overrides stale cached window label"

: > "$remote_window_label_log"
TMUX_TEST_AGENT_KIND=codex TMUX_TEST_LOCAL_TASK=1 \
TMUX_WINDOW_LABEL_LOG="$remote_window_label_log" PATH="$remote_window_label_tmux_dir:$PATH" \
  "$WINDOW_LABEL" "%5" codex
assert_file_contains "$remote_window_label_log" "rename-window -t @5 codex: tmux subject labels" "live local task keeps cached window label precedence"

: > "$remote_window_label_log"
TMUX_TEST_TITLE=plain TMUX_PANE_LABEL_BIN="$PANE_LABEL" TMUX_WINDOW_LABEL_LOG="$remote_window_label_log" \
  PATH="$remote_window_label_tmux_dir:$PATH" "$WINDOW_LABEL" "%5"
assert_equals "$(cat "$remote_window_label_log")" "rename-window -t @5 ssh | current" "unowned stale window cache uses non-agent command and directory"

: > "$remote_window_label_log"
TMUX_TEST_TITLE=plain TMUX_TEST_STRUCTURED=1 TMUX_TEST_PANE_LABEL='stale local pane label' \
TMUX_PANE_LABEL_BIN="$PANE_LABEL" TMUX_WINDOW_LABEL_LOG="$remote_window_label_log" \
  PATH="$remote_window_label_tmux_dir:$PATH" "$WINDOW_LABEL" "%5"
assert_equals "$(cat "$remote_window_label_log")" "rename-window -t @5 ssh | current" "marked pane rejects nonstructured cached pane label"

cached_tmux_dir="$TMPROOT/fake-tmux-bin-cached"
cached_log="$TMPROOT/window-label-cached.log"
mkdir -p "$cached_tmux_dir"
cat >"$cached_tmux_dir/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  display-message)
    printf '@2__NMB_TMUX_FIELD__1__NMB_TMUX_FIELD__old-window__NMB_TMUX_FIELD__/dev/null__NMB_TMUX_FIELD__/tmp/project__NMB_TMUX_FIELD__pi__NMB_TMUX_FIELD____NMB_TMUX_FIELD__%%2\n'
    exit 0
    ;;
  show-options)
    for arg in "$@"; do
      case "$arg" in
        @pane-label)
          printf '(cached-branch) cached-repo | host-a\n'
          exit 0
          ;;
        @agent_worktree_path)
          printf '/tmp/agent-worktree\n'
          exit 0
          ;;
        @agent_kind)
          printf 'pi\n'
          exit 0
          ;;
      esac
    done
    exit 0
    ;;
  rename-window)
    printf '%s\n' "$*" >> "$TMUX_WINDOW_LABEL_LOG"
    exit 0
    ;;
esac
exit 0
STUB
chmod +x "$cached_tmux_dir/tmux"

TMUX_WINDOW_LABEL_LOG="$cached_log" PATH="$cached_tmux_dir:$PATH" "$WINDOW_LABEL" "%2"
assert_file_contains "$cached_log" "rename-window -t @2 (cached-branch) cached-repo" "agent panes use cached @pane-label for window name"

window_label_log="$TMPROOT/window-label-priority.log"
window_label_tmux_dir="$TMPROOT/window-label-priority-bin"
mkdir -p "$window_label_tmux_dir"
cat >"$window_label_tmux_dir/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  display-message)
    printf '@4__NMB_TMUX_FIELD__1__NMB_TMUX_FIELD__old-name__NMB_TMUX_FIELD__/dev/null__NMB_TMUX_FIELD__/tmp/current__NMB_TMUX_FIELD__codex__NMB_TMUX_FIELD__plain__NMB_TMUX_FIELD__%%4\n'
    ;;
  show-options)
    case "${*: -1}" in
      @window-label) printf 'codex: tmux subject labels' ;;
      @task_state) printf 'provisional' ;;
      @task_source) printf 'agent' ;;
      @task_label) printf 'tmux subject labels' ;;
      @agent_kind) printf 'codex' ;;
      @agent_worktree_path) printf '' ;;
      @pane-label) printf '(feature/label) label-repo | host-a' ;;
    esac
    ;;
  rename-window)
    printf '%s\n' "$*" >> "$TMUX_WINDOW_LABEL_LOG"
    ;;
esac
STUB
chmod +x "$window_label_tmux_dir/tmux"

TMUX_WINDOW_LABEL_LOG="$window_label_log" PATH="$window_label_tmux_dir:$PATH" "$WINDOW_LABEL" "%4"
assert_file_contains "$window_label_log" "rename-window -t @4 codex: tmux subject labels" "window labels prefer @window-label over @pane-label"

stale_tmux_dir="$TMPROOT/fake-tmux-bin-stale"
stale_log="$TMPROOT/window-label-stale.log"
mkdir -p "$stale_tmux_dir"
cat >"$stale_tmux_dir/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  display-message)
    printf '@3__NMB_TMUX_FIELD__1__NMB_TMUX_FIELD__old-window__NMB_TMUX_FIELD__/dev/null__NMB_TMUX_FIELD__/tmp/fresh-dir__NMB_TMUX_FIELD__zsh__NMB_TMUX_FIELD____NMB_TMUX_FIELD__%%3\n'
    exit 0
    ;;
  show-options)
    for arg in "$@"; do
      case "$arg" in
        @pane-label)
          printf 'stale-cached-label | host-a\n'
          exit 0
          ;;
        @agent_worktree_path)
          exit 0
          ;;
      esac
    done
    exit 0
    ;;
  rename-window)
    printf '%s\n' "$*" >> "$TMUX_WINDOW_LABEL_LOG"
    exit 0
    ;;
esac
exit 0
STUB
chmod +x "$stale_tmux_dir/tmux"

TMUX_PANE_LABEL_BIN="$PANE_LABEL" TMUX_PANE_LABEL_HOST_TAG=host-a TMUX_WINDOW_LABEL_LOG="$stale_log" \
  PATH="$stale_tmux_dir:$PATH" "$WINDOW_LABEL" "%3"
assert_file_contains "$stale_log" "rename-window -t @3 zsh | fresh-dir" "non-agent panes ignore @pane-label cache and render command with current path"

zshrc_template="$REPO_ROOT/roles/common/templates/dotfiles/zshrc.d/50-personal-dev-shell.zsh"
repo_end_wrapper="$TMPROOT/repo-end-wrapper.zsh"
awk '/^repo-end\(\)/,/^}/' "$zshrc_template" > "$repo_end_wrapper"
assert_file_not_contains "$repo_end_wrapper" "worktree_sync_tmux_state" "repo-end shell wrapper leaves completed tmux label intact"

bash_profile_template="$REPO_ROOT/roles/macos/templates/dotfiles/bash_profile"
bash_repo_end_wrapper="$TMPROOT/repo-end-wrapper.bash"
awk '/^repo-end\(\)/,/^}/' "$bash_profile_template" > "$bash_repo_end_wrapper"
assert_file_not_contains "$bash_repo_end_wrapper" "worktree_sync_tmux_state" "repo-end bash wrapper leaves completed tmux label intact"

assert_link_before_label "$REPO_ROOT/roles/macos/templates/dotfiles/tmux.conf" "macOS pane border renders PR link before label"
assert_link_before_label "$REPO_ROOT/roles/linux/files/dotfiles/tmux.conf" "Linux pane border renders PR link before label"
for config in \
  "$REPO_ROOT/roles/macos/templates/dotfiles/tmux.conf" \
  "$REPO_ROOT/roles/linux/files/dotfiles/tmux.conf"; do
  assert_file_contains "$config" '#{@pane-label}' "$config bottom bar consumes cached pane label"
  assert_file_contains "$config" '#{E:@window-indicators}#{?#{||:#{window_activity_flag},#{window_bell_flag}},#[fg=black#,nodim],#[fg=colour252#,nodim]}#{window_name}' "$config inactive window restores activity-or-bell-aware text color and intensity"
  assert_file_contains "$config" '#{E:@window-indicators}#[fg=black,nodim]#{window_name}' "$config current window expands indicators and restores text color and intensity"
  assert_file_contains "$config" "set -g window-status-current-style 'bg=colour51,fg=black,bold'" "$config current window keeps its cyan background"
  assert_file_contains "$config" "set -g window-status-activity-style 'bg=colour51,fg=black,bold'" "$config activity highlight preserves indicator foreground colors"
  assert_file_contains "$config" "set -g window-status-bell-style 'bg=white,fg=black,bold'" "$config bell highlight uses a distinct white background"
done
assert_file_contains "$REPO_ROOT/roles/common/tasks/main.yml" '- tmux-task-label' "shared task label helper is provisioned"

leaked_git_ai_daemons="$(tmproot_git_ai_daemon_pids | tr '\n' ' ' | sed 's/ *$//')"
assert_equals "$leaked_git_ai_daemons" "" "no git-ai daemon leaks into the test HOME"

printf 'tmux label contract checks complete\n'
