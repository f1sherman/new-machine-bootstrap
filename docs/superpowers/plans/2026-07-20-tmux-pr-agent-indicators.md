# Tmux PR/Agent Indicator Rendering Implementation Plan (nmb side)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render 🤖/⏳ agent-activity and colored PR-state dots in tmux window names, sourced from pane options locally and from a `[nmb-ind=...]` title marker remotely.

**Architecture:** A new `tmux-indicator-glyphs` helper owns the state→glyph mapping. `tmux-window-label` prefixes glyphs onto the final window name (local pane options win; remote marker values are the fallback). `tmux-remote-title` appends the ASCII marker to published titles; parsing paths strip it like `[nmb-edge=...]`.

**Tech Stack:** Bash, tmux pane options, existing shell test harness (`tests/tmux-label-contract.sh`).

**Spec:** `docs/superpowers/specs/2026-07-20-tmux-pr-agent-indicators-design.md`

## Global Constraints

- Pane option names: `@agent_activity` (`working`|`waiting`), `@pr_state` (`draft`|`checks-failing`|`changes-requested`|`ready-for-review`|`approved`|`merged`|`closed`).
- Glyphs: working 🤖, waiting ⏳; draft ⚪, checks-failing 🔴, changes-requested 🟡, ready-for-review 🔵, approved 🟢, merged 🟣, closed ⚫.
- Marker: ` [nmb-ind=<activity>,<pr_state>]` (fields may be empty), appended before `append_edge_marker` runs.
- Absent options/marker → render exactly as today. Unknown values render nothing.
- All new tmux calls best-effort (`|| true`).

---

### Task 1: `tmux-indicator-glyphs` helper

**Files:**
- Create: `roles/common/files/bin/tmux-indicator-glyphs`
- Test: `tests/tmux-label-contract.sh` (append cases)

**Interfaces:**
- Produces: `tmux-indicator-glyphs <activity> <pr_state>` → prints glyph prefix with trailing space (e.g. `🤖🟢 `), empty output when both unmapped/empty; always exits 0.

- [ ] Step 1: add failing test cases to `tests/tmux-label-contract.sh` (near other pure-helper cases):

```bash
GLYPHS="$BIN_DIR/tmux-indicator-glyphs"
assert_equals "$("$GLYPHS" working approved)" "🤖🟢 " "indicator glyphs render working+approved"
assert_equals "$("$GLYPHS" waiting "")" "⏳ " "indicator glyphs render waiting only"
assert_equals "$("$GLYPHS" "" checks-failing)" "🔴 " "indicator glyphs render pr state only"
assert_equals "$("$GLYPHS" "" "")" "" "indicator glyphs render nothing when empty"
assert_equals "$("$GLYPHS" bogus nonsense)" "" "indicator glyphs ignore unknown values"
```

- [ ] Step 2: run `tests/tmux-label-contract.sh`, expect FAIL (helper missing)
- [ ] Step 3: implement:

```bash
#!/usr/bin/env bash
set -euo pipefail

activity="${1:-}"
pr_state="${2:-}"
out=""

case "$activity" in
  working) out+="🤖" ;;
  waiting) out+="⏳" ;;
esac

case "$pr_state" in
  draft) out+="⚪" ;;
  checks-failing) out+="🔴" ;;
  changes-requested) out+="🟡" ;;
  ready-for-review) out+="🔵" ;;
  approved) out+="🟢" ;;
  merged) out+="🟣" ;;
  closed) out+="⚫" ;;
esac

if [ -n "$out" ]; then
  printf '%s ' "$out"
fi
exit 0
```

`chmod +x`. Confirm provisioning copies it (bin dir is copied by glob — verify in `roles/common/tasks`).

- [ ] Step 4: run tests, expect PASS
- [ ] Step 5: commit

### Task 2: remote marker emission in `tmux-remote-title`

**Files:**
- Modify: `roles/common/files/bin/tmux-remote-title`
- Test: `tests/tmux-label-contract.sh`

