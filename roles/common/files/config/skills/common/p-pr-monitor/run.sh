#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF' >&2
Usage: run.sh --platform <github|forgejo> --repo-dir <path> --head-branch <branch> --state-cmd <path> --deadline-epoch <epoch> [--memory-json <json>] [--poll-seconds <n>]
EOF
  exit 1
}

clear_memory() {
  jq -cn '{fingerprint:"", first_seen_epoch:0, last_alerted_epoch:0}'
}

now_epoch() {
  date +%s
}

normalize_memory() {
  local raw="${1:-{}}"
  local normalized

  normalized="$(
    jq -c '
      if type == "object" then
        {
          fingerprint: (.fingerprint // ""),
          first_seen_epoch: (.first_seen_epoch // 0),
          last_alerted_epoch: (.last_alerted_epoch // 0)
        }
      else
        {
          fingerprint: "",
          first_seen_epoch: 0,
          last_alerted_epoch: 0
        }
      end
    ' <<<"$raw" 2>/dev/null || true
  )"

  if [[ -n "$normalized" ]]; then
    printf '%s\n' "$normalized"
  else
    clear_memory
  fi
}

emit_result() {
  local result_kind="$1"
  local snapshot_json="$2"
  local current_memory="$3"
  local cleanup_status="${4:-}"
  local cleanup_output="${5:-}"

  jq -cn \
    --arg result_kind "$result_kind" \
    --arg cleanup_status "$cleanup_status" \
    --arg cleanup_output "$cleanup_output" \
    --argjson snapshot "$snapshot_json" \
    --argjson memory "$current_memory" '
      ($snapshot + {result_kind:$result_kind, memory:$memory})
      + (
        if $cleanup_status == "" then
          {}
        else
          {cleanup_status:$cleanup_status, cleanup_output:$cleanup_output}
        end
      )
    '
}

synthesized_retryable_error() {
  local reason="$1"

  jq -cn \
    --arg platform "$platform" \
    --arg head "$head_branch" \
    --arg error "$reason" '
      {
        platform:$platform,
        head:$head,
        checks_state:"error",
        monitor_state:"retryable_error",
        error:$error
      }
    '
}

capture_snapshot() {
  local snapshot_json
  local exit_status=0

  snapshot_json="$(
    (
      cd "$repo_dir"
      bash "$state_cmd" --head-branch "$head_branch"
    ) 2>&1
  )" || exit_status=$?

  if (( exit_status != 0 )); then
    if [[ -z "$snapshot_json" ]]; then
      snapshot_json='state command failed'
    fi
    synthesized_retryable_error "$snapshot_json"
    return 0
  fi

  if ! jq -e . >/dev/null 2>&1 <<<"$snapshot_json"; then
    synthesized_retryable_error 'state command returned invalid JSON'
    return 0
  fi

  printf '%s\n' "$snapshot_json"
}

alert_fingerprint() {
  local snapshot_json="$1"
  local state
  local head_sha
  local error_reason

  state="$(jq -r '.monitor_state // ""' <<<"$snapshot_json")"
  head_sha="$(jq -r '.head_sha // ""' <<<"$snapshot_json")"
  error_reason="$(jq -r '.error // ""' <<<"$snapshot_json")"

  case "$state" in
    checks_failed|merge_conflict)
      if [[ -n "$head_sha" ]]; then
        printf '%s:%s\n' "$state" "$head_sha"
      else
        printf '%s:%s\n' "$state" "$head_branch"
      fi
      ;;
    missing)
      printf 'missing:%s\n' "$head_branch"
      ;;
    retryable_error)
      printf 'retryable_error:%s\n' "$error_reason"
      ;;
    *)
      printf '\n'
      ;;
  esac
}

remember_fingerprint() {
  local current_memory="$1"
  local fingerprint="$2"
  local now="$3"

  jq -cn \
    --argjson memory "$current_memory" \
    --arg fingerprint "$fingerprint" \
    --argjson now "$now" '
      if $memory.fingerprint == $fingerprint then
        $memory
      else
        {
          fingerprint: $fingerprint,
          first_seen_epoch: $now,
          last_alerted_epoch: 0
        }
      end
    '
}

