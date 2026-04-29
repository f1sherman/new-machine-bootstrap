# Tmux Session-Name Status-Left Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a bright-green session-name block to the left edge of the top tmux status bar, pushing the window list right by the block width plus one space.

**Architecture:** Pure tmux config change — replace `status-left ''` and `status-left-length 0` with a styled `#S` block in both `tmux.conf` files (macOS template + Linux static). The existing parity test is extended with two `assert_contains` assertions inside its `assert_tmux_file` helper so both files stay in lockstep.

**Tech Stack:** tmux config, bash test harness.

**Spec:** `docs/superpowers/specs/2026-04-29-tmux-session-name-status-left-design.md`

**Working directory:** `/Users/brianjohn/projects/new-machine-bootstrap/.worktrees/tmux-session-name-status-left`

---

## File Structure

- **Modify:** `roles/common/files/bin/tmux-window-bar-config.test` — add 2 assertions inside `assert_tmux_file`
- **Modify:** `roles/macos/templates/dotfiles/tmux.conf` — replace `status-left` and `status-left-length` lines
- **Modify:** `roles/linux/files/dotfiles/tmux.conf` — same replacement

---

### Task 1: Add failing test assertions (RED)

**Files:**
- Modify: `roles/common/files/bin/tmux-window-bar-config.test` — inside `assert_tmux_file()`, after the existing status-bar assertions

- [ ] **Step 1: Add the two new assertions to `assert_tmux_file`**

Open `roles/common/files/bin/tmux-window-bar-config.test`. Locate the `assert_tmux_file()` function. After the line:

```bash
  assert_contains "$file" 'set -g status-right-length 80'
```

insert these two lines:

```bash
  assert_contains "$file" "set -g status-left '#[bg=colour46,fg=black,bold] ❮ #S ❯ #[default] '"
  assert_contains "$file" "set -g status-left-length 50"
```

(The single-quoted outer string lets the inner `'` characters be embedded without escaping. `assert_contains` uses `grep -Fq`, so the `❮` / `❯` literals are matched verbatim.)

- [ ] **Step 2: Run test, verify it fails for both files**

Run: `bash roles/common/files/bin/tmux-window-bar-config.test`

Expected output (truncated): four `FAIL` lines — two for each file (`roles/macos/templates/dotfiles/tmux.conf` and `roles/linux/files/dotfiles/tmux.conf`), one per new assertion. The script exits with status 1.

Do **not** commit yet — RED stage. The configs will catch up in Task 2.

---

### Task 2: Update both tmux.conf files (GREEN)

**Files:**
- Modify: `roles/macos/templates/dotfiles/tmux.conf:95,97` (the `status-left ''` and `status-left-length 0` lines)
- Modify: `roles/linux/files/dotfiles/tmux.conf` (same two lines — line numbers may differ, locate by content)

- [ ] **Step 1: Edit the macOS template**

In `roles/macos/templates/dotfiles/tmux.conf`, replace:

```
set -g status-left ''
```

with:

```
set -g status-left '#[bg=colour46,fg=black,bold] ❮ #S ❯ #[default] '
```

And replace:

```
set -g status-left-length 0
```

with:

```
set -g status-left-length 50
```

- [ ] **Step 2: Edit the Linux static file**

In `roles/linux/files/dotfiles/tmux.conf`, make the identical two replacements. Use `grep -n "status-left" roles/linux/files/dotfiles/tmux.conf` first to confirm the lines exist verbatim.

- [ ] **Step 3: Run the parity test, verify it passes**

Run: `bash roles/common/files/bin/tmux-window-bar-config.test`

Expected: every line `PASS`, final summary `passed=N failed=0`, exit status 0.

If any assertion still fails, fix the offending file (most likely a typo in the unicode brackets — verify by running `grep -F '❮ #S ❯' roles/{macos/templates,linux/files}/dotfiles/tmux.conf` and confirming both files match).

- [ ] **Step 4: Run all bin tests for safety**

Some related tests assert other things about these files (e.g., `terminal-restore-config.test`). Run the full bin test suite to make sure nothing else regressed:

Run: `for t in roles/common/files/bin/*.test; do echo "=== $t ==="; bash "$t" || exit 1; done`

Expected: every test exits 0.

- [ ] **Step 5: Commit**

```bash
git add roles/common/files/bin/tmux-window-bar-config.test \
        roles/macos/templates/dotfiles/tmux.conf \
        roles/linux/files/dotfiles/tmux.conf
```

Then invoke the `_commit` skill (per repo policy — do not call `git commit` directly).

Suggested commit subject: `Add session-name block to top tmux status bar (left)`

---

### Task 3: End-to-end verification (live tmux)

**Files:** none (runtime check only)

- [ ] **Step 1: Apply via provision**

Run from the worktree root:

```bash
bin/provision
```

The macOS role re-templates `~/.tmux.conf` and its handler runs `tmux source-file ~/.tmux.conf` automatically. (On a Linux dev host, the linux role does the equivalent.)

Expected: provision exits 0; the `Reload tmux config` handler shows as triggered.

- [ ] **Step 2: Eyeball the live status bar**

In any tmux session, look at the top status bar. Confirm:
- Left edge has a bright-green block with bold black text reading ` ❮ <session-name> ❯ `
- One space of black bar between the block and the first window tab
- The window list is shifted right; nothing on the right side moved
- The hook-error badge (if `@hook-last-error` is set) still renders unchanged on the far right

- [ ] **Step 3: Confirm the format value programmatically**

Run:

```bash
tmux show-options -gv status-left
tmux show-options -gv status-left-length
```

Expected output:
```
#[bg=colour46,fg=black,bold] ❮ #S ❯ #[default] 
50
```

(Trailing space after `#[default]` is intentional.)

- [ ] **Step 4: Rename a session and confirm the block updates**

```bash
tmux rename-session -t '$<current-id>' brainstorm-test
```

Expected: green block immediately re-renders as ` ❮ brainstorm-test ❯ `. Rename it back when done.

---

### Task 4: Push and open PR

- [ ] **Step 1: Push the branch**

```bash
git push -u origin tmux-session-name-status-left
```

- [ ] **Step 2: Open PR**

Invoke the `_pull-request` skill (per user CLAUDE.md — `create-pull-request` is the user-defined alias for this). The PR description should:
- Reference the spec at `docs/superpowers/specs/2026-04-29-tmux-session-name-status-left-design.md`
- Include a one-line summary: green session-name block in the top status bar, parity test extended
- Test plan checklist:
  - [ ] `bash roles/common/files/bin/tmux-window-bar-config.test` passes
  - [ ] `bin/provision` re-templates `~/.tmux.conf` and reloads tmux
  - [ ] Green block renders on the left of the top status bar
  - [ ] Window list slides right; right-side hook-error badge unchanged

---

## Self-Review

Spec coverage:
- Spec "Format change" → Task 2 steps 1–2.
- Spec "Files" → Task 2 covers both files.
- Spec "Test parity" → Task 1 (assertions added), Task 2 step 3 (assertions pass).
- Spec "Apply" → Task 3 step 1 (`bin/provision`).
- Spec "Visual" / "Interaction with existing config" → Task 3 step 2 (eyeball), step 4 (rename test).

No placeholders. Type/identifier consistency: the bracketed format string `'#[bg=colour46,fg=black,bold] ❮ #S ❯ #[default] '` and length `50` appear identically in spec, test, and both config files.
