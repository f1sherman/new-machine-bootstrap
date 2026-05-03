#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF' >&2
Usage: run.sh --platform <github|forgejo> --repo-dir <path> --head-branch <branch> --state-cmd <path> --comments-cmd <path> --deadline-epoch <epoch> [--memory-json <json>] [--poll-seconds <n>]
EOF
  exit 1
}

resolve_cache_helper() {
  local helper script_dir

  if [[ -n "${PR_STATUS_CACHE_HELPER:-}" ]]; then
    printf '%s\n' "$PR_STATUS_CACHE_HELPER"
    return 0
  fi

  if helper="$(command -v pr-status-cache.sh 2>/dev/null)"; then
    printf '%s\n' "$helper"
    return 0
  fi

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || return 1
  helper="$script_dir/../_pr-workflow-common/pr-status-cache.sh"
  [[ -x "$helper" ]] || return 1
  printf '%s\n' "$helper"
}

update_pr_status_cache() {
  local snapshot_json="$1"
  local helper state pr_number html_url head_sha remote_url

  helper="$(resolve_cache_helper)" || return 0
  state="$(jq -r '.monitor_state // ""' <<<"$snapshot_json" 2>/dev/null)" || return 0

  case "$state" in
    merged|closed|missing|cleaned_elsewhere)
      remote_url="$(jq -r '.remote_url // ""' <<<"$snapshot_json" 2>/dev/null)" || remote_url=""
      [[ -n "$remote_url" ]] || remote_url="${repo_remote_url:-}"
      if [[ -n "$remote_url" && -n "$head_branch" ]]; then
        "$helper" clear --remote-url "$remote_url" --branch "$head_branch" >/dev/null 2>&1 || true
      else
        "$helper" clear --repo-dir "$repo_dir" --branch "$head_branch" >/dev/null 2>&1 || true
      fi
      return 0
      ;;
  esac

  pr_number="$(jq -r 'if (.pr_number // "") == "" then "" else (.pr_number | tostring) end' <<<"$snapshot_json" 2>/dev/null)" || return 0
  html_url="$(jq -r '.html_url // ""' <<<"$snapshot_json" 2>/dev/null)" || return 0
  [[ -n "$pr_number" && -n "$html_url" ]] || return 0

  head_sha="$(jq -r '.head_sha // ""' <<<"$snapshot_json" 2>/dev/null)" || head_sha=""
  "$helper" write \
    --repo-dir "$repo_dir" \
    --platform "$platform" \
    --pr-number "$pr_number" \
    --url "$html_url" \
    --state open \
    --head-sha "$head_sha" \
    --source _pr-monitor \
    >/dev/null 2>&1 || true
}

clear_memory() {
  jq -cn '{fingerprint:"", first_seen_epoch:0, last_alerted_epoch:0, comments_seen:[]}'
}

