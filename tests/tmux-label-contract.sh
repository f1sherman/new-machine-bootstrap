#!/usr/bin/env bash
set -euo pipefail

unset TMUX TMUX_PANE

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
BIN_DIR="$REPO_ROOT/roles/common/files/bin"
PANE_LABEL="$BIN_DIR/tmux-pane-label"
AGENT_WORKTREE="$BIN_DIR/tmux-agent-worktree"
WINDOW_LABEL="$BIN_DIR/tmux-window-label"
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

assert_equals "$("$GLYPHS" working approved)" '🤖#[fg=#b5bd68]● ' "indicator glyphs render working+approved"
assert_equals "$("$GLYPHS" waiting "")" "⏳ " "indicator glyphs render waiting only"
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
    printf '/tmp/project\t/dev/null\t/dev/null\tzsh\t\n'
    ;;
  show-options)
    case "${*: -1}" in
      @task_label) printf '%s' "$TMUX_TEST_TASK_LABEL" ;;
      @task_state) printf '%s' "$TMUX_TEST_TASK_STATE" ;;
      @task_context) printf '%s' "$TMUX_TEST_TASK_CONTEXT" ;;
      @pane-label) printf '%s' "$TMUX_TEST_PANE_LABEL" ;;
    esac
    ;;
esac
STUB
chmod +x "$remote_task_tmux_dir/tmux"
remote_task_title="$(TMUX_PANE=%31 TMUX_REMOTE_TITLE_HOST_TAG=remote-host TMUX_TEST_TASK_LABEL=feature/durable-label TMUX_TEST_TASK_STATE=active TMUX_TEST_TASK_CONTEXT=project TMUX_TEST_PANE_LABEL='(feature/durable-label fj#42) project | wrong-host' PATH="$remote_task_tmux_dir:$PATH" "$REMOTE_TITLE" print)"
assert_equals "$remote_task_title" "(feature/durable-label) project | remote-host" "remote title builds active label from canonical task fields"

remote_pipe_title="$(TMUX_PANE=%31 TMUX_REMOTE_TITLE_HOST_TAG=remote-host TMUX_TEST_TASK_LABEL='auth | billing' TMUX_TEST_TASK_STATE=provisional TMUX_TEST_TASK_CONTEXT=project TMUX_TEST_PANE_LABEL='~ wrong rendered label | wrong-host' PATH="$remote_task_tmux_dir:$PATH" "$REMOTE_TITLE" print)"
assert_equals "$remote_pipe_title" "~ auth | billing · project | remote-host" "remote title preserves pipe in canonical provisional subject"

remote_dot_title="$(TMUX_PANE=%31 TMUX_REMOTE_TITLE_HOST_TAG=remote-host TMUX_TEST_TASK_LABEL='auth · billing' TMUX_TEST_TASK_STATE=provisional TMUX_TEST_TASK_CONTEXT='project | remote-host' TMUX_TEST_PANE_LABEL='~ wrong rendered label | wrong-host' PATH="$remote_task_tmux_dir:$PATH" "$REMOTE_TITLE" print)"
assert_equals "$remote_dot_title" "~ auth · billing · project | remote-host" "remote title preserves middle dot and avoids duplicate host"

remote_completed_title="$(TMUX_PANE=%31 TMUX_REMOTE_TITLE_HOST_TAG=remote-host TMUX_TEST_TASK_LABEL=feature/durable-label TMUX_TEST_TASK_STATE=completed TMUX_TEST_TASK_CONTEXT=project TMUX_TEST_PANE_LABEL='✓ wrong rendered label | wrong-host' PATH="$remote_task_tmux_dir:$PATH" "$REMOTE_TITLE" print)"
assert_equals "$remote_completed_title" "✓ (feature/durable-label) project | remote-host" "remote title builds completed label from canonical task fields"

zsh_hook_home="$TMPROOT/zsh-hook-home"
zsh_hook_log="$TMPROOT/zsh-hook.log"
zsh_hook_bin="$TMPROOT/zsh-hook-bin"
mkdir -p "$zsh_hook_home" "$zsh_hook_bin"
cat >"$zsh_hook_bin/tmux-remote-title" <<'STUB'
#!/usr/bin/env bash
printf '%s\t%s\n' "${TMUX_REMOTE_TITLE_SUPPRESS_EDGE:-0}" "${1:-}" >> "$TMUX_REMOTE_TITLE_HOOK_LOG"
STUB
cat >"$zsh_hook_bin/tmux-window-label" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
cat >"$zsh_hook_bin/tmux-sync-pane-border-status" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$zsh_hook_bin/tmux-remote-title" "$zsh_hook_bin/tmux-window-label" "$zsh_hook_bin/tmux-sync-pane-border-status"
HOME="$zsh_hook_home" \
TMUX=/tmp/tmux-test \
TMUX_PANE=%1 \
SSH_CONNECTION="127.0.0.1 1 127.0.0.1 2" \
TMUX_REMOTE_TITLE_HOOK_LOG="$zsh_hook_log" \
PATH="$zsh_hook_bin:$PATH" \
  zsh -fc "source '$REPO_ROOT/roles/common/templates/dotfiles/zshrc.d/10-common-shell.zsh'; _tmux_remote_title_preexec 'nvim'; _tmux_remote_title_precmd"
