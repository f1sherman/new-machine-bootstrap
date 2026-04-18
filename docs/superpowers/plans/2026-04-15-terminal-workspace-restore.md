# Terminal Workspace Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make macOS Ghostty restart into the same practical tmux-backed workspace, and keep Linux dev-host tmux session growth bounded without adding a manual workflow.

**Architecture:** Put tmux session selection and stale-session cleanup in shared Bash helpers under `roles/common/files/bin/`. Keep Ghostty-specific save/reconcile logic in macOS-only helpers under `roles/macos/files/bin/`, with a lightweight LaunchAgent for periodic layout snapshots and the existing `tmux-attach-or-new` wrapper triggering one reconcile pass after login or reboot. Linux dev hosts reuse the shared attach helper and piggyback stale-session GC on tmux's `client-attached` hook instead of adding a separate timer service.

**Tech Stack:** Bash, `jq`, `tmux`, `osascript`/AppleScript, Ansible, launchd plist templates, repo-local shell test harnesses.

---

## File Structure

- `roles/common/files/bin/tmux-restore-lib.sh`
  Responsibility: shared state-path helpers, boot-marker helpers, session-key normalization, and tiny utilities reused by restore and cleanup scripts.
- `roles/common/files/bin/tmux-restore-client`
  Responsibility: attach to an explicit tmux session when requested, otherwise attach to the first unattached session, otherwise create a new session.
- `roles/common/files/bin/tmux-restore-client.test`
  Responsibility: TDD harness for explicit attach, unattached-session attach, and new-session fallback.
- `roles/common/files/bin/tmux-session-gc`
  Responsibility: prune macOS restore leftovers immediately from a saved Ghostty manifest, and prune Linux sessions only after they have been unattached for more than 14 days.
- `roles/common/files/bin/tmux-session-gc.test`
  Responsibility: TDD harness for Linux `unattached_since` tracking and macOS manifest-based pruning.
- `roles/common/files/bin/tmux-client-attached`
  Responsibility: keep the tmux global `PATH` in sync with the attaching shell and opportunistically run Linux stale-session GC after a client attaches.
- `roles/common/files/bin/tmux-client-attached.test`
  Responsibility: verify the hook helper updates `PATH` and invokes Linux GC only on Linux.
- `roles/common/files/bin/terminal-restore-config.test`
  Responsibility: text-level regression test for provisioning and config wiring across tmux, macOS Ghostty config, and Linux dev-host login config.
- `roles/common/tasks/main.yml`
  Responsibility: install the new shared restore helpers into `~/.local/bin`.
- `roles/macos/files/bin/ghostty-layout-save`
  Responsibility: snapshot current Ghostty windows and tabs into `~/.local/state/terminal-restore/ghostty-layout.json`, preserving a last-good copy.
- `roles/macos/files/bin/ghostty-layout-save.test`
  Responsibility: verify snapshot JSON shape, session-name capture, and last-good preservation on malformed AppleScript output.
- `roles/macos/files/bin/ghostty-layout-reconcile`
  Responsibility: wait for Ghostty and tmux restore to settle, retarget restored tabs to the saved tmux sessions, restore focus, and trigger macOS cleanup.
- `roles/macos/files/bin/ghostty-layout-reconcile.test`
  Responsibility: verify reconcile command sequencing, one-shot locking, focus restore, and macOS cleanup invocation with mocked `osascript`.
- `roles/macos/files/bin/tmux-attach-or-new`
  Responsibility: keep ad hoc Ghostty behavior unchanged while asynchronously triggering one reconcile pass when a saved layout from before the current boot exists.
- `roles/macos/files/bin/tmux-attach-or-new.test`
  Responsibility: verify reconcile trigger conditions and fallback to the shared attach helper.
- `roles/macos/templates/launchd/com.user.ghostty-layout-save.plist`
  Responsibility: schedule periodic Ghostty layout snapshots on macOS.
- `roles/macos/tasks/main.yml`
  Responsibility: install the macOS helpers and LaunchAgent, enable Ghostty AppleScript explicitly, and keep Ghostty using the existing wrapper command.
- `roles/macos/templates/dotfiles/tmux.conf`
  Responsibility: run the shared `client-attached` hook helper and shorten continuum save cadence for fresher restores.
- `roles/linux/files/dotfiles/tmux.conf`
  Responsibility: mirror the shared `client-attached` hook helper and shorter continuum save cadence on Linux hosts.
- `roles/dev_host/tasks/main.yml`
  Responsibility: switch dev-host login auto-attach from inline shell logic to the shared `tmux-restore-client` helper.

## Task 1: Add the shared tmux attach helper

**Files:**
- Create: `roles/common/files/bin/tmux-restore-lib.sh`
- Create: `roles/common/files/bin/tmux-restore-client`
- Create: `roles/common/files/bin/tmux-restore-client.test`
- Test: `roles/common/files/bin/tmux-restore-client.test`

- [ ] **Step 1: Write the failing attach-helper test**

