# Tmux Title Client Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent an inactive remote tmux task from renaming the local tmux window that displays another remote pane.

**Architecture:** Keep the existing OSC-over-SSH title flow, but separate pane metadata from client metadata. `tmux-remote-title` will resolve the source pane's session/window, enumerate attached clients, and write only to client TTYs currently displaying that source window.

**Tech Stack:** Bash, tmux format strings, existing shell contract harness.

## Global Constraints

- The local tmux title follows only the currently visible pane in the corresponding remote tmux client.
- Inactive sessions, windows, and panes publish no title to unrelated clients.
- Multiple clients intentionally viewing the same source window each receive the title.
- Missing/disappearing clients and TTY delivery failures remain best effort and do not fail Pi or tmux lifecycle hooks.
- `print` mode, title formatting, task labels, indicators, edge markers, outer parsing, and focus hooks remain unchanged.
- Modify only repository-managed files in `new-machine-bootstrap`; do not edit deployed files directly.

---

### Task 1: Route remote titles to matching visible clients

**Files:**
- Modify: `roles/common/files/bin/tmux-remote-title`
- Modify: `tests/tmux-label-contract.sh`

**Interfaces:**
- Consumes: tmux source-pane metadata from `display-message -p -t "$pane_id"` and client metadata from `list-clients -F`.
- Produces: `matching_client_ttys <session_id> <window_id>`, one valid client TTY per line; `publish_title <title> <session_id> <window_id> <pane_active>`, best-effort OSC delivery to matching clients only.

- [ ] **Step 1: Add failing multi-client routing coverage**

Add a focused fake-tmux block after the current remote-title formatting assertions in `tests/tmux-label-contract.sh`. The fake `display-message` reports source session `$source`, window `@source`, and active state from `TMUX_TEST_PANE_ACTIVE`; `list-clients` emits `TMUX_TEST_CLIENTS`. Use capture files as client TTYs and assert:

```bash
remote_publish_tmux_dir="$TMPROOT/remote-publish-tmux-bin"
remote_publish_visible="$TMPROOT/remote-publish-visible"
remote_publish_other="$TMPROOT/remote-publish-other"
remote_publish_second="$TMPROOT/remote-publish-second"
mkdir -p "$remote_publish_tmux_dir"
: > "$remote_publish_visible"
: > "$remote_publish_other"
: > "$remote_publish_second"
cat >"$remote_publish_tmux_dir/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  display-message)
    printf '/tmp/project\t/dev/null\tzsh\t\t$source\t@source\t%s\n' "${TMUX_TEST_PANE_ACTIVE:-1}"
    ;;
  list-clients)
    printf '%b' "$TMUX_TEST_CLIENTS"
    ;;
  show-options)
    case "${*: -1}" in
      @task_label) printf 'status check' ;;
      @task_state) printf 'provisional' ;;
      @task_context) printf 'project' ;;
    esac
    ;;
esac
STUB
chmod +x "$remote_publish_tmux_dir/tmux"

TMUX_PANE=%31 \
TMUX_REMOTE_TITLE_HOST_TAG=remote-host \
TMUX_TEST_CLIENTS="$remote_publish_visible\t\$source\t@source\n$remote_publish_other\t\$other\t@other\n" \
PATH="$remote_publish_tmux_dir:$PATH" \
  "$REMOTE_TITLE" publish
assert_file_contains "$remote_publish_visible" '~ status check · project | remote-host' "remote title reaches client displaying source window"
assert_equals "$(wc -c < "$remote_publish_other" | tr -d ' ')" "0" "remote title does not leak to another session"

: > "$remote_publish_visible"
TMUX_PANE=%31 \
TMUX_REMOTE_TITLE_HOST_TAG=remote-host \
TMUX_TEST_CLIENTS="$remote_publish_visible\t\$source\t@different\n$remote_publish_other\t\$source\t@other\n" \
PATH="$remote_publish_tmux_dir:$PATH" \
  "$REMOTE_TITLE" publish
assert_equals "$(wc -c < "$remote_publish_visible" | tr -d ' ')" "0" "remote title skips client viewing another window"
assert_equals "$(wc -c < "$remote_publish_other" | tr -d ' ')" "0" "remote title skips all nonmatching windows"

: > "$remote_publish_visible"
: > "$remote_publish_second"
TMUX_PANE=%31 \
TMUX_REMOTE_TITLE_HOST_TAG=remote-host \
TMUX_TEST_CLIENTS="$remote_publish_visible\t\$source\t@source\n$remote_publish_second\t\$source\t@source\n" \
PATH="$remote_publish_tmux_dir:$PATH" \
  "$REMOTE_TITLE" publish
assert_file_contains "$remote_publish_visible" '~ status check · project | remote-host' "remote title reaches first client viewing source window"
assert_file_contains "$remote_publish_second" '~ status check · project | remote-host' "remote title reaches second client viewing source window"

: > "$remote_publish_visible"
TMUX_PANE=%31 \
TMUX_REMOTE_TITLE_HOST_TAG=remote-host \
TMUX_TEST_PANE_ACTIVE=0 \
TMUX_TEST_CLIENTS="$remote_publish_visible\t\$source\t@source\n" \
PATH="$remote_publish_tmux_dir:$PATH" \
  "$REMOTE_TITLE" publish
assert_equals "$(wc -c < "$remote_publish_visible" | tr -d ' ')" "0" "inactive source pane publishes no remote title"
```

