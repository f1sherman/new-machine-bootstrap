# Tmux-Resurrect Neovim Space-Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore a single existing Neovim file or directory path containing spaces as one shell argument after tmux-resurrect.

**Architecture:** Add one conservative Bash strategy implementing tmux-resurrect's existing process-strategy interface. Platform roles copy the shared strategy into the installed plugin after TPM setup, and both tmux configurations select it.

**Tech Stack:** Bash, tmux-resurrect strategy interface, Ansible, ShellCheck, shell contract tests

## Global Constraints

- Preserve existing Neovim `Session.vim` behavior, including the stale `nvim -S` fallback to plain `nvim` when no local `Session.vim` exists, without changing other processes.
- Treat the entire flat text after `nvim ` as one path candidate; when it exists, that single-path interpretation wins even if the text could theoretically represent multiple arguments.
- Leave other flags, flat text that does not resolve as one existing path (including unresolved ambiguous/multiple arguments), nonexistent paths, and other processes unchanged.
- Manage deployed files only through this repository and `bin/provision`.
- Install the same strategy on macOS and Linux.

---

### Task 1: Conservative Neovim Restore Strategy

**Files:**
- Create: `roles/common/files/tmux-resurrect-strategies/nvim_nmb.sh`
- Create: `tests/tmux-resurrect-nvim-space-path.sh`
- Modify: `.github/workflows/integration-test.yml`

**Interfaces:**
- Consumes: positional argument `$1` containing tmux-resurrect's flat Neovim command and `$2` containing the pane working directory.
- Produces: one shell command on stdout; either `nvim -S`, a command with one `%q`-escaped path argument, or the unchanged original command.

- [ ] **Step 1: Write the failing contract test**

Create a temporary directory tree and invoke the strategy as a standalone program. Assert these exact behaviors:

```bash
expect_output "nvim $absolute_space_path" "$pane_dir" "nvim ${absolute_space_path// /\\ }"
expect_output "nvim Relative Dir/file" "$pane_dir" 'nvim Relative\ Dir/file'
touch "$pane_dir/looks like multiple args"
expect_output "nvim looks like multiple args" "$pane_dir" 'nvim looks\ like\ multiple\ args'
expect_output "nvim ordinary" "$pane_dir" 'nvim ordinary'
expect_output "nvim -u NONE file" "$pane_dir" 'nvim -u NONE file'
expect_output "nvim missing path" "$pane_dir" 'nvim missing path'
expect_output "nvim -S" "$pane_dir" 'nvim'
touch "$pane_dir/Session.vim"
expect_output "nvim anything" "$pane_dir" 'nvim -S'
expect_output "vim foo" "$pane_dir" 'vim foo'
```

Also assert CI invokes this test. Platform configuration and provisioning assertions are added in Task 2.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/tmux-resurrect-nvim-space-path.sh`

Expected: FAIL because `roles/common/files/tmux-resurrect-strategies/nvim_nmb.sh` does not exist and configuration still selects `session`.

- [ ] **Step 3: Implement the minimal strategy**

Implement:

```bash
#!/usr/bin/env bash
set -euo pipefail

original_command="${1:-}"
pane_dir="${2:-}"

case "$original_command" in
  nvim\ *) argument=${original_command#nvim } ;;
  *) printf '%s\n' "$original_command"; exit 0 ;;
esac

if [ -f "$pane_dir/Session.vim" ]; then
  printf '%s\n' 'nvim -S'
  exit 0
fi

case "$argument" in
  -S) printf '%s\n' 'nvim'; exit 0 ;;
  '') printf '%s\n' 'nvim'; exit 0 ;;
  -*) printf '%s\n' "$original_command"; exit 0 ;;
esac