```bash
#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/tmux-restore-client"

if [ ! -x "$SCRIPT" ]; then
  printf 'ERROR: %s is not executable (or does not exist)\n' "$SCRIPT" >&2
  exit 2
fi

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

pass=0
fail=0

run_case() {
  local name="$1" explicit="$2" list_output="$3" has_target="$4" expected_log="$5"
  local bindir log actual rc

  bindir="$(mktemp -d "$TMPROOT/bin.XXXXXX")"
  log="$(mktemp "$TMPROOT/tmux.XXXXXX")"

  cat > "$bindir/tmux" <<'EOF'
#!/usr/bin/env bash
set -eu

printf '%s\n' "$*" >> "$TMUX_RESTORE_CLIENT_LOG"

case "${1:-}" in
  has-session)
    [ "${3:-}" = "$TMUX_RESTORE_CLIENT_HAS_TARGET" ]
    ;;
  list-sessions)
    printf '%s\n' "$TMUX_RESTORE_CLIENT_LIST"
    ;;
  attach)
    exit 0
    ;;
  new-session)
    exit 0
    ;;
  *)
    printf 'unexpected tmux invocation: %s\n' "$*" >&2
    exit 99
    ;;
esac
EOF
  chmod +x "$bindir/tmux"

  if [ -n "$explicit" ]; then
    if actual=$(
      PATH="$bindir:$PATH" \
      TMUX_RESTORE_CLIENT_LOG="$log" \
      TMUX_RESTORE_CLIENT_LIST="$list_output" \
      TMUX_RESTORE_CLIENT_HAS_TARGET="$has_target" \
      "$SCRIPT" --session "$explicit"
    ); then
      rc=0
    else
      rc=$?
    fi
  else
    if actual=$(
      PATH="$bindir:$PATH" \
      TMUX_RESTORE_CLIENT_LOG="$log" \
      TMUX_RESTORE_CLIENT_LIST="$list_output" \
      TMUX_RESTORE_CLIENT_HAS_TARGET="$has_target" \
      "$SCRIPT"
    ); then
      rc=0
    else
      rc=$?
    fi
  fi

  if [ "$rc" -eq 0 ] && grep -Fqx "$expected_log" "$log"; then
    pass=$((pass + 1))
    printf 'PASS  %s\n' "$name"
  else
    fail=$((fail + 1))
    printf 'FAIL  %s\n' "$name"
    printf '      rc: %s\n' "$rc"
    printf '      log:\n'
    sed 's/^/        /' "$log"
  fi
}

run_case \
  "explicit session wins" \
  "focus" \
  $'1\tother\n0\tfocus' \
  "=focus" \
  "attach -t =focus"

run_case \
  "first unattached session is reused" \
  "" \
  $'1\tbusy\n0\talpha\n0\tbeta' \
  "" \
  "attach -t =alpha"

run_case \
  "new session when nothing is reusable" \
  "" \
  "" \
  "" \
  "new-session"

printf '\n'
printf 'passed=%s failed=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the attach-helper test to confirm it fails**

Run: `bash roles/common/files/bin/tmux-restore-client.test`
Expected: FAIL because `tmux-restore-client` and `tmux-restore-lib.sh` do not exist yet.

- [ ] **Step 3: Implement the shared attach helper**

Create `roles/common/files/bin/tmux-restore-lib.sh`:

```bash
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
```

Create `roles/common/files/bin/tmux-restore-client`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./tmux-restore-lib.sh
source "$SCRIPT_DIR/tmux-restore-lib.sh"

requested_session=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --session)
      requested_session="${2:-}"
      shift 2
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

if [ -n "$requested_session" ] && tmux has-session -t "=$requested_session" 2>/dev/null; then
  exec tmux attach -t "=$requested_session"
fi

if tmux list-sessions >/dev/null 2>&1; then
  reusable_session="$(
    tmux list-sessions -F '#{session_attached}\t#{session_name}' 2>/dev/null | \
      awk -F '\t' '$1 == "0" { print $2; exit }'
  )"
  if [ -n "$reusable_session" ]; then
    exec tmux attach -t "=$reusable_session"
  fi
fi

exec tmux new-session
```

- [ ] **Step 4: Run the attach-helper test to verify it passes**

Run: `bash roles/common/files/bin/tmux-restore-client.test`
Expected: PASS with explicit attach, unattached attach, and new-session fallback cases.

- [ ] **Step 5: Commit the attach-helper task**

Run:

```bash
git add \
  roles/common/files/bin/tmux-restore-lib.sh \
  roles/common/files/bin/tmux-restore-client \
  roles/common/files/bin/tmux-restore-client.test
git commit -m "Add shared tmux restore client helper"
```

Expected: one commit containing only the shared attach helper and its test.

## Task 2: Add stale-session GC and the tmux `client-attached` hook helper

**Files:**
- Create: `roles/common/files/bin/tmux-session-gc`
- Create: `roles/common/files/bin/tmux-session-gc.test`
- Create: `roles/common/files/bin/tmux-client-attached`
- Create: `roles/common/files/bin/tmux-client-attached.test`
- Test: `roles/common/files/bin/tmux-session-gc.test`
- Test: `roles/common/files/bin/tmux-client-attached.test`

- [ ] **Step 1: Write the failing GC and hook-helper tests**

