#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
tasks="$repo_root/roles/common/tasks/main.yml"

ruby - "$tasks" <<'RUBY'
require "yaml"

tasks = YAML.load_file(ARGV.fetch(0))
by_name = tasks.filter_map { |task| [task["name"], task] if task.is_a?(Hash) && task["name"] }.to_h

install = by_name["Install Pi main worktree mutation guard"] or abort "missing guard extension installation task"
copy = install.fetch("copy")
raise "wrong guard source" unless copy["src"] == "pi/extensions/main-worktree-guard.ts"
raise "wrong guard destination" unless copy["dest"] == "{{ ansible_facts['user_dir'] }}/.pi/agent/extensions/main-worktree-guard.ts"
raise "wrong guard mode" unless copy["mode"] == "0644"

[
  "Check if Pi settings.json exists",
  "Read existing Pi settings.json if it exists",
  "Parse existing Pi settings or use empty object",
  "Build Pi subagent main worktree guard overrides",
  "Merge Pi subagent main worktree guard settings",
  "Write merged Pi settings.json",
].each do |name|
  raise "missing task: #{name}" unless by_name.key?(name)
end

overrides = by_name.fetch("Build Pi subagent main worktree guard overrides").inspect
%w[worker reviewer delegate planner oracle scout context-builder researcher].each do |agent|
  raise "missing explicit child guard override for #{agent}" unless overrides.include?(agent)
end
raise "missing subagentOnlyExtensions" unless overrides.include?("subagentOnlyExtensions")
raise "missing guard extension path" unless overrides.include?("main-worktree-guard.ts")
raise "child extension merge does not preserve existing entries" unless overrides.include?("unique")

merge = by_name.fetch("Merge Pi subagent main worktree guard settings").inspect
raise "Pi settings are not recursively merged" unless merge.include?("combine") && merge.include?("recursive=True")

write = by_name.fetch("Write merged Pi settings.json").fetch("copy")
raise "wrong Pi settings destination" unless write["dest"] == "{{ ansible_facts['user_dir'] }}/.pi/agent/settings.json"
raise "wrong Pi settings mode" unless write["mode"] == "0600"
raise "Pi settings are not serialized as JSON" unless write["content"].include?("to_nice_json")

puts "Pi main worktree guard provisioning checks complete"
RUBY
