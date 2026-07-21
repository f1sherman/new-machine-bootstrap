# Tmux PR Status Colors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace fixed-color PR circle emoji in tmux tabs with a text dot styled to match Pi's PR-link palette.

**Architecture:** Keep activity and PR state transport unchanged. Convert state to tmux format syntax in `tmux-indicator-glyphs`, store the formatted prefix in the window-scoped `@window-indicators` option, and expand that option from both platform tmux status formats while keeping `window_name` plain.

**Tech Stack:** Bash, tmux format strings, shell contract tests, Ansible-managed tmux configuration.

## Global Constraints

- Preserve `@agent_activity`, `@pr_state`, and `[nmb-ind=<activity>,<pr_state>]` contracts.
- Match Pi dark-theme colors exactly: draft `#808080`, checks failing `#cc6666`, changes requested `#ffff00`, ready `#8abeb7`, approved `#b5bd68`, merged `#8957e5`, closed `#cf4f4f` plus dim.
- Keep styled format syntax out of `window_name`.
- Apply identical behavior on macOS and Linux.
- Unknown or absent states render no PR indicator.

---

### Task 1: Render and Store Styled PR Indicators

**Files:**
- Modify: `roles/common/files/bin/tmux-indicator-glyphs`
- Modify: `roles/common/files/bin/tmux-window-label`
- Modify: `roles/macos/templates/dotfiles/tmux.conf`
- Modify: `roles/linux/files/dotfiles/tmux.conf`
- Test: `tests/tmux-label-contract.sh`

**Interfaces:**
- Consumes: activity and PR state positional arguments; existing local pane options and remote marker state.
- Produces: a tmux-format prefix containing the activity emoji and/or styled `●`; window-scoped `@window-indicators`; plain `window_name`; status formats that expand the option.

- [ ] **Step 1: Replace direct helper assertions with failing palette assertions**

Use these exact assertions:

```bash
assert_equals "$("$GLYPHS" working approved)" '🤖#[fg=#b5bd68]● ' "indicator glyphs render working+approved"
assert_equals "$("$GLYPHS" waiting "")" "⏳ " "indicator glyphs render waiting only"
assert_equals "$("$GLYPHS" "" draft)" '#[fg=#808080]● ' "draft indicator matches Pi muted"
assert_equals "$("$GLYPHS" "" checks-failing)" '#[fg=#cc6666]● ' "checks-failing indicator matches Pi error"
assert_equals "$("$GLYPHS" "" changes-requested)" '#[fg=#ffff00]● ' "changes-requested indicator matches Pi warning"
assert_equals "$("$GLYPHS" "" ready-for-review)" '#[fg=#8abeb7]● ' "ready indicator matches Pi accent"
assert_equals "$("$GLYPHS" "" approved)" '#[fg=#b5bd68]● ' "approved indicator matches Pi success"
assert_equals "$("$GLYPHS" "" merged)" '#[fg=#8957e5]● ' "merged indicator matches Pi purple"
assert_equals "$("$GLYPHS" "" closed)" '#[fg=#cf4f4f,dim]● ' "closed indicator matches Pi dim red"
assert_equals "$("$GLYPHS" "" "")" "" "indicator glyphs render nothing when empty"
assert_equals "$("$GLYPHS" bogus nonsense)" "" "indicator glyphs ignore unknown values"
```

- [ ] **Step 2: Extend the fake tmux and replace window-label assertions**

Add option logging to the fake tmux:

```bash
  set-option)
    printf '%s\n' "$*" >> "$TMUX_WINDOW_LABEL_LOG"
    ;;
```

Require remote, local, and local-over-remote cases to store the styled option while renaming with a plain label:

```bash
assert_file_contains "$window_log" "set-option -wq -t @1 @window-indicators 🤖#[fg=#808080]● " "remote marker stores formatted indicators"
assert_file_contains "$window_log" "rename-window -t @1 feature/remote" "remote marker keeps window name plain"
assert_file_contains "$window_log" "set-option -wq -t @1 @window-indicators ⏳#[fg=#b5bd68]● " "local pane state stores formatted indicators"
assert_file_contains "$window_log" "rename-window -t @1 feature/remote" "local pane state keeps window name plain"
assert_file_contains "$window_log" "set-option -wq -t @1 @window-indicators ⏳ " "local pane state wins over remote marker"
assert_file_contains "$window_log" "rename-window -t @1 feature/remote" "local precedence keeps window name plain"
```

Add a no-state invocation that expects cleanup:

```bash
assert_file_contains "$window_log" "set-option -wqu -t @1 @window-indicators" "missing state clears formatted indicators"
```

- [ ] **Step 3: Add failing configuration assertions for both platforms**

For each tmux config, require these exact format fragments:

```bash
'#{E:@window-indicators}#[fg=colour252,nodim]#{window_name}'
'#{E:@window-indicators}#[fg=black,nodim]#{window_name}'
```

Inactive format restores `colour252`; current format restores `black`. Both restore `nodim` to reset closed-state intensity before the plain label and bell marker.

- [ ] **Step 4: Run the contract test and verify the new assertions fail**

Run: `./tests/tmux-label-contract.sh`

Expected: first new helper assertion fails because the helper still emits colored-circle emoji.

- [ ] **Step 5: Implement exact state-to-style mapping**

Replace the PR-state case in `tmux-indicator-glyphs` with:

```bash
case "$pr_state" in
  draft) out+='#[fg=#808080]●' ;;
  checks-failing) out+='#[fg=#cc6666]●' ;;
  changes-requested) out+='#[fg=#ffff00]●' ;;
  ready-for-review) out+='#[fg=#8abeb7]●' ;;
  approved) out+='#[fg=#b5bd68]●' ;;
  merged) out+='#[fg=#8957e5]●' ;;
  closed) out+='#[fg=#cf4f4f,dim]●' ;;
esac
```

Keep existing activity mapping and trailing-space behavior.

- [ ] **Step 6: Store or clear formatted indicators instead of prefixing the label**

In `tmux-window-label`, replace `label="${glyphs}${label}"` with:

```bash
glyphs=""
if { [ -n "$activity" ] || [ -n "$pr_state" ]; } && [ -x "$glyphs_helper" ]; then
  glyphs="$("$glyphs_helper" "$activity" "$pr_state" 2>/dev/null || true)"
fi
if [ -n "$glyphs" ]; then
  tmux set-option -wq -t "$window_id" @window-indicators "$glyphs" 2>/dev/null || true
else
  tmux set-option -wqu -t "$window_id" @window-indicators 2>/dev/null || true
fi
```

Leave `label` plain. Perform option management before the existing rename equality check so state cleanup still occurs when the label itself is unchanged.

- [ ] **Step 7: Expand and contain indicator styles in both tmux configs**

Use these exact lines in both platform files:

```tmux
set -g window-status-format ' #{E:@window-indicators}#[fg=colour252,nodim]#{window_name}#{?window_bell_flag,!,} '
set -g window-status-current-format ' #{E:@window-indicators}#[fg=black,nodim]#{window_name}#{?window_bell_flag,!,} '
```

Foreground and `nodim` restoration occurs after indicator expansion and before the plain name, preserving each tab's existing background and bold style while resetting closed-state intensity before the label and bell marker.

- [ ] **Step 8: Run the full contract test**

Run: `./tests/tmux-label-contract.sh`

Expected: all checks pass and output ends with `tmux label contract checks complete`.

- [ ] **Step 9: Commit the complete renderer behavior**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Align tmux PR indicators with Pi colors" \
  roles/common/files/bin/tmux-indicator-glyphs \
  roles/common/files/bin/tmux-window-label \
  roles/macos/templates/dotfiles/tmux.conf \
  roles/linux/files/dotfiles/tmux.conf \
  tests/tmux-label-contract.sh
```

---

### Task 2: Verify Provisioned and Live Tmux Behavior

**Files:**
- No source files modified.

**Interfaces:**
- Consumes: committed helper, window renderer, and platform config.
- Produces: empirical verification that source tests, provisioning, and live tmux format expansion work.

- [ ] **Step 1: Run static and contract verification**

```bash
./tests/tmux-label-contract.sh
git diff --check main...HEAD
git status --short
```

Expected: contract suite completes; no diff-check errors; clean worktree.

- [ ] **Step 2: Provision NMB from the feature worktree**

Run: `bin/provision`

Expected: successful Ansible recap with `failed=0`; managed helper and tmux config installed from this worktree.

- [ ] **Step 3: Reload tmux and force a live refresh**

```bash
tmux source-file ~/.tmux.conf
tmux-window-label "$TMUX_PANE"
```

Expected: both commands exit zero.

- [ ] **Step 4: Inspect live option and format expansion**

```bash
tmux show-options -wqv -t "$TMUX_PANE" @window-indicators
tmux display-message -p -t "$TMUX_PANE" '#{E:@window-indicators}#[fg=black,nodim]#{window_name}'
```

Expected: when this pane has PR state, the option contains an activity emoji and/or `#[fg=#RRGGBB]● ` while `#{window_name}` stays plain. Tmux expands the option in the tab rather than displaying raw syntax.

- [ ] **Step 5: Inspect the complete branch diff**

```bash
git status --short --branch
git log --oneline main..HEAD
git diff --stat main...HEAD
git diff main...HEAD
```

Expected: only the approved spec, plan, helper, renderer, platform configs, and contract tests differ from `main`.
