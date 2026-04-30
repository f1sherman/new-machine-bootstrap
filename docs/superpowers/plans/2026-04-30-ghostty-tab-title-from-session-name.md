# Ghostty Tab Title From Session Name Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pin the Ghostty tab title to the local tmux session name (`#S`) by disabling tmux's DCS passthrough, so inner programs (Claude Code, vim, etc.) can no longer override the outer terminal title.

**Architecture:** Pure tmux config change. Flip `set -g allow-passthrough all` → `set -g allow-passthrough off` in `roles/macos/templates/dotfiles/tmux.conf`, and add the same explicit setting (currently absent) to `roles/linux/files/dotfiles/tmux.conf` for parity. tmux's existing `set-titles-string '#S'` becomes the sole authority for the tab title. The `tmux-window-bar-config.test` parity test gets two new assertions per file.

**Tech Stack:** tmux config, bash test harness, Ansible (for `bin/provision` to re-template `~/.tmux.conf`).

**Spec:** `docs/superpowers/specs/2026-04-30-ghostty-tab-title-from-session-name-design.md`

**Working directory:** `/Users/brianjohn/projects/new-machine-bootstrap/.worktrees/ghostty-tab-title-from-session-name`

---

## File Structure

- **Modify:** `roles/common/files/bin/tmux-window-bar-config.test` — add three assertions (one positive, two negative) inside `assert_tmux_file`.
- **Modify:** `roles/macos/templates/dotfiles/tmux.conf` — replace existing comment + option line at line 168–169.
- **Modify:** `roles/linux/files/dotfiles/tmux.conf` — add new comment + option line (currently absent; tmux default is `off` but we set it explicitly for parity).

---

### Task 1: Add failing test assertions (RED)

**Files:**
- Modify: `roles/common/files/bin/tmux-window-bar-config.test` — inside `assert_tmux_file()`, after the existing assertions

- [ ] **Step 1: Add three assertions to `assert_tmux_file`**

Open `roles/common/files/bin/tmux-window-bar-config.test`. Locate the `assert_tmux_file()` function. After the line:

```bash
  assert_not_contains "$file" 'tmux-host-tag'
```

(this is currently the last line inside the function, just before the closing `}`), insert these three lines:

```bash
  assert_contains "$file" 'set -g allow-passthrough off'
  assert_not_contains "$file" 'allow-passthrough all'
  assert_not_contains "$file" 'allow-passthrough on'
```

Note on the negative assertions: `assert_not_contains` uses `grep -Fq`, which is a fixed-string substring match. The string `'allow-passthrough all'` is a strict substring of neither `'allow-passthrough off'` nor any other value we want to allow, so the negative test correctly fails only when the explicit forbidden value is present. Same for `'allow-passthrough on'`.

- [ ] **Step 2: Run the test, verify it fails for both files**

Run: `bash roles/common/files/bin/tmux-window-bar-config.test`

Expected output: at least three FAIL lines:
- macOS file: FAIL on missing `set -g allow-passthrough off`
- macOS file: FAIL on unexpectedly contains `allow-passthrough all` (the current state on line 169)
- Linux file: FAIL on missing `set -g allow-passthrough off`

The script exits with status 1.

Do **not** commit yet — RED stage. The configs catch up in Task 2.

---

### Task 2: Update both tmux.conf files (GREEN)

**Files:**
- Modify: `roles/macos/templates/dotfiles/tmux.conf:168-169`
- Modify: `roles/linux/files/dotfiles/tmux.conf` (add new lines, exact location: just below the line `set -g visual-activity off`, which currently sits at line 116)

- [ ] **Step 1: Edit the macOS template**

In `roles/macos/templates/dotfiles/tmux.conf`, replace these two lines (currently at 168 and 169):

```
# Allow escape sequences (notifications, progress bars) to pass through to the outer terminal
set -g allow-passthrough all
```

with:

