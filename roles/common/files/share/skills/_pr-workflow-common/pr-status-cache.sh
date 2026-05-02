#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF' >&2
Usage:
  pr-status-cache.sh write --repo-dir <path> --platform <github|forgejo> --pr-number <n> --url <url> [--branch <branch>] [--state open] [--head-sha sha] [--source name]
  pr-status-cache.sh clear --repo-dir <path> [--branch <branch>]
  pr-status-cache.sh clear --remote-url <url> --branch <branch>
EOF
  exit 2
}

state_dir() {
  printf '%s/.local/state/pr-status\n' "${HOME:?}"
}

repo_branch() {
  local branch
  branch="$(git -C "$1" branch --show-current)"
  if [[ -z "$branch" ]]; then
    echo "Error: pr-status-cache.sh requires a checked-out branch" >&2
    exit 1
  fi
  printf '%s\n' "$branch"
}

repo_remote_url() {
  git -C "$1" remote get-url origin
}

repo_root() {
  git -C "$1" rev-parse --path-format=absolute --show-toplevel
}

repo_common_dir() {
  git -C "$1" rev-parse --path-format=absolute --git-common-dir
}

cache_key() {
  local remote_url="$1"
  local branch="$2"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s\n%s\n' "$remote_url" "$branch" | sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s\n%s\n' "$remote_url" "$branch" | shasum -a 256 | awk '{print $1}'
  elif command -v ruby >/dev/null 2>&1; then
    printf '%s\n%s\n' "$remote_url" "$branch" | ruby -rdigest -e 'print Digest::SHA256.hexdigest(STDIN.read)'
  else
    echo "Error: missing SHA-256 digest command" >&2
    exit 1
  fi
}

cache_path() {
  local remote_url="$1"
  local branch="$2"
  local key
  key="$(cache_key "$remote_url" "$branch")"
  printf '%s/%s.json\n' "$(state_dir)" "$key"
}

cache_path_for_repo() {
  local repo_dir="$1"
  local branch="${2:-}"
  local remote_url
  remote_url="$(repo_remote_url "$repo_dir")"
  [[ -n "$branch" ]] || branch="$(repo_branch "$repo_dir")"
  cache_path "$remote_url" "$branch"
}

clear_entries_for_repo_root() {
  local repo_dir="$1"
  local branch="${2:-}"
  local root path

  if [[ -d "$repo_dir" ]]; then
    root="$(repo_root "$repo_dir" 2>/dev/null || printf '%s\n' "$repo_dir")"
  else
    root="$repo_dir"
  fi

  [[ -d "$(state_dir)" ]] || return 0
  for path in "$(state_dir)"/*.json; do
    [[ -e "$path" ]] || continue
    if jq -e --arg root "$root" --arg branch "$branch" '
      (.schema_version == 1)
      and (.repo_root == $root)
      and (($branch == "") or (.branch == $branch))
    ' "$path" >/dev/null 2>&1; then
      rm -f "$path"
    fi
  done
}

display_ref_for() {
  local platform="$1"
  local pr_number="$2"
  case "$platform" in
    github) printf 'gh#%s\n' "$pr_number" ;;
    forgejo) printf 'fg#%s\n' "$pr_number" ;;
    *) echo "Error: unsupported platform: $platform" >&2; exit 1 ;;
  esac
}

validate_pr_number() {
  if [[ ! "$1" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: --pr-number must be a positive integer" >&2
    exit 1
  fi
}

write_cache() {
  local repo_dir="" branch="" platform="" pr_number="" url="" state="open" head_sha="" source="unknown"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo-dir) [[ $# -ge 2 ]] || usage; repo_dir="$2"; shift 2 ;;
      --branch) [[ $# -ge 2 ]] || usage; branch="$2"; shift 2 ;;
      --platform) [[ $# -ge 2 ]] || usage; platform="$2"; shift 2 ;;
      --pr-number) [[ $# -ge 2 ]] || usage; pr_number="$2"; shift 2 ;;
      --url) [[ $# -ge 2 ]] || usage; url="$2"; shift 2 ;;
      --state) [[ $# -ge 2 ]] || usage; state="$2"; shift 2 ;;
      --head-sha) [[ $# -ge 2 ]] || usage; head_sha="$2"; shift 2 ;;
      --source) [[ $# -ge 2 ]] || usage; source="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  [[ -n "$repo_dir" && -n "$platform" && -n "$pr_number" && -n "$url" ]] || usage
  validate_pr_number "$pr_number"

  local remote_url path dir tmp now expires display_ref root common_dir
  remote_url="$(repo_remote_url "$repo_dir")"
  [[ -n "$branch" ]] || branch="$(repo_branch "$repo_dir")"
  root="$(repo_root "$repo_dir")"
  common_dir="$(repo_common_dir "$repo_dir")"
  path="$(cache_path_for_repo "$repo_dir" "$branch")"
  dir="$(dirname "$path")"
  now="$(date +%s)"
  expires="$((now + 604800))"
  display_ref="$(display_ref_for "$platform" "$pr_number")"
  mkdir -p "$dir"
  tmp="$(mktemp "$dir/.tmp.XXXXXX")"
  if ! jq -n \
    --argjson schema_version 1 \
    --arg platform "$platform" \
    --arg repo_root "$root" \
    --arg git_common_dir "$common_dir" \
    --arg remote_url "$remote_url" \
    --arg branch "$branch" \
    --arg head_sha "$head_sha" \
    --argjson pr_number "$pr_number" \
    --arg display_ref "$display_ref" \
    --arg html_url "$url" \
    --arg state "$state" \
    --arg source "$source" \
    --argjson updated_at_epoch "$now" \
    --argjson expires_at_epoch "$expires" \
    '{schema_version:$schema_version,platform:$platform,repo_root:$repo_root,git_common_dir:$git_common_dir,remote_url:$remote_url,branch:$branch,head_sha:$head_sha,pr_number:$pr_number,display_ref:$display_ref,html_url:$html_url,state:$state,source:$source,updated_at_epoch:$updated_at_epoch,expires_at_epoch:$expires_at_epoch}' \
    >"$tmp"; then
    rm -f "$tmp"
    exit 1
  fi
  mv "$tmp" "$path"
}

clear_cache() {
  local repo_dir="" remote_url="" branch="" live_remote_url="" path=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo-dir) [[ $# -ge 2 ]] || usage; repo_dir="$2"; shift 2 ;;
      --remote-url) [[ $# -ge 2 ]] || usage; remote_url="$2"; shift 2 ;;
      --branch) [[ $# -ge 2 ]] || usage; branch="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  if [[ -n "$remote_url" || -n "$branch" ]]; then
    if [[ -n "$remote_url" ]]; then
      [[ -n "$branch" ]] || usage
      rm -f "$(cache_path "$remote_url" "$branch")"
    else
      [[ -n "$repo_dir" && -n "$branch" ]] || usage
      if live_remote_url="$(repo_remote_url "$repo_dir" 2>/dev/null)"; then
        rm -f "$(cache_path "$live_remote_url" "$branch")"
      fi
      clear_entries_for_repo_root "$repo_dir" "$branch"
    fi
    return 0
  fi

  [[ -n "$repo_dir" ]] || usage
  if path="$(cache_path_for_repo "$repo_dir" 2>/dev/null)"; then
    rm -f "$path"
  else
    clear_entries_for_repo_root "$repo_dir"
  fi
}

cmd="${1:-}"
shift || true
case "$cmd" in
  write) write_cache "$@" ;;
  clear) clear_cache "$@" ;;
  *) usage ;;
esac
