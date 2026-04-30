# Pane-Level Error Reporting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a reusable `report-pane-error` shell primitive, migrate `tmux-hook-run` to delegate to it, and make the failure indicator pane-scoped so multiple panes can independently surface failures via badge + log.

**Architecture:** Single new bash script (`report-pane-error`) is the source of truth for "log a failure + flag the pane that produced it". `tmux-hook-run` becomes a thin wrap-and-run convenience that calls the new primitive on its failure path. tmux config flips the option from server-global `@hook-last-error` to per-pane `@pane-last-error`, with a `!` sigil in `pane-border-format` (per-pane glanceability) and the full message in `status-right` (active pane). Log file moves from `~/.local/state/tmux/hooks.log` to `~/.local/state/failures.log` since the failures are no longer tmux-hook-specific.

**Tech Stack:** Bash, tmux user options, Ansible.

Spec: `docs/superpowers/specs/2026-04-30-pane-error-reporting-design.md`.

---

## File Structure

**New:**
- `roles/common/files/bin/report-pane-error` — primitive script (~40 lines bash). Single responsibility: append failure record to log, optionally set `@pane-last-error` on a pane.
- `roles/common/files/bin/report-pane-error.test` — bash test, same style as `tmux-hook-run.test` (stub `tmux` and `date` on PATH).

**Modified:**
- `roles/common/files/bin/tmux-hook-run` — delegate failure-path work to `report-pane-error`.
- `roles/common/files/bin/tmux-hook-run.test` — assert wrapper invokes `report-pane-error`; passing-command behavior unchanged.
- `roles/common/files/bin/tmux-window-bar-config.test` — replace assertions about `@hook-last-error` / `~/.local/state/tmux/hooks.log` with the new names; add assertions for the per-pane sigil in `pane-border-format` and the `TMUX_HOOK_PANE_ID=#{pane_id}` env on each `tmux-hook-run` invocation.
- `roles/common/tasks/main.yml` — install `report-pane-error` alongside `tmux-hook-run`; rename the "tmux state directory" task to create `~/.local/state/` (parent only) since the new log is at `~/.local/state/failures.log`.
- `roles/macos/templates/dotfiles/tmux.conf` — switch `pane-border-format`, `status-right`, `bind h`, and the three `set-hook` lines as described in the spec.
- `roles/linux/files/dotfiles/tmux.conf` — same edits as macOS.

---

## Task 1: Build `report-pane-error` primitive (TDD)

**Files:**
- Create: `roles/common/files/bin/report-pane-error`
- Create: `roles/common/files/bin/report-pane-error.test`

- [ ] **Step 1: Create the test scaffolding (no cases yet, just framework)**

Save as `roles/common/files/bin/report-pane-error.test`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/report-pane-error"

if [ ! -x "$SCRIPT" ]; then
  printf 'ERROR: %s is not executable (or does not exist)\n' "$SCRIPT" >&2
  exit 2
fi

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

bindir="$TMPROOT/bin"
mkdir -p "$bindir"
tmux_log="$TMPROOT/tmux.log"
log_file="$TMPROOT/.local/state/failures.log"
mkdir -p "$(dirname "$log_file")"

# Stub tmux: record args, succeed for set-option, fail otherwise.
cat > "$bindir/tmux" <<'EOTMUX'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$REPORT_PANE_ERROR_TEST_TMUX_LOG"
case "${1:-}" in
  set-option) exit 0 ;;
  *) exit 1 ;;
esac
EOTMUX
chmod +x "$bindir/tmux"

# Stub date for deterministic timestamps.
cat > "$bindir/date" <<'EOD'
#!/usr/bin/env bash
printf '2026-04-30T12:00:00-0500\n'
EOD
chmod +x "$bindir/date"

run_primitive() {
  PATH="$bindir:/usr/bin:/bin" \
  HOME="$TMPROOT" \
  REPORT_PANE_ERROR_TEST_TMUX_LOG="$tmux_log" \
  "$SCRIPT" "$@"
}

reset_state() {
  : > "$tmux_log"
  : > "$log_file"
}

assert_exit_zero() {
  local label="$1"; shift
  if "$@"; then
    printf 'PASS  %s\n' "$label"
  else
    printf 'FAIL  %s (exit %d)\n' "$label" "$?" >&2
    exit 1
  fi
}

