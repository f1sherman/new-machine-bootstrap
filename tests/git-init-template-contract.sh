#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
gitconfig_template="$repo_root/roles/common/templates/dotfiles/gitconfig"

if grep -Eiq '^[[:space:]]*templatedir[[:space:]]*=' "$gitconfig_template"; then
  echo "managed gitconfig must not set init.templateDir" >&2
  exit 1
fi

echo "git init template contract checks passed"
