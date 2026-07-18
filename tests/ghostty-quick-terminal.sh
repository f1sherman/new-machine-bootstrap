#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
TASKS="$REPO_ROOT/roles/macos/tasks/main.yml"

ruby - "$TASKS" <<'RUBY'
require "yaml"

tasks = YAML.safe_load_file(ARGV.fetch(0), aliases: true)
task = tasks.find do |candidate|
  candidate["name"] == "Configure ghostty quick-terminal shortcut"
end
abort "missing Ghostty quick-terminal task" unless task

config = task["lineinfile"]
abort "Ghostty quick-terminal task must use lineinfile" unless config

expected = {
  "regexp" => "^keybind\\s*=\\s*global:ctrl\\+space=",
  "line" => "keybind = global:ctrl+space=toggle_quick_terminal",
}
expected.each do |key, value|
  abort "unexpected Ghostty quick-terminal #{key}: #{config[key].inspect}" unless config[key] == value
end
RUBY

echo "Ghostty quick-terminal shortcut contract verified"
