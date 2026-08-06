#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
HOOK="$REPO_ROOT/roles/common/files/bin/codex-bind-tmux-pane"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

fail_case() { printf 'FAIL  %s\n%s\n' "$1" "$2" >&2; exit 1; }
assert_file_contains() {
  local path="$1" needle="$2" name="$3"
  grep -Fq -- "$needle" "$path" || fail_case "$name" "missing '$needle' in $path"
  printf 'PASS  %s\n' "$name"
}

stubdir="$TMPROOT/bin"
mkdir -p "$stubdir"
cat >"$stubdir/tmux" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMPROOT/tmux.log"
if [ "\$1" = show-options ]; then printf '%s' /some/worktree; fi
STUB
for helper in tmux-update-pane-label tmux-window-label tmux-agent-state; do
  cat >"$stubdir/$helper" <<STUB
#!/usr/bin/env bash
printf '%s %s\n' "$helper" "\$*" >> "$TMPROOT/helpers.log"
STUB
done
chmod +x "$stubdir"/*

printf '%s' \
  '{"session_id":"abc","cwd":"/tmp/launch","transcript_path":"/tmp/t.jsonl","source":"resume"}' |
  TMUX=1 TMUX_PANE="%17" PATH="$stubdir:$PATH" "$HOOK" >/dev/null

assert_file_contains "$TMPROOT/tmux.log" \
  'set-option -pt %17 @codex_session_id abc' \
  'resume binds session id to the exact pane'
assert_file_contains "$TMPROOT/tmux.log" \
  'set-option -pt %17 @codex_session_cwd /tmp/launch' \
  'resume binds cwd to the exact pane'
assert_file_contains "$TMPROOT/tmux.log" \
  'set-option -pt %17 @codex_session_transcript /tmp/t.jsonl' \
  'resume binds transcript to the exact pane'

printf 'codex-bind-tmux-pane checks complete\n'
