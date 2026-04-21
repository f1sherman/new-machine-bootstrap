#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="${1:-}"

if [[ -z "$repo_dir" ]]; then
  repo_dir="$(bash "$script_dir/agent-worktree-path.sh")"
fi

repo_dir="$(git -C "$repo_dir" rev-parse --show-toplevel)"

base="$(bash "$script_dir/context.sh" "$repo_dir" "${2:-}" | jq -r '.base')"

while IFS= read -r path; do
  if [[ "$path" =~ dashboards/ ]] || [[ "$path" =~ \.(css|scss|sass|tsx|jsx|html|erb|vue)$ ]]; then
    echo visual
    exit 0
  fi
done < <(git -C "$repo_dir" diff --name-only "$base...HEAD")

echo non-visual
