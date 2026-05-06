#!/usr/bin/env bash
set -euo pipefail

retryable_error() {
  local reason="$1"
  jq -n \
    --arg platform github \
    --arg head "$head" \
    --arg checks_state error \
    --arg monitor_state retryable_error \
    --arg error "$reason" \
    '{platform:$platform, head:$head, checks_state:$checks_state, monitor_state:$monitor_state, error:$error}'
}

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
repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || true)"
if [[ -z "$repo" ]]; then
  retryable_error "gh repo view failed"
  exit 0
fi
local_head_sha="$(git rev-parse --verify "${head}^{commit}" 2>/dev/null || true)"

pr_json='null'
branch_open_json='null'
branch_closed_json='null'
page=1
while :; do
  page_json="$(gh api "repos/${repo}/pulls?state=all&per_page=100&page=${page}" 2>/dev/null || true)"
  if [[ -z "$page_json" ]]; then
    retryable_error "gh pr list failed"
    exit 0
  fi

  if ! sha_open_json="$(
    echo "$page_json" | jq -c --arg sha "$local_head_sha" '
      if type != "array" then
        null
      else
        ([.[] | select(.head.sha == $sha and .state == "open")] | first)
      end
    ' 2>/dev/null
  )"; then
    retryable_error "gh pr list parse failed"
    exit 0
  fi
  if [[ "$sha_open_json" != "null" ]]; then
    pr_json="$sha_open_json"
    break
  fi

  if [[ "$pr_json" == "null" ]]; then
    if ! pr_json="$(
      echo "$page_json" | jq -c --arg sha "$local_head_sha" '
        if type != "array" then
          null
        else
          ([.[] | select(.head.sha == $sha)] | first)
        end
      ' 2>/dev/null
    )"; then
      retryable_error "gh pr list parse failed"
      exit 0
    fi
  fi

  if [[ "$branch_open_json" == "null" ]]; then
    if ! branch_open_json="$(
      echo "$page_json" | jq -c --arg head "$head" '
        if type != "array" then
          null
        else
          ([.[] | select(.head.ref == $head and .state == "open")] | first)
        end
      ' 2>/dev/null
    )"; then
      retryable_error "gh pr list parse failed"
      exit 0
    fi
  fi

  if [[ "$branch_closed_json" == "null" ]]; then
    if ! branch_closed_json="$(
      echo "$page_json" | jq -c --arg head "$head" '
        if type != "array" then
          null
        else
          ([.[] | select(.head.ref == $head and .state == "closed")] | first)
        end
      ' 2>/dev/null
    )"; then
      retryable_error "gh pr list parse failed"
      exit 0
    fi
  fi

  if ! page_size="$(echo "$page_json" | jq 'if type == "array" then length else -1 end' 2>/dev/null)"; then
    retryable_error "gh pr list parse failed"
    exit 0
  fi
  if [[ "$page_size" -eq 0 ]]; then
    break
  fi
  page=$((page + 1))
done

if [[ "$pr_json" == "null" ]]; then
  pr_json="$branch_open_json"
fi
if [[ "$pr_json" == "null" ]]; then
  pr_json="$branch_closed_json"
fi

if [[ -z "$pr_json" || "$pr_json" == "null" ]]; then
  jq -n --arg platform github --arg head "$head" '{platform:$platform, head:$head, monitor_state:"missing"}'
  exit 0
fi

if ! state="$(echo "$pr_json" | jq -r '.state' 2>/dev/null)"; then
  retryable_error "gh pr response parse failed"
  exit 0
fi
if ! pr_number="$(echo "$pr_json" | jq -r '.number' 2>/dev/null)"; then
  retryable_error "gh pr response parse failed"
  exit 0
fi
checks_state="unknown"
monitor_state="pending"

if ! merged_at="$(echo "$pr_json" | jq -r '.merged_at // empty' 2>/dev/null)"; then
  retryable_error "gh pr response parse failed"
  exit 0
fi
if [[ -n "$merged_at" ]]; then
  monitor_state="merged"
elif [[ "$state" == "closed" ]]; then
  monitor_state="closed"
else
  detail_json="$(gh api "repos/${repo}/pulls/${pr_number}" 2>/dev/null || true)"
  if [[ -z "$detail_json" ]]; then
    retryable_error "gh pr detail failed"
    exit 0
  fi
  if ! mergeable="$(echo "$detail_json" | jq -r 'if .mergeable == null then "" else (.mergeable | tostring) end' 2>/dev/null)"; then
    retryable_error "gh pr detail parse failed"
    exit 0
  fi
  if ! mergeable_state="$(echo "$detail_json" | jq -r '.mergeable_state // ""' 2>/dev/null)"; then
    retryable_error "gh pr detail parse failed"
    exit 0
  fi
  mergeable_state_lc="$(printf '%s' "$mergeable_state" | tr '[:upper:]' '[:lower:]')"
  if [[ "$mergeable" == "false" || "$mergeable_state_lc" == "dirty" ]]; then
    monitor_state="merge_conflict"
  else
  checks_json="$(gh pr checks "$pr_number" --repo "$repo" --json bucket 2>/dev/null || true)"
  if [[ -z "$checks_json" ]]; then
    retryable_error "gh pr checks failed"
    exit 0
  fi

  if ! checks_state="$(
    echo "$checks_json" | jq -r '
      if type != "array" or length == 0 then
        "unknown"
      elif any(.[]; (.bucket // "") | ascii_downcase | test("^(fail|cancel)$")) then
        "failure"
      elif any(.[]; (.bucket // "") | ascii_downcase == "pending") then
        "pending"
      elif all(.[]; ((.bucket // "") | ascii_downcase) as $bucket | ($bucket == "pass" or $bucket == "skipping")) then
        "success"
      else
        "unknown"
      end
    ' 2>/dev/null
  )"; then
    retryable_error "gh pr checks parse failed"
    exit 0
  fi
  if [[ "$checks_state" == "failure" ]]; then
    monitor_state="checks_failed"
  fi
  fi
fi

if ! head_sha="$(echo "$pr_json" | jq -r '.head.sha' 2>/dev/null)"; then
  retryable_error "gh pr response parse failed"
  exit 0
fi
if ! html_url="$(echo "$pr_json" | jq -r '.html_url' 2>/dev/null)"; then
  retryable_error "gh pr response parse failed"
  exit 0
fi

jq -n \
  --arg platform github \
  --arg head "$head" \
  --argjson pr "$pr_json" \
  --arg checks_state "$checks_state" \
  --arg monitor_state "$monitor_state" \
  --arg html_url "$html_url" \
  --arg head_sha "$head_sha" \
  '{platform:$platform, head:$head, pr_number:$pr.number, html_url:$html_url, head_sha:$head_sha, checks_state:$checks_state, monitor_state:$monitor_state}'