- [ ] **Step 2: Run the contract test and verify the new case fails**

Run:

```bash
bash tests/tmux-label-contract.sh
```

Expected: FAIL at `remote title reaches client displaying source window` because the current publisher reads an ambiguous client TTY from `display-message` and never enumerates matching clients.

- [ ] **Step 3: Separate source-pane metadata from client routing**

In `roles/common/files/bin/tmux-remote-title`, change `pane_info` to return:

```bash
pane_path, pane_tty, pane_command, edge_flags, source_session_id, source_window_id, pane_active
```

Use this live tmux format:

```bash
'#{pane_current_path}\t#{pane_tty}\t#{pane_current_command}\t#{?pane_at_left,h,}#{?pane_at_bottom,j,}#{?pane_at_top,k,}#{?pane_at_right,l,}\t#{session_id}\t#{window_id}\t#{pane_active}'
```

Keep the environment-injected path used by formatting tests when any injected pane metadata variable is present, returning empty IDs and active state `1` by default because `print` mode does not need client routing:

```bash
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "${TMUX_REMOTE_TITLE_PANE_PATH:-}" \
  "${TMUX_REMOTE_TITLE_PANE_TTY:-}" \
  "${TMUX_REMOTE_TITLE_PANE_COMMAND:-}" \
  "${TMUX_REMOTE_TITLE_EDGE_FLAGS:-}" \
  "${TMUX_REMOTE_TITLE_SESSION_ID:-}" \
  "${TMUX_REMOTE_TITLE_WINDOW_ID:-}" \
  "${TMUX_REMOTE_TITLE_PANE_ACTIVE:-1}"
```

Remove `client_tty` from `main` and parse the new fields explicitly.

- [ ] **Step 4: Implement matching-client publication**

Add these helpers before `main`:

```bash
matching_client_ttys() {
  local source_session_id="$1" source_window_id="$2"
  local client_tty client_session_id client_window_id

  tmux list-clients -F '#{client_tty}\t#{session_id}\t#{window_id}' 2>/dev/null |
    while IFS=$'\t' read -r client_tty client_session_id client_window_id; do
      [ -n "$client_tty" ] || continue
      [ "$client_session_id" = "$source_session_id" ] || continue
      [ "$client_window_id" = "$source_window_id" ] || continue
      printf '%s\n' "$client_tty"
    done
}

publish_title() {
  local title="$1" source_session_id="$2" source_window_id="$3" pane_active="$4"
  local client_tty

  [ "$pane_active" = "1" ] || return 0
  [ -n "$source_session_id" ] || return 0
  [ -n "$source_window_id" ] || return 0

  while IFS= read -r client_tty; do
    [ -n "$client_tty" ] || continue
    printf '\033]2;%s\033\\' "$title" > "$client_tty" 2>/dev/null || true
  done < <(matching_client_ttys "$source_session_id" "$source_window_id")
}
```

Change the `publish)` case to:

```bash
publish)
  publish_title "$title" "$source_session_id" "$source_window_id" "$pane_active"
  ;;
```

- [ ] **Step 5: Run focused verification**

Run:

```bash
bash tests/tmux-label-contract.sh
bash -n roles/common/files/bin/tmux-remote-title
```

Expected: all tmux label contract cases pass; Bash syntax check exits `0`.

- [ ] **Step 6: Run repository verification**

Run:

```bash
bin/test
bin/lint
ansible-playbook --syntax-check playbook.yml
git diff --check
```

Expected: every available repository command passes. If `bin/test` or `bin/lint` is not a supported entry point, use the repository's listed test commands and record the exact substitute rather than treating command absence as a product failure.

- [ ] **Step 7: Commit the implementation**

Use the `z-commit` skill to commit:

```text
roles/common/files/bin/tmux-remote-title
tests/tmux-label-contract.sh
```

Commit message:

```text
Route tmux titles to visible clients
```

- [ ] **Step 8: Review and open the PR**

Run the centralized `review` workflow against `main`, resolve any valid findings, rerun affected verification, then invoke the `pull-request` skill. Classify the change as non-visual; no screenshot proof is required. After merge, provision both the remote Linux development host and the local macOS machine so both ends use the current managed tmux helpers, then verify two simultaneous remote sessions keep independent outer window labels.
