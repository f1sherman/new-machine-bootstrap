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
mkdir -p "$bin" "$session_dir" "$pane_path" "$agent_path"

cat >"$bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "$1" in
  show-option)
    printf '%s\n' "$FAKE_AGENT_WORKTREE_PATH"
    ;;
  display-message)
    printf '%s\n' "$FAKE_PANE_CURRENT_PATH"
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
cat >"$session_dir/other-pane.jsonl" <<JSONL
{"timestamp":"2026-04-25T17:00:00Z","type":"session_meta","payload":{"id":"other-pane","timestamp":"2026-04-25T17:00:00Z","cwd":"$pane_path","git":{"branch":"feature/other"}}}
JSONL
touch -t 202604251500 "$session_dir/pane-older.jsonl"
touch -t 202604251600 "$session_dir/pane-newer.jsonl"
touch -t 202604251700 "$session_dir/other-pane.jsonl"

HOME="$home" \
PATH="$bin:$PATH" \
TMUX=/tmp/tmux-socket \
TMUX_PANE=%91 \
FAKE_AGENT_WORKTREE_PATH="$agent_path" \
FAKE_PANE_CURRENT_PATH="$pane_path" \
CODEX_TEST_LOG="$log" \
zsh -fic "
  source '$PERSONAL_ZSHRC'
  alias cr | grep -F \"cr=codex-resume-pane\" >/dev/null || exit 20
  codex-resume-pane
"

expected="$agent_path|--dangerously-bypass-approvals-and-sandbox resume pane-newer"
actual="$(cat "$log")"
[[ "$actual" == "$expected" ]] || fail "codex-resume-pane uses codex-yolo for newest session in current pane worktree"
pass "codex-resume-pane uses codex-yolo for newest session in current pane worktree"