Create `roles/common/files/bin/tmux-session-gc.test`:

```bash
#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/tmux-session-gc"

if [ ! -x "$SCRIPT" ]; then
  printf 'ERROR: %s is not executable (or does not exist)\n' "$SCRIPT" >&2
  exit 2
fi

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

make_tmux() {
  local bindir="$1"
  cat > "$bindir/tmux" <<'EOF'
#!/usr/bin/env bash
set -eu

printf '%s\n' "$*" >> "$TMUX_SESSION_GC_LOG"

case "${1:-}" in
  list-sessions)
    printf '%s\n' "$TMUX_SESSION_GC_LIST"
    ;;
  kill-session)
    exit 0
    ;;
  *)
    printf 'unexpected tmux invocation: %s\n' "$*" >&2
    exit 99
    ;;
esac
EOF
  chmod +x "$bindir/tmux"
}

linux_home="$TMPROOT/linux-home"
mkdir -p "$linux_home"
bindir="$(mktemp -d "$TMPROOT/bin.XXXXXX")"
log="$(mktemp "$TMPROOT/tmux.XXXXXX")"
make_tmux "$bindir"

mkdir -p "$linux_home/.local/state/terminal-restore/sessions"
printf '%s' "$(( $(date +%s) - 15 * 24 * 60 * 60 ))" > \
  "$linux_home/.local/state/terminal-restore/sessions/stale.unattached_since"

PATH="$bindir:$PATH" \
HOME="$linux_home" \
TMUX_SESSION_GC_LOG="$log" \
TMUX_SESSION_GC_LIST=$'stale\t0\nfresh\t0\nattached\t1' \
"$SCRIPT" --platform linux --days 14

grep -Fqx 'kill-session -t =stale' "$log"
[ -f "$linux_home/.local/state/terminal-restore/sessions/fresh.unattached_since" ]
[ ! -f "$linux_home/.local/state/terminal-restore/sessions/attached.unattached_since" ]

mac_home="$TMPROOT/mac-home"
mkdir -p "$mac_home/.local/state/terminal-restore"
cat > "$mac_home/.local/state/terminal-restore/ghostty-layout.json" <<'EOF'
{"windows":[{"tabs":[{"session_name":"keep-me"}]}]}
EOF

log2="$(mktemp "$TMPROOT/tmux-mac.XXXXXX")"
PATH="$bindir:$PATH" \
HOME="$mac_home" \
TMUX_SESSION_GC_LOG="$log2" \
TMUX_SESSION_GC_LIST=$'keep-me\t0\nremove-me\t0\nattached\t1' \
"$SCRIPT" --platform macos --manifest "$mac_home/.local/state/terminal-restore/ghostty-layout.json"

grep -Fqx 'kill-session -t =remove-me' "$log2"
! grep -Fq 'kill-session -t =keep-me' "$log2"
```

Create `roles/common/files/bin/tmux-client-attached.test`:

```bash
#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/tmux-client-attached"

if [ ! -x "$SCRIPT" ]; then
  printf 'ERROR: %s is not executable (or does not exist)\n' "$SCRIPT" >&2
  exit 2
fi

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

bindir="$(mktemp -d "$TMPROOT/bin.XXXXXX")"
log="$(mktemp "$TMPROOT/log.XXXXXX")"

cat > "$bindir/tmux" <<'EOF'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$TMUX_CLIENT_ATTACHED_LOG"
EOF
chmod +x "$bindir/tmux"

cat > "$bindir/uname" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${TMUX_CLIENT_ATTACHED_UNAME:-Linux}"
EOF
chmod +x "$bindir/uname"

mkdir -p "$TMPROOT/home/.local/bin"
cat > "$TMPROOT/home/.local/bin/tmux-session-gc" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TMUX_CLIENT_ATTACHED_GC_LOG"
EOF
chmod +x "$TMPROOT/home/.local/bin/tmux-session-gc"

PATH="$bindir:$PATH" \
HOME="$TMPROOT/home" \
TMUX_CLIENT_ATTACHED_LOG="$log" \
TMUX_CLIENT_ATTACHED_GC_LOG="$TMPROOT/gc.log" \
"$SCRIPT" '/usr/local/bin:/opt/homebrew/bin'

grep -Fqx 'set-environment -g PATH /usr/local/bin:/opt/homebrew/bin' "$log"
grep -Fqx '--platform linux --days 14' "$TMPROOT/gc.log"
```

- [ ] **Step 2: Run the GC and hook-helper tests to confirm they fail**

Run:

```bash
bash roles/common/files/bin/tmux-session-gc.test
bash roles/common/files/bin/tmux-client-attached.test
```

Expected: FAIL because the scripts do not exist yet.

- [ ] **Step 3: Implement stale-session GC and the tmux hook helper**

Create `roles/common/files/bin/tmux-session-gc`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./tmux-restore-lib.sh
source "$SCRIPT_DIR/tmux-restore-lib.sh"

platform=""
days=14
manifest_path=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --platform)
      platform="${2:-}"
      shift 2
      ;;
    --days)
      days="${2:-}"
      shift 2
      ;;
    --manifest)
      manifest_path="${2:-}"
      shift 2
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