mark_alerted() {
  local current_memory="$1"
  local now="$2"

  jq -cn \
    --argjson memory "$current_memory" \
    --argjson now "$now" \
    '$memory + {last_alerted_epoch:$now}'
}

run_merged_cleanup() {
  local snapshot_json="$1"
  local cleanup_output

  if ! cleanup_output="$(cleanup-branches --branch "$head_branch" --delete-remote --yes 2>&1)"; then
    emit_result final "$snapshot_json" "$(clear_memory)" cleanup_failed "$cleanup_output"
    return 0
  fi

  if grep -Fq 'Remote branch retained:' <<<"$cleanup_output"; then
    emit_result final "$snapshot_json" "$(clear_memory)" remote_retained "$cleanup_output"
    return 0
  fi

  tmux-agent-worktree clear >/dev/null 2>&1 || true
  emit_result final "$snapshot_json" "$(clear_memory)" cleaned "$cleanup_output"
}

platform=""
repo_dir=""
head_branch=""
state_cmd=""
deadline_epoch=""
memory_json='{}'
poll_seconds=60

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform)
      [[ $# -ge 2 ]] || usage
      platform="$2"
      shift 2
      ;;
    --repo-dir)
      [[ $# -ge 2 ]] || usage
      repo_dir="$2"
      shift 2
      ;;
    --head-branch)
      [[ $# -ge 2 ]] || usage
      head_branch="$2"
      shift 2
      ;;
    --state-cmd)
      [[ $# -ge 2 ]] || usage
      state_cmd="$2"
      shift 2
      ;;
    --deadline-epoch)
      [[ $# -ge 2 ]] || usage
      deadline_epoch="$2"
      shift 2
      ;;
    --memory-json)
      [[ $# -ge 2 ]] || usage
      memory_json="$2"
      shift 2
      ;;
    --poll-seconds)
      [[ $# -ge 2 ]] || usage
      poll_seconds="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$platform" && -n "$repo_dir" && -n "$head_branch" && -n "$state_cmd" && -n "$deadline_epoch" ]] || usage

memory_json="$(normalize_memory "$memory_json")"

while :; do
  now="$(now_epoch)"
  if (( now >= deadline_epoch )); then
    timeout_snapshot="$(
      jq -cn \
        --arg platform "$platform" \
        --arg head "$head_branch" '
          {
            platform:$platform,
            head:$head,
            monitor_state:"timeout_24h"
          }
        '
    )"
    emit_result final "$timeout_snapshot" "$(clear_memory)"
    exit 0
  fi

  snapshot_json="$(capture_snapshot)"
  state="$(jq -r '.monitor_state // ""' <<<"$snapshot_json")"

  case "$state" in
    merged)
      run_merged_cleanup "$snapshot_json"
      exit 0
      ;;
    closed)
      emit_result final "$snapshot_json" "$(clear_memory)"
      exit 0
      ;;
  esac

  fingerprint="$(alert_fingerprint "$snapshot_json")"
  if [[ -z "$fingerprint" ]]; then
    memory_json="$(clear_memory)"
    sleep "$poll_seconds"
    continue
  fi

  memory_json="$(remember_fingerprint "$memory_json" "$fingerprint" "$now")"
  first_seen_epoch="$(jq -r '.first_seen_epoch' <<<"$memory_json")"
  last_alerted_epoch="$(jq -r '.last_alerted_epoch' <<<"$memory_json")"

  alert_due=false
  if [[ "$state" == "retryable_error" ]]; then
    if (( now - first_seen_epoch >= 300 )) && (( last_alerted_epoch == 0 || now - last_alerted_epoch >= 600 )); then
      alert_due=true
    fi
  else
    if (( last_alerted_epoch == 0 || now - last_alerted_epoch >= 600 )); then
      alert_due=true
    fi
  fi

  if [[ "$alert_due" == true ]]; then
    memory_json="$(mark_alerted "$memory_json" "$now")"
    emit_result alert "$snapshot_json" "$memory_json"
    exit 0
  fi

  sleep "$poll_seconds"
done