**Interfaces:**
- Consumes: pane options `@agent_activity`, `@pr_state` (via `read_pane_option`), test env overrides `TMUX_REMOTE_TITLE_ACTIVITY`, `TMUX_REMOTE_TITLE_PR_STATE`.
- Produces: published/printed titles ending `... [nmb-ind=<activity>,<pr_state>]` (before the edge marker segment when both present).

- [ ] Step 1: failing tests (pattern-match existing `remote_edge_title` case):

```bash
remote_ind_title="$(TMUX_PANE= TMUX_REMOTE_TITLE_PANE_PATH="$repo_path" TMUX_REMOTE_TITLE_CLIENT_TTY=/dev/null TMUX_REMOTE_TITLE_PANE_TTY=/dev/null TMUX_REMOTE_TITLE_HOST_TAG=remote-host TMUX_REMOTE_TITLE_PANE_COMMAND=zsh TMUX_REMOTE_TITLE_ACTIVITY=working TMUX_REMOTE_TITLE_PR_STATE=draft "$REMOTE_TITLE" print)"
assert_equals "$remote_ind_title" "label-repo | remote-host [nmb-ind=working,draft]" "remote title publishes indicator marker"

remote_ind_edge_title="$(TMUX_PANE= TMUX_REMOTE_TITLE_PANE_PATH="$repo_path" TMUX_REMOTE_TITLE_CLIENT_TTY=/dev/null TMUX_REMOTE_TITLE_PANE_TTY=/dev/null TMUX_REMOTE_TITLE_HOST_TAG=remote-host TMUX_REMOTE_TITLE_PANE_COMMAND=tmux TMUX_REMOTE_TITLE_EDGE_FLAGS=hj TMUX_REMOTE_TITLE_ACTIVITY=waiting "$REMOTE_TITLE" print)"
assert_equals "$remote_ind_edge_title" "label-repo | remote-host [nmb-ind=waiting,] [nmb-edge=hj]" "indicator marker precedes edge marker"
```

- [ ] Step 2: run, expect FAIL
- [ ] Step 3: implement — extend `read_pane_option` env fallbacks and add `append_ind_marker`, called in `main` before `append_edge_marker`:

```bash
# in read_pane_option, after the worktree env fallbacks:
if [ "$option_name" = "@agent_activity" ] && [ -n "${TMUX_REMOTE_TITLE_ACTIVITY:-}" ]; then
  printf '%s\n' "$TMUX_REMOTE_TITLE_ACTIVITY"
  return 0
fi
if [ "$option_name" = "@pr_state" ] && [ -n "${TMUX_REMOTE_TITLE_PR_STATE:-}" ]; then
  printf '%s\n' "$TMUX_REMOTE_TITLE_PR_STATE"
  return 0
fi

append_ind_marker() {
  local title="$1" activity pr_state
  activity="$(read_pane_option "@agent_activity" 2>/dev/null || true)"
  pr_state="$(read_pane_option "@pr_state" 2>/dev/null || true)"
  if [ -n "$activity" ] || [ -n "$pr_state" ]; then
    printf '%s [nmb-ind=%s,%s]\n' "$title" "$activity" "$pr_state"
  else
    printf '%s\n' "$title"
  fi
}

# in main(), before: title="$(append_edge_marker ...)"
title="$(append_ind_marker "$title")"
```

- [ ] Step 4: run tests, expect PASS
- [ ] Step 5: commit

### Task 3: marker stripping in parse paths

**Files:**
- Modify: `roles/common/files/bin/tmux-task-label` (strip in `structured_remote_label`)
- Modify: `roles/common/files/bin/tmux-window-label` (strip + capture in main flow)
- Test: `tests/tmux-label-contract.sh`

**Interfaces:**
- Produces: `strip_ind_marker <title>` (both scripts) removes ` [nmb-ind=...]`; `tmux-window-label` captures marker values into `ind_activity`/`ind_pr_state` shell vars for Task 4.

- [ ] Step 1: failing test:

```bash
assert_equals "$($TASK_LABEL extract-remote '(feature/x) project | remote-host [nmb-ind=working,draft] [nmb-edge=hj]')" 'feature/x' "remote parser strips indicator marker"
```