[ -n "$platform" ] || exit 0
terminal_restore_ensure_dirs

now="$(date +%s)"
threshold="$(( days * 24 * 60 * 60 ))"
manifest_sessions=""

if [ -n "$manifest_path" ] && [ -f "$manifest_path" ]; then
  manifest_sessions="$(jq -r '.windows[]?.tabs[]?.session_name // empty' "$manifest_path" 2>/dev/null || true)"
fi

tmux list-sessions -F '#{session_name}\t#{session_attached}' 2>/dev/null | \
while IFS=$'\t' read -r session_name attached; do
  [ -n "$session_name" ] || continue
  marker_file="$(terminal_restore_sessions_dir)/$(terminal_restore_session_key "$session_name").unattached_since"

  if [ "$attached" != "0" ]; then
    rm -f "$marker_file"
    continue
  fi

  if [ "$platform" = "macos" ]; then
    if ! printf '%s\n' "$manifest_sessions" | grep -Fxq "$session_name"; then
      tmux kill-session -t "=$session_name"
    fi
    continue
  fi

  if [ ! -f "$marker_file" ]; then
    printf '%s' "$now" > "$marker_file"
    continue
  fi

  unattached_since="$(cat "$marker_file" 2>/dev/null || printf '0')"
  if [ $(( now - unattached_since )) -gt "$threshold" ]; then
    tmux kill-session -t "=$session_name"
    rm -f "$marker_file"
  fi
done
```

Create `roles/common/files/bin/tmux-client-attached`:

```bash
#!/usr/bin/env bash
set -euo pipefail

incoming_path="${1:-$PATH}"
tmux set-environment -g PATH "$incoming_path"

case "$(uname -s)" in
  Linux)
    "$HOME/.local/bin/tmux-session-gc" --platform linux --days 14 >/dev/null 2>&1 || true
    ;;
esac
```

- [ ] **Step 4: Run the GC and hook-helper tests to verify they pass**

Run:

```bash
bash roles/common/files/bin/tmux-session-gc.test
bash roles/common/files/bin/tmux-client-attached.test
```

Expected: PASS with Linux `unattached_since` behavior, macOS manifest pruning, and `client-attached` PATH propagation.

- [ ] **Step 5: Commit the GC and hook-helper task**

Run:

```bash
git add \
  roles/common/files/bin/tmux-session-gc \
  roles/common/files/bin/tmux-session-gc.test \
  roles/common/files/bin/tmux-client-attached \
  roles/common/files/bin/tmux-client-attached.test
git commit -m "Add tmux stale-session cleanup helpers"
```

Expected: one commit containing only the GC logic and the `client-attached` helper.

## Task 3: Add macOS Ghostty layout snapshots and the save LaunchAgent

**Files:**
- Create: `roles/macos/files/bin/ghostty-layout-save`
- Create: `roles/macos/files/bin/ghostty-layout-save.test`
- Create: `roles/macos/templates/launchd/com.user.ghostty-layout-save.plist`
- Test: `roles/macos/files/bin/ghostty-layout-save.test`

- [ ] **Step 1: Write the failing Ghostty layout save test**

```bash
#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/ghostty-layout-save"

if [ ! -x "$SCRIPT" ]; then
  printf 'ERROR: %s is not executable (or does not exist)\n' "$SCRIPT" >&2
  exit 2
fi

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

bindir="$(mktemp -d "$TMPROOT/bin.XXXXXX")"
home="$TMPROOT/home"
mkdir -p "$home"

cat > "$bindir/osascript" <<'EOF'
#!/usr/bin/env bash
body="$(cat)"
if printf '%s' "$body" | grep -q 'front window'; then
  printf '%s' "$GHOSTTY_LAYOUT_SAVE_FOCUSED_WINDOW"
else
  printf '%s' "$GHOSTTY_LAYOUT_SAVE_ROWS"
fi
EOF
chmod +x "$bindir/osascript"

PATH="$bindir:$PATH" \
HOME="$home" \
GHOSTTY_LAYOUT_SAVE_FOCUSED_WINDOW='2' \
GHOSTTY_LAYOUT_SAVE_ROWS=$'1\t1\t1\t(alpha)\t/Users/brian/projects/a\n1\t1\t2\t(beta)\t/Users/brian/projects/b\n2\t1\t1\t(gamma)\t/Users/brian/projects/c\n' \
"$SCRIPT"

manifest="$home/.local/state/terminal-restore/ghostty-layout.json"
last_good="$home/.local/state/terminal-restore/ghostty-layout.last-good.json"

[ -f "$manifest" ]
[ -f "$last_good" ]
[ "$(jq -r '.windows[0].tabs[1].session_name' "$manifest")" = "(beta)" ]
[ "$(jq -r '.focused_window_index' "$manifest")" = "2" ]
[ "$(jq -r '.windows[1].selected_tab_index' "$manifest")" = "1" ]

printf '{"windows":[{"tabs":[{"session_name":"keep"}]}]}' > "$last_good"
PATH="$bindir:$PATH" \
HOME="$home" \
GHOSTTY_LAYOUT_SAVE_ROWS='garbage-without-tabs' \
"$SCRIPT" || true

