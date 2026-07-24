#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
installer="$repo_root/roles/linux/files/install-pinned-github-binaries"
linux_tasks="$repo_root/roles/linux/tasks/install_packages.yml"

fail() {
  printf 'FAIL  %s\n' "$1" >&2
  exit 1
}

if rg -n '\bsudo\b' "$installer"; then
  fail "parallel user binary installer must not bypass Ansible become"
fi

rg -F -- '- name: Install rg' "$linux_tasks" >/dev/null ||
  fail "ripgrep must have a dedicated Ansible task"
rg -F -- "include_tasks: '{{ playbook_dir }}/roles/common/tasks/install_github_binary.yml'" "$linux_tasks" >/dev/null ||
  fail "ripgrep must use the Ansible GitHub binary installer"
rg -F -- 'download_type: deb' "$linux_tasks" >/dev/null ||
  fail "ripgrep must retain Debian package installation"
rg -F -- 'install_dest: /usr/bin/rg' "$linux_tasks" >/dev/null ||
  fail "ripgrep must remain installed system-wide"

printf 'PASS  pinned GitHub installers preserve the Ansible privilege boundary\n'