if [[ "$argument" = /* ]]; then
  candidate="$argument"
else
  candidate="$pane_dir/$argument"
fi

if [ -e "$candidate" ]; then
  printf 'nvim %q\n' "$argument"
else
  printf '%s\n' "$original_command"
fi
```

- [ ] **Step 4: Add the test to CI and verify green**

Add a `Verify tmux-resurrect Neovim space paths` step running `bash tests/tmux-resurrect-nvim-space-path.sh` after restore diagnostics.

Run:

```bash
bash tests/tmux-resurrect-nvim-space-path.sh
bash tests/ci-test-inventory.sh
shellcheck roles/common/files/tmux-resurrect-strategies/nvim_nmb.sh tests/tmux-resurrect-nvim-space-path.sh
```

Expected: all commands exit zero.

- [ ] **Step 5: Commit the strategy and test**

```bash
git add roles/common/files/tmux-resurrect-strategies/nvim_nmb.sh tests/tmux-resurrect-nvim-space-path.sh .github/workflows/integration-test.yml
git commit -m "Preserve Neovim paths with spaces during restore"
```

### Task 2: Provision the Strategy on Both Platforms

**Files:**
- Modify: `roles/macos/tasks/main.yml`
- Modify: `roles/linux/tasks/main.yml`
- Modify: `roles/macos/templates/dotfiles/tmux.conf`
- Modify: `roles/linux/files/dotfiles/tmux.conf`
- Test: `tests/tmux-resurrect-nvim-space-path.sh`

**Interfaces:**
- Consumes: `roles/common/files/tmux-resurrect-strategies/nvim_nmb.sh` from Task 1.
- Produces: executable `~/.tmux/plugins/tmux-resurrect/strategies/nvim_nmb.sh` and tmux option `@resurrect-strategy-nvim nmb` on both platforms.

- [ ] **Step 1: Extend the failing provisioning assertions**

Require each platform role to copy the shared strategy to:

```text
{{ ansible_facts["user_dir"] }}/.tmux/plugins/tmux-resurrect/strategies/nvim_nmb.sh
```

with mode `0755`, after its `Install tmux plugins via tpm` task. Require both tmux configs to contain:

```tmux
set -g @resurrect-strategy-nvim 'nmb'
```

Run: `bash tests/tmux-resurrect-nvim-space-path.sh`

Expected: FAIL until all four integration files are updated.

- [ ] **Step 2: Add platform copy tasks and select the strategy**

Add this task after TPM installation in each platform role:

```yaml
- name: Install tmux-resurrect Neovim restore strategy
  copy:
    src: '{{ playbook_dir }}/roles/common/files/tmux-resurrect-strategies/nvim_nmb.sh'
    dest: '{{ ansible_facts["user_dir"] }}/.tmux/plugins/tmux-resurrect/strategies/nvim_nmb.sh'
    mode: '0755'
```

Change both tmux configs from strategy `session` to `nmb`.

- [ ] **Step 3: Verify contracts and Ansible syntax**

Run:

```bash
bash tests/tmux-resurrect-nvim-space-path.sh
bash tests/ci-test-inventory.sh
ansible-playbook playbook.yml --syntax-check
```

Expected: all commands exit zero.

- [ ] **Step 4: Provision and verify deployed behavior**

Run `bin/provision`, then verify:

```bash
cmp roles/common/files/tmux-resurrect-strategies/nvim_nmb.sh "$HOME/.tmux/plugins/tmux-resurrect/strategies/nvim_nmb.sh"
tmux show-options -gv @resurrect-strategy-nvim
"$HOME/.tmux/plugins/tmux-resurrect/strategies/nvim_nmb.sh" \
  'nvim /Users/brian/Library/Mobile Documents/com~apple~CloudDocs/journal/journal' \
  /Users/brian
```

Expected: byte comparison passes, tmux prints `nmb`, and the strategy prints the path with an escaped space.

- [ ] **Step 5: Run final focused verification and commit**

Run:

```bash
bash tests/tmux-resurrect-nvim-space-path.sh
bash tests/ci-test-inventory.sh
shellcheck roles/common/files/tmux-resurrect-strategies/nvim_nmb.sh tests/tmux-resurrect-nvim-space-path.sh
ansible-playbook playbook.yml --syntax-check
git diff --check
```

Expected: all commands exit zero.

Commit:

```bash
git add roles/macos/tasks/main.yml roles/linux/tasks/main.yml roles/macos/templates/dotfiles/tmux.conf roles/linux/files/dotfiles/tmux.conf tests/tmux-resurrect-nvim-space-path.sh
git commit -m "Deploy Neovim tmux restore strategy"
```
