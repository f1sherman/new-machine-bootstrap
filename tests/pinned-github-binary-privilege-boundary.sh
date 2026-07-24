#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
test_dir="$(mktemp -d)"
test_playbook="$(mktemp "$repo_root/.pinned-ripgrep-test.XXXXXX.yml")"
trap 'rm -rf "$test_dir"; rm -f "$test_playbook"' EXIT

mkdir -p "$test_dir/callback_plugins"
cat > "$test_dir/callback_plugins/privilege_boundary.py" <<'PY'
from ansible.errors import AnsibleError
from ansible.plugins.callback import CallbackBase


class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "aggregate"
    CALLBACK_NAME = "privilege_boundary"

    def v2_playbook_on_task_start(self, task, is_conditional):
        if task.action == "apt" and task.get_name().endswith("rg | Install .deb package"):
            if not task.become:
                raise AnsibleError("ripgrep apt task does not use Ansible become")
            self._display.display("PASS  ripgrep apt task uses Ansible become")
PY

cat > "$test_playbook" <<YAML
---
- hosts: localhost
  connection: local
  gather_facts: true
  vars_files:
    - $repo_root/vars/tool_versions.yml
  tasks:
    - name: Load Linux package tasks
      import_tasks: $repo_root/roles/linux/tasks/install_packages.yml
YAML

printf '{"rg":"15.2.0"}\n' > "$test_dir/manifest.json"

output="$(
  ANSIBLE_CALLBACK_PLUGINS="$test_dir/callback_plugins" \
  ANSIBLE_CALLBACKS_ENABLED=privilege_boundary \
  ANSIBLE_LOCAL_TEMP="$test_dir/ansible-local" \
  ansible-playbook \
    --inventory localhost, \
    --connection local \
    --check \
    --tags nmb_ripgrep \
    --extra-vars "nmb_ripgrep_manifest_path=$test_dir/manifest.json" \
    "$test_playbook"
)"

printf '%s\n' "$output"
rg -F -- 'PASS  ripgrep apt task uses Ansible become' <<< "$output" >/dev/null
