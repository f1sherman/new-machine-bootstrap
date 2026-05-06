#!/usr/bin/env bash
set -euo pipefail

# Upload a PR attachment to Forgejo and print the browser download URL.
#
# Usage:
#   upload-attachment.sh <pr-number> <file> [--name attachment-name]
#
# Environment:
#   FORGEJO_TOKEN  - API token (default: read from ~/.config/home-network/forgejo-token)
#   FORGEJO_URL    - Base URL (default: https://forgejo.brianjohn.com)

FORGEJO_URL="${FORGEJO_URL:-https://forgejo.brianjohn.com}"
TOKEN_FILE="${HOME}/.config/home-network/forgejo-token"

name=""
positionals=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      name="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: upload-attachment.sh <pr-number> <file> [--name attachment-name]"
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      positionals+=("$1")
      shift
      ;;
  esac
done

if [[ "${#positionals[@]}" -ne 2 ]]; then
  echo "Usage: upload-attachment.sh <pr-number> <file> [--name attachment-name]" >&2
  exit 1
fi

pr_number="${positionals[0]}"
file_path="${positionals[1]}"

if [[ ! -f "$file_path" ]]; then
  echo "Error: Attachment file not found: ${file_path}" >&2
  exit 1
fi

if [[ -z "$name" ]]; then
  name="$(basename "$file_path")"
fi

if [[ -n "${FORGEJO_TOKEN:-}" ]]; then
  token="$FORGEJO_TOKEN"
elif [[ -f "$TOKEN_FILE" ]]; then
  token="$(cat "$TOKEN_FILE")"
else
  echo "Error: No Forgejo token found. Set FORGEJO_TOKEN or create ${TOKEN_FILE}" >&2
  exit 1
fi

remote_url="$(git remote get-url origin 2>/dev/null || true)"
if [[ -z "$remote_url" ]]; then
  echo "Error: No 'origin' remote found" >&2
  exit 1
fi

repo_path="$(echo "$remote_url" | sed -E 's|.*[:/]([^/]+/[^/]+)$|\1|' | sed 's/\.git$//')"
owner="$(echo "$repo_path" | cut -d/ -f1)"
repo="$(echo "$repo_path" | cut -d/ -f2)"

response="$(
  curl -sf \
    -X POST \
    -H "Authorization: token ${token}" \
    -F "attachment=@${file_path}" \
    "${FORGEJO_URL}/api/v1/repos/${owner}/${repo}/issues/${pr_number}/assets?name=$(jq -rn --arg name "$name" '$name|@uri')"
)"

attachment_url="$(echo "$response" | jq -r '.browser_download_url')"
if [[ -z "$attachment_url" || "$attachment_url" == "null" ]]; then
  echo "Error: Forgejo did not return a browser_download_url" >&2
  exit 1
fi

echo "$attachment_url"
