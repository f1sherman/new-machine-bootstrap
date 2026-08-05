#!/bin/sh
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
gitconfig_template="$repo_root/roles/common/templates/dotfiles/gitconfig"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

render_gitconfig() {
  os_family=$1
  destination=$2

  ansible localhost -c local -m ansible.builtin.template \
    -a "src=$gitconfig_template dest=$destination" \
    -e "{\"ansible_facts\":{\"os_family\":\"$os_family\"}}" \
    >/dev/null 2>&1
}

assert_helper() {
  config=$1
  key=$2
  expected=$3
  actual=$(git config --file "$config" --get-all "$key" || true)

  if [ "$actual" != "$expected" ]; then
    echo "expected $key to be '$expected', got '$actual'" >&2
    exit 1
  fi
}

assert_missing() {
  config=$1
  key=$2

  if git config --file "$config" --get-all "$key" >/dev/null; then
    echo "expected $key to be absent" >&2
    exit 1
  fi
}

linux_helpers=$(printf '\n%s' "!/usr/bin/gh auth git-credential")

render_gitconfig Debian "$tmp/linux-gitconfig"
assert_helper "$tmp/linux-gitconfig" credential.https://github.com.helper "$linux_helpers"
assert_helper "$tmp/linux-gitconfig" credential.https://gist.github.com.helper "$linux_helpers"
assert_missing "$tmp/linux-gitconfig" credential.helper

render_gitconfig Darwin "$tmp/macos-gitconfig"
assert_helper "$tmp/macos-gitconfig" credential.helper osxkeychain
assert_missing "$tmp/macos-gitconfig" credential.https://github.com.helper
assert_missing "$tmp/macos-gitconfig" credential.https://gist.github.com.helper

echo "Git credential helper contract checks passed"
