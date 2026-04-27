#!/usr/bin/env bash

tmux_review_tmux_bin() {
  printf '%s\n' "${TMUX_REVIEW_TMUX_BIN:-tmux}"
}

tmux_review_require_tmux() {
  local caller="$1"
  [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] && return 0
  printf '%s: tmux is required\n' "$caller" >&2
  return 1
}

tmux_review_state_file() {
  printf '%s/%s.%s\n' "$TMUX_REVIEW_STATE_DIR" "$1" "$2"
}

tmux_review_get_option() {
  local target_type="$1" target="$2" option_name="$3" path tmux_bin
  if [ -n "${TMUX_REVIEW_STATE_DIR:-}" ]; then
    path="$(tmux_review_state_file "$target" "$option_name")"
    [ -f "$path" ] || return 1
    cat "$path"
    return 0
  fi

  tmux_bin="$(tmux_review_tmux_bin)"
  case "$target_type" in
    pane)
      "$tmux_bin" show-options -p -v -t "$target" "$option_name" 2>/dev/null
      ;;
    window)
      "$tmux_bin" show-options -w -v -t "$target" "$option_name" 2>/dev/null
      ;;
    *)
      return 1
      ;;
  esac
}

tmux_review_set_option() {
  local target_type="$1" target="$2" option_name="$3" value="$4" tmux_bin
  if [ -n "${TMUX_REVIEW_STATE_DIR:-}" ]; then
    mkdir -p "$TMUX_REVIEW_STATE_DIR"
    printf '%s' "$value" > "$(tmux_review_state_file "$target" "$option_name")"
    return 0
  fi

  tmux_bin="$(tmux_review_tmux_bin)"
  case "$target_type" in
    pane)
      "$tmux_bin" set-option -p -t "$target" "$option_name" "$value" >/dev/null 2>&1
      ;;
    window)
      "$tmux_bin" set-option -w -t "$target" "$option_name" "$value" >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

tmux_review_clear_option() {
  local target_type="$1" target="$2" option_name="$3" tmux_bin
  if [ -n "${TMUX_REVIEW_STATE_DIR:-}" ]; then
    rm -f "$(tmux_review_state_file "$target" "$option_name")"
    return 0
  fi

  tmux_bin="$(tmux_review_tmux_bin)"
  case "$target_type" in
    pane)
      "$tmux_bin" set-option -p -t "$target" -u "$option_name" >/dev/null 2>&1
      ;;
    window)
      "$tmux_bin" set-option -w -t "$target" -u "$option_name" >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

tmux_review_window_exists() {
  local tmux_bin
  tmux_bin="$(tmux_review_tmux_bin)"
  # `display-message -p -t` returns rc=0 with empty stdout when the target is
  # missing, so it cannot distinguish live from stale windows. `list-windows`
  # fails for unknown targets.
  "$tmux_bin" list-windows -t "$1" -F '' >/dev/null 2>&1
}

tmux_review_pane_exists() {
  local tmux_bin
  tmux_bin="$(tmux_review_tmux_bin)"
  "$tmux_bin" list-panes -t "$1" -F '' >/dev/null 2>&1
}

tmux_review_current_window_id() {
  local tmux_bin
  tmux_bin="$(tmux_review_tmux_bin)"
  "$tmux_bin" display-message -p -t "$1" '#{window_id}' 2>/dev/null
}

tmux_review_current_path() {
  local tmux_bin
  tmux_bin="$(tmux_review_tmux_bin)"
  "$tmux_bin" display-message -p -t "$1" '#{pane_current_path}' 2>/dev/null
}

tmux_review_window_name() {
  local tmux_bin
  tmux_bin="$(tmux_review_tmux_bin)"
  "$tmux_bin" display-message -p -t "$1" '#{window_name}' 2>/dev/null
}

tmux_review_message() {
  local tmux_bin
  tmux_bin="$(tmux_review_tmux_bin)"
  "$tmux_bin" display-message "$1" >/dev/null 2>&1 || true
}

tmux_review_quote() {
  printf '%q' "$1"
}

tmux_review_window_label() {
  local pane_id="$1" raw label
  raw="$(tmux_review_window_name "$pane_id" 2>/dev/null || true)"
  [ -n "$raw" ] || raw="${pane_id#%}"
  label="${raw// /-}"
  label="${label//[^[:alnum:]:_.-]/-}"
  [ -n "$label" ] || label="${pane_id#%}"
  printf 'review:%s\n' "$label"
}