[ "$(jq -r '.windows[0].tabs[0].session_name' "$last_good")" = "keep" ]
```

- [ ] **Step 2: Run the Ghostty layout save test to confirm it fails**

Run: `bash roles/macos/files/bin/ghostty-layout-save.test`
Expected: FAIL because the save helper does not exist yet.

- [ ] **Step 3: Implement the Ghostty layout save helper and LaunchAgent**

Create `roles/macos/files/bin/ghostty-layout-save`:

```bash
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="$HOME/.local/state/terminal-restore"
MANIFEST="$STATE_DIR/ghostty-layout.json"
LAST_GOOD="$STATE_DIR/ghostty-layout.last-good.json"

mkdir -p "$STATE_DIR"

rows="$(osascript <<'APPLESCRIPT' 2>/dev/null || true
tell application "Ghostty"
  if (count of windows) = 0 then return ""
  set output to ""
  repeat with w in windows
    set selectedIndex to index of selected tab of w
    repeat with t in tabs of w
      set termRef to focused terminal of t
      set output to output & (index of w as text) & tab & (selectedIndex as text) & tab & (index of t as text) & tab & (name of t as text) & tab & (working directory of termRef as text) & linefeed
    end repeat
  end repeat
  return output
end tell
APPLESCRIPT
)"

[ -n "$rows" ] || exit 0

focused_window_index="$(osascript <<'APPLESCRIPT' 2>/dev/null || true
tell application "Ghostty"
  if (count of windows) = 0 then return ""
  return index of front window
end tell
APPLESCRIPT
)"

tmp="$(mktemp "$STATE_DIR/ghostty-layout.XXXXXX")"

printf '%s' "$rows" | jq -Rn --argjson focused_window_index "$focused_window_index" '
  [inputs | select(length > 0) | split("\t")] as $rows
  | {
      version: 1,
      saved_at: now | floor,
      focused_window_index: $focused_window_index,
      windows: (
        $rows
        | group_by(.[0] | tonumber)
        | map({
            window_index: (.[0][0] | tonumber),
            selected_tab_index: (.[0][1] | tonumber),
            tabs: map({
              tab_index: (.[2] | tonumber),
              session_name: .[3],
              working_directory: .[4]
            })
          })
      )
    }
' > "$tmp"

jq -e '.windows | length > 0' "$tmp" >/dev/null
mv "$tmp" "$MANIFEST"
cp "$MANIFEST" "$LAST_GOOD"
```

Create `roles/macos/templates/launchd/com.user.ghostty-layout-save.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.ghostty-layout-save</string>
    <key>ProgramArguments</key>
    <array>
        <string>{{ ansible_facts["user_dir"] }}/.local/bin/ghostty-layout-save</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>60</integer>
</dict>
</plist>
```

- [ ] **Step 4: Run the save-helper test and plist validation**

Run:

```bash
bash roles/macos/files/bin/ghostty-layout-save.test
plutil -lint roles/macos/templates/launchd/com.user.ghostty-layout-save.plist
```

Expected: the shell test PASSes and `plutil` reports `OK`.

- [ ] **Step 5: Commit the layout-save task**

Run:

```bash
git add \
  roles/macos/files/bin/ghostty-layout-save \
  roles/macos/files/bin/ghostty-layout-save.test \
  roles/macos/templates/launchd/com.user.ghostty-layout-save.plist
git commit -m "Add Ghostty layout snapshot helper"
```

Expected: one commit containing the save helper, test, and LaunchAgent template.

## Task 4: Add macOS Ghostty reconcile and keep the wrapper behavior stable

**Files:**
- Create: `roles/macos/files/bin/ghostty-layout-reconcile`
- Create: `roles/macos/files/bin/ghostty-layout-reconcile.test`
- Create: `roles/macos/files/bin/tmux-attach-or-new.test`
- Modify: `roles/macos/files/bin/tmux-attach-or-new`
- Test: `roles/macos/files/bin/ghostty-layout-reconcile.test`
- Test: `roles/macos/files/bin/tmux-attach-or-new.test`

- [ ] **Step 1: Write the failing reconcile and wrapper tests**

Create `roles/macos/files/bin/ghostty-layout-reconcile.test`:

```bash
#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/ghostty-layout-reconcile"

if [ ! -x "$SCRIPT" ]; then
  printf 'ERROR: %s is not executable (or does not exist)\n' "$SCRIPT" >&2
  exit 2
fi

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

home="$TMPROOT/home"
bindir="$(mktemp -d "$TMPROOT/bin.XXXXXX")"
mkdir -p "$home/.local/state/terminal-restore" "$home/.local/bin"

cp "$(cd "$SCRIPT_DIR/../../common/files/bin" && pwd)/tmux-restore-lib.sh" \
  "$home/.local/bin/tmux-restore-lib.sh"