assert_file_contains "$zsh_hook_log" $'1\tpublish' "zsh preexec clears remote edge marker before vim-like command"
assert_file_contains "$zsh_hook_log" $'0\tpublish' "zsh precmd restores remote edge marker at prompt"

# Non-vim foreground commands (agents) must keep the edge marker live so the
# outer tmux can use C-h/j/k/l edge fallback while the agent runs.
zsh_agent_log="$TMPROOT/zsh-agent-hook.log"
HOME="$zsh_hook_home" \
TMUX=/tmp/tmux-test \
TMUX_PANE=%1 \
SSH_CONNECTION="127.0.0.1 1 127.0.0.1 2" \
TMUX_REMOTE_TITLE_HOOK_LOG="$zsh_agent_log" \
PATH="$zsh_hook_bin:$PATH" \
  zsh -fc "source '$REPO_ROOT/roles/common/templates/dotfiles/zshrc.d/10-common-shell.zsh'; _tmux_remote_title_preexec 'claude --resume'"
assert_file_contains "$zsh_agent_log" $'0\tpublish' "zsh preexec keeps remote edge marker for non-vim command"
assert_file_not_contains "$zsh_agent_log" $'1\tpublish' "zsh preexec does not suppress edge marker for non-vim command"

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
    printf '@1\t1\t%s\t/dev/null\t/tmp/project\t%s\t%s\t%%1\n' \
      "${TMUX_TEST_WINDOW_NAME:-old-window}" "${TMUX_TEST_COMMAND:-ssh}" "${TMUX_TEST_TITLE:-}"
    ;;
  show-options)
    case "${*: -1}" in
      @window-label) printf '%s' "${TMUX_TEST_WINDOW_LABEL:-}" ;;
      @task_state) [ -z "${TMUX_TEST_LOCAL_TASK:-}" ] || printf 'active' ;;
      @task_source) [ -z "${TMUX_TEST_LOCAL_TASK:-}" ] || printf 'branch' ;;
      @task_label) [ -z "${TMUX_TEST_LOCAL_TASK:-}" ] || printf 'feature/durable-label' ;;
      @agent_activity) printf '%s' "${TMUX_TEST_ACTIVITY:-}" ;;
      @pr_state) printf '%s' "${TMUX_TEST_PR_STATE:-}" ;;
    esac
    ;;
  set-option)
    printf '%s\n' "$*" >> "$TMUX_WINDOW_LABEL_LOG"
    ;;
  rename-window)
    printf '%s\n' "$*" >> "$TMUX_WINDOW_LABEL_LOG"
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

: > "$window_log"
TMUX_TEST_TITLE='(feature/remote) project | remote-host [nmb-ind=working,draft] [nmb-edge=hjl]' \
TMUX_WINDOW_LABEL_LOG="$window_log" PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" "%1"
assert_file_contains "$window_log" "set-option -wq -t @1 @window-indicators 🤖#[fg=#808080]● " "remote marker stores formatted indicators"
assert_file_contains "$window_log" "rename-window -t @1 feature/remote" "remote marker keeps window name plain"

: > "$window_log"
TMUX_TEST_TITLE='(feature/remote) project | remote-host' TMUX_TEST_ACTIVITY=waiting TMUX_TEST_PR_STATE=approved \
TMUX_WINDOW_LABEL_LOG="$window_log" PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" "%1"
assert_file_contains "$window_log" "set-option -wq -t @1 @window-indicators ⏳#[fg=#b5bd68]● " "local pane state stores formatted indicators"
assert_file_contains "$window_log" "rename-window -t @1 feature/remote" "local pane state keeps window name plain"

: > "$window_log"
TMUX_TEST_TITLE='(feature/remote) project | remote-host [nmb-ind=working,draft]' TMUX_TEST_ACTIVITY=waiting \
TMUX_WINDOW_LABEL_LOG="$window_log" PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" "%1"
assert_file_contains "$window_log" "set-option -wq -t @1 @window-indicators ⏳ " "local pane state wins over remote marker"
assert_file_contains "$window_log" "rename-window -t @1 feature/remote" "local precedence keeps window name plain"

: > "$window_log"
TMUX_TEST_TITLE='(feature/remote) project | remote-host' \
TMUX_WINDOW_LABEL_LOG="$window_log" PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" "%1"
assert_file_contains "$window_log" "set-option -wqu -t @1 @window-indicators" "missing state clears formatted indicators"

