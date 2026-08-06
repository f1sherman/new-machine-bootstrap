#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
HOOK="$REPO_ROOT/roles/common/files/bin/tmux-claude-session-start"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

fail_case() { printf 'FAIL  %s\n%s\n' "$1" "$2" >&2; exit 1; }
assert_file_contains() {
  local path="$1" needle="$2" name="$3"
  grep -Fq -- "$needle" "$path" || fail_case "$name" "missing '$needle' in $path"
  printf 'PASS  %s\n' "$name"
}
assert_file_empty() {
  local path="$1" name="$2"
  [ ! -s "$path" ] || fail_case "$name" "unexpected calls: $(cat "$path")"
  printf 'PASS  %s\n' "$name"
}

make_stubs() {
  local dir="$1" existing="$2"
  mkdir -p "$dir"
  cat >"$dir/tmux" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMPROOT/tmux.log"
if [ "\$1" = show-options ]; then
  case "\${*: -1}" in
    @persist_claude_session_id) printf '%s' "$existing" ;;
    @agent_worktree_path) printf '%s' /some/worktree ;;
  esac
fi
STUB
  for helper in tmux-update-pane-label tmux-window-label tmux-agent-state; do
    cat >"$dir/$helper" <<STUB
#!/usr/bin/env bash
printf '%s %s\n' "$helper" "\$*" >> "$TMPROOT/helpers.log"
STUB
  done
  chmod +x "$dir"/*
}

resume_bin="$TMPROOT/resume-bin"
make_stubs "$resume_bin" outer-session
: >"$TMPROOT/tmux.log"
printf '%s' '{"session_id":"resumed-session","source":"resume"}' |
  TMUX_PANE="%17" PATH="$resume_bin:$PATH" "$HOOK" >/dev/null
assert_file_contains "$TMPROOT/tmux.log" \
  'set-option -pt %17 @persist_claude_session_id resumed-session' \
  'resume replaces the exact-pane session binding'

nested_bin="$TMPROOT/nested-bin"
make_stubs "$nested_bin" outer-session
: >"$TMPROOT/tmux.log"
: >"$TMPROOT/helpers.log"
printf '%s' '{"session_id":"nested-session","source":"startup"}' |
  TMUX_PANE="%17" PATH="$nested_bin:$PATH" "$HOOK" >/dev/null
if grep -Fq 'set-option' "$TMPROOT/tmux.log"; then
  fail_case 'nested startup preserves outer session binding' "$(cat "$TMPROOT/tmux.log")"
fi
assert_file_empty "$TMPROOT/helpers.log" \
  'nested startup exits before label and identity side effects'

printf 'tmux-claude-session-start checks complete\n'