```
# Block inner programs from bypassing tmux to talk directly to the outer
# terminal. Keeps the Ghostty tab title pinned to '#S' instead of letting
# Claude Code, vim, ssh, etc. override it via DCS-wrapped OSC 2.
set -g allow-passthrough off
```

- [ ] **Step 2: Edit the Linux static file**

The Linux config does not currently set `allow-passthrough` at all (tmux default is `off`). Add the same comment + setting for explicit parity.

Open `roles/linux/files/dotfiles/tmux.conf`. Locate the line:

```
set -g visual-activity off
```

Insert the following block immediately after it (preserve the blank-line spacing pattern of the surrounding file):

```

# Block inner programs from bypassing tmux to talk directly to the outer
# terminal. Keeps the Ghostty tab title pinned to '#S' instead of letting
# Claude Code, vim, ssh, etc. override it via DCS-wrapped OSC 2.
set -g allow-passthrough off
```

- [ ] **Step 3: Run the parity test, verify it passes**

Run: `bash roles/common/files/bin/tmux-window-bar-config.test`

Expected: every line `PASS`, final summary `passed=N failed=0`, exit status 0.

If any assertion still fails, re-check both files with:

```bash
grep -n 'allow-passthrough' roles/macos/templates/dotfiles/tmux.conf roles/linux/files/dotfiles/tmux.conf
```

Each file should show exactly one match: `set -g allow-passthrough off`.

- [ ] **Step 4: Run the full bin test suite**

Other tests assert various things about these tmux config files. Run them all to make sure nothing regressed:

Run: `for t in roles/common/files/bin/*.test; do echo "=== $t ==="; bash "$t" || exit 1; done`

Expected: every test exits 0.

- [ ] **Step 5: Commit**

```bash
git add roles/common/files/bin/tmux-window-bar-config.test \
        roles/macos/templates/dotfiles/tmux.conf \
        roles/linux/files/dotfiles/tmux.conf
```

Then invoke the `_commit` skill (per repo policy — do not call `git commit` directly).

Suggested commit subject: `Pin Ghostty tab title to tmux session name (allow-passthrough off)`

---

### Task 3: End-to-end verification (live tmux on the Mac)

**Files:** none (runtime check only).

This task does not modify code. It runs the live verification steps from the spec to confirm the change actually changes Ghostty's behavior.

- [ ] **Step 1: Apply via provision**

Run from the worktree root:

```bash
bin/provision
```

The macOS role re-templates `~/.tmux.conf` from `roles/macos/templates/dotfiles/tmux.conf` and its handler runs `tmux source-file ~/.tmux.conf` automatically.

Expected: provision exits 0; the `Reload tmux config` handler shows as triggered (or any equivalent notification — the relevant handler name in your playbook output).

- [ ] **Step 2: Confirm the option is live**

Run:

```bash
tmux show-options -gv allow-passthrough
```

Expected output:
```
off
```

If this prints anything else, the source-file step did not pick up the change. Re-run `tmux source-file ~/.tmux.conf` manually.

- [ ] **Step 3: Confirm the Ghostty tab title shows the session name**

In a Ghostty tab attached to a tmux session named (for example) `nmb`, look at the tab title. It should read `nmb`.

- [ ] **Step 4: Verify the tab does not flicker when an inner program tries to override**

In a tmux pane in that tab, run:

```bash
claude --version
```

(or any other Claude/Codex/vim invocation that previously caused the tab title to change).

Expected: the Ghostty tab title stays `nmb` throughout. No flicker, no momentary other title.

If the title still changes, the option is not actually being respected — most likely the tmux server was started before the config was applied and never reloaded. Run:

```bash
tmux kill-server
```

and re-attach in a fresh Ghostty tab. (This restarts the tmux server with the new config; only do this when you have nothing in flight.)

- [ ] **Step 5: Verify session-rename still propagates**

```bash
tmux rename-session -t '$0' tab-title-test
```

(Adjust `$0` to your current session ID; `tmux display-message -p '#{session_id}'` prints it.)

Expected: the Ghostty tab title updates to `tab-title-test` immediately. Rename it back when done.