: > "$window_log"
TMUX_TEST_COMMAND=zsh TMUX_TEST_WINDOW_LABEL='feature/durable-label' TMUX_TEST_LOCAL_TASK=1 \
TMUX_WINDOW_LABEL_LOG="$window_log" PATH="$fake_tmux_dir:$PATH" "$WINDOW_LABEL" "%1"
assert_file_contains "$window_log" "rename-window -t @1 feature/durable-label" "local window uses task-only cached label unchanged"

sync_remote_log="$TMPROOT/sync-remote-title.log"
sync_remote_tmux_dir="$TMPROOT/sync-remote-title-bin"
mkdir -p "$sync_remote_tmux_dir"
cat >"$sync_remote_tmux_dir/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  display-message)
    printf '@9\t1\tssh\t/dev/null\t%s\t%s\n' "$TMUX_TEST_TITLE" "${TMUX_TEST_WINDOW_NAME:-old-window}"
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
      '#{window_id}'$'\t'*)
        printf '@12\t1\t%s\t/dev/null\t/tmp/local-project\t%s\t%s\t%%12\n' \
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
        printf '%s\t%s\n' "$(cat "$state/pane-title")" "$(cat "$state/window-name")"
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
    printf '@5\t1\told-window\t/dev/null\t/tmp/current\tssh\t%s\t%%5\n' \
      "${TMUX_TEST_TITLE:-~ remote task · remote-repo | remote-host}"
    ;;
  show-options)
    case "${*: -1}" in
      @window-label) printf 'codex: tmux subject labels' ;;
      @task_state) [ -z "${TMUX_TEST_LOCAL_TASK:-}" ] || printf 'provisional' ;;
      @task_source) [ -z "${TMUX_TEST_LOCAL_TASK:-}" ] || printf 'agent' ;;
      @task_label) [ -z "${TMUX_TEST_LOCAL_TASK:-}" ] || printf 'tmux subject labels' ;;
      @agent_worktree_path) printf '' ;;
      @pane-label) printf '(feature/label) label-repo | host-a' ;;
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
TMUX_TEST_LOCAL_TASK=1 TMUX_WINDOW_LABEL_LOG="$remote_window_label_log" PATH="$remote_window_label_tmux_dir:$PATH" "$WINDOW_LABEL" "%5"
assert_file_contains "$remote_window_label_log" "rename-window -t @5 codex: tmux subject labels" "valid local task keeps cached window label precedence"

: > "$remote_window_label_log"
TMUX_TEST_TITLE=plain TMUX_WINDOW_LABEL_LOG="$remote_window_label_log" PATH="$remote_window_label_tmux_dir:$PATH" "$WINDOW_LABEL" "%5"
assert_equals "$(cat "$remote_window_label_log")" "rename-window -t @5 current" "unowned stale window cache does not suppress host suffix stripping"

cached_tmux_dir="$TMPROOT/fake-tmux-bin-cached"
cached_log="$TMPROOT/window-label-cached.log"
mkdir -p "$cached_tmux_dir"
cat >"$cached_tmux_dir/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  display-message)
    printf '@2\t1\told-window\t/dev/null\t/tmp/project\tzsh\t\t%%2\n'
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
    printf '@4\t1\told-name\t/dev/null\t/tmp/current\tzsh\tplain\t%%4\n'
    ;;
  show-options)
    case "${*: -1}" in
      @window-label) printf 'codex: tmux subject labels' ;;
      @task_state) printf 'provisional' ;;
      @task_source) printf 'agent' ;;
      @task_label) printf 'tmux subject labels' ;;
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
    printf '@3\t1\told-window\t/dev/null\t/tmp/fresh-dir\tzsh\t\t%%3\n'
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

TMUX_PANE_LABEL_HOST_TAG=host-a TMUX_WINDOW_LABEL_LOG="$stale_log" PATH="$stale_tmux_dir:$PATH" "$WINDOW_LABEL" "%3"
assert_file_contains "$stale_log" "rename-window -t @3 fresh-dir" "non-agent panes ignore @pane-label cache and re-derive from current path"

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
  assert_file_contains "$config" '#{E:@window-indicators}#[fg=colour252,nodim]#{window_name}' "$config inactive window expands indicators and restores text color and intensity"
  assert_file_contains "$config" '#{E:@window-indicators}#[fg=black,nodim]#{window_name}' "$config current window expands indicators and restores text color and intensity"
done
assert_file_contains "$REPO_ROOT/roles/common/tasks/main.yml" '- tmux-task-label' "shared task label helper is provisioned"

leaked_git_ai_daemons="$(tmproot_git_ai_daemon_pids | tr '\n' ' ' | sed 's/ *$//')"
assert_equals "$leaked_git_ai_daemons" "" "no git-ai daemon leaks into the test HOME"

printf 'tmux label contract checks complete\n'
