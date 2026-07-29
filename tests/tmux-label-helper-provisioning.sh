#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
test_dir="$(mktemp -d "$repo_root/.tmux-label-provisioning.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/home/.local/bin" "$test_dir/ansible-local" "$test_dir/ansible-remote"
cat > "$test_dir/extra-vars.yml" <<YAML
ansible_facts:
  user_dir: '$test_dir/home'
YAML

output="$(
  HOME="$test_dir/home" \
  ANSIBLE_LOCAL_TEMP="$test_dir/ansible-local" \
  ANSIBLE_REMOTE_TEMP="$test_dir/ansible-remote" \
  ANSIBLE_NOCOLOR=1 \
    ansible-playbook \
      --inventory localhost, \
      --connection local \
      --check \
      --tags nmb_tmux_label_helpers \
      --extra-vars "@$test_dir/extra-vars.yml" \
      "$repo_root/playbook.yml"
)"

printf '%s\n' "$output"
rg -F -- 'TASK [common : Install tmux label helpers]' <<< "$output" >/dev/null
rg -F -- '(item=tmux-title-transition)' <<< "$output" >/dev/null
test ! -e "$test_dir/home/.local/bin/tmux-title-transition"

printf 'PASS  playbook check resolves tmux-title-transition without deploying it\n'
