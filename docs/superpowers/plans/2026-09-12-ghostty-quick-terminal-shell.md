# Ghostty Quick Terminal Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Ghostty's quick terminal start a plain login shell without changing regular Herdr or tmux routing.

**Architecture:** Keep `ghostty-tab-launch` as Ghostty's managed command. Add an early branch that detects Ghostty's `GHOSTTY_QUICK_TERMINAL=1` marker and replaces the helper with `${SHELL:-/bin/zsh} -l` before it creates launcher state.

**Tech Stack:** Bash, Ansible, Ghostty on macOS

**Spec:** `docs/superpowers/specs/2026-09-12-ghostty-quick-terminal-shell-design.md`

## Global Constraints

- A quick terminal must start the configured shell without Herdr or tmux.
- Regular Ghostty surfaces must retain existing Herdr and tmux behavior.
- The quick-terminal path must not create or consume Herdr launcher state.
- Do not add a retained automated test for this low-impact routing rule.

---

### Task 1: Route the Quick Terminal to a Login Shell

**Files:**
- Modify: `roles/macos/files/bin/ghostty-tab-launch`

**Interfaces:**
- Consumes: Ghostty's `GHOSTTY_QUICK_TERMINAL=1` process environment marker and the standard `SHELL` environment variable.
- Produces: a direct `exec "${SHELL:-/bin/zsh}" -l` quick-terminal path; all other invocations continue into the existing Herdr/tmux router.

- [x] **Step 1: Run a focused failing behavior check**

Create a temporary home with fake `herdr-launch`, `tmux-attach-or-new`, and shell executables. Each fake executable records its name and arguments. Run the production helper with:

```bash
GHOSTTY_QUICK_TERMINAL=1 \
GHOSTTY_TAB_LAUNCH_APP_PID="$$" \
HOME="$fixture_home" \
SHELL="$fixture_home/fake-shell" \
roles/macos/files/bin/ghostty-tab-launch
```

Expected before the fix: FAIL because the record identifies `herdr-launch`, not `fake-shell -l`, and launcher state is created.

- [x] **Step 2: Add the minimal early route**

After PATH normalization and before any launcher state variables, add:

```bash
if [[ "${GHOSTTY_QUICK_TERMINAL:-}" == 1 ]]; then
  exec "${SHELL:-/bin/zsh}" -l
fi
```

Do not modify the existing Herdr marker, lock, signal, or tmux routing code.

- [x] **Step 3: Repeat the focused behavior check**

Run the same isolated fixture from Step 1.

Expected after the fix: PASS because the record is exactly `fake-shell -l`, the helper returns the fake shell's status, and `$fixture_home/.local/state/ghostty-tab-launch` does not exist.

- [x] **Step 4: Validate the production artifact**

Run:

```bash
bash -n roles/macos/files/bin/ghostty-tab-launch
shellcheck roles/macos/files/bin/ghostty-tab-launch
ansible-playbook --syntax-check playbook.yml
```

Expected: all commands exit 0.

- [x] **Step 5: Commit the implementation**

Commit only `roles/macos/files/bin/ghostty-tab-launch` with an imperative message equivalent to:

```text
Open Ghostty quick terminal in a shell
```

- [x] **Step 6: Provision and verify deployed behavior**

Run `bin/provision` from this worktree. Then run:

```bash
cmp roles/macos/files/bin/ghostty-tab-launch \
  "$HOME/.local/bin/ghostty-tab-launch"

ghostty +show-config | \
  grep -F 'command = /Users/brian/.local/bin/ghostty-tab-launch'
```

Expected: provisioning exits 0, `cmp` exits 0, and the effective Ghostty command remains the managed helper. Confirm the isolated focused fixture against the deployed helper too. A newly created quick terminal will use the plain login-shell branch; an already-running quick-terminal process must be closed before Ghostty creates it again.