cat > "$home/.local/state/terminal-restore/ghostty-layout.last-good.json" <<'EOF'
{
  "focused_window_index": 1,
  "windows": [
    {
      "window_index": 1,
      "selected_tab_index": 2,
      "tabs": [
        { "tab_index": 1, "session_name": "alpha" },
        { "tab_index": 2, "session_name": "beta" }
      ]
    }
  ]
}
EOF

cat > "$bindir/osascript" <<'EOF'
#!/usr/bin/env bash
cat >> "$GHOSTTY_RECONCILE_LOG"
printf '\n---\n' >> "$GHOSTTY_RECONCILE_LOG"
EOF
chmod +x "$bindir/osascript"

cat > "$bindir/tmux" <<'EOF'
#!/usr/bin/env bash
set -eu
case "${1:-}" in
  has-session) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$bindir/tmux"

cat > "$home/.local/bin/tmux-session-gc" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GHOSTTY_RECONCILE_GC_LOG"
EOF
chmod +x "$home/.local/bin/tmux-session-gc"

PATH="$bindir:$PATH" \
HOME="$home" \
GHOSTTY_RECONCILE_LOG="$TMPROOT/osascript.log" \
GHOSTTY_RECONCILE_GC_LOG="$TMPROOT/gc.log" \
"$SCRIPT"

grep -Fq 'tmux switch-client -t =alpha' "$TMPROOT/osascript.log"
grep -Fq 'tmux switch-client -t =beta' "$TMPROOT/osascript.log"
grep -Fq 'set selected tab of targetWindow to tab 2' "$TMPROOT/osascript.log"
grep -Fqx '--platform macos --manifest '"$home"'/.local/state/terminal-restore/ghostty-layout.last-good.json' "$TMPROOT/gc.log"
```

Create `roles/macos/files/bin/tmux-attach-or-new.test`:

```bash
#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/tmux-attach-or-new"

if [ ! -x "$SCRIPT" ]; then
  printf 'ERROR: %s is not executable (or does not exist)\n' "$SCRIPT" >&2
  exit 2
fi

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

home="$TMPROOT/home"
bindir="$(mktemp -d "$TMPROOT/bin.XXXXXX")"
mkdir -p "$home/.local/bin" "$home/.local/state/terminal-restore"

cat > "$bindir/sysctl" <<'EOF'
#!/usr/bin/env bash
printf '{ sec = 1, usec = 0 } Sat Jan  1 00:00:01 2000\n'
EOF
chmod +x "$bindir/sysctl"

cat > "$home/.local/bin/ghostty-layout-reconcile" <<'EOF'
#!/usr/bin/env bash
printf 'reconcile\n' >> "$TMUX_ATTACH_OR_NEW_LOG"
EOF
chmod +x "$home/.local/bin/ghostty-layout-reconcile"

cat > "$home/.local/bin/tmux-restore-client" <<'EOF'
#!/usr/bin/env bash
printf 'restore-client\n' >> "$TMUX_ATTACH_OR_NEW_LOG"
EOF
chmod +x "$home/.local/bin/tmux-restore-client"

printf '{}' > "$home/.local/state/terminal-restore/ghostty-layout.last-good.json"
TMUX_ATTACH_OR_NEW_LOG="$TMPROOT/run.log" PATH="$bindir:$PATH" HOME="$home" "$SCRIPT"
sleep 1

grep -Fqx 'restore-client' "$TMPROOT/run.log"
grep -Fqx 'reconcile' "$TMPROOT/run.log"
```

- [ ] **Step 2: Run the reconcile and wrapper tests to confirm they fail**

Run:

```bash
bash roles/macos/files/bin/ghostty-layout-reconcile.test
bash roles/macos/files/bin/tmux-attach-or-new.test
```

Expected: FAIL because the reconcile helper does not exist and the wrapper still directly calls tmux.

- [ ] **Step 3: Implement reconcile and update the macOS wrapper**

Create `roles/macos/files/bin/ghostty-layout-reconcile`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../../common/files/bin/tmux-restore-lib.sh
source "$HOME/.local/bin/tmux-restore-lib.sh"

manifest="${1:-$(terminal_restore_last_good_manifest_path)}"
[ -f "$manifest" ] || exit 0

terminal_restore_ensure_dirs

lock_dir="$(terminal_restore_reconcile_lock_dir)"
if ! mkdir "$lock_dir" 2>/dev/null; then
  exit 0
fi
trap 'rmdir "$lock_dir"' EXIT

boot_epoch="$(terminal_restore_boot_epoch)"
marker="$(terminal_restore_reconcile_marker_path)"
if [ -f "$marker" ] && [ "$(cat "$marker")" -ge "$boot_epoch" ]; then
  exit 0
fi

sleep 2

jq -c '.windows[]' "$manifest" | while IFS= read -r window_json; do
  window_index="$(jq -r '.window_index' <<< "$window_json")"
  selected_tab_index="$(jq -r '.selected_tab_index' <<< "$window_json")"

  jq -c '.tabs[]' <<< "$window_json" | while IFS= read -r tab_json; do
    tab_index="$(jq -r '.tab_index' <<< "$tab_json")"
    session_name="$(jq -r '.session_name' <<< "$tab_json")"
    if ! tmux has-session -t "=$session_name" 2>/dev/null; then
      continue
    fi
    osascript <<APPLESCRIPT >/dev/null
tell application "Ghostty"
  repeat while (count of windows) < ${window_index}
    create window
  end repeat
  set targetWindow to window ${window_index}
  repeat while (count of tabs of targetWindow) < ${tab_index}
    create tab in targetWindow
  end repeat
  set targetTab to tab ${tab_index} of targetWindow
  set t to focused terminal of targetTab
  input text "tmux switch-client -t =${session_name}" to t
  send key "enter" to t
  if ${selected_tab_index} = ${tab_index} then
    set selected tab of targetWindow to tab ${tab_index}
  end if
end tell
APPLESCRIPT
  done
done

focused_window_index="$(jq -r '.focused_window_index // 1' "$manifest")"
osascript <<APPLESCRIPT >/dev/null
tell application "Ghostty"
  if (count of windows) >= ${focused_window_index} then
    set index of window ${focused_window_index} to 1
  end if
end tell
APPLESCRIPT

"$HOME/.local/bin/tmux-session-gc" --platform macos --manifest "$manifest" >/dev/null 2>&1 || true
printf '%s' "$(date +%s)" > "$marker"
```

