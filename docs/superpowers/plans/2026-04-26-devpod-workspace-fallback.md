# DevPod Workspace Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make tmux DevPod labels prefer the best available workspace identity so they degrade to bare `devpod` only as a last resort.

**Architecture:** Add one small shared DevPod-name helper under `roles/common/files/bin/`, install it with the other tmux helpers, and route the existing DevPod naming branches in `tmux-pane-label`, `tmux-remote-title`, and `tmux-session-name` through the same precedence chain. Lock the behavior with existing shell test harnesses before and after the implementation.

**Tech Stack:** Bash, tmux helper scripts, Ansible-managed file installs, shell test harnesses.

---

### Task 1: Lock the DevPod precedence chain in failing tests

**Files:**
- Modify: `roles/common/files/bin/tmux-pane-label.test`
- Modify: `roles/common/files/bin/tmux-remote-title.test`
- Modify: `roles/common/files/bin/tmux-session-name.test`

- [x] **Step 1: Add a red DevPod env-fallback case to `tmux-pane-label.test`**

Add a case where the process list proves DevPod, but the argv shape is not parseable by the current helper while `DEVPOD_WORKSPACE_ID` is present.

```bash
run_case \
  "devpod pane falls back to env workspace name" \
  "tty-devpod-env" \
  "$tmp_dir" \
  "ruby" \
  "tmp | workspace-beta" \
  "devpod ssh --agent workspace-beta" \
  "1" \
  "0"
```

Run it with the environment set in `run_case`:

```bash
DEVPOD_WORKSPACE_ID="${DEVPOD_WORKSPACE_ID:-workspace-beta}"
```

Expected today: FAIL because the script currently emits `devpod`.

- [x] **Step 2: Add a red DevPod env-fallback case to `tmux-remote-title.test`**

Add a case where `DEVPOD_WORKSPACE_ID` is set without a direct `TMUX_REMOTE_TITLE_HOST_TAG` override so the test proves the shared resolver preserves the same workspace name:

```bash
output="$(
  TMUX=/tmp/fake \
  TMUX_PANE=%91 \
  TMUX_REMOTE_TITLE_PANE_PATH="$TMPROOT/tmp-dir" \
  TMUX_REMOTE_TITLE_CLIENT_TTY="$TMPROOT/$label.client" \
  DEVPOD_WORKSPACE_ID=workspace-beta \
  "$SCRIPT" print
)"

assert_eq "$output" "tmp-dir | workspace-beta" "$label"
```

Expected today: either pass through the existing host-tag code or fail if the refactor breaks parity. This test becomes the contract that the new shared helper must preserve.

- [x] **Step 3: Add a red DevPod env-fallback case to `tmux-session-name.test`**

Add a DevPod-specific remote case where the pane title is just `workspace-beta`, the process list shows an unparseable DevPod ssh line, and `DEVPOD_WORKSPACE_ID=workspace-beta` is exported:

```bash
PATH="$fake_bin:$PATH" \
  TMUX=1 \
  TMPDIR="$tmp_root" \
  TMUX_LOG="$tmp_root/tmux-devpod.log" \
  TMUX_DISPLAY_OUTPUT=$'/dev/ttys004\t/tmp/repo\tworkspace-beta\t$1\tworkspace-beta' \
  PS_ARGS_OUTPUT="devpod ssh --agent workspace-beta" \
  DEVPOD_WORKSPACE_ID="workspace-beta" \
  HOSTNAME="local-host" \
  USER="brian" \
  bash "$script" "%14"
```

Assert the rename target uses the workspace name instead of a degraded fallback:

```bash
assert_file_contains "$tmp_root/tmux-devpod.log" "rename-session -t \$1 workspace-beta" "devpod env fallback preserves workspace session name"
```

Expected today: FAIL because the current code path does not consult one shared DevPod resolver.

- [x] **Step 4: Run the focused red tests**

Run:

```bash
bash roles/common/files/bin/tmux-pane-label.test
bash roles/common/files/bin/tmux-remote-title.test
bash roles/common/files/bin/tmux-session-name.test
```

Expected:

- `tmux-pane-label.test` fails on the new DevPod env-fallback case
- `tmux-session-name.test` fails on the new DevPod env-fallback case
- `tmux-remote-title.test` stays green or becomes the guardrail for parity during refactor

Actual on 2026-04-26:

- `bash roles/common/files/bin/tmux-pane-label.test` failed on `devpod pane falls back to env workspace name output` with `got: devpod`
- `bash roles/common/files/bin/tmux-session-name.test` failed on `devpod env fallback preserves workspace session name`
- `bash roles/common/files/bin/tmux-remote-title.test` passed all 6 assertions and stayed green

