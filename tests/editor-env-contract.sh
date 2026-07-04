#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
zshenv_fragment="$repo_root/roles/common/templates/dotfiles/zshenv.d/10-common-env.zsh"
zshrc_fragment="$repo_root/roles/common/templates/dotfiles/zshrc.d/10-common-shell.zsh"

require_line() {
  local file="$1"
  local line="$2"

  if ! grep -qxF "$line" "$file"; then
    printf 'FAIL  expected %s to contain exactly: %s\n' "$file" "$line" >&2
    exit 1
  fi
}

reject_line() {
  local file="$1"
  local line="$2"

  if grep -qxF "$line" "$file"; then
    printf 'FAIL  expected %s not to contain obsolete line: %s\n' "$file" "$line" >&2
    exit 1
  fi
}

require_line "$zshenv_fragment" 'export EDITOR="${EDITOR:-nvim}"'
require_line "$zshenv_fragment" 'export VISUAL="${VISUAL:-nvim}"'
reject_line "$zshenv_fragment" 'export EDITOR=nvim'
reject_line "$zshenv_fragment" 'export VISUAL=nvim'
reject_line "$zshrc_fragment" 'export EDITOR=nvim'

printf 'PASS  editor defaults are exported from zshenv\n'
