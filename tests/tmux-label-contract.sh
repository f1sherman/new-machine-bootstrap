#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
BIN_DIR="$REPO_ROOT/roles/common/files/bin"
PANE_LABEL="$BIN_DIR/tmux-pane-label"
AGENT_WORKTREE="$BIN_DIR/tmux-agent-worktree"
WINDOW_LABEL="$BIN_DIR/tmux-window-label"
PANE_LINK="$BIN_DIR/tmux-pane-link"
REMOTE_TITLE="$BIN_DIR/tmux-remote-title"

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

remote_edge_title="$(TMUX_REMOTE_TITLE_PANE_PATH="$repo_path" TMUX_REMOTE_TITLE_CLIENT_TTY=/dev/null TMUX_REMOTE_TITLE_PANE_TTY=/dev/null TMUX_REMOTE_TITLE_HOST_TAG=remote-host TMUX_REMOTE_TITLE_PANE_COMMAND=tmux TMUX_REMOTE_TITLE_EDGE_FLAGS=hj "$REMOTE_TITLE" print)"
assert_equals "$remote_edge_title" "label-repo | remote-host [nmb-edge=hj]" "remote title publishes tmux edge marker"

remote_vim_title="$(TMUX_REMOTE_TITLE_PANE_PATH="$repo_path" TMUX_REMOTE_TITLE_CLIENT_TTY=/dev/null TMUX_REMOTE_TITLE_PANE_TTY=/dev/null TMUX_REMOTE_TITLE_HOST_TAG=remote-host TMUX_REMOTE_TITLE_PANE_COMMAND=nvim TMUX_REMOTE_TITLE_EDGE_FLAGS=hj "$REMOTE_TITLE" print)"
assert_equals "$remote_vim_title" "label-repo | remote-host" "remote title suppresses edge marker for vim panes"

remote_suppressed_title="$(TMUX_REMOTE_TITLE_PANE_PATH="$repo_path" TMUX_REMOTE_TITLE_CLIENT_TTY=/dev/null TMUX_REMOTE_TITLE_PANE_TTY=/dev/null TMUX_REMOTE_TITLE_HOST_TAG=remote-host TMUX_REMOTE_TITLE_PANE_COMMAND=zsh TMUX_REMOTE_TITLE_EDGE_FLAGS=hj TMUX_REMOTE_TITLE_SUPPRESS_EDGE=1 "$REMOTE_TITLE" print)"
assert_equals "$remote_suppressed_title" "label-repo | remote-host" "remote title can suppress stale edge marker while commands run"

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
assert_file_contains "$zsh_hook_log" $'1\tpublish' "zsh preexec clears remote edge marker before foreground command"
assert_file_contains "$zsh_hook_log" $'0\tpublish' "zsh precmd restores remote edge marker at prompt"

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

assert_no_file "$state_dir/%1.@agent_worktree_path" "repo-end tmux clearer removes explicit repo path"
assert_no_file "$state_dir/%1.@agent_worktree_pid" "repo-end tmux clearer removes explicit repo pid"
assert_file_contains "$state_dir/%1.@pane-label" "feature/label" "repo-end tmux clearer preserves completed work label"

subject_state_dir="$TMPROOT/state-subject-retained"
mkdir -p "$subject_state_dir"
printf 'codex' > "$subject_state_dir/%12.@agent_kind"
printf 'tmux subject labels' > "$subject_state_dir/%12.@agent_subject"
printf '%s' "$repo_path" > "$subject_state_dir/%12.@agent_worktree_path"
printf '12345' > "$subject_state_dir/%12.@agent_worktree_pid"
printf 'fj#42 https://example.com/pr/42' > "$subject_state_dir/%12.@pane-link"
printf 'pr-status-cache' > "$subject_state_dir/%12.@pane-link-source"
TMUX=1 \
TMUX_PANE="%12" \
TMUX_AGENT_WORKTREE_STATE_DIR="$subject_state_dir" \
TMUX_AGENT_STATE_DIR="$subject_state_dir" \
PATH="$stub_bin:$BIN_DIR:$PATH" \
  "$AGENT_WORKTREE" clear
