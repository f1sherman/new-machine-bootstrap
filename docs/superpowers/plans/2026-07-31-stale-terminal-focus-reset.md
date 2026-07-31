# Stale Terminal Focus Reset Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent stale terminal focus reporting from making idle Zsh tmux windows ring on every focus change.

**Architecture:** Register a small managed Zsh `precmd` function that disables DEC mode 1004 when a foreground command returns to the prompt. Test the exact terminal bytes and hook registration as a shell contract.

**Tech Stack:** Zsh, shell contract tests, Ansible-managed dotfile templates

## Global Constraints

- Keep tmux focus events and bell monitoring enabled.
- Reset focus reporting only when Zsh is about to display an interactive prompt.
- Do not suppress unrelated terminal bells.

---

### Task 1: Add the focus-reporting reset hook

**Files:**
- Create: `tests/zsh-terminal-focus-reset.sh`
- Modify: `roles/common/templates/dotfiles/zshrc.d/10-common-shell.zsh:65-92`

**Interfaces:**
- Consumes: Zsh `add-zsh-hook` and the `precmd` hook lifecycle.
- Produces: `_reset_terminal_focus_reporting`, which writes exactly `ESC [ ? 1 0 0 4 l` and is registered for `precmd`.

- [ ] **Step 1: Write the failing contract test**

Create a test that copies the Zsh fragment to a temporary directory, replaces `autoload -Uz add-zsh-hook` with a stub that records registrations, sources the fragment, invokes `_reset_terminal_focus_reporting`, and asserts the exact output bytes and `precmd:_reset_terminal_focus_reporting` registration.

- [ ] **Step 2: Run the test and verify the expected failure**

Run: `bash tests/zsh-terminal-focus-reset.sh`

Expected: FAIL because `_reset_terminal_focus_reporting` is not defined and is not registered.

- [ ] **Step 3: Add the minimal Zsh hook**

Add:

```zsh
_reset_terminal_focus_reporting() {
  printf '\e[?1004l'
}
add-zsh-hook precmd _reset_terminal_focus_reporting
```

Place it with the existing `precmd` hooks.

- [ ] **Step 4: Run focused and related tests**

Run:

```sh
bash tests/zsh-terminal-focus-reset.sh
bash tests/tmux-label-contract.sh
bash tests/editor-env-contract.sh
```

Expected: all commands exit 0.

- [ ] **Step 5: Provision and verify live behavior**

Run `bin/provision`, then reproduce stale focus mode in a disposable tmux pane and verify that returning to the Zsh prompt disables mode 1004 before the window becomes inactive. Confirm `window_bell_flag=0` after repeated window switches.

- [ ] **Step 6: Commit the implementation**

Commit the spec, plan, test, and managed Zsh template with a concise bug-fix commit message.
