#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
CLAUDE_HOOK="$REPO_ROOT/roles/common/files/claude/hooks/remind-agent-subject-on-prompt.sh"
CODEX_HOOK="$REPO_ROOT/roles/common/files/bin/codex-remind-agent-subject-on-prompt"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

pass_case() { printf 'PASS  %s\n' "$1"; }
fail_case() { printf 'FAIL  %s\n%s\n' "$1" "$2" >&2; exit 1; }

assert_contains() {
  local haystack="$1" needle="$2" name="$3"
  [[ "$haystack" == *"$needle"* ]] || fail_case "$name" "missing '$needle' in: $haystack"
  pass_case "$name"
}

assert_empty() {
  local value="$1" name="$2"
  [[ -z "$value" ]] || fail_case "$name" "expected empty, got: $value"
  pass_case "$name"
}

make_state_stub() {
  local status="$1" stubdir="$2"
  mkdir -p "$stubdir"
  cat >"$stubdir/tmux-agent-state" <<STUB
#!/usr/bin/env bash
[[ "\${1:-}" == status ]] || exit 1
printf '%s' '$status'
STUB
  chmod +x "$stubdir/tmux-agent-state"
}

run_hook() {
  local hook="$1" status="$2" payload="$3" stubdir="$4"
  make_state_stub "$status" "$stubdir"
  printf '%s' "$payload" | TMUX=1 TMUX_PANE=%1 PATH="$stubdir:$PATH" "$hook"
}

for hook_name in claude codex; do
  case "$hook_name" in
    claude) hook="$CLAUDE_HOOK" ;;
    codex) hook="$CODEX_HOOK" ;;
  esac

  missing_out="$(run_hook "$hook" "" '{"prompt":"improve tmux labels"}' "$TMPROOT/$hook_name-missing")"
  assert_contains "$missing_out" "tmux-agent-subject set" "$hook_name ordinary prompt reminds when task missing"
  assert_contains "$missing_out" "provisional label will be replaced by the feature branch" "$hook_name explains provisional branch replacement"

  completed_out="$(run_hook "$hook" $'completed\tbranch\told-task\n' '{"prompt":"start another task"}' "$TMPROOT/$hook_name-completed")"
  assert_contains "$completed_out" "tmux-agent-subject set" "$hook_name completed task reminds for next subject"

  provisional_out="$(run_hook "$hook" $'provisional\tagent\tshort subject\n' '{"prompt":"continue"}' "$TMPROOT/$hook_name-provisional")"
  assert_empty "$provisional_out" "$hook_name provisional task skips reminder"

  active_out="$(run_hook "$hook" $'active\tbranch\tfeature/current\n' '{"prompt":"continue"}' "$TMPROOT/$hook_name-active")"
  assert_empty "$active_out" "$hook_name active task skips reminder"
done

outside_out="$(printf '%s' '{"prompt":"improve tmux labels"}' | env -u TMUX -u TMUX_PANE "$CODEX_HOOK")"
assert_empty "$outside_out" "prompt hook quietly skips outside tmux"

printf 'agent subject hook checks complete\n'
