#!/usr/bin/env bash

TMUX_RESTORE_STATE_DIR="${TMUX_RESTORE_STATE_DIR:-$HOME/.local/state/tmux}"
TMUX_RESTORE_LOG="${TMUX_RESTORE_LOG:-$TMUX_RESTORE_STATE_DIR/restore.log}"
TMUX_RESTORE_LOG_LIMIT="${TMUX_RESTORE_LOG_LIMIT:-262144}"
TMUX_RESTORE_LOG_SEQUENCE=0

tmux_restore_sanitize() {
  printf '%s' "$1" | tr '\r\n\t' '   '
}

tmux_restore_rotate_log() {
  local log_size

  [ -f "$TMUX_RESTORE_LOG" ] || return 0
  log_size="$(wc -c < "$TMUX_RESTORE_LOG" 2>/dev/null)" || return 0
  [ "$log_size" -gt "$TMUX_RESTORE_LOG_LIMIT" ] 2>/dev/null || return 0
  mv -f "$TMUX_RESTORE_LOG" "$TMUX_RESTORE_LOG.previous" 2>/dev/null || return 0
}

tmux_restore_log_event() {
  local event line field tab

  event="$1"
  shift
  TMUX_RESTORE_LOG_SEQUENCE=$((TMUX_RESTORE_LOG_SEQUENCE + 1))
  mkdir -p "$TMUX_RESTORE_STATE_DIR" 2>/dev/null || return 0
  tmux_restore_rotate_log

  tab="$(printf '\t')"
  line="timestamp=$(date '+%Y-%m-%dT%H:%M:%S%z')"
  line="$line${tab}seq=$TMUX_RESTORE_LOG_SEQUENCE${tab}pid=$$${tab}ppid=$PPID"
  line="$line${tab}event=$(tmux_restore_sanitize "$event")"
  for field in "$@"; do
    line="$line${tab}$(tmux_restore_sanitize "$field")"
  done
  printf '%s\n' "$line" >> "$TMUX_RESTORE_LOG" 2>/dev/null || return 0
}