assert_grep() {
  local file="$1" pattern="$2" label="$3"
  if grep -Fq -- "$pattern" "$file"; then
    printf 'PASS  %s\n' "$label"
  else
    printf 'FAIL  %s\nmissing %q in %s:\n' "$label" "$pattern" "$file" >&2
    cat "$file" >&2
    exit 1
  fi
}

assert_no_grep() {
  local file="$1" pattern="$2" label="$3"
  if [ ! -s "$file" ] || ! grep -Fq -- "$pattern" "$file"; then
    printf 'PASS  %s\n' "$label"
  else
    printf 'FAIL  %s\nunexpectedly found %q in %s\n' "$label" "$pattern" "$file" >&2
    exit 1
  fi
}

# (cases added in following steps)

printf '\nALL TESTS PASSED\n'
```

`chmod +x roles/common/files/bin/report-pane-error.test`

- [ ] **Step 2: Add Case 1 — basic invocation with `--pane` writes log and sets option**

Insert before `printf '\nALL TESTS PASSED\n'`:

```bash
# --- Case 1: --pane flag → log entry + tmux set-option on that pane ---
reset_state
assert_exit_zero "basic call exits 0" run_primitive my-source "boom message" --pane %42
assert_grep "$log_file" "name=my-source" "log records source name"
assert_grep "$log_file" "boom message" "log records message"
assert_grep "$log_file" "pane=%42" "log records pane id"
assert_grep "$log_file" "2026-04-30T12:00:00-0500" "log records timestamp"
assert_grep "$tmux_log" "set-option -pq -t %42 @pane-last-error" "tmux set-option targets pane"
assert_grep "$tmux_log" "my-source: boom message" "tmux value contains source: msg"
```

- [ ] **Step 3: Run the test, expect FAIL because the script doesn't exist**

Run: `roles/common/files/bin/report-pane-error.test`
Expected: `ERROR: …/report-pane-error is not executable (or does not exist)`, exit 2.

- [ ] **Step 4: Implement minimal `report-pane-error` to satisfy Case 1**

Save as `roles/common/files/bin/report-pane-error`:

```bash
#!/usr/bin/env bash
# report-pane-error <name> [<message>] [--pane <pane_id>]
#
# Append a timestamped failure record to ~/.local/state/failures.log, and
# (when a pane id is known) set @pane-last-error on that pane so the tmux
# status indicator surfaces it. Always exits 0.
#
# Pane id resolution: --pane flag > $TMUX_PANE > none (log-only).
# If no message is given as the second positional arg, stdin is consumed and
# the first non-empty line is used for the badge while the full content
# goes to the log.
set -u

name=""
message=""
pane_id="${TMUX_PANE:-}"

# Parse args. Accept up to two positional (name, message) plus --pane <id>.
positional=()
while [ $# -gt 0 ]; do
  case "$1" in
    --pane)
      pane_id="${2:-}"
      shift 2 || shift
      ;;
    --pane=*)
      pane_id="${1#--pane=}"
      shift
      ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done

[ "${#positional[@]}" -ge 1 ] || exit 0
name="${positional[0]}"
if [ "${#positional[@]}" -ge 2 ]; then
  message="${positional[1]}"
fi

stdin_content=""
if [ ! -t 0 ]; then
  stdin_content="$(cat || true)"
fi
if [ -z "$message" ]; then
  message="${stdin_content%%[$'\r\n']*}"
fi

log_file="${HOME:-/tmp}/.local/state/failures.log"
mkdir -p "$(dirname "$log_file")" 2>/dev/null || true

ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
{
  printf '[%s] pane=%s name=%s\n' "$ts" "${pane_id:-none}" "$name"
  printf 'message: %s\n' "$message"
  if [ -n "$stdin_content" ]; then
    printf '%s\n' "$stdin_content"
  fi
  printf -- '---\n'
} >> "$log_file"

if [ -n "$pane_id" ]; then
  badge="${name}: ${message:-error}"
  if [ "${#badge}" -gt 60 ]; then
    badge="${badge:0:57}..."
  fi
  tmux set-option -pq -t "$pane_id" @pane-last-error "$badge" 2>/dev/null || true
fi

