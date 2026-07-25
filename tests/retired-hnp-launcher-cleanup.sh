#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
cleanup_tasks="$repo_root/roles/common/tasks/retire_hnp_launcher.yml"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

known_home="$tmp_root/known-home"
unknown_home="$tmp_root/unknown-home"
mkdir -p "$known_home/.local/bin" "$unknown_home/.local/bin"
printf 'retired NMB fixture\n' > "$known_home/.local/bin/hnp"
printf 'HNP-rendered fixture\n' > "$unknown_home/.local/bin/hnp"
known_checksum="$(sha256sum "$known_home/.local/bin/hnp" | cut -d' ' -f1)"

cat > "$tmp_root/playbook.yml" <<YAML
---
- hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: Exercise cleanup for configured retired content
      include_tasks: $cleanup_tasks
      vars:
        nmb_hnp_launcher_path: $known_home/.local/bin/hnp
        nmb_retired_hnp_checksums:
          - $known_checksum

    - name: Exercise cleanup for unknown HNP content
      include_tasks: $cleanup_tasks
      vars:
        nmb_hnp_launcher_path: $unknown_home/.local/bin/hnp
        nmb_retired_hnp_checksums:
          - $known_checksum
YAML

ansible-playbook "$tmp_root/playbook.yml" >/dev/null

test ! -e "$known_home/.local/bin/hnp"
test -f "$unknown_home/.local/bin/hnp"
test "$(cat "$unknown_home/.local/bin/hnp")" = 'HNP-rendered fixture'

ansible-playbook "$tmp_root/playbook.yml" > "$tmp_root/idempotence.log"
rg -F 'changed=0' "$tmp_root/idempotence.log" >/dev/null

echo 'Retired HNP launcher cleanup checks complete'
