#!/usr/bin/env bash

terminal_restore_state_dir() {
  printf '%s/.local/state/terminal-restore\n' "$HOME"
}

terminal_restore_manifest_path() {
  printf '%s/ghostty-layout.json\n' "$(terminal_restore_state_dir)"
}

terminal_restore_last_good_manifest_path() {
  printf '%s/ghostty-layout.last-good.json\n' "$(terminal_restore_state_dir)"
}

terminal_restore_sessions_dir() {
  printf '%s/sessions\n' "$(terminal_restore_state_dir)"
}

terminal_restore_reconcile_lock_dir() {
  printf '%s/reconcile.lock.d\n' "$(terminal_restore_state_dir)"
}

terminal_restore_reconcile_marker_path() {
  printf '%s/reconcile.done\n' "$(terminal_restore_state_dir)"
}

terminal_restore_ensure_dirs() {
  mkdir -p "$(terminal_restore_state_dir)" "$(terminal_restore_sessions_dir)"
}

terminal_restore_session_key() {
  printf '%s' "$1" | tr '/ :\t' '____'
}

terminal_restore_boot_epoch() {
  case "$(uname -s)" in
    Darwin)
      sysctl -n kern.boottime | awk -F '[ ,}]+' '{print $4}'
      ;;
    Linux)
      date -d "$(uptime -s)" +%s
      ;;
    *)
      date +%s
      ;;
  esac
}