exit 0
```

`chmod +x roles/common/files/bin/report-pane-error`

- [ ] **Step 5: Run the test, expect PASS**

Run: `roles/common/files/bin/report-pane-error.test`
Expected: `PASS` lines for each Case 1 assertion, then `ALL TESTS PASSED`.

- [ ] **Step 6: Add Case 2 — `$TMUX_PANE` fallback when `--pane` omitted**

Insert before `printf '\nALL TESTS PASSED\n'`:

```bash
# --- Case 2: $TMUX_PANE fallback ---
reset_state
TMUX_PANE=%9 assert_exit_zero "TMUX_PANE fallback exits 0" run_primitive my-src "fallback msg"
assert_grep "$tmux_log" "set-option -pq -t %9 @pane-last-error" "uses TMUX_PANE when --pane omitted"
```

- [ ] **Step 7: Run the test, expect PASS** (the implementation already supports this via the `TMUX_PANE` env-var default)

Run: `roles/common/files/bin/report-pane-error.test`
Expected: PASS through Case 2.

- [ ] **Step 8: Add Case 3 — no pane info → log only, no tmux call**

Insert before `printf '\nALL TESTS PASSED\n'`:

```bash
# --- Case 3: no pane info → log only, no tmux call ---
reset_state
assert_exit_zero "no-pane call exits 0" env -u TMUX_PANE run_primitive my-src "no pane msg"
assert_grep "$log_file" "pane=none" "log records pane=none"
assert_grep "$log_file" "no pane msg" "log records message"
assert_no_grep "$tmux_log" "set-option" "no tmux set-option without pane info"
```

Note: `env -u TMUX_PANE run_primitive ...` — `env -u` strips the variable so the helper sees no pane.

- [ ] **Step 9: Run the test, expect PASS**

Run: `roles/common/files/bin/report-pane-error.test`
Expected: PASS through Case 3.

- [ ] **Step 10: Add Case 4 — stdin path (multi-line message)**

Insert before `printf '\nALL TESTS PASSED\n'`:

```bash
# --- Case 4: message from stdin (multi-line) ---
reset_state
multiline="first line of stderr
second line should be in log only"
assert_exit_zero "stdin call exits 0" bash -c "
  printf '%s\n' '$multiline' | \
    PATH='$bindir:/usr/bin:/bin' \
    HOME='$TMPROOT' \
    REPORT_PANE_ERROR_TEST_TMUX_LOG='$tmux_log' \
    TMUX_PANE='%17' \
    '$SCRIPT' my-src
"
assert_grep "$log_file" "first line of stderr" "log includes first line"
assert_grep "$log_file" "second line should be in log only" "log includes second line"
assert_grep "$tmux_log" "my-src: first line of stderr" "badge uses only first line"
assert_no_grep "$tmux_log" "second line should be in log only" "badge omits subsequent lines"
```

- [ ] **Step 11: Run the test, expect PASS**

Run: `roles/common/files/bin/report-pane-error.test`
Expected: PASS through Case 4.

- [ ] **Step 12: Add Case 5 — badge truncates to ≤60 chars**

Insert before `printf '\nALL TESTS PASSED\n'`:

```bash
# --- Case 5: long message truncates badge to <=60 chars ---
reset_state
long_msg="abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_extra"
assert_exit_zero "long-message call exits 0" run_primitive my-src "$long_msg" --pane %1
short_line="$(grep -F 'set-option -pq -t %1 @pane-last-error' "$tmux_log" | tail -n1)"
if [ -z "$short_line" ]; then
  printf 'FAIL  truncation: no set-option call found\n' >&2
  exit 1
fi
short_value="${short_line#*@pane-last-error }"
short_value="${short_value#\"}"
short_value="${short_value%\"}"
if [ "${#short_value}" -le 60 ]; then
  printf 'PASS  truncated badge is %d chars (<=60)\n' "${#short_value}"
else
  printf 'FAIL  truncated badge is %d chars: %q\n' "${#short_value}" "$short_value" >&2
  exit 1
fi
assert_grep "$log_file" "$long_msg" "full long message present in log"
```

- [ ] **Step 13: Run the test, expect PASS**

Run: `roles/common/files/bin/report-pane-error.test`
Expected: PASS through Case 5.

- [ ] **Step 14: Add Case 6 — `tmux` binary missing → still exits 0, log still written**

Insert before `printf '\nALL TESTS PASSED\n'`:

```bash
# --- Case 6: missing tmux still logs and exits 0 ---
reset_state
# Make tmux fail-not-found by overriding PATH for this call only.
no_tmux_dir="$TMPROOT/no-tmux"; mkdir -p "$no_tmux_dir"
cp "$bindir/date" "$no_tmux_dir/date"
PATH="$no_tmux_dir:/usr/bin:/bin" \
HOME="$TMPROOT" \
REPORT_PANE_ERROR_TEST_TMUX_LOG="$tmux_log" \
"$SCRIPT" my-src "msg without tmux" --pane %3 \
  && printf 'PASS  exits 0 with no tmux on PATH\n' \
  || { printf 'FAIL  expected exit 0 with no tmux\n' >&2; exit 1; }
