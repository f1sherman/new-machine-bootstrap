#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: state.sh <path|load|save|clear> <repo-dir> [json]" >&2
  exit 1
}

canonical_repo_dir() {
  local input_path="$1"

  if git -C "$input_path" rev-parse --show-toplevel >/dev/null 2>&1; then
    git -C "$input_path" rev-parse --show-toplevel
  elif [[ "$input_path" == /* ]]; then
    printf '%s\n' "$input_path"
  else
    ruby -e 'puts File.expand_path(ARGV[0])' "$input_path"
  fi
}

state_key() {
  local canonical_path="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$canonical_path" | sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$canonical_path" | shasum -a 256 | awk '{print $1}'
  else
    ruby -rdigest -e 'puts Digest::SHA256.hexdigest(ARGF.read)' <<<"$canonical_path"
  fi
}

sanitize_repo_name() {
  basename "$1" | tr -cs 'A-Za-z0-9._-' '_'
}

cmd="${1:-}"
repo_dir="${2:-}"
json_payload="${3:-}"

[[ -n "$cmd" && -n "$repo_dir" ]] || usage

repo_dir="$(canonical_repo_dir "$repo_dir")"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/pr-monitor"
repo_name="$(sanitize_repo_name "$repo_dir")"
state_path="${state_dir}/${repo_name}-$(state_key "$repo_dir").json"


case "$cmd" in
  path)
    printf '%s\n' "$state_path"
    ;;
  load)
    if [[ -f "$state_path" ]]; then
      jq -c . "$state_path"
    else
      printf '{}\n'
    fi
    ;;
  save)
    [[ -n "$json_payload" ]] || usage
    jq -e . >/dev/null <<<"$json_payload"
    mkdir -p "$state_dir"
    printf '%s\n' "$json_payload" >"$state_path"
    ;;
  clear)
    rm -f "$state_path"
    ;;
  *)
    usage
    ;;
esac