- [ ] Step 2: run, expect FAIL
- [ ] Step 3: implement. In both scripts add (bash-compatible with each script's style):

```bash
strip_ind_marker() {
  local title="${1:-}"
  # marker may appear before the edge marker; strip wherever it sits
  printf '%s\n' "$title" | sed -E 's/ \[nmb-ind=[^]]*\]//'
}
```

`tmux-task-label`: call `strip_ind_marker` at the top of `structured_remote_label` (before `strip_edge_marker`). `tmux-window-label`: after reading `pane_title`/`window_name`, capture then strip:

```bash
ind_activity=""
ind_pr_state=""
capture_ind_marker() {
  local title="${1:-}" values
  case "$title" in
    *"[nmb-ind="*"]"*) ;;
    *) return 0 ;;
  esac
  values="${title##*\[nmb-ind=}"
  values="${values%%]*}"
  ind_activity="${values%%,*}"
  ind_pr_state="${values#*,}"
}
capture_ind_marker "$pane_title"
[ -n "$ind_activity$ind_pr_state" ] || capture_ind_marker "$window_name"
pane_title="$(strip_ind_marker "$pane_title")"
window_name="$(strip_ind_marker "$window_name")"
```

Also strip in the cached `@pane-label` branch before `task_from_remote_label`.

- [ ] Step 4: run tests, expect PASS
- [ ] Step 5: commit

### Task 4: glyph prefixing in `tmux-window-label`

**Files:**
- Modify: `roles/common/files/bin/tmux-window-label`
- Test: `tests/tmux-label-contract.sh`

**Interfaces:**
- Consumes: `tmux-indicator-glyphs` (Task 1), `ind_activity`/`ind_pr_state` (Task 3), local pane options `@agent_activity`/`@pr_state`.
- Produces: final window name `<glyphs> <label>`; unchanged label when no indicator state.

- [ ] Step 1: failing test. Use the existing tmux-stub pattern (`remote_task_tmux_dir` stub) extended so `show-options` answers `@agent_activity`/`@pr_state` from `TMUX_TEST_ACTIVITY`/`TMUX_TEST_PR_STATE`, and `display-message` returns a title carrying an ind marker; assert the stub-captured `rename-window` argument equals `🤖⚪ feature-branch` (exact expectation per stub fixture).
- [ ] Step 2: run, expect FAIL
- [ ] Step 3: implement — resolve helper next to `task_label_helper`:

```bash
glyphs_helper="${TMUX_INDICATOR_GLYPHS_BIN:-$script_dir/tmux-indicator-glyphs}"
[ -x "$glyphs_helper" ] || glyphs_helper="${HOME:-}/.local/bin/tmux-indicator-glyphs"
```

Just before `rename-window`:

```bash
activity="$(tmux show-options -qv -p -t "$pane_id" "@agent_activity" 2>/dev/null || true)"
pr_state="$(tmux show-options -qv -p -t "$pane_id" "@pr_state" 2>/dev/null || true)"
if [ -z "$activity" ] && [ -z "$pr_state" ]; then
  activity="$ind_activity"
  pr_state="$ind_pr_state"
fi
if [ -n "$activity" ] || [ -n "$pr_state" ]; then
  glyphs="$([ -x "$glyphs_helper" ] && "$glyphs_helper" "$activity" "$pr_state" 2>/dev/null || true)"
  label="${glyphs}${label}"
fi
```

(Keep the `label != window_name` early-exit after prefixing.)

- [ ] Step 4: run full `tests/tmux-label-contract.sh` + `tests/tmux-agent-state.sh`, expect PASS
- [ ] Step 5: commit

### Task 5: provision + end-to-end verify

- [ ] Step 1: `bin/provision --check --diff` then `bin/provision`; confirm `~/.local/bin/tmux-indicator-glyphs` installed and modified scripts deployed.
- [ ] Step 2: manual smoke: in a tmux pane run `tmux set-option -p @agent_activity working; tmux set-option -p @pr_state approved; tmux-window-label $TMUX_PANE` → tab shows `🤖🟢 ...`; unset both, rerun, tab reverts.
- [ ] Step 3: commit any fixups; open PR (nmb lands first — renderer is a no-op until producers ship).