assert_grep "$log_file" "msg without tmux" "log entry written even without tmux"
assert_no_grep "$tmux_log" "set-option" "stub tmux not called when not on PATH"
```

- [ ] **Step 15: Run the test, expect PASS**

Run: `roles/common/files/bin/report-pane-error.test`
Expected: All six cases PASS, ending with `ALL TESTS PASSED`.

- [ ] **Step 16: Commit**

```bash
git add roles/common/files/bin/report-pane-error roles/common/files/bin/report-pane-error.test
git commit -m "Add report-pane-error primitive with TDD coverage"
```

---

## Task 2: Migrate `tmux-hook-run` to delegate to `report-pane-error`

**Files:**
- Modify: `roles/common/files/bin/tmux-hook-run`
- Modify: `roles/common/files/bin/tmux-hook-run.test`

- [ ] **Step 1: Update `tmux-hook-run.test` to expect delegation**

The current test stubs `tmux` and asserts on `set-option -gq @hook-last-error`. Rewrite it to:
- Stub `report-pane-error` on PATH
- Drop the `tmux` stub from this test (the wrapper no longer calls `tmux` directly)
- Assert that `report-pane-error` was invoked with the right name + first-line stderr + `--pane $TMUX_HOOK_PANE_ID`

Replace the contents of `roles/common/files/bin/tmux-hook-run.test` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/tmux-hook-run"

if [ ! -x "$SCRIPT" ]; then
  printf 'ERROR: %s is not executable (or does not exist)\n' "$SCRIPT" >&2
  exit 2
fi

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

bindir="$TMPROOT/bin"
mkdir -p "$bindir"
report_log="$TMPROOT/report.log"

# Stub report-pane-error: record argv, succeed.
cat > "$bindir/report-pane-error" <<'EOR'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$REPORT_LOG"
exit 0
EOR
chmod +x "$bindir/report-pane-error"

assert_exit_zero() {
  local label="$1"; shift
  if "$@"; then
    printf 'PASS  %s\n' "$label"
  else
    printf 'FAIL  %s (exit %d)\n' "$label" "$?" >&2
    exit 1
  fi
}

assert_file_empty() {
  local file="$1" label="$2"
  if [ ! -s "$file" ]; then
    printf 'PASS  %s\n' "$label"
  else
    printf 'FAIL  %s\nfile %s should be empty but contains:\n' "$label" "$file" >&2
    cat "$file" >&2
    exit 1
  fi
}

assert_grep() {
  local file="$1" pattern="$2" label="$3"
  if grep -Fq -- "$pattern" "$file"; then
    printf 'PASS  %s\n' "$label"
  else
    printf 'FAIL  %s\nmissing %q in %s:\n' "$label" "$pattern" "$file" >&2
    cat "$file" >&2
    exit 1
  fi
}

run_wrapper() {
  PATH="$bindir:/usr/bin:/bin" \
  HOME="$TMPROOT" \
  REPORT_LOG="$report_log" \
  "$SCRIPT" "$@"
}

reset_state() { : > "$report_log"; }

# --- Case 1: passing wrapped command → no delegation ---
reset_state
cat > "$bindir/successful" <<'EOC'
#!/usr/bin/env bash
exit 0
EOC
chmod +x "$bindir/successful"
assert_exit_zero "passing command exits 0" run_wrapper successful arg1
assert_file_empty "$report_log" "passing command does not call report-pane-error"

# --- Case 2: failing wrapped command → delegates with first-line stderr ---
reset_state
cat > "$bindir/noisy_fail" <<'EOC'
#!/usr/bin/env bash
echo "boom: something broke" >&2
echo "second line" >&2
exit 7
EOC
chmod +x "$bindir/noisy_fail"
TMUX_HOOK_PANE_ID=%53 assert_exit_zero "failing command still exits 0" run_wrapper noisy_fail %53
assert_grep "$report_log" "noisy_fail" "delegate gets command basename as name"
assert_grep "$report_log" "boom: something broke" "delegate gets first stderr line as message"
assert_grep "$report_log" "--pane %53" "delegate gets pane via TMUX_HOOK_PANE_ID"

# --- Case 3: failing command with no stderr → delegates with synthetic message ---
reset_state
cat > "$bindir/silent_fail" <<'EOC'
#!/usr/bin/env bash
exit 3
EOC
chmod +x "$bindir/silent_fail"
TMUX_HOOK_PANE_ID=%1 assert_exit_zero "silent failing command still exits 0" run_wrapper silent_fail
assert_grep "$report_log" "silent_fail" "silent failure delegates"
assert_grep "$report_log" "exit 3" "silent failure includes exit-3 fallback"

# --- Case 4: TMUX_HOOK_PANE_ID unset → delegate called without --pane ---
reset_state
env -u TMUX_HOOK_PANE_ID assert_exit_zero "no pane id still exits 0" run_wrapper noisy_fail
assert_grep "$report_log" "noisy_fail" "delegate still invoked"
if grep -Fq -- "--pane" "$report_log"; then
  printf 'FAIL  --pane unexpectedly forwarded when TMUX_HOOK_PANE_ID unset\n' >&2
  exit 1
else
  printf 'PASS  --pane omitted when TMUX_HOOK_PANE_ID unset\n'
fi

# --- Case 5: missing wrapped command → delegates ---
reset_state
TMUX_HOOK_PANE_ID=%4 assert_exit_zero "missing command exits 0" run_wrapper this-does-not-exist
assert_grep "$report_log" "this-does-not-exist" "missing command name appears in delegate args"

# --- Case 6: no args → no-op ---
reset_state
assert_exit_zero "no-args invocation exits 0" run_wrapper
assert_file_empty "$report_log" "no-args does not call report-pane-error"

printf '\nALL TESTS PASSED\n'
```

