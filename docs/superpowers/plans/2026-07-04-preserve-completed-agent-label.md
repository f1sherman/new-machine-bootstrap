# Preserve Completed Agent Label Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve completed tmux/Pi work identity after `repo-end` by rendering completed labels with a leading check mark.

**Architecture:** Extend pane-local agent state with explicit completion markers. `tmux-agent-worktree clear` marks an existing subject done, or preserves the current `@window-label` as a completed label when no subject exists; `tmux-agent-state render` uses those markers to keep completed work visible.

**Tech Stack:** Bash helpers, tmux pane options, shell-based verification scripts.

## Global Constraints

- Make changes only inside this repository.
- Use an isolated git worktree for implementation.
- Preserve operational cleanup of worktree path, agent pid, and pane links.
- Do not add fallback heuristics or migration logic.
- Do not add third-party dependencies.

---

### Task 1: Add tests for completed subject rendering

**Files:**
- Create: `tests/tmux-agent-state-completed-subject.sh`

**Interfaces:**
- Consumes: `roles/common/files/bin/tmux-agent-state`, `roles/common/files/bin/tmux-agent-worktree`
- Produces: Executable shell test covering file-backed pane state via `TMUX_AGENT_STATE_DIR` and `TMUX_AGENT_WORKTREE_STATE_DIR`, including subject-based and prior-window-label-based completion.

- [ ] **Step 1: Write the failing test**

Create `tests/tmux-agent-state-completed-subject.sh` with tests that set `TMUX`, `TMUX_PANE`, `TMUX_AGENT_STATE_DIR`, `TMUX_AGENT_WORKTREE_STATE_DIR`, and `TMUX_AGENT_STATE_CURRENT_PATH`, then call the helper scripts directly.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/tmux-agent-state-completed-subject.sh`

Expected: FAIL because `@agent_subject_done` is not set/rendered yet.

- [ ] **Step 3: Implement completed marker support**

Modify `roles/common/files/bin/tmux-agent-state` to:

- read `@agent_subject_done` and `@agent_completed_window_label` in `render`
- render `✓ ${kind}: ${subject}` when kind, subject, and done marker are present
- render the preserved completed window label when no subject exists
- clear completion state in `set-kind`, `set-subject`, `clear-subject`, and `set-worktree`
- add commands to mark the current subject done and to preserve a completed window label

Modify `roles/common/files/bin/tmux-agent-worktree` so `cmd_clear` marks the subject done when clearing a worktree with an existing subject, or preserves the prior `@window-label` as completed when no subject exists.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/tmux-agent-state-completed-subject.sh`

Expected: PASS.

- [ ] **Step 5: Run broader verification**

Run: `bash tests/repo-tests-tmux-isolation.sh`

Expected: PASS or documented pre-existing skip/failure unrelated to this change.

- [ ] **Step 6: Commit**

Commit modified helper scripts and tests with message:

```bash
git commit -m "Preserve completed agent labels after repo-end"
```