assert_no_file "$subject_state_dir/%12.@agent_worktree_path" "repo-end tmux clearer removes subject pane repo path"
assert_no_file "$subject_state_dir/%12.@agent_worktree_pid" "repo-end tmux clearer removes subject pane repo pid"
assert_no_file "$subject_state_dir/%12.@pane-link" "repo-end tmux clearer removes subject pane PR link"
assert_no_file "$subject_state_dir/%12.@pane-link-source" "repo-end tmux clearer removes subject pane PR link source"
assert_file_contains "$subject_state_dir/%12.@agent_subject" "tmux subject labels" "repo-end tmux clearer retains agent subject"
assert_file_contains "$subject_state_dir/%12.@agent_subject_stale" "1" "repo-end tmux clearer marks subject stale"
assert_file_contains "$subject_state_dir/%12.@agent_subject_done" "1" "repo-end tmux clearer marks subject done"
assert_file_contains "$subject_state_dir/%12.@window-label" "✓ codex: tmux subject labels" "repo-end tmux clearer visibly marks subject done"
assert_file_not_contains "$subject_state_dir/%12.@window-label" "stale" "repo-end tmux clearer does not visibly mark stale"

stale_window_state_dir="$TMPROOT/state-stale-window-label"
mkdir -p "$stale_window_state_dir"
printf 'codex' > "$stale_window_state_dir/%13.@agent_kind"
printf '%s' "$repo_path" > "$stale_window_state_dir/%13.@agent_worktree_path"
printf 'codex: old task subject' > "$stale_window_state_dir/%13.@window-label"
TMUX=1 \
TMUX_PANE="%13" \
TMUX_AGENT_WORKTREE_STATE_DIR="$stale_window_state_dir" \
TMUX_AGENT_STATE_DIR="$stale_window_state_dir" \
PATH="$stub_bin:$BIN_DIR:$PATH" \
  "$AGENT_WORKTREE" clear
assert_file_contains "$stale_window_state_dir/%13.@agent_completed_window_label" "✓ codex: old task subject" "repo-end tmux clearer stores completed window label without subject"
assert_file_contains "$stale_window_state_dir/%13.@window-label" "✓ codex: old task subject" "repo-end tmux clearer preserves completed window label without subject"

fake_tmux_dir="$TMPROOT/fake-tmux-bin"
window_log="$TMPROOT/window-label.log"
mkdir -p "$fake_tmux_dir"
cat >"$fake_tmux_dir/tmux" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "display-message" ]; then
  printf '@1\t1\told-window\t/dev/null\t/tmp/project\tssh\t(feature/remote) project | remote-host [nmb-edge=hjl]\t%%1\n'
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
assert_file_contains "$window_log" "rename-window -t @1 (feature/remote) project" "window labels strip hostname from structured labels"

remote_window_label_log="$TMPROOT/window-label-remote-priority.log"
remote_window_label_tmux_dir="$TMPROOT/window-label-remote-priority-bin"
mkdir -p "$remote_window_label_tmux_dir"
cat >"$remote_window_label_tmux_dir/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  display-message)
    printf '@5\t1\t(feature/remote-window) remote-repo | remote-host\t/dev/null\t/tmp/current\tssh\t(feature/remote-title) remote-repo | remote-host\t%%5\n'
    ;;
  show-options)
    case "${*: -1}" in
      @window-label) printf 'codex: tmux subject labels' ;;
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
assert_file_contains "$remote_window_label_log" "rename-window -t @5 codex: tmux subject labels" "window labels prefer @window-label over structured remote label"

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

leaked_git_ai_daemons="$(tmproot_git_ai_daemon_pids | tr '\n' ' ' | sed 's/ *$//')"
assert_equals "$leaked_git_ai_daemons" "" "no git-ai daemon leaks into the test HOME"

printf 'tmux label contract checks complete\n'