- [ ] **Step 2: Run the updated test, expect FAIL because the wrapper still calls tmux directly**

Run: `roles/common/files/bin/tmux-hook-run.test`
Expected: FAIL (no `--pane`/`report-pane-error` in `report.log`).

- [ ] **Step 3: Rewrite `tmux-hook-run` to delegate**

Replace the contents of `roles/common/files/bin/tmux-hook-run` with:

```bash
#!/usr/bin/env bash
# Hook wrapper: runs a command, swallows failure (always exits 0), and on
# failure delegates to `report-pane-error` to write the failure log and set
# the per-pane @pane-last-error option (when TMUX_HOOK_PANE_ID is set).
set -u

if [ $# -lt 1 ]; then
  exit 0
fi

err="$("$@" 2>&1 1>/dev/null)" || rc=$?
rc="${rc:-0}"

if [ "$rc" -eq 0 ]; then
  exit 0
fi

base="${1##*/}"
first_line="${err%%[$'\r\n']*}"
if [ -n "$first_line" ]; then
  msg="$first_line"
else
  msg="exit $rc"
fi

args=("$base" "$msg")
if [ -n "${TMUX_HOOK_PANE_ID:-}" ]; then
  args+=(--pane "$TMUX_HOOK_PANE_ID")
fi

if [ -n "$err" ]; then
  printf '%s\n' "$err" | report-pane-error "${args[@]}" || true
else
  report-pane-error "${args[@]}" || true
fi

exit 0
```

- [ ] **Step 4: Run the updated test, expect PASS**

Run: `roles/common/files/bin/tmux-hook-run.test`
Expected: All six cases PASS.

- [ ] **Step 5: Commit**

```bash
git add roles/common/files/bin/tmux-hook-run roles/common/files/bin/tmux-hook-run.test
git commit -m "Migrate tmux-hook-run to delegate to report-pane-error"
```

---

## Task 3: Update `tmux-window-bar-config.test` for the new shape

**Files:**
- Modify: `roles/common/files/bin/tmux-window-bar-config.test`

- [ ] **Step 1: Replace stale assertions and add new ones**

In `roles/common/files/bin/tmux-window-bar-config.test`, inside `assert_tmux_file()`:

Remove these lines:
```bash
assert_contains "$file" '@hook-last-error'
assert_contains "$file" 'bind h display-popup -E -h 80% -w 80% "less +G ~/.local/state/tmux/hooks.log"'
assert_contains "$file" 'set-option -gq @hook-last-error ""'
assert_contains "$file" "set -g pane-border-format '#{?pane_active,#[bg=black#,fg=colour51],#[bg=black#,fg=colour240]} #(~/.local/bin/tmux-pane-label \"#{pane_tty}\" \"#{pane_current_path}\" \"#{pane_current_command}\" \"#{pane_id}\") '"
assert_contains "$file" 'tmux-hook-run tmux-sync-pane-border-status #{pane_id}'
assert_contains "$file" 'tmux-hook-run tmux-sync-remote-title #{pane_id}'
assert_contains "$file" 'tmux-hook-run tmux-window-label #{pane_id}'
assert_contains "$file" 'tmux-hook-run tmux-sync-status-visibility #{pane_id}'
assert_contains "$file" 'tmux-hook-run tmux-remote-title publish'
```

Add these lines:
```bash
# Pane-border-format: same label content + per-pane error sigil at the end.
assert_contains "$file" "set -g pane-border-format '#{?pane_active,#[bg=black#,fg=colour51],#[bg=black#,fg=colour240]} #(~/.local/bin/tmux-pane-label \"#{pane_tty}\" \"#{pane_current_path}\" \"#{pane_current_command}\" \"#{pane_id}\")#{?#{@pane-last-error}, #[bg=colour196#,fg=white#,bold] ! #[default],} '"

# Per-pane option name; old global option must be gone.
assert_contains "$file" '@pane-last-error'
assert_not_contains "$file" '@hook-last-error'

# Hook invocations carry pane id via env var so the wrapper can flag the right pane.
assert_contains "$file" 'TMUX_HOOK_PANE_ID=#{pane_id} $HOME/.local/bin/tmux-hook-run tmux-sync-pane-border-status #{pane_id}'
assert_contains "$file" 'TMUX_HOOK_PANE_ID=#{pane_id} $HOME/.local/bin/tmux-hook-run tmux-sync-remote-title #{pane_id}'
assert_contains "$file" 'TMUX_HOOK_PANE_ID=#{pane_id} $HOME/.local/bin/tmux-hook-run tmux-window-label #{pane_id}'
assert_contains "$file" 'TMUX_HOOK_PANE_ID=#{pane_id} $HOME/.local/bin/tmux-hook-run tmux-sync-status-visibility #{pane_id}'
assert_contains "$file" 'TMUX_HOOK_PANE_ID=#{pane_id} $HOME/.local/bin/tmux-hook-run tmux-remote-title publish'

# New keybind/log path; old log path forbidden.
assert_contains "$file" 'bind h display-popup -E -h 80% -w 80% "less +G ~/.local/state/failures.log"'
assert_contains "$file" 'set-option -pqu @pane-last-error'
assert_not_contains "$file" '~/.local/state/tmux/hooks.log'
assert_not_contains "$file" 'set-option -gq @hook-last-error ""'
```

- [ ] **Step 2: Run the test, expect FAIL (config files still hold the old shape)**

Run: `roles/common/files/bin/tmux-window-bar-config.test`
Expected: many `FAIL` lines complaining about missing/unexpected strings in `roles/macos/templates/dotfiles/tmux.conf` and `roles/linux/files/dotfiles/tmux.conf`.

- [ ] **Step 3: Commit (red test that will go green in Tasks 4 + 5)**

```bash
git add roles/common/files/bin/tmux-window-bar-config.test
git commit -m "Update tmux-window-bar-config.test for pane-scoped error reporting"
```

---

## Task 4: Update `roles/macos/templates/dotfiles/tmux.conf`

**Files:**
- Modify: `roles/macos/templates/dotfiles/tmux.conf`

- [ ] **Step 1: Replace the hook comment + three set-hook lines**

Around line 20, replace:

```
# Keep remote-title and window labels in sync without renaming sessions.
# tmux-hook-run logs each failure to ~/.local/state/tmux/hooks.log and updates
# @hook-last-error so the status bar surfaces the most recent failure. The
# wrapper always exits 0 — tmux never sees a failed hook.
set-hook -g pane-focus-in 'run-shell -b "$HOME/.local/bin/tmux-hook-run tmux-remote-title publish"; run-shell -b "$HOME/.local/bin/tmux-hook-run tmux-window-label #{pane_id}"; run-shell -b "$HOME/.local/bin/tmux-hook-run tmux-sync-status-visibility #{pane_id}"; run-shell -b "$HOME/.local/bin/tmux-hook-run tmux-sync-pane-border-status #{pane_id}"'
set-hook -g client-session-changed 'run-shell -b "$HOME/.local/bin/tmux-hook-run tmux-remote-title publish"; run-shell -b "$HOME/.local/bin/tmux-hook-run tmux-window-label #{pane_id}"; run-shell -b "$HOME/.local/bin/tmux-hook-run tmux-sync-status-visibility #{pane_id}"; run-shell -b "$HOME/.local/bin/tmux-hook-run tmux-sync-pane-border-status #{pane_id}"'
set-hook -g pane-title-changed 'run-shell -b "$HOME/.local/bin/tmux-hook-run tmux-sync-remote-title #{pane_id}"; run-shell -b "$HOME/.local/bin/tmux-hook-run tmux-sync-pane-border-status #{pane_id}"'
```

