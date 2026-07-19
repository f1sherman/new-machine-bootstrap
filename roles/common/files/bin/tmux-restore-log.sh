#!/usr/bin/env bash

TMUX_RESTORE_STATE_DIR="${TMUX_RESTORE_STATE_DIR:-$HOME/.local/state/tmux}"
TMUX_RESTORE_LOG="${TMUX_RESTORE_LOG:-$TMUX_RESTORE_STATE_DIR/restore.log}"
TMUX_RESTORE_LOG_LIMIT="${TMUX_RESTORE_LOG_LIMIT:-262144}"
TMUX_RESTORE_LOCK="${TMUX_RESTORE_LOCK:-$TMUX_RESTORE_STATE_DIR/restore.lock}"
TMUX_RESTORE_LOG_SEQUENCE=0

_tmux_restore_log_limit() {
  local limit

  limit="$TMUX_RESTORE_LOG_LIMIT"
  case "$limit" in
    ''|*[!0-9]*)
      printf '%s' 262144
      return
      ;;
  esac
  while [ "${limit#0}" != "$limit" ]; do
    limit="${limit#0}"
  done
  case "$limit" in
    ''|*[!0-9]*) limit=262144 ;;
  esac
  [ "${#limit}" -le 9 ] || limit=262144
  printf '%s' "$limit"
}

tmux_restore_sanitize() {
  printf '%s' "$1" | tr '\r\n\t' '   '
}

_tmux_restore_cap_file_unlocked() {
  local file limit log_size temporary

  file="$1"
  limit="$2"
  [ -f "$file" ] || return 0
  log_size="$(wc -c < "$file" 2>/dev/null)" || return 1
  [ "$log_size" -gt "$limit" ] 2>/dev/null || return 0

  temporary="$file.tmp.$$"
  tail -c "$limit" "$file" 2>/dev/null | sed '1d' > "$temporary" || {
    rm -f "$temporary"
    return 1
  }
  mv -f "$temporary" "$file" 2>/dev/null || {
    rm -f "$temporary"
    return 1
  }
}

_tmux_restore_rotate_log_unlocked() {
  local limit log_size

  limit="$1"
  [ -f "$TMUX_RESTORE_LOG" ] || return 0
  log_size="$(wc -c < "$TMUX_RESTORE_LOG" 2>/dev/null)" || return 1
  [ "$log_size" -gt "$limit" ] 2>/dev/null || return 0
  mv -f "$TMUX_RESTORE_LOG" "$TMUX_RESTORE_LOG.previous" 2>/dev/null || return 1
  _tmux_restore_cap_file_unlocked "$TMUX_RESTORE_LOG.previous" "$limit"
}

tmux_restore_rotate_log() {
  local limit

  limit="$(_tmux_restore_log_limit)"
  mkdir -p "$TMUX_RESTORE_STATE_DIR" 2>/dev/null || return 0
  (
    flock -n -x 9 2>/dev/null || exit 0
    _tmux_restore_cap_file_unlocked "$TMUX_RESTORE_LOG.previous" "$limit" || exit 0
    _tmux_restore_rotate_log_unlocked "$limit" || exit 0
  ) 9> "$TMUX_RESTORE_LOCK" 2>/dev/null || return 0
}

tmux_restore_log_event() {
  local event line field tab limit

  event="$1"
  shift
  TMUX_RESTORE_LOG_SEQUENCE=$((TMUX_RESTORE_LOG_SEQUENCE + 1))
  mkdir -p "$TMUX_RESTORE_STATE_DIR" 2>/dev/null || return 0

  tab="$(printf '\t')"
  line="timestamp=$(date '+%Y-%m-%dT%H:%M:%S%z')"
  line="$line${tab}seq=$TMUX_RESTORE_LOG_SEQUENCE${tab}pid=$$${tab}ppid=$PPID"
  line="$line${tab}event=$(tmux_restore_sanitize "$event")"
  for field in "$@"; do
    line="$line${tab}$(tmux_restore_sanitize "$field")"
  done
  limit="$(_tmux_restore_log_limit)"
  (
    local line_size incoming_size current_size maximum_line_size

    flock -n -x 9 2>/dev/null || exit 0
    maximum_line_size=$((limit - 1))
    line_size="$(printf '%s' "$line" | wc -c | tr -d ' ')" || exit 0
    if [ "$line_size" -gt "$maximum_line_size" ] 2>/dev/null; then
      if [ "$maximum_line_size" -eq 0 ]; then
        line=""
      else
        line="$(printf '%s' "$line" | LC_ALL=C cut -c "1-$maximum_line_size")" || exit 0
      fi
    fi
    incoming_size="$(printf '%s\n' "$line" | wc -c | tr -d ' ')" || exit 0

    _tmux_restore_cap_file_unlocked "$TMUX_RESTORE_LOG.previous" "$limit" || exit 0
    current_size=0
    if [ -f "$TMUX_RESTORE_LOG" ]; then
      current_size="$(wc -c < "$TMUX_RESTORE_LOG" 2>/dev/null)" || exit 0
    fi
    if [ $((current_size + incoming_size)) -gt "$limit" ]; then
      mv -f "$TMUX_RESTORE_LOG" "$TMUX_RESTORE_LOG.previous" 2>/dev/null || exit 0
      _tmux_restore_cap_file_unlocked "$TMUX_RESTORE_LOG.previous" "$limit" || exit 0
    fi
    printf '%s\n' "$line" >> "$TMUX_RESTORE_LOG" 2>/dev/null || exit 0
  ) 9> "$TMUX_RESTORE_LOCK" 2>/dev/null || return 0
}
