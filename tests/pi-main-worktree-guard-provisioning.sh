#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
main_tasks="$repo_root/roles/common/tasks/main.yml"
settings_tasks="$repo_root/roles/common/tasks/pi_main_worktree_guard_settings.yml"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

ruby - "$main_tasks" "$settings_tasks" <<'RUBY'
require "yaml"

main_tasks = YAML.load_file(ARGV.fetch(0))
by_name = main_tasks.filter_map { |task| [task["name"], task] if task.is_a?(Hash) && task["name"] }.to_h
install = by_name["Install Pi main worktree mutation guard"] or abort "missing guard extension installation task"
copy = install.fetch("copy")
raise "wrong guard source" unless copy["src"] == "pi/extensions/main-worktree-guard.ts"
raise "wrong guard destination" unless copy["dest"] == "{{ ansible_facts['user_dir'] }}/.pi/agent/extensions/main-worktree-guard.ts"
raise "wrong guard mode" unless copy["mode"] == "0644"
include_task = by_name["Configure Pi subagent main worktree guard"] or abort "missing Pi guard settings include"
raise "wrong settings task include" unless include_task["include_tasks"] == "pi_main_worktree_guard_settings.yml"

settings_tasks = YAML.load_file(ARGV.fetch(1))
settings_names = settings_tasks.filter_map { |task| task["name"] if task.is_a?(Hash) }
[
  "Check if Pi settings.json exists",
  "Read existing Pi settings.json if it exists",
  "Parse existing Pi settings or use empty object",
  "Build Pi subagent main worktree guard overrides",
  "Merge Pi subagent main worktree guard settings",
  "Write merged Pi settings.json",
].each { |name| raise "missing task: #{name}" unless settings_names.include?(name) }
RUBY

mkdir -p "$tmp_root/pi-agent"
cat > "$tmp_root/pi-agent/settings.json" <<'JSON'
{
  "packages": ["npm:existing-package"],
  "defaultModel": "existing-model",
  "theme": "existing-theme",
  "subagents": {
    "agentOverrides": {
      "worker": {
        "model": "existing-worker-model",
        "subagentOnlyExtensions": ["/existing/worker-extension.ts"]
      },
      "custom-agent": {
        "thinking": "high"
      }
    }
  }
}
JSON
cat > "$tmp_root/playbook.yml" <<EOF
---
- hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - include_tasks: $settings_tasks
      vars:
        pi_agent_dir: $tmp_root/pi-agent
EOF

ansible-playbook "$tmp_root/playbook.yml" >/dev/null
settings="$tmp_root/pi-agent/settings.json"

test "$(jq -r '.defaultModel' "$settings")" = existing-model
test "$(jq -r '.theme' "$settings")" = existing-theme
test "$(jq -r '.packages[0]' "$settings")" = npm:existing-package
test "$(jq -r '.subagents.agentOverrides.worker.model' "$settings")" = existing-worker-model
test "$(jq -r '.subagents.agentOverrides["custom-agent"].thinking' "$settings")" = high

guard="$tmp_root/pi-agent/extensions/main-worktree-guard.ts"
for agent in worker reviewer delegate planner oracle scout context-builder researcher; do
  jq -e --arg agent "$agent" --arg guard "$guard" '.subagents.agentOverrides[$agent].subagentOnlyExtensions | index($guard) != null' "$settings" >/dev/null
done
jq -e '.subagents.agentOverrides.worker.subagentOnlyExtensions | index("/existing/worker-extension.ts") != null' "$settings" >/dev/null

ansible-playbook "$tmp_root/playbook.yml" >/tmp/pi-main-worktree-guard-idempotence.log
rg -F 'changed=0' /tmp/pi-main-worktree-guard-idempotence.log >/dev/null

echo "Pi main worktree guard provisioning checks complete"
