# Restore SSH tmux Outside Herdr Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore tmux auto-attachment for interactive SSH logins while leaving Herdr-managed shells outside tmux.

**Architecture:** The Linux `dev_host` role will own one `.zprofile` condition. It will call the existing `tmux-attach-or-new` helper only for an interactive SSH login that is outside tmux, outside fallback recovery, and outside Herdr. Repository guidance will describe the same behavior.

**Tech Stack:** Ansible YAML, zsh profile syntax, tmux, SSH

## Global Constraints

- Use the explicit `HERDR_ENV=1` marker. Do not infer Herdr from process ancestry.
- Do not change `tmux-attach-or-new`, Herdr startup, or Herdr mirroring.
- Do not launch tmux for non-interactive SSH commands or local console shells.
- Do not add a retained automated test because this behavior does not meet the repository's material-value test gates.
- Verify the production profile behavior on `dev` and verify provisioning stability.

---

### Task 1: Restore guarded tmux auto-launch

**Files:**
- Modify: `roles/dev_host/tasks/main.yml:8-14`
- Modify: `CLAUDE.md:67-70,140-145`

**Interfaces:**
- Consumes: `HERDR_ENV`, `SSH_CONNECTION`, `TMUX`, `TMUX_ATTACH_FALLBACK`, terminal state from `test -t 0`, and `~/.local/bin/tmux-attach-or-new`.
- Produces: an Ansible-managed `.zprofile` block that conditionally replaces the login shell with `tmux-attach-or-new`.

- [x] **Step 1: Record the failing production behavior**

Run from the controller:

```bash
ssh dev 'grep -F "HERDR_ENV" ~/.zprofile || true; \
  test ! -e ~/.local/bin/tmux-restore-client'
```

Expected before the fix: no `HERDR_ENV` condition is present. A plain interactive SSH login stays outside tmux, as already reproduced.

- [x] **Step 2: Restore the managed profile block**

Replace the removal task with this task body:

```yaml
- name: Configure tmux auto-launch in .zprofile
  blockinfile:
    path: '{{ ansible_facts["user_dir"] }}/.zprofile'
    create: yes
    mode: 0644
    marker: "# {mark} ANSIBLE MANAGED BLOCK - TMUX"
    block: |
      # Launch tmux for interactive SSH logins outside Herdr
      if [ -z "$TMUX" ] &&
         [ -z "${TMUX_ATTACH_FALLBACK:-}" ] &&
         [ "${HERDR_ENV:-}" != "1" ] &&
         [ -n "${SSH_CONNECTION:-}" ] &&
         [ -t 0 ]; then
        exec {{ ansible_facts["user_dir"] }}/.local/bin/tmux-attach-or-new
      fi
```

- [x] **Step 3: Align repository guidance**

Change the Dev Host Role bullet to `tmux auto-launch for SSH sessions outside Herdr`. Change the Linux Dev Host note to `tmux attaches automatically for interactive SSH logins outside Herdr`.

- [x] **Step 4: Validate syntax and review the patch**

Run:

```bash
ansible-playbook playbook.yml --syntax-check
git diff --check
git diff -- roles/dev_host/tasks/main.yml CLAUDE.md
```

Expected: syntax check succeeds, diff check prints nothing, and the diff contains only the guarded launch task and matching documentation.

- [x] **Step 5: Commit the implementation**

Run the repository commit helper with explicit paths and message `Restore SSH tmux launch outside Herdr`.

### Task 2: Verify deployed behavior on dev

**Files:**
- No repository file changes.

**Interfaces:**
- Consumes: the committed feature branch and `bin/provision` on `dev`.
- Produces: live evidence for ordinary SSH, Herdr-marked login, non-interactive SSH, and idempotent provisioning.

- [x] **Step 1: Push the feature branch for the dev checkout**

Push `fix/restore-ssh-tmux-outside-herdr` to `origin` without creating the pull request yet.

- [x] **Step 2: Create a temporary branch worktree on dev**

Fetch the branch in `/home/brian/projects/new-machine-bootstrap`, then create `/home/brian/projects/new-machine-bootstrap/.worktrees/restore-ssh-tmux-outside-herdr` from `origin/fix/restore-ssh-tmux-outside-herdr`. Do not modify the deployed checkout directly.

- [x] **Step 3: Provision from the dev worktree**

Run `bin/provision` directly in the remote worktree. Require zero failed and unreachable tasks.

- [x] **Step 4: Verify the profile contract**

Check that `~/.zprofile` contains the managed block and all five guards. Confirm `~/.local/bin/tmux-attach-or-new` is executable.

- [x] **Step 5: Verify ordinary interactive SSH**

Use a forced TTY login with scripted input that prints `TMUX` and exits. Expected: `TMUX` is nonempty, which proves the login entered tmux.

- [x] **Step 6: Verify the Herdr exception**

Use a forced TTY login that starts `env HERDR_ENV=1 zsh -l`, prints `HERDR_ENV` and `TMUX`, and exits. Expected: `HERDR_ENV=1` and `TMUX` is empty.

- [x] **Step 7: Verify non-interactive SSH**

Run `ssh dev 'test -z "${TMUX:-}"'`. Expected: exit status 0.

- [x] **Step 8: Verify idempotence**

Run `bin/provision` a second time from the remote worktree. Require zero failed and unreachable tasks and no unexpected changes.

- [x] **Step 9: Retain the active implementation worktree**

The controller and `dev` are the same host, so the provisioning worktree is also the active implementation worktree. Retain it through pull request creation. Leave the live managed profile in place for new SSH logins.

### Task 3: Final branch verification and pull request

**Files:**
- Modify: `docs/superpowers/plans/2026-08-14-restore-ssh-tmux-outside-herdr.md` only to mark completed checkboxes if plan tracking changes it.

**Interfaces:**
- Consumes: completed implementation and live verification evidence.
- Produces: a clean feature branch and an open GitHub pull request.

- [x] **Step 1: Run final repository checks**

Run:

```bash
ansible-playbook playbook.yml --syntax-check
git diff --check
git status --short --branch
```

Expected: syntax succeeds, diff check is empty, and the branch contains no uncommitted implementation files.

- [x] **Step 2: Commit plan tracking if changed**

If checkbox tracking changed the plan, commit only the plan with an imperative message. Otherwise, report no tracking change.

- [ ] **Step 3: Create the pull request**

Invoke the repository pull-request workflow. Include a `## Verification` section that reports only author-initiated evidence not duplicated by normal PR automation.
