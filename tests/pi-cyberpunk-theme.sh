#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
theme_file="$repo_root/roles/common/files/pi/themes/cyberpunk-2077.json"
tasks_file="$repo_root/roles/common/tasks/main.yml"

if command -v yq >/dev/null 2>&1; then
  yq_bin="$(command -v yq)"
elif [ -x "$HOME/.local/bin/yq" ]; then
  yq_bin="$HOME/.local/bin/yq"
else
  printf 'FAIL  Cyberpunk Pi theme contract: missing yq\n' >&2
  exit 1
fi

required_colors='[
  "accent", "bashMode", "border", "borderAccent", "borderMuted", "customMessageBg",
  "customMessageLabel", "customMessageText", "dim", "error", "mdCode", "mdCodeBlock",
  "mdCodeBlockBorder", "mdHeading", "mdHr", "mdLink", "mdLinkUrl", "mdListBullet",
  "mdQuote", "mdQuoteBorder", "muted", "selectedBg", "success", "syntaxComment",
  "syntaxFunction", "syntaxKeyword", "syntaxNumber", "syntaxOperator", "syntaxPunctuation",
  "syntaxString", "syntaxType", "syntaxVariable", "text", "thinkingHigh", "thinkingLow",
  "thinkingMax", "thinkingMedium", "thinkingMinimal", "thinkingOff", "thinkingText",
  "thinkingXhigh", "toolDiffAdded", "toolDiffContext", "toolDiffRemoved", "toolErrorBg",
  "toolOutput", "toolPendingBg", "toolSuccessBg", "toolTitle", "userMessageBg",
  "userMessageText", "warning"
]'

jq -e --argjson required "$required_colors" '
  .name == "cyberpunk-2077" and
  ((.colors | keys | sort) == ($required | sort)) and
  (.vars | type == "object") and
  (. as $theme | all(.colors[];
    . as $value |
    type == "string" and
    (. == "" or test("^#[0-9A-Fa-f]{6}$") or ($theme.vars | has($value)))
  ))
' "$theme_file" >/dev/null

"$yq_bin" -o=json '.' "$tasks_file" | jq -e '
  any(.[];
    .name == "Create pi-coding-agent global themes directory" and
    .file.path == "{{ ansible_facts[\u0027user_dir\u0027] }}/.pi/agent/themes" and
    .file.state == "directory" and .file.mode == "0755"
  ) and
  any(.[];
    .name == "Install Cyberpunk 2077 pi-coding-agent theme" and
    .copy.src == "pi/themes/cyberpunk-2077.json" and
    .copy.dest == "{{ ansible_facts[\u0027user_dir\u0027] }}/.pi/agent/themes/cyberpunk-2077.json" and
    .copy.mode == "0644"
  )
' >/dev/null

if rg -n 'theme[^[:alnum:]]+cyberpunk-2077' "$tasks_file" >/dev/null; then
  printf 'FAIL  Cyberpunk theme must remain optional\n' >&2
  exit 1
fi

printf 'PASS  Cyberpunk Pi theme contract\n'
