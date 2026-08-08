#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
settings_tasks="$repo_root/roles/common/tasks/pi_main_worktree_guard_settings.yml"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

mkdir -p "$tmp_root/pi-agent"
cat >"$tmp_root/pi-agent/settings.json" <<'JSON'
{
  "packages": [
    "npm:existing-package",
    {"source":"git:github.com/algal/pi-openai-server-compaction@previous-ref","extensions":[]},
    "npm:@ogulcancelik/pi-codex-compaction@0.1.2",
    {"source":"npm:@ogulcancelik/pi-codex-compaction","extensions":[]}
  ],
  "defaultModel": "existing-model",
  "theme": "existing-theme",
  "subagents": {
    "agentOverrides": {
      "worker": {"model":"existing-worker-model","subagentOnlyExtensions":false},
      "reviewer": {"subagentOnlyExtensions":["/existing/reviewer-extension.ts"]},
      "custom-agent": {"thinking":"high"}
    }
  }
}
JSON
cat >"$tmp_root/playbook.yml" <<EOF
---
- hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - include_tasks: $settings_tasks
      vars:
        pi_agent_dir: $tmp_root/pi-agent
EOF

ansible-playbook "$tmp_root/playbook.yml" >"$tmp_root/first.log"
settings="$tmp_root/pi-agent/settings.json"

test "$(jq -r '.defaultModel' "$settings")" = existing-model
test "$(jq -r '.theme' "$settings")" = existing-theme
test "$(jq -r '.packages[0]' "$settings")" = npm:existing-package
jq -e '[.packages[] | select((if type == "object" then .source else . end) |
  startswith("git:github.com/algal/pi-openai-server-compaction"))] | length == 0' \
  "$settings" >/dev/null
jq -e '[.packages[] | select((if type == "object" then .source else . end) |
  startswith("npm:@ogulcancelik/pi-codex-compaction"))] | length == 2' \
  "$settings" >/dev/null
test "$(jq -r '.subagents.agentOverrides.worker.model' "$settings")" = \
  existing-worker-model
test "$(jq -r '.subagents.agentOverrides["custom-agent"].thinking' "$settings")" = high

guard="$tmp_root/pi-agent/extensions/main-worktree-guard.ts"
for agent in worker reviewer delegate planner oracle scout context-builder researcher; do
  jq -e --arg agent "$agent" --arg guard "$guard" \
    '.subagents.agentOverrides[$agent].subagentOnlyExtensions | index($guard) != null' \
    "$settings" >/dev/null
done
jq -e '.subagents.agentOverrides.reviewer.subagentOnlyExtensions |
  index("/existing/reviewer-extension.ts") != null' "$settings" >/dev/null

before_second="$(cat "$settings")"
ansible-playbook "$tmp_root/playbook.yml" >"$tmp_root/second.log"
test "$(cat "$settings")" = "$before_second"
rg -F 'changed=0' "$tmp_root/second.log" >/dev/null

printf 'Pi main worktree guard merge behavior passed\n'