resolve_repo_common_dir() {
  local common_dir

  common_dir="$(
    cd "$repo_dir" 2>/dev/null &&
      git rev-parse --git-common-dir 2>/dev/null
  )" || return 1

  if [[ "$common_dir" == /* ]]; then
    printf '%s\n' "$common_dir"
  else
    (
      cd "$repo_dir/$common_dir" 2>/dev/null &&
        pwd -P
    ) || return 1
  fi
}

resolve_repo_abs_dir() {
  (
    cd "$repo_dir" 2>/dev/null &&
      pwd -P
  ) || return 1
}

resolve_repo_remote_url() {
  git -C "$repo_dir" remote get-url origin 2>/dev/null
}

resolve_repo_safe_dir() {
  local repo_abs_dir="$1"
  local candidate

  if [[ -n "${repo_common_dir:-}" ]]; then
    candidate="$(dirname "$repo_common_dir")"
    candidate="$(
      cd "$candidate" 2>/dev/null &&
        pwd -P
    )" || candidate="/tmp"
  else
    candidate="/tmp"
  fi

  if [[ "$candidate" == "$repo_abs_dir" ]]; then
    printf '/tmp\n'
  else
    printf '%s\n' "$candidate"
  fi
}

clear_status_memory() {
  local current_memory="$1"

  jq -cn \
    --argjson memory "$current_memory" '
      {
        fingerprint: "",
        first_seen_epoch: 0,
        last_alerted_epoch: 0,
        comments_seen: ($memory.comments_seen // [])
      }
    '
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
          last_alerted_epoch: (.last_alerted_epoch // 0),
          comments_seen: (
            if (.comments_seen // []) | type == "array" then
              (.comments_seen // [])
            else
              []
            end
          )
        }
      else
        {
          fingerprint: "",
          first_seen_epoch: 0,
          last_alerted_epoch: 0,
          comments_seen: []
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

action_json_for_alert() {
  local snapshot_json="$1"
  local state
  local next_action
  local reply_required="false"
  local reply_command_template=""
  local comment_json_source=""

  state="$(jq -r '.monitor_state // "unknown"' <<<"$snapshot_json")"

  case "$state" in
    new_comment)
      next_action="Triage the new PR comments. Inline review comments (type: \"review\") always require a reply after handling feedback. PR-level comments (type: \"issue\") require a reply only when actionable or when a useful status response is warranted. Make changes only for valid feedback, run targeted verification, commit if files changed, update the PR description if your changes invalidate it, use the platform reply helper when a reply is required, then resume monitoring."
      reply_required=""
      comment_json_source="new_comment_threads[]"
      case "$platform" in
        github)
          reply_command_template='bash ~/.local/share/skills/_pr-github/reply-comment.sh "$OWNER/$REPO" "$PR_NUMBER" "$COMMENT_JSON" "reply text"'
          ;;
        forgejo)
          reply_command_template='bash ~/.local/share/skills/_pr-forgejo/reply-comment.sh "$OWNER" "$REPO" "$PR_NUMBER" "$COMMENT_JSON" "reply text"'
          ;;
      esac
      ;;
    checks_failed)
      next_action="Inspect the failing checks, fix the branch, run targeted verification, commit if files changed, update the PR description if your changes invalidate it, post a status comment when useful, then resume monitoring."
      ;;
    merge_conflict)
      next_action="Update the branch against the base branch, resolve the merge conflict, run targeted verification, commit if files changed, update the PR description if your changes invalidate it, post a status comment when useful, then resume monitoring."
      ;;
    missing)
      next_action="Inspect why the PR or branch lookup failed before assuming a code change is needed. If any follow-up changes invalidate the PR description, update it, then resume monitoring when the PR can be monitored again."
      ;;
    retryable_error)
      next_action="Investigate the monitor or helper error before re-arming monitoring. If any follow-up changes invalidate the PR description, update it. No PR feedback reply is required unless a user-facing status comment is useful."
      ;;
    *)
      next_action="Inspect the full monitor alert payload and monitor setup before acting. If any follow-up changes invalidate the PR description, update it, then resume monitoring when the correct next step is clear."
      ;;
  esac

  jq -cn \
    --arg next_action "$next_action" \
    --arg reply_required "$reply_required" \
    --arg reply_command_template "$reply_command_template" \
    --arg comment_json_source "$comment_json_source" '
      {
        required: true,
        next_action: $next_action,
        update_pr_description_if_invalidated: true
      }
      + (
        if $reply_required == "" then
          {}
        else
          {reply_required: ($reply_required == "true")}
        end
      )
      + (
        if $reply_command_template == "" then
          {}
        else
          {reply_command_template: $reply_command_template}
        end
      )
      + (
        if $comment_json_source == "" then
          {}
        else
          {comment_json_source: $comment_json_source}
        end
      )
    '
}

emit_result() {
  local result_kind="$1"
  local snapshot_json="$2"
  local current_memory="$3"
  local cleanup_status="${4:-}"
  local cleanup_output="${5:-}"
  local action_json="{}"

  if [[ "$result_kind" == "alert" ]]; then
    action_json="$(action_json_for_alert "$snapshot_json")"
  fi

  jq -c \
    --arg result_kind "$result_kind" \
    --arg cleanup_status "$cleanup_status" \
    --arg cleanup_output "$cleanup_output" \
    --slurpfile memory <(printf '%s\n' "$current_memory") \
    --argjson action "$action_json" '
      (. + {result_kind:$result_kind, memory:($memory[0] // {})})
      + (
        if $result_kind == "alert" then
          {action:$action}
        else
          {}
        end
      )
      + (
        if $cleanup_status == "" then
          {}
        else
          {cleanup_status:$cleanup_status, cleanup_output:$cleanup_output}
        end
      )
    ' <<<"$snapshot_json"
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

branch_exists_in_repo_common_dir() {
  [[ -n "${repo_common_dir:-}" ]] || return 1
  git --git-dir="$repo_common_dir" show-ref --verify --quiet "refs/heads/$head_branch" >/dev/null 2>&1
}

repo_dir_fallback_snapshot() {
  if [[ -d "$repo_dir" ]]; then
    return 1
  fi

  if branch_exists_in_repo_common_dir; then
    synthesized_retryable_error "repo dir missing: $repo_dir"
  else
    jq -cn \
      --arg platform "$platform" \
      --arg head "$head_branch" \
      --arg remote_url "${repo_remote_url:-}" '
        {
          platform:$platform,
          head:$head,
          branch:$head,
          remote_url:$remote_url,
          checks_state:"unknown",
          monitor_state:"cleaned_elsewhere",
          cleanup_status:"already_cleaned_elsewhere"
        }
      '
  fi
}

capture_snapshot() {
  local snapshot_json
  local exit_status=0

  if snapshot_json="$(repo_dir_fallback_snapshot)"; then
    printf '%s\n' "$snapshot_json"
    return 0
  fi

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

capture_comments() {
  local comments_json
  local exit_status=0

  if comments_json="$(repo_dir_fallback_snapshot)"; then
    printf '%s\n' "$comments_json"
    return 0
  fi

  comments_json="$(
    (
      cd "$repo_dir"
      bash "$comments_cmd" --head-branch "$head_branch"
    ) 2>&1
  )" || exit_status=$?

  if (( exit_status != 0 )); then
    if [[ -z "$comments_json" ]]; then
      comments_json='comments command failed'
    fi
    synthesized_retryable_error "$comments_json"
    return 0
  fi

  if ! jq -e . >/dev/null 2>&1 <<<"$comments_json"; then
    synthesized_retryable_error 'comments command returned invalid JSON'
    return 0
  fi

  if ! comments_error="$(jq -r '.error // ""' <<<"$comments_json" 2>/dev/null)"; then
    synthesized_retryable_error 'comments command returned invalid JSON'
    return 0
  fi
  if [[ -n "$comments_error" ]]; then
    synthesized_retryable_error "$comments_error"
    return 0
  fi

  printf '%s\n' "$comments_json"
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
          last_alerted_epoch: 0,
          comments_seen: ($memory.comments_seen // [])
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

remember_seen_comments() {
  local current_memory="$1"
  local new_comments_json="$2"

  jq -c \
    --argjson memory "$current_memory" \
    '
      . as $new_comments |
      $memory + {
        comments_seen: (
          (($memory.comments_seen // []) + ($new_comments | map(.comment_key))) | unique
        )
      }
    ' <<<"$new_comments_json"
}

enrich_comments() {
  local comments_json="$1"

  jq -c '
    (.current_user // "") as $current_user |
    (.comments // [])
    | to_entries
    | map(
        .value + {
          comment_index: .key,
          comment_key: (
            ((.value.platform // "") | tostring)
            + ":"
            + ((.value.type // "") | tostring)
            + ":"
            + ((.value.id // "") | tostring)
          ),
          is_agent_reply: (
            if ((.value.body | type) == "string") then
              (
                (((.value.user // "") == $current_user) and (.value.body | startswith("[Agent]")))
                or (
                  ((.value.user // "") == $current_user)
                  and ((.value.type // "") == "issue")
                  and (.value.body | startswith("> "))
                  and (.value.body | contains("\n\n[Agent]"))
                )
              )
            else
              false
            end
          )
        }
      )
  ' <<<"$comments_json"
}

select_new_comment_triggers() {
  local enriched_comments_json="$1"
  local current_memory="$2"

  jq -c \
    --argjson seen "$(jq '.comments_seen' <<<"$current_memory")" '
      map(select(.is_agent_reply | not))
      | map(select((.comment_key as $comment_key | $seen | index($comment_key)) | not))
    ' <<<"$enriched_comments_json"
}

dedupe_new_comment_triggers() {
  local trigger_comments_json="$1"

  jq -c '
      def root_id($comment):
        if (($comment.type // "") == "review") and (($comment.in_reply_to_id // null) != null) then
          $comment.in_reply_to_id
        else
          $comment.id
        end;

      sort_by(.comment_index)
      | reverse
      | unique_by(
          if ((.type // "") == "review") then
            "review:" + ((root_id(.)) | tostring)
          else
            .comment_key
          end
        )
      | sort_by(.comment_index)
    ' <<<"$trigger_comments_json"
}

build_new_comment_threads() {
  local enriched_comments_json="$1"
  local trigger_comments_json="$2"

  jq -c \
    --slurpfile triggers <(printf '%s\n' "$trigger_comments_json") '
      def root_id($comment):
        if (($comment.type // "") == "review") and (($comment.in_reply_to_id // null) != null) then
          $comment.in_reply_to_id
        else
          $comment.id
        end;

      def same_thread($trigger):
        if (($trigger.type // "") == "review") then
          (root_id($trigger)) as $root |
          map(
            select(
              ((.type // "") == "review")
              and (root_id(.) == $root)
              and (.comment_index <= $trigger.comment_index)
            )
          )
        else
          map(select(.comment_key == $trigger.comment_key))
        end;

      . as $all_comments |
      ($triggers[0] // [])
      | map(
          . as $trigger |
          ($all_comments | same_thread($trigger) | sort_by(.comment_index)) as $thread |
          {
            thread_comments: (
              $thread
              | map(del(.comment_key, .comment_index))
            )
          }
          + (
            if ($thread | length) > 1 then
              {response_instruction: "Respond to the last comment in this thread."}
            else
              {}
            end
          )
        )
    ' <<<"$enriched_comments_json"
}

platform=""
repo_dir=""
head_branch=""
state_cmd=""
comments_cmd=""
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
    --comments-cmd)
      [[ $# -ge 2 ]] || usage
      comments_cmd="$2"
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

[[ -n "$platform" && -n "$repo_dir" && -n "$head_branch" && -n "$state_cmd" && -n "$comments_cmd" && -n "$deadline_epoch" ]] || usage

memory_json="$(normalize_memory "$memory_json")"
repo_common_dir="$(resolve_repo_common_dir || true)"
repo_abs_dir="$(resolve_repo_abs_dir || true)"
repo_remote_url="$(resolve_repo_remote_url || true)"
repo_safe_dir="$(resolve_repo_safe_dir "$repo_abs_dir")"

if [[ -n "$repo_safe_dir" ]]; then
  cd "$repo_safe_dir" || true
fi

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
  update_pr_status_cache "$snapshot_json"
  state="$(jq -r '.monitor_state // ""' <<<"$snapshot_json")"

  case "$state" in
    cleaned_elsewhere)
      emit_result final "$snapshot_json" "$(clear_memory)"
      exit 0
      ;;
    merged)
      emit_result final "$snapshot_json" "$(clear_memory)"
      exit 0
      ;;
    closed)
      emit_result final "$snapshot_json" "$(clear_memory)"
      exit 0
      ;;
  esac

  fingerprint="$(alert_fingerprint "$snapshot_json")"
  if [[ -n "$fingerprint" ]]; then
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
    continue
  fi

  comments_json="$(capture_comments)"
  if [[ "$(jq -r '.monitor_state // ""' <<<"$comments_json")" == "retryable_error" ]]; then
    snapshot_json="$comments_json"
    update_pr_status_cache "$snapshot_json"
    state="$(jq -r '.monitor_state // ""' <<<"$snapshot_json")"
    fingerprint="$(alert_fingerprint "$snapshot_json")"
    memory_json="$(remember_fingerprint "$memory_json" "$fingerprint" "$now")"
    first_seen_epoch="$(jq -r '.first_seen_epoch' <<<"$memory_json")"
    last_alerted_epoch="$(jq -r '.last_alerted_epoch' <<<"$memory_json")"

    alert_due=false
    if (( now - first_seen_epoch >= 300 )) && (( last_alerted_epoch == 0 || now - last_alerted_epoch >= 600 )); then
      alert_due=true
    fi

    if [[ "$alert_due" == true ]]; then
      memory_json="$(mark_alerted "$memory_json" "$now")"
      emit_result alert "$snapshot_json" "$memory_json"
      exit 0
    fi

    sleep "$poll_seconds"
    continue
  fi

  memory_json="$(clear_status_memory "$memory_json")"
  enriched_comments_json="$(enrich_comments "$comments_json")"
  new_comment_triggers_json="$(select_new_comment_triggers "$enriched_comments_json" "$memory_json")"
  deduped_comment_triggers_json="$(dedupe_new_comment_triggers "$new_comment_triggers_json")"
  new_comment_threads_json="$(build_new_comment_threads "$enriched_comments_json" "$deduped_comment_triggers_json")"

  if [[ "$(jq 'length' <<<"$new_comment_triggers_json")" -gt 0 ]]; then
    memory_json="$(remember_seen_comments "$memory_json" "$new_comment_triggers_json")"
    snapshot_json="$(
      jq -c \
        --slurpfile new_comment_threads <(printf '%s\n' "$new_comment_threads_json") '
          . + {
            monitor_state: "new_comment",
            new_comment_threads: ($new_comment_threads[0] // [])
          }
        ' <<<"$snapshot_json"
    )"
    emit_result alert "$snapshot_json" "$memory_json"
    exit 0
  fi

  sleep "$poll_seconds"
done
