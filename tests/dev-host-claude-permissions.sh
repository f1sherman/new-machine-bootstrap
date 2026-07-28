#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
tasks_file="$repo_root/roles/dev_host/tasks/main.yml"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

resolve_yq() {
  if command -v yq >/dev/null 2>&1; then
    command -v yq
  elif [ -x "$HOME/.local/bin/yq" ]; then
    printf '%s\n' "$HOME/.local/bin/yq"
  else
    return 1
  fi
}

yq_bin="$(resolve_yq)" || {
  printf 'FAIL  missing yq\n' >&2
  exit 1
}

payload="$tmp/configure-claude-settings.sh"
"$yq_bin" -r '.[] | select(.name == "Configure Claude Code settings in .claude.json") | .shell' "$tasks_file" >"$payload"
test -s "$payload"

home="$tmp/home"
config="$home/.claude.json"
mkdir -p "$home/projects/alpha" "$home/projects/beta"
HOME="$home" CONFIG_FILE="$config" /usr/bin/python3 <<'PY'
import json
import os

home = os.environ["HOME"]
alpha = os.path.join(home, "projects", "alpha")
beta = os.path.join(home, "projects", "beta")
stale = os.path.join(home, "projects", "not-present")
data = {
    "projects": {
        alpha: {
            "allowedTools": [
                "Read(custom/**)",
                "Write(.coding-agent/plans/**)",
                "Write(.coding-agent/research/**)",
                "Write(.coding-agent/handoffs/**)",
            ]
        },
        beta: {
            "allowedTools": [
                "Write(.coding-agent/handoffs/**)",
                "Write(.superpowers/handoffs/**)",
                "Bash(custom:*)",
            ]
        },
        stale: {
            "allowedTools": ["Write(.coding-agent/plans/**)"]
        },
    }
}
with open(os.environ["CONFIG_FILE"], "w") as handle:
    json.dump(data, handle)
PY

first_output="$(HOME="$home" CONFIG_FILE="$config" PATH=/usr/bin:/bin /bin/bash "$payload")"
test "$first_output" = "changed"

HOME="$home" CONFIG_FILE="$config" /usr/bin/python3 <<'PY'
import json
import os
import stat

legacy = {
    "Write(.coding-agent/plans/**)",
    "Write(.coding-agent/research/**)",
    "Write(.coding-agent/handoffs/**)",
}
defaults = [
    "Write(.superpowers/handoffs/**)",
    "Bash(mkdir -p:*)",
    "Bash(~/.local/bin/spec-metadata:*)",
]
with open(os.environ["CONFIG_FILE"]) as handle:
    data = json.load(handle)

home = os.environ["HOME"]
for name, custom in [("alpha", "Read(custom/**)"), ("beta", "Bash(custom:*)")]:
    tools = data["projects"][os.path.join(home, "projects", name)]["allowedTools"]
    assert legacy.isdisjoint(tools), (name, tools)
    assert custom in tools, (name, custom, tools)
    for default in defaults:
        assert tools.count(default) == 1, (name, default, tools)

stale_tools = data["projects"][os.path.join(home, "projects", "not-present")]["allowedTools"]
assert stale_tools == ["Write(.coding-agent/plans/**)"], stale_tools
assert stat.S_IMODE(os.stat(os.environ["CONFIG_FILE"]).st_mode) == 0o600
PY

before="$(shasum -a 256 "$config" | awk '{print $1}')"
second_output="$(HOME="$home" CONFIG_FILE="$config" PATH=/usr/bin:/bin /bin/bash "$payload")"
after="$(shasum -a 256 "$config" | awk '{print $1}')"
test "$second_output" = "unchanged"
test "$before" = "$after"

printf 'PASS  dev-host Claude permissions remove exact retired tools and converge idempotently\n'
