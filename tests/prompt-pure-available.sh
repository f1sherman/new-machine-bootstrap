#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${REPO_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)}"
ZSHRC="$ROOT/roles/common/templates/dotfiles/zshrc"
COMMON_ZSHRC="$ROOT/roles/common/templates/dotfiles/zshrc.d/10-common-shell.zsh"

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

# Lay out a fake HOME with the zshrc loader + the common shell fragment and a
# stubbed prezto checkout that provides pure's autoload files.
mkdir -p \
  "$tmp_dir/.zshrc.d" \
  "$tmp_dir/.zprezto/modules/prompt/external/pure" \
  "$tmp_dir/.zprezto/modules/prompt/functions"
cp "$ZSHRC" "$tmp_dir/.zshrc"
cp "$COMMON_ZSHRC" "$tmp_dir/.zshrc.d/10-common-shell.zsh"

cat >"$tmp_dir/.zprezto/modules/prompt/external/pure/prompt_pure_setup" <<'EOF'
# Stub of sindresorhus/pure used by prompt-pure-available test.
typeset -g _TEST_PROMPT_PURE_RAN=1
EOF

cat >"$tmp_dir/.zprezto/modules/prompt/external/pure/async" <<'EOF'
# Stub async autoload for the prompt_pure_setup test stub.
:
EOF

# zshrc.local mirrors what provisioned machines do: `prompt pure`. The
# fragments loader must already have initialised `promptinit` and added the
# pure theme to fpath by the time this file is sourced.
cat >"$tmp_dir/.zshrc.local" <<'EOF'
prompt pure
EOF

# Check that `prompt pure` is accepted without a "command not found" error and
# that the autoloaded setup function ran.
HOME="$tmp_dir" ZDOTDIR="$tmp_dir" zsh -lic '
  [[ "${_TEST_PROMPT_PURE_RAN:-0}" == "1" ]] || {
    print -u2 "prompt pure setup did not run"; exit 1
  }
' >"$tmp_dir/out" 2>"$tmp_dir/err" || {
  printf 'stdout:\n%s\nstderr:\n%s\n' "$(cat "$tmp_dir/out")" "$(cat "$tmp_dir/err")" >&2
  fail "prompt pure should be available to ~/.zshrc.local"
}

if grep -q 'command not found: prompt' "$tmp_dir/err"; then
  printf 'stderr:\n%s\n' "$(cat "$tmp_dir/err")" >&2
  fail "'prompt' command must be initialised before ~/.zshrc.local runs"
fi

pass "prompt pure is available to ~/.zshrc.local after fragments load"
