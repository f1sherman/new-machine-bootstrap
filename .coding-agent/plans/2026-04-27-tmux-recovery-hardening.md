# tmux Recovery Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce work loss when the tmux server crashes by (1) preserving the last known-good resurrect save against post-crash overwrites, (2) continuously logging pane scrollback, and (3) providing an extensible mechanism for restoring per-pane state (with Claude Code session restoration as the first concrete consumer).

**Architecture:** A general persistence layer added to tmux-resurrect via its hook system. Pane-local user options prefixed `@persist_*` declare arbitrary "things to restore"; a save-time helper extracts them into a JSON sidecar next to the resurrect text save; a restore-time dispatcher invokes per-key handler scripts (`~/.local/bin/tmux-restore-handler-<key>`) found on `$PATH` by name. This plan ships the infrastructure plus one handler (`claude_session_id`); additional handlers can be added by anyone dropping a matching script on `$PATH`.

**Tech Stack:** bash, tmux 3.x hooks (`@resurrect-hook-post-save-layout`, `@resurrect-hook-post-restore-all`, `after-split-window`, `after-new-window`, `after-new-session`, `window-linked`), `tmux pipe-pane`, jq for sidecar JSON, `tmux set-option -p` user options, Claude Code `SessionStart` hook in `~/.claude/settings.json`.

**Branch:** `tmux-recovery-hardening`.

---

## File Structure

| Action | Path | Responsibility |
|---|---|---|
| Create | `roles/common/files/bin/tmux-resurrect-save-extra` | Post-save-layout hook: writes sidecar JSON, rotates `last.safe`. |
| Create | `roles/common/files/bin/tmux-resurrect-save-extra.test` | Test for the above. |
| Create | `roles/common/files/bin/tmux-resurrect-restore-extra` | Post-restore-all hook: reads sidecar, dispatches per-pane per-key to handlers on `$PATH`. |
| Create | `roles/common/files/bin/tmux-resurrect-restore-extra.test` | Test. |
| Create | `roles/common/files/bin/tmux-pipe-pane-start` | Hook helper: starts pipe-pane logging on a single pane. |
| Create | `roles/common/files/bin/tmux-pipe-pane-start.test` | Test. |
| Create | `roles/common/files/bin/tmux-pipe-pane-rotate` | Cleanup script: deletes pane logs older than 7 days; pruned by launchd. |
| Create | `roles/common/files/bin/tmux-pipe-pane-rotate.test` | Test. |
| Create | `roles/common/files/bin/tmux-claude-session-start` | Claude `SessionStart` hook: parses stdin JSON, sets `@persist_claude_session_id` on the current tmux pane. |
| Create | `roles/common/files/bin/tmux-claude-session-start.test` | Test. |
| Create | `roles/common/files/bin/tmux-restore-handler-claude_session_id` | Restore handler: sends `claude --resume <id>` to a target pane. |
| Create | `roles/common/files/bin/tmux-restore-handler-claude_session_id.test` | Test. |
| Modify | `roles/macos/templates/dotfiles/tmux.conf` | Wire save/restore hooks and pane logging hooks. |
| Modify | `roles/linux/files/dotfiles/tmux.conf` | Wire save/restore hooks and pane logging hooks. |
| Modify | `roles/common/tasks/main.yml` | Install helpers and register the Claude `SessionStart` hook. |
| Create | `roles/macos/templates/launchd/com.user.tmux-pipe-pane-rotate.plist` | Daily launchd job that runs `tmux-pipe-pane-rotate`. |
| Modify | `roles/macos/tasks/main.yml` | Install/load the launchd plist. |

---

## Sidecar JSON schema (used by save + restore)

Filename convention: `<resurrect_save>.meta.json`, written next to e.g. `tmux_resurrect_20260427T143000.txt`.

```json
{
  "version": 1,
  "saved_at": "2026-04-27T14:30:00-05:00",
  "panes": {
    "main:0.0": {
      "claude_session_id": "9169fac8-de26-4424-ad1f-3825b7f38a93"
    }
  }
}
```

Pane key: `<session_name>:<window_index>.<pane_index>` — matches resurrect's coordinate system and survives a server restart.

