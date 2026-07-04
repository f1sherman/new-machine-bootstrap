#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
zshenv_fragment="$repo_root/roles/common/templates/dotfiles/zshenv.d/10-common-env.zsh"
zshrc_fragment="$repo_root/roles/common/templates/dotfiles/zshrc.d/10-common-shell.zsh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

sourceable_zshenv="$tmpdir/10-common-env.zsh"
awk '
  /^[[:space:]]*{% if / { skip = 1; next }
  /^[[:space:]]*{% endif %}/ { skip = 0; next }
  skip == 0 { print }
' "$zshenv_fragment" > "$sourceable_zshenv"

run_zshenv() {
  local editor_value="$1"
  local visual_value="$2"

  env -i \
    HOME="$tmpdir/home" \
    PATH="/usr/bin:/bin" \
    EDITOR="$editor_value" \
    VISUAL="$visual_value" \
    zsh -fc "source '$sourceable_zshenv'; printf '%s\n%s\n' \"\$EDITOR\" \"\$VISUAL\""
}

expect_editors() {
  local name="$1"
  local editor_input="$2"
  local visual_input="$3"
  local expected_editor="$4"
  local expected_visual="$5"
  local actual

  actual="$(run_zshenv "$editor_input" "$visual_input")"
  if [[ "$actual" != "$expected_editor"$'\n'"$expected_visual" ]]; then
    printf 'FAIL  %s\nexpected EDITOR=%s VISUAL=%s\nactual:\n%s\n' \
      "$name" "$expected_editor" "$expected_visual" "$actual" >&2
    exit 1
  fi
}

if grep -qxF 'export EDITOR=nvim' "$zshrc_fragment"; then
  printf 'FAIL  expected %s not to contain obsolete line: export EDITOR=nvim\n' \
    "$zshrc_fragment" >&2
  exit 1
fi

expect_editors 'unset editor variables default to nvim' '' '' nvim nvim
expect_editors 'VISUAL derives from caller EDITOR' vim '' vim vim
expect_editors 'EDITOR derives from caller VISUAL' '' code code code
expect_editors 'caller EDITOR and VISUAL are preserved' vim code vim code

printf 'PASS  editor defaults are exported from zshenv behaviorally\n'
