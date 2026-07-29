# Non-Agent Tmux Window Title Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render non-agent tmux windows as `<program> | <Git root or current directory>` while preserving managed labels for live coding-agent TUIs.

**Architecture:** `tmux-window-label` remains the sole window-name renderer. It accepts an optional effective-command override, checks live agent ownership before honoring cached task state, and computes a Git-root-aware fallback for other commands. Zsh lifecycle hooks asynchronously dispatch ordered transitions through `tmux-title-transition`, which serializes label rendering before remote publication and drops stale requests; tmux focus hooks remain repair paths.

**Tech Stack:** Bash, zsh hooks, tmux CLI, Git CLI, shell contract tests

## Global Constraints

- Non-agent format is exactly `<program> | <directory>`.
- Inside Git, directory is the worktree root basename; outside Git, current directory basename.
- Managed coding-agent titles remain authoritative only while their TUI is live.
- Do not enable `automatic-rename`, `allow-rename`, Linux `set-titles`, or terminal passthrough.
- Do not poll panes or clear durable coding-agent state solely because another program runs.
- All shell and tmux synchronization remains best effort and must not block command execution.

---

### Task 1: Make window authority depend on the live command

**Files:**
- Modify: `tests/tmux-label-contract.sh`
- Modify: `roles/common/files/bin/tmux-window-label`

**Interfaces:**
- Consumes: `tmux-window-label <pane-id> [effective-command]`, pane options `@agent_kind`, `@task_state`, `@task_source`, `@task_label`, and `@window-label`
- Produces: a visible tmux window name and `@window-indicators` derived from live command authority

- [ ] **Step 1: Add failing window-label cases**

Extend the fake tmux fixture so `show-options` can return `TMUX_TEST_AGENT_KIND` for `@agent_kind`. Add cases with stale task state and a nested Git path:

```bash
nested_path="$repo_path/content/posts"
mkdir -p "$nested_path"
: > "$window_log"
TMUX_TEST_AGENT_KIND=pi TMUX_TEST_TASK_STATE=provisional \
TMUX_TEST_TASK_SOURCE=agent TMUX_TEST_TASK_LABEL='Summer 2027 award flights' \
TMUX_TEST_WINDOW_LABEL='~ Summer 2027 award flights' \
TMUX_TEST_PATH="$nested_path" TMUX_TEST_COMMAND=nvim \
TMUX_WINDOW_LABEL_LOG="$window_log" PATH="$fake_tmux_dir:$PATH" \
  "$WINDOW_LABEL" %1
assert_file_contains "$window_log" 'rename-window -t @1 nvim | label-repo' \
  'non-agent command ignores stale agent title and uses Git root'
assert_file_contains "$window_log" 'set-option -wqu -t @1 @window-indicators' \
  'non-agent command clears managed indicators'
```

Add a live Pi case expecting the cached task label, an explicit `nvim` override case while tmux still reports `zsh`, and a non-Git path case expecting `nvim | plain-dir`.

- [ ] **Step 2: Run the focused contract and verify RED**

Run:

```bash
bash tests/tmux-label-contract.sh
```

Expected: FAIL because stale task state still wins and the optional command is ignored.

- [ ] **Step 3: Implement live-agent authority and fallback rendering**

In `tmux-window-label`:

1. Read `effective_command="${2:-$pane_current_command}"`.
2. Read `@agent_kind`.
3. Add `is_live_agent` that accepts direct `claude`, `codex`, and `pi` commands; a generic `node` command additionally requires matching foreground argv evidence from the pane tty for the cached Claude or Pi kind.
4. Honor cached managed task/window labels and `@agent_worktree_path` only when `is_live_agent` succeeds.
5. For non-agent panes, compute the Git top level with `git -C "$pane_current_path" rev-parse --show-toplevel`; fall back to `pane_current_path`; take its basename; render `"$effective_command | $directory"`.
6. Clear `@window-indicators` on non-agent panes and avoid remote structured-label parsing unless the effective command is a remote candidate.
7. Preserve current task, remote-title, and host-stripping behavior for live agents and remote panes.

- [ ] **Step 4: Run the focused contract and verify GREEN**

Run:

```bash
bash tests/tmux-label-contract.sh
```

Expected: all assertions pass, including stale-task fallback and live-agent preservation.

- [ ] **Step 5: Commit the renderer change**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Restore non-agent tmux window titles" \
  tests/tmux-label-contract.sh roles/common/files/bin/tmux-window-label
