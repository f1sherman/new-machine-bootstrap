#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${REPO_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)}"
PERSONAL_ZSHRC="$ROOT/roles/common/templates/dotfiles/zshrc.d/50-personal-dev-shell.zsh"
CDXR_SCRIPT="$ROOT/roles/common/files/bin/cdxr"
COMMON_TASKS="$ROOT/roles/common/tasks/main.yml"
tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

fail() {
  printf 'FAIL  %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'PASS  %s\n' "$1"
}

rg -q -F -- "roles/common/files/bin/cdxr" "$COMMON_TASKS" \
  || fail "common provisioning installs cdxr"
pass "common provisioning installs cdxr"

home="$tmp_dir/home"
bin="$tmp_dir/bin"
session_dir="$home/.codex/sessions/2026/04/25"
pane_path="$tmp_dir/pane-path"
agent_path="$tmp_dir/agent-worktree"
log="$tmp_dir/codex.log"
tmux_log="$tmp_dir/tmux.log"
mkdir -p "$bin" "$session_dir" "$pane_path" "$agent_path"

cat >"$bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "$1" in
  show-option)
    option_name="${@: -1}"
    case "$option_name" in
      @codex_session_id)
        printf '%s\n' "${FAKE_CODEX_SESSION_ID:-}"
        ;;
      @codex_session_cwd)
        printf '%s\n' "${FAKE_CODEX_SESSION_CWD:-}"
        ;;
      @codex_session_transcript)
        printf '%s\n' "${FAKE_CODEX_SESSION_TRANSCRIPT:-}"
        ;;
      @agent_worktree_path)
        printf '%s\n' "$FAKE_AGENT_WORKTREE_PATH"
        ;;
    esac
    ;;
  display-message)
    format="${@: -1}"
    case "$format" in
      '#{pane_current_path}')
        printf '%s\n' "$FAKE_PANE_CURRENT_PATH"
        ;;
    esac
    ;;
  set-option)
    printf '%s\n' "$*" >> "$TMUX_TEST_LOG"
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$bin/tmux"

cat >"$bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s|%s\n' "$PWD" "$*" >> "$CODEX_TEST_LOG"
EOF
chmod +x "$bin/codex"

cat >"$session_dir/pane-newer.jsonl" <<JSONL
{"timestamp":"2026-04-25T16:00:00Z","type":"session_meta","payload":{"id":"pane-newer","timestamp":"2026-04-25T16:00:00Z","cwd":"$agent_path","git":{"branch":"feature/newer"}}}
JSONL
cat >"$session_dir/pane-older.jsonl" <<JSONL
{"timestamp":"2026-04-25T15:00:00Z","type":"session_meta","payload":{"id":"pane-older","timestamp":"2026-04-25T15:00:00Z","cwd":"$agent_path","git":{"branch":"feature/older"}}}
JSONL
cat >"$session_dir/pane-bound.jsonl" <<JSONL
{"timestamp":"2026-04-25T14:00:00Z","type":"session_meta","payload":{"id":"pane-bound","timestamp":"2026-04-25T14:00:00Z","cwd":"$agent_path","git":{"branch":"feature/bound"}}}
JSONL
cat >"$session_dir/other-pane.jsonl" <<JSONL
{"timestamp":"2026-04-25T17:00:00Z","type":"session_meta","payload":{"id":"other-pane","timestamp":"2026-04-25T17:00:00Z","cwd":"$pane_path","git":{"branch":"feature/other"}}}
JSONL
touch -t 202604251400 "$session_dir/pane-bound.jsonl"
touch -t 202604251500 "$session_dir/pane-older.jsonl"
touch -t 202604251600 "$session_dir/pane-newer.jsonl"
touch -t 202604251700 "$session_dir/other-pane.jsonl"

HOME="$home" \
PATH="$bin:$PATH" \
TMUX=/tmp/tmux-socket \
TMUX_PANE=%91 \
FAKE_CODEX_SESSION_ID= \
FAKE_CODEX_SESSION_CWD= \
FAKE_CODEX_SESSION_TRANSCRIPT= \
FAKE_AGENT_WORKTREE_PATH="$agent_path" \
FAKE_PANE_CURRENT_PATH="$pane_path" \
CODEX_TEST_LOG="$log" \
TMUX_TEST_LOG="$tmux_log" \
zsh -fic "
  source '$PERSONAL_ZSHRC'
  ! alias cr >/dev/null 2>&1
"
pass "cr alias is removed"

HOME="$home" \
PATH="$bin:$PATH" \
TMUX=/tmp/tmux-socket \
TMUX_PANE=%91 \
FAKE_CODEX_SESSION_ID= \
FAKE_CODEX_SESSION_CWD= \
FAKE_CODEX_SESSION_TRANSCRIPT= \
FAKE_AGENT_WORKTREE_PATH="$agent_path" \
FAKE_PANE_CURRENT_PATH="$pane_path" \
CODEX_TEST_LOG="$log" \
TMUX_TEST_LOG="$tmux_log" \
"$CDXR_SCRIPT"

