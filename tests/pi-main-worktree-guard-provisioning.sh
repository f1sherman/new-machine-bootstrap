#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
main_tasks="$repo_root/roles/common/tasks/main.yml"
settings_tasks="$repo_root/roles/common/tasks/pi_main_worktree_guard_settings.yml"
model_tasks="$repo_root/roles/common/tasks/pi_model_overrides.yml"
model_overrides="$repo_root/roles/common/files/pi/models.json"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

ruby - "$main_tasks" "$settings_tasks" "$model_tasks" <<'RUBY'
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
model_include = by_name["Configure managed pi-coding-agent model overrides"] or abort "missing Pi model settings include"
raise "wrong model task include" unless model_include["include_tasks"] == "pi_model_overrides.yml"

{
  "macOS" => "Darwin",
  "Linux" => "Debian",
}.each do |platform, family|
  task = by_name["Install or update OpenAI server compaction extension for Pi (#{platform})"] or abort "missing #{platform} compaction extension task"
  shell = task.fetch("shell")
  raise "wrong #{platform} compaction source" unless shell.include?("pi install git:github.com/algal/pi-openai-server-compaction")
  raise "missing #{platform} revision comparison" unless shell.include?('before=') && shell.include?('after=')
  raise "wrong #{platform} platform condition" unless task["when"] == %(ansible_facts["os_family"] == "#{family}")
  raise "missing #{platform} changed detection" unless task.fetch("changed_when").include?("stdout_lines")
end

settings_tasks = YAML.load_file(ARGV.fetch(1))
settings_names = settings_tasks.filter_map { |task| task["name"] if task.is_a?(Hash) }
[
  "Check if Pi settings.json exists",
  "Read existing Pi settings.json if it exists",
  "Parse existing Pi settings or use empty object",
  "Build Pi subagent main worktree guard overrides",
  "Initialize preserved Pi package entries",
  "Preserve Pi packages other than managed server compaction",
  "Merge managed Pi settings",
  "Write merged Pi settings.json",
].each { |name| raise "missing task: #{name}" unless settings_names.include?(name) }

model_tasks = YAML.load_file(ARGV.fetch(2))
model_names = model_tasks.filter_map { |task| task["name"] if task.is_a?(Hash) }
[
  "Check if Pi models.json exists",
  "Read existing Pi models.json if it exists",
  "Parse existing Pi models or use empty object",
  "Load managed Pi model overrides",
  "Merge managed Pi model overrides",
  "Write merged Pi models.json",
].each { |name| raise "missing task: #{name}" unless model_names.include?(name) }
RUBY

mkdir -p "$tmp_root/pi-agent"
cat > "$tmp_root/pi-agent/settings.json" <<'JSON'
{
  "packages": [
    "npm:existing-package",
    {
      "source": "git:github.com/algal/pi-openai-server-compaction",
      "extensions": []
    }
  ],
  "defaultModel": "existing-model",
  "theme": "existing-theme",
  "subagents": {
    "agentOverrides": {
      "worker": {
        "model": "existing-worker-model",
        "subagentOnlyExtensions": false
      },
      "reviewer": {
        "subagentOnlyExtensions": ["/existing/reviewer-extension.ts"]
      },
      "custom-agent": {
        "thinking": "high"
      }
    }
  }
}
JSON
cat > "$tmp_root/pi-agent/models.json" <<'JSON'
{
  "providers": {
    "existing-provider": {
      "baseUrl": "https://example.test/v1"
    },
    "openai-codex": {
      "modelOverrides": {
        "existing-model": {
          "contextWindow": 123456
        }
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
    - include_tasks: $model_tasks
      vars:
        pi_agent_dir: $tmp_root/pi-agent
        pi_model_overrides_file: $model_overrides
EOF

ansible-playbook "$tmp_root/playbook.yml" >/dev/null
settings="$tmp_root/pi-agent/settings.json"

test "$(jq -r '.defaultModel' "$settings")" = existing-model
test "$(jq -r '.theme' "$settings")" = existing-theme
test "$(jq -r '.packages[0]' "$settings")" = npm:existing-package
jq -e '[.packages[] | select((if type == "object" then .source else . end) == "git:github.com/algal/pi-openai-server-compaction")] | length == 1' "$settings" >/dev/null
jq -e '.packages[] | select(. == "git:github.com/algal/pi-openai-server-compaction")' "$settings" >/dev/null
jq -e '.hideThinkingBlock == true and .quietStartup == true and .collapseChangelog == true' "$settings" >/dev/null
test "$(jq -r '.subagents.agentOverrides.worker.model' "$settings")" = existing-worker-model
test "$(jq -r '.subagents.agentOverrides["custom-agent"].thinking' "$settings")" = high

guard="$tmp_root/pi-agent/extensions/main-worktree-guard.ts"
for agent in worker reviewer delegate planner oracle scout context-builder researcher; do
  jq -e --arg agent "$agent" --arg guard "$guard" '.subagents.agentOverrides[$agent].subagentOnlyExtensions | index($guard) != null' "$settings" >/dev/null
done
jq -e '.subagents.agentOverrides.reviewer.subagentOnlyExtensions | index("/existing/reviewer-extension.ts") != null' "$settings" >/dev/null

models="$tmp_root/pi-agent/models.json"
test "$(jq -r '.providers["existing-provider"].baseUrl' "$models")" = https://example.test/v1
test "$(jq -r '.providers["openai-codex"].modelOverrides["existing-model"].contextWindow' "$models")" = 123456
for model in gpt-5.6-luna gpt-5.6-sol gpt-5.6-terra; do
  test "$(jq -r --arg model "$model" '.providers["openai-codex"].modelOverrides[$model].contextWindow' "$models")" = 272000
done

ansible-playbook "$tmp_root/playbook.yml" >/tmp/pi-main-worktree-guard-idempotence.log
rg -F 'changed=0' /tmp/pi-main-worktree-guard-idempotence.log >/dev/null

echo "Pi main worktree guard provisioning checks complete"
