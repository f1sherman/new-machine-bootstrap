#!/bin/sh
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
gitconfig_template="$repo_root/roles/common/templates/dotfiles/gitconfig"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir "$tmp/home"
sed '/^{%/d' "$gitconfig_template" >"$tmp/gitconfig"

HOME="$tmp/home" GIT_CONFIG_GLOBAL="$tmp/gitconfig" \
  git init -q "$tmp/repository" 2>"$tmp/git-init.stderr"

if [ -s "$tmp/git-init.stderr" ]; then
  cat "$tmp/git-init.stderr" >&2
  exit 1
fi

for template_path in info/exclude hooks description; do
  if [ ! -e "$tmp/repository/.git/$template_path" ]; then
    echo "git init did not install .git/$template_path" >&2
    exit 1
  fi
done

echo "git init template contract checks passed"
