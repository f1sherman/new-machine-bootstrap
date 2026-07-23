#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
main_tasks="$repo_root/roles/common/tasks/main.yml"
config="$repo_root/roles/common/files/pi/extensions/subagent/config.json"

ruby -rjson -ryaml - "$main_tasks" "$config" <<'RUBY'
main_tasks = YAML.load_file(ARGV.fetch(0))
config = JSON.parse(File.read(ARGV.fetch(1)))
raise "unexpected scheduled-run config" unless config == { "scheduledRuns" => { "enabled" => true } }

by_name = main_tasks.filter_map { |task| [task["name"], task] if task.is_a?(Hash) && task["name"] }.to_h
directory = by_name["Create Pi subagent configuration directory"] or abort "missing subagent configuration directory task"
file = directory.fetch("file")
raise "wrong subagent directory" unless file["path"] == "{{ ansible_facts['user_dir'] }}/.pi/agent/extensions/subagent"
raise "wrong subagent directory state" unless file["state"] == "directory"
raise "wrong subagent directory mode" unless file["mode"] == "0755"

install = by_name["Enable Pi scheduled subagent runs"] or abort "missing scheduled-run configuration task"
copy = install.fetch("copy")
raise "wrong scheduled-run source" unless copy["src"] == "pi/extensions/subagent/config.json"
raise "wrong scheduled-run destination" unless copy["dest"] == "{{ ansible_facts['user_dir'] }}/.pi/agent/extensions/subagent/config.json"
raise "wrong scheduled-run mode" unless copy["mode"] == "0644"
raise "scheduled-run task must apply to all common-role hosts" if install.key?("when")
RUBY

printf 'Pi scheduled subagent run provisioning checks complete\n'