Update `roles/macos/files/bin/tmux-attach-or-new`:

```bash
#!/bin/bash
set -euo pipefail

state_dir="$HOME/.local/state/terminal-restore"
manifest="$state_dir/ghostty-layout.last-good.json"
marker="$state_dir/reconcile.done"
boot_epoch="$(
  sysctl -n kern.boottime | awk -F '[ ,}]+' '{print $4}'
)"

if [ -f "$manifest" ] && { [ ! -f "$marker" ] || [ "$(cat "$marker" 2>/dev/null || printf '0')" -lt "$boot_epoch" ]; }; then
  "$HOME/.local/bin/ghostty-layout-reconcile" >/dev/null 2>&1 &
fi

exec "$HOME/.local/bin/tmux-restore-client"
```

- [ ] **Step 4: Run the reconcile and wrapper tests to verify they pass**

Run:

```bash
bash roles/macos/files/bin/ghostty-layout-reconcile.test
bash roles/macos/files/bin/tmux-attach-or-new.test
```

Expected: PASS with reconcile emitting `tmux switch-client -t =...` commands and the wrapper triggering exactly one background reconcile before delegating to the shared attach helper.

- [ ] **Step 5: Commit the reconcile task**

Run:

```bash
git add \
  roles/macos/files/bin/ghostty-layout-reconcile \
  roles/macos/files/bin/ghostty-layout-reconcile.test \
  roles/macos/files/bin/tmux-attach-or-new \
  roles/macos/files/bin/tmux-attach-or-new.test
git commit -m "Add Ghostty layout reconcile flow"
```

Expected: one commit containing only the macOS reconcile flow and wrapper update.

## Task 5: Wire provisioning and config across macOS and Linux dev hosts

**Files:**
- Create: `roles/common/files/bin/terminal-restore-config.test`
- Modify: `roles/common/tasks/main.yml`
- Modify: `roles/macos/tasks/main.yml`
- Modify: `roles/macos/templates/dotfiles/tmux.conf`
- Modify: `roles/linux/files/dotfiles/tmux.conf`
- Modify: `roles/dev_host/tasks/main.yml`
- Test: `roles/common/files/bin/terminal-restore-config.test`

- [ ] **Step 1: Write the failing config-wiring regression test**

```bash
#!/usr/bin/env bash
set -eu

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"

grep -Fq 'tmux-restore-lib.sh' "$ROOT/roles/common/tasks/main.yml"
grep -Fq 'tmux-restore-client' "$ROOT/roles/common/tasks/main.yml"
grep -Fq 'tmux-session-gc' "$ROOT/roles/common/tasks/main.yml"
grep -Fq 'tmux-client-attached' "$ROOT/roles/common/tasks/main.yml"

grep -Fq 'macos-applescript = true' "$ROOT/roles/macos/tasks/main.yml"
grep -Fq 'com.user.ghostty-layout-save.plist' "$ROOT/roles/macos/tasks/main.yml"
grep -Fq 'tmux-client-attached' "$ROOT/roles/macos/templates/dotfiles/tmux.conf"
grep -Fq "@continuum-save-interval '5'" "$ROOT/roles/macos/templates/dotfiles/tmux.conf"

grep -Fq 'tmux-client-attached' "$ROOT/roles/linux/files/dotfiles/tmux.conf"
grep -Fq "@continuum-save-interval '5'" "$ROOT/roles/linux/files/dotfiles/tmux.conf"
grep -Fq 'exec {{ ansible_facts["user_dir"] }}/.local/bin/tmux-restore-client' "$ROOT/roles/dev_host/tasks/main.yml"
```

- [ ] **Step 2: Run the config-wiring test to confirm it fails**

Run: `bash roles/common/files/bin/terminal-restore-config.test`
Expected: FAIL because none of the provisioning or config wiring exists yet.

- [ ] **Step 3: Wire the helpers into Ansible, tmux, Ghostty, and Linux login**

