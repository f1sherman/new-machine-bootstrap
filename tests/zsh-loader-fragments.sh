#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${REPO_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)}"
ZSHRC="$ROOT/roles/common/templates/dotfiles/zshrc"
ZSHENV="$ROOT/roles/common/templates/dotfiles/zshenv"
COMMON_ZSHENV="$ROOT/roles/common/templates/dotfiles/zshenv.d/10-common-env.zsh"
COMMON_ZSHRC="$ROOT/roles/common/templates/dotfiles/zshrc.d/10-common-shell.zsh"
PERSONAL_ZSHRC="$ROOT/roles/common/templates/dotfiles/zshrc.d/50-personal-dev-shell.zsh"
tmp_dir="$(mktemp -d)"
tmp_dir="$(cd "$tmp_dir" && pwd -P)"

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

require_line() {
  local label="$1" pattern="$2" path="$3"

  if rg -q -F -- "$pattern" "$path"; then
    pass "$label"
  else
    fail "$label"
  fi
}

require_line "zshenv loader iterates fragments" \
  '.zshenv.d/*.zsh' \
  "$ZSHENV"
require_line "zshenv loader sources zshenv.local" \
  '. ~/.zshenv.local' \
  "$ZSHENV"
require_line "zshrc loader iterates fragments" \
  '.zshrc.d/*.zsh' \
  "$ZSHRC"
require_line "zshrc loader sources zshrc.local" \
  '. ~/.zshrc.local' \
  "$ZSHRC"

[[ -f "$COMMON_ZSHENV" ]] || fail "missing $COMMON_ZSHENV"
[[ -f "$COMMON_ZSHRC" ]] || fail "missing $COMMON_ZSHRC"
[[ -f "$PERSONAL_ZSHRC" ]] || fail "missing $PERSONAL_ZSHRC"

if rg -n '\.zshenv\.local|\.zshrc\.local' \
  "$COMMON_ZSHENV" "$COMMON_ZSHRC" "$PERSONAL_ZSHRC" >/dev/null 2>&1; then
  fail "fragment files should not source local override files"
else
  pass "fragment files do not source local override files"
fi

require_line "common shell fragment keeps canonical duss" \
  "alias duss=\"du -d 1 -h 2>/dev/null | sort -hr\"" \
  "$COMMON_ZSHRC"
require_line "personal shell fragment keeps codex-yolo" \
  "alias codex-yolo='codex --dangerously-bypass-approvals-and-sandbox'" \
  "$PERSONAL_ZSHRC"
if rg -q -F -- '/home/linuxbrew/.linuxbrew' "$COMMON_ZSHENV"; then
  fail "common env fragment should not hardcode Linux Homebrew"
else
  pass "common env fragment no longer hardcodes Linux Homebrew"
fi

cp "$ZSHRC" "$tmp_dir/.zshrc"
cp "$ZSHENV" "$tmp_dir/.zshenv"
mkdir -p "$tmp_dir/.zshrc.d" "$tmp_dir/.zshenv.d"

cat >"$tmp_dir/.zshenv.d/10-test.zsh" <<'EOF'
typeset -g ZSHENV_FRAGMENT_COUNT=$(( ${ZSHENV_FRAGMENT_COUNT:-0} + 1 ))
EOF

cat >"$tmp_dir/.zshenv.local" <<'EOF'
typeset -g ZSHENV_LOCAL_COUNT=$(( ${ZSHENV_LOCAL_COUNT:-0} + 1 ))
EOF

cat >"$tmp_dir/.zshrc.d/10-test.zsh" <<'EOF'
typeset -g ZSHRC_FRAGMENT_COUNT=$(( ${ZSHRC_FRAGMENT_COUNT:-0} + 1 ))
EOF

cat >"$tmp_dir/.zshrc.local" <<'EOF'
typeset -g ZSHRC_LOCAL_COUNT=$(( ${ZSHRC_LOCAL_COUNT:-0} + 1 ))
EOF

cat >"$tmp_dir/assert-counts.zsh" <<'EOF'
[[ "${ZSHENV_FRAGMENT_COUNT:-0}" == "1" ]] || { print -u2 "bad ZSHENV_FRAGMENT_COUNT=${ZSHENV_FRAGMENT_COUNT:-unset}"; exit 1; }
[[ "${ZSHENV_LOCAL_COUNT:-0}" == "1" ]] || { print -u2 "bad ZSHENV_LOCAL_COUNT=${ZSHENV_LOCAL_COUNT:-unset}"; exit 1; }
[[ "${ZSHRC_FRAGMENT_COUNT:-0}" == "1" ]] || { print -u2 "bad ZSHRC_FRAGMENT_COUNT=${ZSHRC_FRAGMENT_COUNT:-unset}"; exit 1; }
[[ "${ZSHRC_LOCAL_COUNT:-0}" == "1" ]] || { print -u2 "bad ZSHRC_LOCAL_COUNT=${ZSHRC_LOCAL_COUNT:-unset}"; exit 1; }
EOF

HOME="$tmp_dir" ZDOTDIR="$tmp_dir" zsh -lic 'source "$HOME/assert-counts.zsh"'
pass "loaders source fragments and locals exactly once"