expected="$agent_path|--dangerously-bypass-approvals-and-sandbox resume pane-newer"
actual="$(cat "$log")"
[[ "$actual" == "$expected" ]] || fail "cdxr uses codex-yolo for newest session in current pane worktree"
pass "cdxr uses codex-yolo for newest session in current pane worktree"

: >"$log"
HOME="$home" \
PATH="$bin:$PATH" \
TMUX=/tmp/tmux-socket \
TMUX_PANE=%91 \
FAKE_CODEX_SESSION_ID=pane-bound \
FAKE_CODEX_SESSION_CWD="$agent_path" \
FAKE_CODEX_SESSION_TRANSCRIPT="$session_dir/pane-bound.jsonl" \
FAKE_AGENT_WORKTREE_PATH="$agent_path" \
FAKE_PANE_CURRENT_PATH="$pane_path" \
CODEX_TEST_LOG="$log" \
TMUX_TEST_LOG="$tmux_log" \
"$CDXR_SCRIPT"

expected="$agent_path|--dangerously-bypass-approvals-and-sandbox resume pane-bound"
actual="$(cat "$log")"
[[ "$actual" == "$expected" ]] || fail "cdxr prefers pane-local session id over newest cwd match"
pass "cdxr prefers pane-local session id over newest cwd match"

: >"$log"
: >"$tmux_log"
HOME="$home" \
PATH="$bin:$PATH" \
TMUX=/tmp/tmux-socket \
TMUX_PANE=%91 \
FAKE_CODEX_SESSION_ID=other-pane \
FAKE_CODEX_SESSION_CWD="$pane_path" \
FAKE_CODEX_SESSION_TRANSCRIPT="$session_dir/other-pane.jsonl" \
FAKE_AGENT_WORKTREE_PATH="$agent_path" \
FAKE_PANE_CURRENT_PATH="$pane_path" \
CODEX_TEST_LOG="$log" \
TMUX_TEST_LOG="$tmux_log" \
"$CDXR_SCRIPT"

expected="$agent_path|--dangerously-bypass-approvals-and-sandbox resume pane-newer"
actual="$(cat "$log")"
[[ "$actual" == "$expected" ]] || fail "cdxr ignores stale pane-local session id"
pass "cdxr ignores stale pane-local session id"

if rg -q -F -- 'set-option -pt %91 @codex_session_id ' "$tmux_log" &&
   rg -q -F -- 'set-option -pt %91 @codex_session_cwd ' "$tmux_log" &&
   rg -q -F -- 'set-option -pt %91 @codex_session_transcript ' "$tmux_log"; then
  pass "cdxr clears stale pane-local session options"
else
  fail "cdxr clears stale pane-local session options"
fi

: >"$log"
: >"$tmux_log"
HOME="$home" \
PATH="$bin:$PATH" \
TMUX=/tmp/tmux-socket \
TMUX_PANE=%91 \
FAKE_CODEX_SESSION_ID=other-pane \
FAKE_CODEX_SESSION_CWD= \
FAKE_CODEX_SESSION_TRANSCRIPT= \
FAKE_AGENT_WORKTREE_PATH="$agent_path" \
FAKE_PANE_CURRENT_PATH="$pane_path" \
CODEX_TEST_LOG="$log" \
TMUX_TEST_LOG="$tmux_log" \
"$CDXR_SCRIPT"

expected="$agent_path|--dangerously-bypass-approvals-and-sandbox resume pane-newer"
actual="$(cat "$log")"
[[ "$actual" == "$expected" ]] || fail "cdxr ignores unverifiable pane-local session id"
pass "cdxr ignores unverifiable pane-local session id"

: >"$log"
: >"$tmux_log"
HOME="$home" \
PATH="$bin:$PATH" \
TMUX=/tmp/tmux-socket \
TMUX_PANE=%91 \
FAKE_CODEX_SESSION_ID=missing-session \
FAKE_CODEX_SESSION_CWD="$agent_path" \
FAKE_CODEX_SESSION_TRANSCRIPT="$tmp_dir/missing-session.jsonl" \
FAKE_AGENT_WORKTREE_PATH="$agent_path" \
FAKE_PANE_CURRENT_PATH="$pane_path" \
CODEX_TEST_LOG="$log" \
TMUX_TEST_LOG="$tmux_log" \
"$CDXR_SCRIPT"

expected="$agent_path|--dangerously-bypass-approvals-and-sandbox resume pane-newer"
actual="$(cat "$log")"
[[ "$actual" == "$expected" ]] || fail "cdxr ignores stale pane-local session id with matching cwd"
pass "cdxr ignores stale pane-local session id with matching cwd"
