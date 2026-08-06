#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
log_lib="$repo_root/roles/common/files/bin/tmux-restore-log.sh"
wrapper="$repo_root/roles/common/files/bin/tmux-resurrect-restore-wrapper"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/tmux-restore-diagnostics.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }
assert_contains() {
  case "$1" in *"$2"*) ;; *) fail "expected output to contain: $2" ;; esac
}

export HOME="$tmpdir/home"
export TMUX_RESTORE_STATE_DIR="$tmpdir/state"
export TMUX_RESTORE_LOG="$TMUX_RESTORE_STATE_DIR/restore.log"
export TMUX_RESTORE_LOG_LIMIT=512
resurrect_dir="$HOME/.local/share/tmux/resurrect"
mkdir -p "$resurrect_dir" "$TMUX_RESTORE_STATE_DIR"

restore_script="$tmpdir/restore.sh"
cat >"$restore_script" <<'SH'
#!/usr/bin/env bash
exit 23
SH
chmod +x "$restore_script"
printf 'wrapper snapshot\n' >"$resurrect_dir/snapshot.txt"
ln -s snapshot.txt "$resurrect_dir/last"

set +e
TMUX_RESTORE_LOG_LIB="$log_lib" \
TMUX_RESURRECT_DIR="$resurrect_dir" \
TMUX_RESURRECT_RESTORE_SCRIPT="$restore_script" \
  "$wrapper"
wrapper_status=$?
set -e
[ "$wrapper_status" -eq 23 ] || fail "restore wrapper did not preserve exit status"
wrapper_events="$(cat "$TMUX_RESTORE_LOG" "$TMUX_RESTORE_LOG.previous" 2>/dev/null || true)"
assert_contains "$wrapper_events" 'event=restore_start'
assert_contains "$wrapper_events" 'event=restore_end'
assert_contains "$wrapper_events" 'status=23'

missing_log_restore_marker="$tmpdir/missing-log-restore-ran"
cat >"$restore_script" <<'SH'
#!/usr/bin/env bash
: > "$MISSING_LOG_RESTORE_MARKER"
SH
chmod +x "$restore_script"
MISSING_LOG_RESTORE_MARKER="$missing_log_restore_marker" \
TMUX_RESTORE_LOG_LIB="$tmpdir/missing-log-library" \
TMUX_RESURRECT_DIR="$resurrect_dir" \
TMUX_RESURRECT_RESTORE_SCRIPT="$restore_script" \
  "$wrapper" || fail "restore wrapper treated diagnostics as mandatory"
[ -f "$missing_log_restore_marker" ] || \
  fail "restore wrapper did not run restore when diagnostics were unavailable"

printf 'PASS  restore status preservation and diagnostics fail-open behavior\n'
