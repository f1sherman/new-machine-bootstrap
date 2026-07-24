# Tmux Bell Indicator Style Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep inline PR-state dot colors as foreground colors and label text dark when tmux highlights a window with a bell.

**Architecture:** Replace tmux's inherited reverse bell style with the same explicit cyan-background, black-foreground style used for current and activity-highlighted windows. Make the normal window format restore dark text for activity or bell highlights and light text only for ordinary inactive windows. Lock both behaviors into the existing tmux configuration contract for both supported platforms.

**Tech Stack:** tmux configuration, Bash contract tests, Ansible provisioning

## Global Constraints

- Apply the style to both macOS and Linux managed tmux configurations.
- Preserve bell highlighting and the trailing `!` marker.
- Do not change indicator glyph generation or state publication.
- Use `bg=colour51,fg=black,bold` exactly.
- After indicators, use `fg=black,nodim` when either `window_activity_flag` or `window_bell_flag` is true.
- Preserve `fg=colour252,nodim` for ordinary inactive windows.

---

### Task 1: Prevent reverse styling on bell-highlighted tabs

**Files:**
- Modify: `tests/tmux-label-contract.sh`
- Modify: `roles/macos/templates/dotfiles/tmux.conf`
- Modify: `roles/linux/files/dotfiles/tmux.conf`

**Interfaces:**
- Consumes: tmux `window-status-bell-style` and existing `@window-indicators` format expansion.
- Produces: identical explicit bell styling on macOS and Linux.

- [ ] **Step 1: Write the failing contract assertions**

In the tmux config assertion loop in `tests/tmux-label-contract.sh`, add:

```bash
assert_file_contains "$tmux_config" \
  "set -g window-status-bell-style 'bg=colour51,fg=black,bold'" \
  "$tmux_config bell highlight preserves indicator foreground colors"
```

- [ ] **Step 2: Run the contract test and verify RED**

Run:

```bash
tests/tmux-label-contract.sh
```

Expected: two failures stating that the macOS and Linux tmux configs do not yet preserve indicator foreground colors for bell highlights.

- [ ] **Step 3: Add the explicit bell style**

After `window-status-activity-style` in each managed tmux config, add:

```tmux
set -g window-status-bell-style 'bg=colour51,fg=black,bold'
```

- [ ] **Step 4: Run focused and behavioral verification**

Run:

```bash
tests/tmux-label-contract.sh
```

Expected: exit 0 with both new bell-style checks passing.

Then start a temporary tmux server, load the managed config, set a purple indicator on a bell-marked window, and inspect the configured style:

```bash
socket="nmb-bell-style-$$"
tmux -L "$socket" -f /dev/null new-session -d -s bell-style
tmux -L "$socket" source-file roles/macos/templates/dotfiles/tmux.conf
tmux -L "$socket" set-window-option -t bell-style:0 @window-indicators '#[fg=#8957e5]● '
tmux -L "$socket" display-message -p -t bell-style:0 '#{window-status-bell-style}|#{E:@window-indicators}'
tmux -L "$socket" kill-server
```

Expected:

```text
bg=colour51,fg=black,bold|#[fg=#8957e5]●<space>
```

- [ ] **Step 5: Provision and verify live state**

Run:

```bash
bin/provision
tmux show-options -gwv window-status-bell-style
```

Expected provisioning exit 0, followed by:

```text
bg=colour51,fg=black,bold
```

- [ ] **Step 6: Commit**

```bash
git add tests/tmux-label-contract.sh roles/macos/templates/dotfiles/tmux.conf roles/linux/files/dotfiles/tmux.conf
git commit -m "Preserve tmux indicator colors on bell tabs"
```

### Task 2: Preserve bell-highlight label contrast

**Files:**
- Modify: `tests/tmux-label-contract.sh`
- Modify: `roles/macos/templates/dotfiles/tmux.conf`
- Modify: `roles/linux/files/dotfiles/tmux.conf`
- Modify: `docs/superpowers/specs/2026-07-23-tmux-bell-indicator-style-design.md`
- Modify: `docs/superpowers/plans/2026-07-23-tmux-bell-indicator-style.md`

**Interfaces:**
- Consumes: tmux `window_activity_flag`, `window_bell_flag`, and normal `window-status-format`.
- Produces: dark label text for activity or bell highlights, with light text retained for ordinary inactive windows.

- [ ] **Step 1: Require the combined activity-or-bell condition**

Update the cross-platform assertion to require:

```bash
assert_file_contains "$config" '#{E:@window-indicators}#{?#{||:#{window_activity_flag},#{window_bell_flag}},#[fg=black#,nodim],#[fg=colour252#,nodim]}#{window_name}' "$config inactive window restores activity-or-bell-aware text color and intensity"
```

- [ ] **Step 2: Run the contract test and verify RED**

Run:

```bash
tests/tmux-label-contract.sh
```

Expected: exit 1 because the macOS config still restores black text only for `window_activity_flag`.

- [ ] **Step 3: Update both normal window formats**

Use this format in both managed tmux configs:

```tmux
set -g window-status-format ' #{E:@window-indicators}#{?#{||:#{window_activity_flag},#{window_bell_flag}},#[fg=black#,nodim],#[fg=colour252#,nodim]}#{window_name}#{?window_bell_flag,!,} '
```

- [ ] **Step 4: Verify GREEN and whitespace**

Run:

```bash
tests/tmux-label-contract.sh
git diff --check
```

Expected: both commands exit 0, including macOS and Linux activity-or-bell-aware text checks.
