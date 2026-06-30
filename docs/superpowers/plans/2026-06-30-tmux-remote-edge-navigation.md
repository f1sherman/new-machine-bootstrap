# Tmux Remote Edge Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `C-h/j/k/l` in an SSH-nested remote tmux fall back to outer local pane navigation when the remote window has no pane in that direction.

**Architecture:** Remote tmux publishes active-pane edge state through the existing structured title bridge. Local tmux reads the marker from `#{pane_title}` and decides whether to select an outer pane or forward the key into SSH/nested tmux.

**Tech Stack:** tmux config formats, Bash contract tests, GitHub Actions integration workflow.

## Global Constraints

- Do not edit deployed files directly; change managed files in this repo.
- Preserve existing Vim, SSH, and nested tmux forwarding when no remote edge marker is present.
- `C-h/j/k/l` are pane-navigation keys; agent panes must not consume them just because `@agent_kind` is set.
- Stale `@agent_kind` on shell panes must not trigger agent helper passthrough.
- Use focused behavior tests; avoid tautological exact-prose tests.

---

### Task 1: Edge-Aware Remote Navigation

**Files:**
- Modify: `roles/common/files/bin/tmux-remote-title`
- Modify: `roles/common/files/bin/tmux-pane-label`
- Modify: `roles/common/files/bin/tmux-window-label`
- Modify: `roles/common/files/bin/tmux-sync-remote-title`
- Modify: `roles/linux/files/dotfiles/tmux.conf`
- Modify: `roles/macos/templates/dotfiles/tmux.conf`
- Modify: `tests/tmux-agent-key-passthrough.sh`

**Interfaces:**
- Consumes: existing structured remote title bridge.
- Produces: local root bindings that select the outer pane when `#{pane_title}` contains a matching `[nmb-edge=...]` marker.

- [x] **Step 1: Write failing regression checks**

Add assertions to `tests/tmux-agent-key-passthrough.sh` that extract the loaded `C-h` binding and require it to match `[nmb-edge=...h...]`. Update the agent assertions so active and stale `@agent_kind` do not make the `C-h` predicate true, while `M-d` still matches an active agent command.

- [x] **Step 2: Run the focused test and verify failure**

Run: `bash tests/tmux-agent-key-passthrough.sh`

Expected: failure because the current `C-h` binding does not inspect the remote edge marker and still treats active agent panes as key passthrough.

- [x] **Step 3: Implement edge fallback in tmux configs**

Update `tmux-remote-title` to append edge markers for non-Vim active panes. Update label parsers to strip the marker before rendering labels. Change each `C-h/j/k/l` binding so a matching edge marker selects the outer pane; otherwise SSH/nested tmux still receives the key.

- [x] **Step 4: Verify focused behavior**

Run: `bash tests/tmux-agent-key-passthrough.sh`

Expected: pass.

- [x] **Step 5: Verify adjacent contracts**

Run:

```bash
bash tests/ci-test-inventory.sh
bash tests/tmux-managed-bars-contract.sh
bash tests/tmux-agent-state.sh
bash tests/tmux-label-contract.sh
ruby tests/tmux-pane-title-changed.rb
git diff --check
```

Expected: all commands exit 0.