with:

```
# Keep remote-title and window labels in sync without renaming sessions.
# tmux-hook-run logs each failure to ~/.local/state/failures.log and (via
# report-pane-error) sets @pane-last-error on the originating pane so the
# status indicator surfaces the most recent failure. The wrapper always
# exits 0 — tmux never sees a failed hook.
set-hook -g pane-focus-in 'run-shell -b "TMUX_HOOK_PANE_ID=#{pane_id} $HOME/.local/bin/tmux-hook-run tmux-remote-title publish"; run-shell -b "TMUX_HOOK_PANE_ID=#{pane_id} $HOME/.local/bin/tmux-hook-run tmux-window-label #{pane_id}"; run-shell -b "TMUX_HOOK_PANE_ID=#{pane_id} $HOME/.local/bin/tmux-hook-run tmux-sync-status-visibility #{pane_id}"; run-shell -b "TMUX_HOOK_PANE_ID=#{pane_id} $HOME/.local/bin/tmux-hook-run tmux-sync-pane-border-status #{pane_id}"'
set-hook -g client-session-changed 'run-shell -b "TMUX_HOOK_PANE_ID=#{pane_id} $HOME/.local/bin/tmux-hook-run tmux-remote-title publish"; run-shell -b "TMUX_HOOK_PANE_ID=#{pane_id} $HOME/.local/bin/tmux-hook-run tmux-window-label #{pane_id}"; run-shell -b "TMUX_HOOK_PANE_ID=#{pane_id} $HOME/.local/bin/tmux-hook-run tmux-sync-status-visibility #{pane_id}"; run-shell -b "TMUX_HOOK_PANE_ID=#{pane_id} $HOME/.local/bin/tmux-hook-run tmux-sync-pane-border-status #{pane_id}"'
set-hook -g pane-title-changed 'run-shell -b "TMUX_HOOK_PANE_ID=#{pane_id} $HOME/.local/bin/tmux-hook-run tmux-sync-remote-title #{pane_id}"; run-shell -b "TMUX_HOOK_PANE_ID=#{pane_id} $HOME/.local/bin/tmux-hook-run tmux-sync-pane-border-status #{pane_id}"'
```

- [ ] **Step 2: Replace the prefix+h binding**

Around line 81, replace:

```
# Hook-failure indicator: prefix + h opens the log and clears the badge.
bind h display-popup -E -h 80% -w 80% "less +G ~/.local/state/tmux/hooks.log" \; set-option -gq @hook-last-error ""
```

with:

```
# Pane error indicator: prefix + h opens the log and clears the badge on the active pane.
bind h display-popup -E -h 80% -w 80% "less +G ~/.local/state/failures.log" \; set-option -pqu @pane-last-error
```

- [ ] **Step 3: Replace `status-right`**

Around line 96, replace:

```
set -g status-right '#{?@hook-last-error, #[bg=colour196#,fg=white#,bold] ! #{@hook-last-error} #[default],}'
```

with:

```
set -g status-right '#{?#{@pane-last-error}, #[bg=colour196#,fg=white#,bold] ! #{@pane-last-error} #[default],}'
```

- [ ] **Step 4: Append per-pane sigil to `pane-border-format`**

Around line 113, replace:

```
set -g pane-border-format '#{?pane_active,#[bg=black#,fg=colour51],#[bg=black#,fg=colour240]} #(~/.local/bin/tmux-pane-label "#{pane_tty}" "#{pane_current_path}" "#{pane_current_command}" "#{pane_id}") '
```

with:

```
set -g pane-border-format '#{?pane_active,#[bg=black#,fg=colour51],#[bg=black#,fg=colour240]} #(~/.local/bin/tmux-pane-label "#{pane_tty}" "#{pane_current_path}" "#{pane_current_command}" "#{pane_id}")#{?#{@pane-last-error}, #[bg=colour196#,fg=white#,bold] ! #[default],} '
```

