#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
template="$repo_root/roles/common/templates/dotfiles/gitignore"

fail() {
  printf 'FAIL  %s\n' "$1" >&2
  exit 1
}

count="$(grep -Fxc '.pi/remote-pi/' "$template" || true)"
[[ "$count" == "1" ]] || fail "managed global ignore must contain exactly one .pi/remote-pi/ rule"

if grep -Fxq '.pi/' "$template"; then
  fail "managed global ignore must not hide all .pi project configuration"
fi

printf 'PASS  managed global ignore targets only Remote Pi runtime state\n'