- [ ] **Step 6: Verify SSH window-rename pipeline still works**

If you have a dev host accessible via SSH:

1. SSH into the dev host from a tmux pane in the same tab.
2. On the dev host, run `worktree-start <some-existing-branch-name>` (or any other invocation of the existing remote worktree publisher).
3. Confirm:
   - The local tmux **window** name changes to the structured remote label like `(*<branch>) <repo> | <host>` — this proves `tmux-remote-title` → `tmux-sync-remote-title` still works without DCS passthrough.
   - The Ghostty tab title still shows the local session name (`tab-title-test` or whatever you renamed it to). It does **not** show the remote worktree label.

If you do not have a dev host handy, mark this step as deferred and note it in the PR body — the unit-level parity test plus steps 3–5 cover the regression risk.

- [ ] **Step 7: Verify multiple Ghostty tabs each show their own session name**

Open a second Ghostty tab. In it, attach to a different tmux session (or create one):

```bash
tmux new-session -s second-session
```

Expected: the new tab's title shows `second-session`. The original tab still shows its own session name. They do not interfere.

If any verification step fails, do **not** proceed to Task 4. Instead, diagnose and either fix the spec/plan or abandon the change.

---

### Task 4: Push and open PR

- [ ] **Step 1: Push the branch**

```bash
git push -u origin ghostty-tab-title-from-session-name
```

- [ ] **Step 2: Open PR**

Invoke the `_pull-request` skill (per user CLAUDE.md — `create-pull-request` is the user-defined alias). The PR description should:

- Reference the spec at `docs/superpowers/specs/2026-04-30-ghostty-tab-title-from-session-name-design.md`.
- Include a one-line summary: disable tmux DCS passthrough so the Ghostty tab title stays pinned to the local session name.
- Test plan checklist:
  - [ ] `bash roles/common/files/bin/tmux-window-bar-config.test` passes
  - [ ] `bin/provision` re-templates `~/.tmux.conf` and reloads tmux
  - [ ] `tmux show-options -gv allow-passthrough` prints `off`
  - [ ] Ghostty tab title shows the local tmux session name
  - [ ] Running `claude` / `vim` / `nvim` does not change the tab title
  - [ ] `tmux rename-session` updates the tab title immediately
  - [ ] SSH window-rename still works (or noted as deferred if no dev host accessible)

---

## Self-Review

**Spec coverage:**
- Spec "Approach: disable DCS passthrough at the tmux layer" → Task 2 steps 1 (macOS) and 2 (Linux).
- Spec "Changes: `roles/macos/templates/dotfiles/tmux.conf`" → Task 2 step 1.
- Spec "Changes: `roles/linux/files/dotfiles/tmux.conf`" → Task 2 step 2.
- Spec "Changes: `roles/common/files/bin/tmux-window-bar-config.test`" → Task 1 step 1 (assertions added) + Task 2 step 3 (assertions pass).
- Spec "Static / parity test" → Task 1 + Task 2 step 3.
- Spec "Manual verification" steps 1–7 → Task 3 steps 3–7 (each spec verification step is mapped to a Task 3 step).
- Spec "Acceptance: extended parity-test assertions pass" → Task 2 step 3.
- Spec "Acceptance: every manual step behaves as described" → Task 3.
- Spec "Acceptance: no regressions in existing test suite" → Task 2 step 4.
- Spec "What stays unchanged" → enforced negatively: no task touches set-titles, set-titles-string, tmux-remote-title, tmux-sync-remote-title, status-left/right, hooks, or any other listed item.

**Placeholder scan:** No "TBD", "TODO", "implement later", "fill in details", or "similar to Task N" references. Every code block is concrete.

**Type/identifier consistency:** The string `set -g allow-passthrough off` appears identically in spec, test assertion, macOS config, and Linux config. The forbidden values `allow-passthrough all` and `allow-passthrough on` appear identically in spec and test. The comment block has the same wording in spec, macOS config, and Linux config.