- [x] **Step 5: Commit the red tests**

```bash
git add \
  roles/common/files/bin/tmux-pane-label.test \
  roles/common/files/bin/tmux-remote-title.test \
  roles/common/files/bin/tmux-session-name.test
git -c commit.gpgsign=false commit -m "Add DevPod tmux fallback tests"
```

Committed as `c747e08` (`Add DevPod tmux fallback tests`).

### Task 2: Implement one shared DevPod resolver and switch the tmux consumers

**Files:**
- Create: `roles/common/files/bin/tmux-devpod-name`
- Modify: `roles/common/tasks/main.yml`
- Modify: `roles/common/files/bin/tmux-pane-label`
- Modify: `roles/common/files/bin/tmux-remote-title`
- Modify: `roles/common/files/bin/tmux-session-name`

- [x] **Step 1: Create `tmux-devpod-name`**

Add a small executable helper that accepts an optional full args line plus an optional host argument and resolves the best DevPod name in the approved order.

```bash
#!/usr/bin/env bash
set -euo pipefail

args="${1:-}"
ssh_host="${2:-}"

extract_devpod_workspace() {
  local line="$1" parts
  read -r -a parts <<< "$line"

  if [ "${#parts[@]}" -ge 3 ] && [ "${parts[0]}" = "devpod" ] && [ "${parts[1]}" = "ssh" ]; then
    case "${parts[2]}" in
      -*)
        return 1
        ;;
      *)
        printf '%s\n' "${parts[2]}"
        return 0
        ;;
    esac
  fi

  return 1
}

if workspace="$(extract_devpod_workspace "$args" 2>/dev/null)"; then
  printf '%s\n' "$workspace"
elif [ -n "${DEVPOD_WORKSPACE_ID:-}" ]; then
  printf '%s\n' "$DEVPOD_WORKSPACE_ID"
elif [ -n "$ssh_host" ]; then
  printf '%s\n' "$ssh_host"
else
  printf '%s\n' "devpod"
fi
```

- [x] **Step 2: Install the helper in `roles/common/tasks/main.yml`**

Add `tmux-devpod-name` to the existing tmux helper copy loop:

```yaml
  loop:
    - tmux-devpod-name
    - tmux-label-format
    - tmux-pane-label
    - tmux-window-label
    - tmux-sync-status-visibility
    - tmux-sync-pane-border-status
```

- [x] **Step 3: Replace inline DevPod fallback in `tmux-pane-label`**

Near the top of the script, resolve the helper path:

```bash
devpod_name_helper="${TMUX_DEVPOD_NAME_BIN:-$script_dir/tmux-devpod-name}"
[ -x "$devpod_name_helper" ] || devpod_name_helper="${HOME:-}/.local/bin/tmux-devpod-name"
```

In the DevPod branch, replace the current inline fallback:

```bash
    *"devpod ssh"*)
      label="$("$devpod_name_helper" "$line" "${TMUX_PANE_LABEL_HOST_TAG:-}" 2>/dev/null || true)"
      if [ -n "$label" ]; then
        label="$(remote_label "$pane_current_path" "$label")"
      else
        label="devpod"
      fi
      break
      ;;
```

Keep the rest of the remote/local fast paths unchanged.

- [x] **Step 4: Switch `tmux-remote-title` to the same helper**

Resolve the helper path near the existing `label_formatter` setup:

```bash
devpod_name_helper="${TMUX_DEVPOD_NAME_BIN:-$script_dir/tmux-devpod-name}"
[ -x "$devpod_name_helper" ] || devpod_name_helper="${HOME:-}/.local/bin/tmux-devpod-name"
```

Update `host_tag()` so the DevPod branch routes through the helper instead of reading the env var directly:

```bash
  elif [ -n "${DEVPOD_WORKSPACE_ID:-}" ]; then
    "$devpod_name_helper" "" "" 2>/dev/null
  elif [ -n "${SSH_CONNECTION:-}" ]; then
    hostname -s 2>/dev/null
  fi
```

Do not change Codespaces precedence or the explicit-worktree title flow.

- [x] **Step 5: Narrow-patch `tmux-session-name` to reuse the helper**

Resolve the helper path near `label_formatter`:

```bash
devpod_name_helper="${TMUX_DEVPOD_NAME_BIN:-$script_dir/tmux-devpod-name}"
[ -x "$devpod_name_helper" ] || devpod_name_helper="${HOME:-}/.local/bin/tmux-devpod-name"
```

In the existing remote branch, derive a DevPod-aware remote name before the `pane_title` logic:

