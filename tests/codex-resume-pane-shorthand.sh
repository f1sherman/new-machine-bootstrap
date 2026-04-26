#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${REPO_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)}"
PERSONAL_ZSHRC="$ROOT/roles/common/templates/dotfiles/zshrc.d/50-personal-dev-shell.zsh"
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

home="$tmp_dir/home"
bin="$tmp_dir/bin"
session_dir="$home/.codex/sessions/2026/04/25"
pane_path="$tmp_dir/pane-path"
agent_path="$tmp_dir/agent-worktree"
log="$tmp_dir/codex.log"
tmux_log="$tmp_dir/tmux.log"
proc_root="$tmp_dir/proc"
mkdir -p "$bin" "$session_dir" "$pane_path" "$agent_path" "$proc_root/9100/fd"

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
      @agent_worktree_path)
        printf '%s\n' "$FAKE_AGENT_WORKTREE_PATH"
        ;;
    esac
    ;;
  display-message)
    format="${@: -1}"
    case "$format" in
      '#{pane_tty}')
        printf '%s\n' '/dev/pts/91'
        ;;
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

cat >"$bin/ps" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${FAKE_PS_LINE:-9100 S+ codex codex --dangerously-bypass-approvals-and-sandbox}"
EOF
chmod +x "$bin/ps"

cat >"$bin/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${FAKE_LSOF_OUTPUT:-}"
EOF
chmod +x "$bin/lsof"

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
cat >"$session_dir/pane-active.jsonl" <<JSONL
{"timestamp":"2026-04-25T18:00:00Z","type":"session_meta","payload":{"id":"pane-active","timestamp":"2026-04-25T18:00:00Z","cwd":"$agent_path","git":{"branch":"feature/active"}}}
JSONL
cat >"$session_dir/other-pane.jsonl" <<JSONL
{"timestamp":"2026-04-25T17:00:00Z","type":"session_meta","payload":{"id":"other-pane","timestamp":"2026-04-25T17:00:00Z","cwd":"$pane_path","git":{"branch":"feature/other"}}}
JSONL
ln -s "$session_dir/pane-active.jsonl" "$proc_root/9100/fd/47"
touch -t 202604251400 "$session_dir/pane-bound.jsonl"
touch -t 202604251500 "$session_dir/pane-older.jsonl"
touch -t 202604251600 "$session_dir/pane-newer.jsonl"
touch -t 202604251700 "$session_dir/other-pane.jsonl"
touch -t 202604251800 "$session_dir/pane-active.jsonl"

HOME="$home" \
PATH="$bin:$PATH" \
TMUX=/tmp/tmux-socket \
TMUX_PANE=%91 \
FAKE_CODEX_SESSION_ID= \
FAKE_AGENT_WORKTREE_PATH="$agent_path" \
FAKE_PANE_CURRENT_PATH="$pane_path" \
CODEX_TEST_LOG="$log" \
TMUX_TEST_LOG="$tmux_log" \
zsh -fic "
  source '$PERSONAL_ZSHRC'
  alias cr | grep -F \"cr=codex-resume-pane\" >/dev/null || exit 20
  codex-resume-pane
"

expected="$agent_path|--dangerously-bypass-approvals-and-sandbox resume pane-active"
actual="$(cat "$log")"
[[ "$actual" == "$expected" ]] || fail "codex-resume-pane uses codex-yolo for newest session in current pane worktree"
pass "codex-resume-pane uses codex-yolo for newest session in current pane worktree"

: >"$log"
HOME="$home" \
PATH="$bin:$PATH" \
TMUX=/tmp/tmux-socket \
TMUX_PANE=%91 \
FAKE_CODEX_SESSION_ID=pane-bound \
FAKE_AGENT_WORKTREE_PATH="$agent_path" \
FAKE_PANE_CURRENT_PATH="$pane_path" \
CODEX_TEST_LOG="$log" \
TMUX_TEST_LOG="$tmux_log" \
zsh -fic "
  source '$PERSONAL_ZSHRC'
  codex-resume-pane
"

expected="$agent_path|--dangerously-bypass-approvals-and-sandbox resume pane-bound"
actual="$(cat "$log")"
[[ "$actual" == "$expected" ]] || fail "codex-resume-pane prefers pane-local session id over newest cwd match"
pass "codex-resume-pane prefers pane-local session id over newest cwd match"

HOME="$home" \
PATH="$bin:$PATH" \
TMUX=/tmp/tmux-socket \
TMUX_PANE=%91 \
FAKE_CODEX_SESSION_ID= \
FAKE_AGENT_WORKTREE_PATH="$agent_path" \
FAKE_PANE_CURRENT_PATH="$pane_path" \
CODEX_TEST_LOG="$log" \
TMUX_TEST_LOG="$tmux_log" \
CODEX_SESSION_PROC_ROOT="$proc_root" \
zsh -fic "
  source '$PERSONAL_ZSHRC'
  [[ \"\$(_codex_active_session_id_for_pane %91)\" == pane-active ]] || exit 30
  _codex_publish_active_pane_session_id %91
"

if rg -q -F -- 'set-option -pt %91 @codex_session_id pane-active' "$tmux_log"; then
  pass "active Codex process publishes pane-local session id"
else
  fail "active Codex process publishes pane-local session id"
fi

: >"$tmux_log"
HOME="$home" \
PATH="$bin:$PATH" \
TMUX=/tmp/tmux-socket \
TMUX_PANE=%91 \
FAKE_CODEX_SESSION_ID= \
FAKE_AGENT_WORKTREE_PATH="$agent_path" \
FAKE_PANE_CURRENT_PATH="$pane_path" \
FAKE_PS_LINE='9101 S+ codex codex --dangerously-bypass-approvals-and-sandbox' \
FAKE_LSOF_OUTPUT="p9101
n$session_dir/pane-bound.jsonl" \
CODEX_TEST_LOG="$log" \
TMUX_TEST_LOG="$tmux_log" \
CODEX_SESSION_PROC_ROOT="$tmp_dir/missing-proc" \
zsh -fic "
  source '$PERSONAL_ZSHRC'
  [[ \"\$(_codex_active_session_id_for_pane %91)\" == pane-bound ]] || exit 40
  _codex_publish_active_pane_session_id %91
"

if rg -q -F -- 'set-option -pt %91 @codex_session_id pane-bound' "$tmux_log"; then
  pass "active Codex process publishes pane-local session id with lsof fallback"
else
  fail "active Codex process publishes pane-local session id with lsof fallback"
fi

: >"$tmux_log"
HOME="$home" \
PATH="$bin:$PATH" \
TMUX=/tmp/tmux-socket \
TMUX_PANE=%91 \
FAKE_CODEX_SESSION_ID= \
FAKE_AGENT_WORKTREE_PATH="$agent_path" \
FAKE_PANE_CURRENT_PATH="$pane_path" \
CODEX_TEST_LOG="$log" \
TMUX_TEST_LOG="$tmux_log" \
CODEX_SESSION_PROC_ROOT="$proc_root" \
zsh -fic "
  source '$PERSONAL_ZSHRC'
  _codex_session_preexec cr codex-resume-pane
  sleep 0.5
"

if rg -q -F -- 'set-option -pt %91 @codex_session_id pane-active' "$tmux_log"; then
  pass "preexec watcher starts for cr alias expansion"
else
  fail "preexec watcher starts for cr alias expansion"
fi