- [ ] **Step 5: Run `tmux-window-bar-config.test`, expect macOS PASSes (Linux still FAILing)**

Run: `roles/common/files/bin/tmux-window-bar-config.test`
Expected: PASS for macOS-template assertions, FAIL for the Linux-file ones.

- [ ] **Step 6: Commit**

```bash
git add roles/macos/templates/dotfiles/tmux.conf
git commit -m "Pane-scope tmux error indicator in macOS tmux.conf template"
```

---

## Task 5: Update `roles/linux/files/dotfiles/tmux.conf`

**Files:**
- Modify: `roles/linux/files/dotfiles/tmux.conf`

- [ ] **Step 1: Apply the same four edits as Task 4**

Repeat Steps 1-4 from Task 4 against `roles/linux/files/dotfiles/tmux.conf`. The strings are identical.

- [ ] **Step 2: Run `tmux-window-bar-config.test`, expect PASS for both files**

Run: `roles/common/files/bin/tmux-window-bar-config.test`
Expected: ALL `PASS`, ending with `passed=N failed=0`.

- [ ] **Step 3: Commit**

```bash
git add roles/linux/files/dotfiles/tmux.conf
git commit -m "Pane-scope tmux error indicator in Linux tmux.conf"
```

---

## Task 6: Install `report-pane-error` via Ansible + rename state dir task

**Files:**
- Modify: `roles/common/tasks/main.yml`

- [ ] **Step 1: Add `report-pane-error` to the `tmux label helpers` install loop**

Around line 251, in the loop at line 257-264, add `report-pane-error`:

```yaml
- name: Install tmux label helpers
  copy:
    backup: yes
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin/{{ item }}'
    src: '{{ playbook_dir }}/roles/common/files/bin/{{ item }}'
    mode: 0755
  loop:
    - tmux-devpod-name
    - tmux-label-format
    - tmux-pane-label
    - tmux-window-label
    - tmux-sync-status-visibility
    - tmux-sync-pane-border-status
    - tmux-hook-run
    - report-pane-error
```

- [ ] **Step 2: Generalize the state-directory task**

Around line 245, replace:

```yaml
- name: Create tmux state directory for hook logs
  file:
    path: '{{ ansible_facts["user_dir"] }}/.local/state/tmux'
    state: directory
    mode: 0755
```

with:

```yaml
- name: Create local state directory for failure logs
  file:
    path: '{{ ansible_facts["user_dir"] }}/.local/state'
    state: directory
    mode: 0755
```

- [ ] **Step 3: Run `--syntax-check` to confirm YAML is valid**

Run: `cd roles/common && ansible-playbook ../../playbook.yml --syntax-check 2>&1 | head -20` from the repo root, or:

Run: `python3 -c "import yaml; yaml.safe_load(open('roles/common/tasks/main.yml'))" && echo OK`
Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
git add roles/common/tasks/main.yml
git commit -m "Install report-pane-error and broaden state dir task"
```

---

## Task 7: Verify end-to-end

**Files:** none modified — verification only.

- [ ] **Step 1: Run all changed bash tests**

Run from repo root:
```bash
roles/common/files/bin/report-pane-error.test
roles/common/files/bin/tmux-hook-run.test
roles/common/files/bin/tmux-window-bar-config.test
```
Expected: each prints `ALL TESTS PASSED` (or `passed=N failed=0`).

- [ ] **Step 2: Provision in check mode**

Run: `bin/provision --check --diff 2>&1 | tail -60`
Expected: clean run; the diff for `roles/common/tasks/main.yml` shows `report-pane-error` being installed and the renamed state-directory task; tmux.conf templates show the new format strings.

- [ ] **Step 3: Manual smoke test (after applying)**

Apply: `bin/provision`
Then in a fresh tmux pane:
```bash
~/.local/bin/report-pane-error test "synthetic failure"
tmux show-options -p @pane-last-error
cat ~/.local/state/failures.log
```
Expected:
- `tmux show-options` reports `@pane-last-error "test: synthetic failure"`.
- `failures.log` contains a record with `name=test`, `message: synthetic failure`, `pane=$TMUX_PANE`.
- The status-right and pane border show the red `!` badge.
- `prefix + h` opens the log; on quitting `less`, the badge clears on that pane only.

- [ ] **Step 4: No commit needed**

Verification produces no source changes.
