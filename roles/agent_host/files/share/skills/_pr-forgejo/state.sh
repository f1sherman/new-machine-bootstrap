#!/usr/bin/env bash
set -euo pipefail

FORGEJO_URL="${FORGEJO_URL:-https://forgejo.brianjohn.com}"
TOKEN_FILE="${HOME}/.config/home-network/forgejo-token"
head=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --head-branch)
      [[ $# -ge 2 ]] || break
      head="$2"
      shift 2
      ;;
    *)
      if [[ -z "$head" ]]; then
        head="$1"
      fi
      shift
      ;;
  esac
done
head="${head:-$(git rev-parse --abbrev-ref HEAD)}"

retryable_error() {
  local reason="$1"
  jq -n \
    --arg platform forgejo \
    --arg head "$head" \
    --arg checks_state error \
    --arg monitor_state retryable_error \
    --arg error "$reason" \
    '{platform:$platform, head:$head, checks_state:$checks_state, monitor_state:$monitor_state, error:$error}'
}

if [[ -n "${FORGEJO_TOKEN:-}" ]]; then
  token="$FORGEJO_TOKEN"
else
  token="$(cat "$TOKEN_FILE" 2>/dev/null || true)"
  if [[ -z "$token" ]]; then
    retryable_error "forgejo token read failed"
    exit 0
  fi
fi

remote_url="$(git remote get-url origin)"
repo_path="$(echo "$remote_url" | sed -E 's|.*[:/]([^/]+/[^/]+)$|\1|' | sed 's/\.git$//')"
owner="$(echo "$repo_path" | cut -d/ -f1)"
repo="$(echo "$repo_path" | cut -d/ -f2)"
local_head_sha="$(git rev-parse --verify "${head}^{commit}" 2>/dev/null || true)"

page=1
pr_json='null'
ref_match_json='null'
closed_ref_match_json='null'

while :; do
  page_json="$(curl -sf -H "Authorization: token ${token}" "${FORGEJO_URL}/api/v1/repos/${owner}/${repo}/pulls?state=all&page=${page}&limit=50" 2>/dev/null || true)"
  if [[ -z "$page_json" ]]; then
    retryable_error "forgejo pulls request failed"
    exit 0
  fi
  if ! pr_json="$(echo "$page_json" | jq --arg sha "$local_head_sha" '
    ([.[] | select(.head.sha == $sha and ((.state // "open") == "open"))] | first) //
    ([.[] | select(.head.sha == $sha)] | first)
  ' 2>/dev/null)"; then
    retryable_error "forgejo pulls response parse failed"
    exit 0
  fi
  if [[ "$pr_json" != "null" ]]; then
    break
  fi

  if [[ "$ref_match_json" == "null" ]]; then
    if ! ref_match_json="$(echo "$page_json" | jq --arg head "$head" '[.[] | select(.head.ref == $head and ((.state // "open") == "open"))][0]' 2>/dev/null)"; then
      retryable_error "forgejo pulls response parse failed"
      exit 0
    fi
  fi

  if [[ "$closed_ref_match_json" == "null" ]]; then
    if ! closed_ref_match_json="$(echo "$page_json" | jq --arg head "$head" '[.[] | select(.head.ref == $head and ((.state // "open") == "closed"))][0]' 2>/dev/null)"; then
      retryable_error "forgejo pulls response parse failed"
      exit 0
    fi
  fi

  if ! page_size="$(echo "$page_json" | jq 'length' 2>/dev/null)"; then
    retryable_error "forgejo pulls response parse failed"
    exit 0
  fi
  if [[ "$page_size" -eq 0 ]]; then
    break
  fi

  page=$((page + 1))
done

if [[ "$pr_json" == "null" ]]; then
  pr_json="$ref_match_json"
fi

if [[ "$pr_json" == "null" ]]; then
  pr_json="$closed_ref_match_json"
fi

if ! pr_number="$(echo "$pr_json" | jq -r '.number // empty' 2>/dev/null)"; then
  retryable_error "forgejo PR response parse failed"
  exit 0
fi

if [[ -z "$pr_number" ]]; then
  jq -n --arg platform forgejo --arg head "$head" '{platform:$platform, head:$head, monitor_state:"missing"}'
  exit 0
fi

if ! sha="$(echo "$pr_json" | jq -r '.head.sha' 2>/dev/null)"; then
  retryable_error "forgejo PR response parse failed"
  exit 0
fi
if ! merged="$(echo "$pr_json" | jq -r '.merged // false' 2>/dev/null)"; then
  retryable_error "forgejo PR response parse failed"
  exit 0
fi
if ! pr_state="$(echo "$pr_json" | jq -r '.state // "open"' 2>/dev/null)"; then
  retryable_error "forgejo PR response parse failed"
  exit 0
fi
if ! mergeable="$(echo "$pr_json" | jq -r 'if .mergeable == null then "true" else (.mergeable | tostring) end' 2>/dev/null)"; then
  retryable_error "forgejo PR response parse failed"
  exit 0
fi

checks_state="unknown"
monitor_state="pending"
if [[ "$merged" == "true" ]]; then
  monitor_state="merged"
elif [[ "$pr_state" == "closed" ]]; then
  monitor_state="closed"
elif [[ "$mergeable" == "false" ]]; then
  monitor_state="merge_conflict"
else
  checks_json="$(curl -sf -H "Authorization: token ${token}" "${FORGEJO_URL}/api/v1/repos/${owner}/${repo}/commits/${sha}/status" 2>/dev/null || true)"
  if [[ -z "$checks_json" ]]; then
    retryable_error "forgejo status request failed"
    exit 0
  fi
  if ! checks_state="$(echo "$checks_json" | jq -r '.state // "unknown"' 2>/dev/null)"; then
    retryable_error "forgejo status response parse failed"
    exit 0
  fi
  if [[ "$checks_state" == "failure" || "$checks_state" == "error" ]]; then
    monitor_state="checks_failed"
  fi
fi

if ! html_url="$(echo "$pr_json" | jq -r '.html_url' 2>/dev/null)"; then
  retryable_error "forgejo PR response parse failed"
  exit 0
fi

jq -n \
  --arg platform forgejo \
  --arg head "$head" \
  --arg pr_number "$pr_number" \
  --arg html_url "$html_url" \
  --arg head_sha "$sha" \
  --arg checks_state "$checks_state" \
  --arg monitor_state "$monitor_state" \
  '{platform:$platform, head:$head, pr_number:($pr_number|tonumber), html_url:$html_url, head_sha:$head_sha, checks_state:$checks_state, monitor_state:$monitor_state}'