Update the shared install loop in `roles/common/tasks/main.yml`:

```yaml
- name: Install worktree helpers
  copy:
    backup: yes
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin/{{ item.name }}'
    src: '{{ playbook_dir }}/roles/common/files/bin/{{ item.name }}'
    mode: '{{ item.mode }}'
  loop:
    - { name: worktree-lib.sh, mode: '0644' }
    - { name: worktree-start, mode: '0755' }
    - { name: worktree-delete, mode: '0755' }
    - { name: worktree-merge, mode: '0755' }
    - { name: worktree-done, mode: '0755' }
    - { name: codex-block-worktree-commands, mode: '0755' }
    - { name: tmux-restore-lib.sh, mode: '0644' }
    - { name: tmux-restore-client, mode: '0755' }
    - { name: tmux-session-gc, mode: '0755' }
    - { name: tmux-client-attached, mode: '0755' }
```

Update the `client-attached` hook and save interval in both tmux configs:

```tmux
set-hook -g client-attached 'run-shell -b "$HOME/.local/bin/tmux-client-attached \"$PATH\""'
set -g @continuum-save-interval '5'
```

Update the Linux dev-host login block in `roles/dev_host/tasks/main.yml`:

```yaml
block: |
  # Launch tmux on interactive login (SSH)
  if [ -z "$TMUX" ] && [ -t 0 ]; then
    exec {{ ansible_facts["user_dir"] }}/.local/bin/tmux-restore-client
  fi
```

Update macOS Ghostty config wiring in `roles/macos/tasks/main.yml`:

```yaml
- name: Configure ghostty applescript support
  lineinfile:
    path: '{{ ansible_facts["user_dir"] }}/Library/Application Support/com.mitchellh.ghostty/config'
    regexp: '^macos-applescript\s*='
    line: 'macos-applescript = true'
    create: yes
    mode: 0644

- name: Install Ghostty layout save LaunchAgent plist
  template:
    src: launchd/com.user.ghostty-layout-save.plist
    dest: '{{ ansible_facts["user_dir"] }}/Library/LaunchAgents/com.user.ghostty-layout-save.plist'
    mode: '0644'
  register: ghostty_layout_save_plist

- name: Unload Ghostty layout save LaunchAgent if changed
  command: launchctl unload {{ ansible_facts["user_dir"] }}/Library/LaunchAgents/com.user.ghostty-layout-save.plist
  when: ghostty_layout_save_plist.changed
  changed_when: false
  failed_when: false

- name: Load Ghostty layout save LaunchAgent
  command: launchctl load {{ ansible_facts["user_dir"] }}/Library/LaunchAgents/com.user.ghostty-layout-save.plist
  changed_when: false
  failed_when: false
```

- [ ] **Step 4: Run the config test and syntax check**

Run:

```bash
bash roles/common/files/bin/terminal-restore-config.test
ansible-playbook playbook.yml --syntax-check
```

Expected: the regression test PASSes and Ansible reports `playbook: playbook.yml`.

- [ ] **Step 5: Commit the wiring task**

Run:

```bash
git add \
  roles/common/files/bin/terminal-restore-config.test \
  roles/common/tasks/main.yml \
  roles/macos/tasks/main.yml \
  roles/macos/templates/dotfiles/tmux.conf \
  roles/linux/files/dotfiles/tmux.conf \
  roles/dev_host/tasks/main.yml
git commit -m "Wire terminal restore helpers into provisioning"
```

Expected: one commit containing only the provisioning, tmux config, and login wiring.

## Final Verification

- [ ] Run the full targeted shell test set:

```bash
bash roles/common/files/bin/tmux-restore-client.test
bash roles/common/files/bin/tmux-session-gc.test
bash roles/common/files/bin/tmux-client-attached.test
bash roles/macos/files/bin/ghostty-layout-save.test
bash roles/macos/files/bin/ghostty-layout-reconcile.test
bash roles/macos/files/bin/tmux-attach-or-new.test
bash roles/common/files/bin/terminal-restore-config.test
```

Expected: all shell tests PASS.

- [ ] Run provisioning syntax and dry-run checks:

```bash
ansible-playbook playbook.yml --syntax-check
bin/provision --check
```

Expected: syntax check passes; `bin/provision --check` completes without template or task errors.

- [ ] Run the manual macOS restart scenario from the spec:

```text
1. Open 3-5 Ghostty tabs across multiple windows.
2. Confirm each tab is attached to a distinct tmux session.
3. Wait at least one LaunchAgent save interval.
4. Restart macOS.
5. Launch Ghostty.
6. Confirm window count, tab count, tab order, focused tab/window, and attached tmux sessions all match.
7. Run `tmux list-sessions` and confirm no extra unattached sessions remain from the restore.
```

- [ ] Run the manual Linux dev-host scenario from the spec:

```text
1. Create several tmux sessions on a Linux dev host.
2. Disconnect and reconnect.
3. Confirm the shared attach helper reconnects as expected.
4. Mark one session unattached and age its marker beyond 14 days in a controlled test.
5. Reattach once more to trigger the `client-attached` hook.
6. Confirm only the long-unattached session is removed.
```