```bash
devpod_name=""
if [ -n "$is_devpod" ]; then
  devpod_line="$(grep -E 'devpod ssh' <<< "$pane_procs" | head -1)"
  devpod_name="$("$devpod_name_helper" "$devpod_line" "${ssh_host:-}" 2>/dev/null || true)"
fi
```

Then keep the current structured-title protection, but use `devpod_name` where the code currently falls back to plain title/host behavior for DevPod:

```bash
        elif [ -n "$is_devpod" ] && [ -n "$devpod_name" ]; then
          name="$devpod_name"
        elif [ -z "$is_codespace" ] && [ -z "$is_devpod" ] && [ -n "$ssh_host" ] && [ "$pane_title" != "$ssh_host" ]; then
          name="$ssh_host | $pane_title"
```

Leave non-DevPod SSH behavior alone.

- [x] **Step 6: Run the focused green tests**

Run:

```bash
bash roles/common/files/bin/tmux-pane-label.test
bash roles/common/files/bin/tmux-remote-title.test
bash roles/common/files/bin/tmux-session-name.test
```

Expected: all pass.

Actual on 2026-04-26:

- `bash roles/common/files/bin/tmux-pane-label.test` passed all cases
- `bash roles/common/files/bin/tmux-remote-title.test` passed all 6 assertions
- `bash roles/common/files/bin/tmux-session-name.test` passed all 8 assertions

- [x] **Step 7: Commit the implementation**

```bash
git add \
  roles/common/files/bin/tmux-devpod-name \
  roles/common/tasks/main.yml \
  roles/common/files/bin/tmux-pane-label \
  roles/common/files/bin/tmux-remote-title \
  roles/common/files/bin/tmux-session-name \
  roles/common/files/bin/tmux-pane-label.test \
  roles/common/files/bin/tmux-remote-title.test \
  roles/common/files/bin/tmux-session-name.test
git -c commit.gpgsign=false commit -m "Improve DevPod tmux label fallback"
```

Committed as `b396f6f` (`Improve DevPod tmux label fallback`).

### Task 3: Verify adjacent tmux helpers and provision the managed scripts

**Files:**
- Test: `roles/common/files/bin/tmux-window-label.test`
- Test: `roles/common/files/bin/tmux-window-bar-config.test`
- Test: `roles/common/files/bin/tmux-host-tag`

- [x] **Step 1: Run adjacent tmux regression tests**

Run:

```bash
bash roles/common/files/bin/tmux-window-label.test
bash roles/common/files/bin/tmux-window-bar-config.test
```

Expected: both pass, proving the label contract still matches the managed tmux setup.

Actual on 2026-04-26:

- `bash roles/common/files/bin/tmux-window-label.test` passed all 15 assertions
- `bash roles/common/files/bin/tmux-window-bar-config.test` passed with `passed=49 failed=0`

- [x] **Step 2: Apply the updated managed files locally**

Run:

```bash
bin/provision
```

Expected: exit `0` and copy the updated tmux helpers into `~/.local/bin/`.

Actual on 2026-04-26:

- `bin/provision` reached the managed helper install steps and copied the updated tmux scripts into `~/.local/bin/`
- the play then failed later in an unrelated macOS Node install step:
  `mise ERROR gpg failed`
- failing task:
  `macos : Install pinned Node.js version if not installed`
- observed root cause in stderr:
  `gpg: ... waiting for lock (held by 35609)`

- [x] **Step 3: Run the full verification batch**

Run:

```bash
bash roles/common/files/bin/tmux-pane-label.test && \
bash roles/common/files/bin/tmux-remote-title.test && \
bash roles/common/files/bin/tmux-session-name.test && \
bash roles/common/files/bin/tmux-window-label.test && \
bash roles/common/files/bin/tmux-window-bar-config.test
```

Expected: exit `0` with all harnesses reporting pass counts and zero failures.

Actual on 2026-04-26:

- ran the full batch command exactly as written; exit `0`
- `tmux-pane-label.test`: passed all cases
- `tmux-remote-title.test`: passed all 6 assertions
- `tmux-session-name.test`: passed all 8 assertions
- `tmux-window-label.test`: passed all 15 assertions
- `tmux-window-bar-config.test`: `passed=49 failed=0`

- [x] **Step 4: Update this plan with actual results and completed checkboxes**

Record the exact commands run and whether they passed in this file before handing off for PR creation.

- [ ] **Step 5: Commit the verification updates if this plan changed**

```bash
git add docs/superpowers/plans/2026-04-26-devpod-workspace-fallback.md
git -c commit.gpgsign=false commit -m "Record DevPod tmux fallback verification"
```
