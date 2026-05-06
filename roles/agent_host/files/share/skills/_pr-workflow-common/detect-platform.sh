#!/usr/bin/env bash
set -euo pipefail

repo_dir="${1:-$(pwd)}"
remote_url="$(git -C "$repo_dir" remote get-url origin 2>/dev/null || true)"

extract_host() {
  local remote_url="$1"

  if [[ "$remote_url" =~ ^ssh://([^@/]+@)?([^:/]+)(:[0-9]+)?/ ]]; then
    printf '%s\n' "${BASH_REMATCH[2]}"
    return 0
  fi

  if [[ "$remote_url" =~ ^https?://([^/@]+@)?([^/:]+)(:[0-9]+)?/ ]]; then
    printf '%s\n' "${BASH_REMATCH[2]}"
    return 0
  fi

  if [[ "$remote_url" =~ ^[^@]+@([^:]+): ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  return 1
}

if [[ -z "$remote_url" ]]; then
  echo "Error: No 'origin' remote found" >&2
  exit 1
fi

host="$(extract_host "$remote_url" || true)"

if [[ -z "$host" ]]; then
  echo "Error: Could not parse origin host from remote: $remote_url" >&2
  exit 1
fi

case "$host" in
  github.com ) echo github ;;
  forgejo | forgejo.* | *.forgejo.* | forgejo-git | forgejo-git.* ) echo forgejo ;;
  * )
    echo "Error: Unsupported origin host: $host" >&2
    exit 1
    ;;
esac
