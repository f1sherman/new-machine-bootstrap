#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
zshrc_fragment="$repo_root/roles/common/templates/dotfiles/zshrc.d/10-common-shell.zsh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

sourceable_zshrc="$tmpdir/10-common-shell.zsh"
registrations="$tmpdir/hook-registrations"
actual_output="$tmpdir/actual-output"
expected_output="$tmpdir/expected-output"
mkdir -p "$tmpdir/home"
: > "$registrations"

awk '
  $0 == "autoload -Uz add-zsh-hook" {
    print "add-zsh-hook() {"
    print "  print -r -- \"$1:$2\" >> \"$FOCUS_HOOK_REGISTRATIONS\""
    print "}"
    next
  }
  { print }
' "$zshrc_fragment" > "$sourceable_zshrc"

status=0
if ! env \
  HOME="$tmpdir/home" \
  FOCUS_HOOK_REGISTRATIONS="$registrations" \
  zsh -fc "source '$sourceable_zshrc'; _reset_terminal_focus_reporting" \
  > "$actual_output"; then
  printf 'FAIL  focus reset function is defined and callable\n' >&2
  status=1
fi

printf '\033[?1004l' > "$expected_output"
if ! cmp -s "$expected_output" "$actual_output"; then
  printf 'FAIL  focus reset writes exactly ESC [ ? 1 0 0 4 l\n' >&2
  printf 'expected: ' >&2
  od -An -tx1 "$expected_output" >&2
  printf 'actual:   ' >&2
  od -An -tx1 "$actual_output" >&2
  status=1
else
  printf 'PASS  focus reset writes exactly ESC [ ? 1 0 0 4 l\n'
fi

if ! grep -Fxq 'precmd:_reset_terminal_focus_reporting' "$registrations"; then
  printf 'FAIL  focus reset is registered for precmd\n' >&2
  status=1
else
  printf 'PASS  focus reset is registered for precmd\n'
fi

exit "$status"