`last.safe` lives next to the resurrect snapshots and is updated only when the new save passes a "substantial" check (file >= 1 KB AND text save contains >= 3 `^pane\t` lines).

---

## Dispatcher contract

For each pane in the sidecar, for each `<key>: <value>` pair, the dispatcher invokes:

```bash
tmux-restore-handler-<key> <target_pane_id> <value>
```

The handler is expected to use `tmux send-keys -t <pane>` (or any other tmux command) to drive the pane. Handlers MUST be idempotent and MUST tolerate a missing/dead target pane (exit 0 with a warning).

If `tmux-restore-handler-<key>` is not found on `$PATH`, the dispatcher silently skips that key and logs a notice to `<resurrect_dir>/restore-extra.log`. This makes the dispatcher safe to ship before any specific handler exists.

---

## Tasks

### Task 1: `tmux-resurrect-save-extra` — sidecar writer + `last.safe` rotation

**Files:**
- Create: `roles/common/files/bin/tmux-resurrect-save-extra`
- Test: `roles/common/files/bin/tmux-resurrect-save-extra.test`

The script is invoked as `tmux-resurrect-save-extra <state_file_path>` from `@resurrect-hook-post-save-layout '...-save-extra "$1"'`.

Behavior:
1. Verify `$1` exists and is a regular file. If not, exit 0 (defensive).
2. List all panes via `tmux list-panes -a -F '#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_id}'`.
3. For each pane, gather all `@persist_*` user options via `tmux show-options -pq -t <pane_id>` (filter lines matching `^@persist_`).
4. Build a JSON document of the schema above; write atomically (tempfile + `mv`) to `$1.meta.json`.
5. Compute "substantial": file size ≥ 1024 bytes AND `grep -c '^pane\t' "$1"` ≥ 3.
6. If substantial: copy `$1` to `<dir>/last.safe.tmp` and `mv` to `<dir>/last.safe` (atomic). Same for `$1.meta.json` → `last.safe.meta.json`.

- [x] **Step 1: Write the failing test**

`roles/common/files/bin/tmux-resurrect-save-extra.test`:

```bash
#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/tmux-resurrect-save-extra"
[ -x "$SCRIPT" ] || { echo "ERROR: $SCRIPT not executable"; exit 2; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

# Stub tmux that returns canned values
fake_bin="$TMPROOT/fake-bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "list-panes -a")
    printf 'main\t0\t0\t%%1\nmain\t0\t1\t%%2\n'
    ;;
  "show-options -pq")
    case "$4" in
      "%1") echo '@persist_claude_session_id "abc-123"' ;;
      "%2") ;;  # no persist options
    esac
    ;;
esac
EOF
chmod +x "$fake_bin/tmux"
PATH="$fake_bin:$PATH"; export PATH

# Build a "substantial" save file (>=1KB, >=3 pane lines)
state="$TMPROOT/tmux_resurrect_20260101T000000.txt"
cat > "$state" <<EOF2
pane	main	0	0	:*	0	t	:/tmp	1	zsh	:
pane	main	0	0	:	1	t	:/tmp	0	zsh	:
pane	main	0	0	:	2	t	:/tmp	0	zsh	:
window	main	0	:main	1	:*	abc	off
EOF2
yes "padding" | head -200 >> "$state"

"$SCRIPT" "$state" || { echo "FAIL: script exited nonzero"; exit 1; }

# Sidecar exists with expected key
[ -f "$state.meta.json" ] || { echo "FAIL: sidecar not written"; exit 1; }
grep -q 'claude_session_id' "$state.meta.json" || { echo "FAIL: sidecar missing claude_session_id"; exit 1; }
grep -q 'abc-123' "$state.meta.json" || { echo "FAIL: sidecar missing value"; exit 1; }

# last.safe rotated
[ -f "$TMPROOT/last.safe" ] || { echo "FAIL: last.safe not created"; exit 1; }
[ -f "$TMPROOT/last.safe.meta.json" ] || { echo "FAIL: last.safe.meta.json not created"; exit 1; }

# Test the threshold: a small file should NOT rotate
small="$TMPROOT/tmux_resurrect_20260102T000000.txt"
echo "pane	main	0	0	:	0	t	:/tmp	1	zsh	:" > "$small"
rm -f "$TMPROOT/last.safe" "$TMPROOT/last.safe.meta.json"
"$SCRIPT" "$small"
[ ! -f "$TMPROOT/last.safe" ] || { echo "FAIL: small file rotated to last.safe"; exit 1; }

echo "OK"
```

