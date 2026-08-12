#!/bin/bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

pinned_ruby="$tmpdir/pinned-ruby"
source_bin="$tmpdir/source-asr"
launcher="$tmpdir/asr"

cat > "$pinned_ruby" <<'SCRIPT'
#!/bin/bash
printf 'ruby=%s\n' "$0"
printf 'script=%s\n' "$1"
printf 'args=%s\n' "${*:2}"
SCRIPT
chmod +x "$pinned_ruby"

cat > "$source_bin" <<'RUBY'
#!/usr/bin/env ruby
abort "the source executable must run through the pinned Ruby"
RUBY
chmod +x "$source_bin"

ANSIBLE_PYTHON_INTERPRETER=auto_silent \
ansible localhost \
  --inventory localhost, \
  --connection local \
  --module-name template \
  --args "src=$repo_root/roles/common/templates/asr.j2 dest=$launcher mode=0755" \
  --extra-vars "{\"agent_session_registry_ruby_bin\":\"$pinned_ruby\",\"agent_session_registry_source_bin\":\"$source_bin\"}" \
  >/dev/null

output=$("$launcher" register --source pi)
expected=$(printf 'ruby=%s\nscript=%s\nargs=register --source pi' \
  "$pinned_ruby" "$source_bin")

if [[ "$output" != "$expected" ]]; then
  printf 'unexpected launcher output:\n%s\n' "$output" >&2
  exit 1
fi

printf 'asr launcher tests passed\n'