```

---

### Task 2: Refresh titles on zsh command transitions

**Files:**
- Modify: `tests/tmux-label-contract.sh`
- Create: `roles/common/files/bin/tmux-title-transition`
- Modify: `roles/common/templates/dotfiles/zshrc.d/10-common-shell.zsh`
- Modify: `roles/common/tasks/main.yml`

**Interfaces:**
- Consumes: zsh `preexec`, `precmd`, and `chpwd` lifecycle callbacks; `tmux-title-transition <pane-id> <request-id> <effective-command> <suppress-edge>`
- Produces: nonblocking pre-launch and post-command requests, serialized in request order with label rendering before remote-title publication

- [ ] **Step 1: Add failing zsh-hook assertions**

Extend the existing zsh hook stub directory with a `tmux-window-label` logger. Exercise:

```zsh
_tmux_window_title_preexec 'nvim content/post.md'
_tmux_window_title_precmd
```

Assert exact calls:

```text
%1 nvim
%1 zsh
```

Also assert the preexec window-label call appears before `tmux-remote-title publish`, and retain the existing vim edge-suppression assertions.

- [ ] **Step 2: Run the focused contract and verify RED**

Run:

```bash
bash tests/tmux-label-contract.sh
```

Expected: FAIL because the lifecycle callbacks do not exist and preexec/precmd only publish remote titles.

- [ ] **Step 3: Implement zsh lifecycle refreshes**

In `10-common-shell.zsh`:

1. Add a small command-name extractor using zsh lexical splitting, taking the first command word and stripping path prefixes.
2. Add `tmux-title-transition`, using monotonic request IDs and a per-pane lock to serialize background work, skip stale requests, render the label, then publish the remote title.
3. Add `_tmux_window_title_preexec` and `_tmux_window_title_precmd` to dispatch the transition helper in disowned background jobs.
4. Preserve vim edge suppression as transition input so publication follows the corrected label.
5. Route `chpwd` through the same asynchronous transition path and provision the helper on macOS and Debian.

- [ ] **Step 4: Run the focused contract and verify GREEN**

Run:

```bash
bash tests/tmux-label-contract.sh
```

Expected: all assertions pass with asynchronous `nvim` and `zsh` dispatches, serialized/stale-request coverage, and correct label-before-publication order.

- [ ] **Step 5: Commit the lifecycle change**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Refresh tmux titles across shell commands" \
  tests/tmux-label-contract.sh roles/common/files/bin/tmux-title-transition \
  roles/common/templates/dotfiles/zshrc.d/10-common-shell.zsh roles/common/tasks/main.yml
```

---

### Task 3: Full verification and deployment

**Files:**
- Verify: `roles/common/files/bin/tmux-window-label`
- Verify: `roles/common/templates/dotfiles/zshrc.d/10-common-shell.zsh`
- Verify: tmux and agent contract suites

**Interfaces:**
- Consumes: completed Tasks 1–2
- Produces: provisioned configuration and empirical tmux transition proof

- [ ] **Step 1: Run static and focused checks**

```bash
bash -n roles/common/files/bin/tmux-window-label
bash -n roles/common/files/bin/tmux-title-transition
zsh -n roles/common/templates/dotfiles/zshrc.d/10-common-shell.zsh
git diff --check
bash tests/tmux-label-contract.sh
bash tests/tmux-agent-state.sh
ruby tests/tmux-pane-title-changed.rb
bash tests/tmux-managed-bars-contract.sh
```

Expected: every command exits 0 with no syntax or whitespace errors.

- [ ] **Step 2: Run repository tests**

```bash
bin/repo-tests
```

Expected: exit 0.

- [ ] **Step 3: Provision from the worktree**

```bash
bin/provision
```

Expected: exit 0 and deploy the changed helper/template through Ansible.

- [ ] **Step 4: Verify the live tmux behavior**

In a disposable tmux window rooted in this worktree, verify `#{window_name}` transitions:

```text
nvim | new-machine-bootstrap
zsh | new-machine-bootstrap
```

Also start a managed coding-agent TUI long enough to confirm its task title replaces the fallback, then exit and confirm the shell fallback returns.

- [ ] **Step 5: Review and final commit if verification produced tracked changes**

Run `git status --short`. If tracked changes remain, commit only coherent implementation files with `~/.pi/agent/skills/z-commit/commit.sh`. Otherwise leave the verified implementation commits unchanged.