- [x] **Step 2: Run test, verify FAIL**

Run: `bash roles/common/files/bin/tmux-resurrect-save-extra.test`
Expected: `ERROR: ... not executable` (script doesn't exist yet).

- [x] **Step 3: Write minimal implementation**

`roles/common/files/bin/tmux-resurrect-save-extra`:

```bash
#!/usr/bin/env bash
set -euo pipefail

state_file="${1:-}"
[ -n "$state_file" ] && [ -f "$state_file" ] || exit 0

dir="$(dirname "$state_file")"
sidecar="$state_file.meta.json"
tmp_sidecar="$(mktemp "$sidecar.XXXXXX")"
trap 'rm -f "$tmp_sidecar"' EXIT

saved_at="$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S%z)"

panes_tsv="$(tmux list-panes -a -F '#{session_name}	#{window_index}	#{pane_index}	#{pane_id}')"

{
  printf '{\n'
  printf '  "version": 1,\n'
  printf '  "saved_at": "%s",\n' "$saved_at"
  printf '  "panes": {\n'

  first=1
  while IFS=$'\t' read -r sess win pane pid; do
    [ -n "$pid" ] || continue
    opts="$(tmux show-options -pq -t "$pid" 2>/dev/null | grep '^@persist_' || true)"
    [ -n "$opts" ] || continue

    pane_first=1
    pane_buf=""
    while IFS= read -r line; do
      key="$(printf '%s' "$line" | awk '{print $1}' | sed 's/^@persist_//')"
      val="$(printf '%s' "$line" | sed 's/^[^ ]* //; s/^"//; s/"$//')"
      [ -n "$key" ] || continue
      if [ $pane_first -eq 1 ]; then
        pane_first=0
      else
        pane_buf="$pane_buf,\n"
      fi
      pane_buf="$pane_buf      \"$key\": \"$val\""
    done <<<"$opts"

    [ -n "$pane_buf" ] || continue
    if [ $first -eq 1 ]; then
      first=0
    else
      printf ',\n'
    fi
    printf '    "%s:%s.%s": {\n' "$sess" "$win" "$pane"
    printf '%b\n' "$pane_buf"
    printf '    }'
  done <<<"$panes_tsv"

  printf '\n  }\n'
  printf '}\n'
} > "$tmp_sidecar"

mv "$tmp_sidecar" "$sidecar"
trap - EXIT

# last.safe rotation
size="$(wc -c < "$state_file" | tr -d ' ')"
pane_count="$(grep -c '^pane	' "$state_file" || true)"
if [ "$size" -ge 1024 ] && [ "$pane_count" -ge 3 ]; then
  cp "$state_file" "$dir/last.safe.tmp" && mv "$dir/last.safe.tmp" "$dir/last.safe"
  cp "$sidecar" "$dir/last.safe.meta.json.tmp" && mv "$dir/last.safe.meta.json.tmp" "$dir/last.safe.meta.json"
fi
```

`chmod +x roles/common/files/bin/tmux-resurrect-save-extra`

- [x] **Step 4: Run test, verify PASS**

- [x] **Step 5: Commit** via `_commit` skill with summary "Add tmux-resurrect-save-extra: sidecar writer + last.safe rotation".

> Implemented in `effdf56`; hardened in `7d9ab0b` per code-quality review (jq-based JSON encoding + strengthened test).

---

### Task 2: `tmux-resurrect-restore-extra` — restore dispatcher

**Files:**
- Create: `roles/common/files/bin/tmux-resurrect-restore-extra`
- Test: `roles/common/files/bin/tmux-resurrect-restore-extra.test`

Invoked as `tmux-resurrect-restore-extra` (no args) from `@resurrect-hook-post-restore-all`.

Behavior:
1. Resolve resurrect dir: `${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect`. If missing, fall back to `$HOME/.tmux/resurrect`.
2. Read sidecar at `<dir>/$(readlink last).meta.json`. If missing, exit 0.
3. Build a map from `<session>:<win>.<pane>` → live `<pane_id>` via `tmux list-panes -a -F`.
4. For each pane in sidecar's `panes`: for each `<key>: <value>`, look up `tmux-restore-handler-<key>` on `$PATH`; if executable, invoke `<handler> <pane_id> <value>`. Capture nonzero exits to `<dir>/restore-extra.log` but continue.

- [x] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/tmux-resurrect-restore-extra"
[ -x "$SCRIPT" ] || { echo "ERROR: $SCRIPT not executable"; exit 2; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

fake_bin="$TMPROOT/fake-bin"
mkdir -p "$fake_bin"

# stub handler that records its invocation
cat > "$fake_bin/tmux-restore-handler-claude_session_id" <<EOF
#!/usr/bin/env bash
echo "called \$1 \$2" > "$TMPROOT/handler.log"
EOF
chmod +x "$fake_bin/tmux-restore-handler-claude_session_id"

# stub tmux: list-panes returns the live mapping
cat > "$fake_bin/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "list-panes -a")
    printf 'main\t0\t0\t%%99\n'
    ;;
esac
EOF
chmod +x "$fake_bin/tmux"

# Build the resurrect dir + sidecar
mkdir -p "$TMPROOT/tmux/resurrect"
ln -s tmux_resurrect_20260101T000000.txt "$TMPROOT/tmux/resurrect/last"
touch "$TMPROOT/tmux/resurrect/tmux_resurrect_20260101T000000.txt"
cat > "$TMPROOT/tmux/resurrect/tmux_resurrect_20260101T000000.txt.meta.json" <<EOF
{
  "version": 1,
  "saved_at": "x",
  "panes": {
    "main:0.0": { "claude_session_id": "abc-123" }
  }
}
EOF

PATH="$fake_bin:$PATH"; export PATH
XDG_DATA_HOME="$TMPROOT" HOME="$TMPROOT" "$SCRIPT" || { echo "FAIL: nonzero exit"; exit 1; }

[ -f "$TMPROOT/handler.log" ] && grep -q "called %99 abc-123" "$TMPROOT/handler.log" || {
  echo "FAIL: handler not called with expected args"
  cat "$TMPROOT/handler.log" 2>/dev/null
  exit 1
}

# Missing-handler case: should not error
rm -f "$fake_bin/tmux-restore-handler-claude_session_id"
XDG_DATA_HOME="$TMPROOT" HOME="$TMPROOT" "$SCRIPT" || { echo "FAIL: missing-handler case errored"; exit 1; }

echo "OK"
```

- [x] **Step 2: Run test, verify FAIL**

- [x] **Step 3: Write minimal implementation**

```bash
#!/usr/bin/env bash
set -u

dir="${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"
[ -d "$dir" ] || dir="$HOME/.tmux/resurrect"
[ -d "$dir" ] || exit 0

last="$dir/last"
[ -L "$last" ] || exit 0
target="$(readlink "$last")"
sidecar="$dir/$target.meta.json"
[ -f "$sidecar" ] || exit 0

log="$dir/restore-extra.log"

# Build live coordinate -> pane_id map
declare -A coord_to_id=()
while IFS=$'\t' read -r sess win pane pid; do
  coord_to_id["$sess:$win.$pane"]="$pid"
done < <(tmux list-panes -a -F '#{session_name}	#{window_index}	#{pane_index}	#{pane_id}')

# Iterate over panes in sidecar (jq required at runtime)
panes="$(jq -r '.panes | to_entries[] | "\(.key)\t\(.value | to_entries[] | "\(.key)=\(.value)")"' "$sidecar")"

while IFS=$'\t' read -r coord kv; do
  [ -n "$kv" ] || continue
  pid="${coord_to_id[$coord]:-}"
  [ -n "$pid" ] || { echo "$(date) skip: no live pane for $coord" >> "$log"; continue; }
  key="${kv%%=*}"; val="${kv#*=}"
  handler="$(command -v "tmux-restore-handler-$key" || true)"
  [ -n "$handler" ] || { echo "$(date) skip: no handler for $key" >> "$log"; continue; }
  "$handler" "$pid" "$val" >>"$log" 2>&1 || echo "$(date) handler-failed: $key for $coord" >> "$log"
done <<<"$panes"
```

`chmod +x roles/common/files/bin/tmux-resurrect-restore-extra`

- [x] **Step 4: Run test, verify PASS**

- [x] **Step 5: Commit.**

> Implemented in `ab4e2e2`. Bash 3.2 compatibility adaptation (linear `lookup_pane_id` instead of `declare -A`); added no-live-pane test case beyond spec minimum. Code review flagged minor follow-ups (log rotation deferred to Task 5; one missing test case for handler-failed branch — small TDD gap, not blocking).

---

### Task 3: Wire save/restore hooks into tmux.conf

**Files:**
- Modify: `roles/macos/templates/dotfiles/tmux.conf`
- Modify: `roles/linux/files/dotfiles/tmux.conf`

Add, immediately after the existing `@continuum-*` block:

```tmux
# Sidecar metadata + last.safe rotation. Helper handles both.
set -g @resurrect-hook-post-save-layout 'run-shell "~/.local/bin/tmux-resurrect-save-extra \"$1\""'

# Restore dispatcher: reads sidecar, invokes per-key handlers found on $PATH.
set -g @resurrect-hook-post-restore-all 'run-shell "~/.local/bin/tmux-resurrect-restore-extra"'
```

- [x] **Step 1**: Add the two lines.
- [x] **Step 2**: Verify syntactically by sourcing into a throwaway tmux server: `tmux -L recovery-test new-session -d \; source-file roles/macos/templates/dotfiles/tmux.conf \; kill-server` (or equivalent — adjust if Jinja2 templating in the file requires rendering first).
- [x] **Step 3**: ~~Manual smoke~~ deferred to Task 8's full integrated smoke (no scripts deployed yet at this point in the sequence).
- [x] **Step 4**: Commit.

> Implemented in `a0e67c1`. Two `@resurrect-hook-*` lines inserted after the `@continuum-*` block. Jinja-rendered config parses cleanly via throwaway tmux server.

---

### Task 4: Pipe-pane logging — `tmux-pipe-pane-start` + `tmux-pipe-pane-rotate`

**Files:**
- Create: `roles/common/files/bin/tmux-pipe-pane-start`
- Test: `roles/common/files/bin/tmux-pipe-pane-start.test`
- Create: `roles/common/files/bin/tmux-pipe-pane-rotate`
- Test: `roles/common/files/bin/tmux-pipe-pane-rotate.test`

`tmux-pipe-pane-start <pane_id>`:
1. Compute log path: `~/.tmux/scrollback/<session>-<window>-<pane>-$(date +%Y%m%d).log`. mkdir -p the dir.
2. Skip if pipe-pane is already active for this pane: `tmux display-message -p -t <pane_id> '#{pane_pipe}'` returns `1` if active.
3. `tmux pipe-pane -t <pane_id> -O 'cat >> "<log_path>"'`. The `-O` flag enables piping (without it, pipe-pane is toggled off).
4. Validate `-O` semantics on macOS during manual smoke (recorded in plan risks).

`tmux-pipe-pane-rotate`:
1. Find files under `~/.tmux/scrollback/` older than 7 days: `find ~/.tmux/scrollback -type f -mtime +7 -delete`.
2. Cap total dir size at 1 GB: list files newest-first, sum sizes, delete oldest until under cap.

- [x] **Step 1: Write failing test for `tmux-pipe-pane-start`** following the same shape as Task 1's test:
  - Stub `tmux` with a fake that records args.
  - Invoke `tmux-pipe-pane-start %1`.
  - Assert the recorded args include `pipe-pane`, `-O`, the pane id, and a path under `~/.tmux/scrollback/`.
  - Assert no-op when the stub reports `pane_pipe=1`.

- [x] **Step 2**: FAIL.

- [x] **Step 3**: Implement `tmux-pipe-pane-start` (~25 lines).

- [x] **Step 4**: PASS.

- [x] **Step 5: Write failing test for `tmux-pipe-pane-rotate`**:
  - Create a fake `~/.tmux/scrollback/` populated with files of various ages (use `touch -t` to backdate).
  - Run the script.
  - Assert files older than 7 days are gone and recent ones remain.
  - Assert the size cap triggers when total > 1GB by populating with sparse files.

- [x] **Step 6**: FAIL.

- [x] **Step 7**: Implement `tmux-pipe-pane-rotate` (~30 lines).

- [x] **Step 8**: PASS.

- [x] **Step 9**: Commit each script separately (clean history).

---

### Task 5: Wire pipe-pane hook + launchd rotation

**Files:**
- Modify: `roles/macos/templates/dotfiles/tmux.conf`
- Modify: `roles/linux/files/dotfiles/tmux.conf`
- Create: `roles/macos/templates/launchd/com.user.tmux-pipe-pane-rotate.plist`
- Modify: `roles/macos/tasks/main.yml`

In tmux.conf, add:

```tmux
# Continuous pane logging. Fires on every newly created pane, including restore.
set-hook -g after-split-window 'run-shell -b "$HOME/.local/bin/tmux-pipe-pane-start #{pane_id}"'
set-hook -g after-new-window 'run-shell -b "$HOME/.local/bin/tmux-pipe-pane-start #{pane_id}"'
set-hook -g after-new-session 'run-shell -b "$HOME/.local/bin/tmux-pipe-pane-start #{pane_id}"'
set-hook -g window-linked 'run-shell -b "$HOME/.local/bin/tmux-pipe-pane-start #{pane_id}"'
```

LaunchAgent `com.user.tmux-pipe-pane-rotate.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.user.tmux-pipe-pane-rotate</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-lc</string>
    <string>$HOME/.local/bin/tmux-pipe-pane-rotate</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>3</integer><key>Minute</key><integer>30</integer></dict>
  <key>StandardErrorPath</key><string>/tmp/tmux-pipe-pane-rotate.err</string>
  <key>StandardOutPath</key><string>/tmp/tmux-pipe-pane-rotate.out</string>
</dict>
</plist>
```

In `roles/macos/tasks/main.yml`, append a task that templates the plist to `~/Library/LaunchAgents/` and registers it by following the existing LaunchAgent load/unload convention.

- [x] **Step 1**: Add tmux.conf hooks.
- [x] **Step 2**: Create plist.
- [x] **Step 3**: Add Ansible task.
- [x] **Step 4**: `ansible-playbook playbook.yml --check --diff` — no errors.
- [x] **Step 5**: ~~Provision smoke~~ deferred to Task 8 integrated end-to-end smoke.
- [x] **Step 6**: Commit.

> tmux 3.6a does not expose `after-new-pane` / `session-window-linked`; substituted `after-split-window`, `after-new-window`, `after-new-session`, and `window-linked` (verified via `show-hooks -g`). Followed existing repo convention for LaunchAgents (`templates/launchd/com.user.*` + `template:` + `launchctl unload/load`) instead of `files/launchd/` + `launchctl bootstrap`.

---

### Task 6: Claude `SessionStart` hook → `@persist_claude_session_id`

**Files:**
- Create: `roles/common/files/bin/tmux-claude-session-start`
- Test: `roles/common/files/bin/tmux-claude-session-start.test`
- Modify: `roles/common/tasks/main.yml`

`tmux-claude-session-start`:
1. Read JSON from stdin (Claude hook protocol).
2. Extract `session_id` via `jq -r '.session_id'`. Exit 0 if empty/null.
3. If `$TMUX_PANE` is unset, exit 0 (Claude not running under tmux).
4. `tmux set-option -p -t "$TMUX_PANE" @persist_claude_session_id "$session_id"`.

Claude settings entry to add (merge with existing `hooks` block if present — do NOT overwrite unrelated keys):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.local/bin/tmux-claude-session-start"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 1**: Inspect current Claude settings file structure.
- [ ] **Step 2**: Write failing test (stub tmux + jq invocations; feed JSON via stdin; assert `set-option -p` was called with the right args; cover the no-tmux case where `TMUX_PANE` is unset).
- [ ] **Step 3**: FAIL.
- [ ] **Step 4**: Implement script.
- [ ] **Step 5**: PASS.
- [ ] **Step 6**: Add hook entry to Claude settings template (merge, don't replace).
- [ ] **Step 7**: `ansible-playbook playbook.yml --check --diff` — verify the rendered settings file is valid JSON.
- [ ] **Step 8**: Manual smoke: launch `claude` in a tmux pane; verify `tmux show-options -pq @persist_claude_session_id` returns the session id.
- [ ] **Step 9**: Commit.

---

### Task 7: `tmux-restore-handler-claude_session_id`

**Files:**
- Create: `roles/common/files/bin/tmux-restore-handler-claude_session_id`
- Test: `roles/common/files/bin/tmux-restore-handler-claude_session_id.test`

Invoked as `tmux-restore-handler-claude_session_id <pane_id> <session_id>`.

Behavior:
1. Validate args: both non-empty.
2. Validate target pane: `tmux display-message -p -t <pane_id> '#{pane_id}'`. If empty/error, exit 0.
3. `tmux send-keys -t <pane_id> 'claude --resume <session_id>' Enter`.

- [ ] **Step 1: Write failing test** (stub tmux; assert `send-keys` was called with the composed command).
- [ ] **Step 2**: FAIL.
- [ ] **Step 3**: Implement (~10 lines).
- [ ] **Step 4**: PASS.
- [ ] **Step 5**: Commit.

---

### Task 8: End-to-end manual integration test + PR

- [ ] **Step 1**: Run `bin/provision` from this worktree to deploy the new scripts and tmux.conf.
- [ ] **Step 2**: Reload tmux config (`tmux source ~/.tmux.conf`).
- [ ] **Step 3**: Open a new tmux pane, run `claude --dangerously-skip-permissions`. Confirm `tmux show-options -pq -t <pane> @persist_claude_session_id` returns a UUID.
- [ ] **Step 4**: Trigger save (`prefix + Ctrl-s`). Inspect `<save>.meta.json` — should contain the pane and the session id. Inspect `last.safe` — should be rotated.
- [ ] **Step 5**: `tmux kill-server`.
- [ ] **Step 6**: Start tmux fresh (`tmux`). continuum-restore should fire. Verify the Claude pane has been relaunched with `claude --resume <id>` (visible in the pane's command line).
- [ ] **Step 7**: Verify pane scrollback log exists at `~/.tmux/scrollback/...` and has post-restore output.
- [ ] **Step 8**: Open a PR via the `_pull-request` skill.

---

## Self-Review Notes

- **Coverage**: Task 1 covers (A) `last.safe` rotation. Tasks 4–5 cover (B) pipe-pane logging. Tasks 6–7 cover Claude session restoration as the first concrete handler. Tasks 2–3 wire the dispatcher infrastructure that any future handler can plug into.
- **Extensibility**: The dispatcher silently no-ops on missing handlers, so additional handlers can be developed and shipped independently from any other repo without breaking this one. The only contract is: a script named `tmux-restore-handler-<key>` on `$PATH` that accepts `<pane_id> <value>` and uses tmux to drive the pane.
- **Deferred work** (surface in the PR description as follow-ups, not in scope here):
  1. Restoring exported shell env vars — out of reach of any tmux plugin; mention `direnv`/`.envrc` as the right tool.
  2. Linux dev-host equivalent of the macOS launchd rotation job — use a systemd timer; mirror in `roles/dev_host/` once macOS is stable.
- **Risk: hook arg passing** — the tmux-resurrect docs say `post-save-layout` is "passed single argument of the state file." The format `'run-shell "... \"$1\""'` should pass `$1` as the script's first positional arg. Verify with a `set -x` early in `tmux-resurrect-save-extra` during Task 3 manual smoke; adjust quoting if needed.
- **Risk: `tmux pipe-pane -O` semantics** — confirm on macOS tmux during Task 4 manual smoke. If `-O` toggles instead of forces "open," fall back to checking `#{pane_pipe}` first and skipping if already piped.
