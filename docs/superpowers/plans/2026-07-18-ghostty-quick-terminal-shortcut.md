# Ghostty Quick-Terminal Shortcut Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `Ctrl+Space` globally toggle Ghostty's native quick terminal on managed macOS machines.

**Architecture:** Extend the existing Ansible-managed Ghostty config with one explicit, idempotent `lineinfile` task. Add a small static contract test and wire it into CI so the exact global keybinding cannot disappear unnoticed.

**Tech Stack:** Ansible YAML, Bash, Ghostty configuration, GitHub Actions

## Global Constraints

- The managed binding must be exactly `keybind = global:ctrl+space=toggle_quick_terminal`.
- Use Ghostty's native global shortcut; add no Hammerspoon logic, macOS automation, scripts, or dependencies.
- Changes must remain inside this repository and deploy through `bin/provision`.
- macOS Accessibility permission and user-level `Ctrl+Space` conflicts remain operational prerequisites, not provisioning concerns.

---

## File Structure

- `roles/macos/tasks/main.yml`: Owns the idempotent Ghostty config binding.
- `tests/ghostty-quick-terminal.sh`: Enforces the exact task name, replacement regexp, and configured keybinding.
- `.github/workflows/integration-test.yml`: Runs the new contract test in CI.

### Task 1: Manage and verify the Ghostty quick-terminal binding

**Files:**
- Create: `tests/ghostty-quick-terminal.sh`
- Modify: `roles/macos/tasks/main.yml:144-151`
- Modify: `.github/workflows/integration-test.yml:21-30`

**Interfaces:**
- Consumes: Ghostty's `global:` keybinding prefix and `toggle_quick_terminal` action; the existing Ghostty config path created in `roles/macos/tasks/main.yml`.
- Produces: One managed Ghostty config line, `keybind = global:ctrl+space=toggle_quick_terminal`.

- [ ] **Step 1: Write the failing static contract test**

Create `tests/ghostty-quick-terminal.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
TASKS="$REPO_ROOT/roles/macos/tasks/main.yml"

assert_contains() {
  local expected="$1"

  if ! grep -F -- "$expected" "$TASKS" >/dev/null; then
    echo "missing Ghostty quick-terminal config: $expected" >&2
    exit 1
  fi
}

assert_contains '- name: Configure ghostty quick-terminal shortcut'
assert_contains "regexp: '^keybind\\s*=\\s*global:ctrl\\+space='"
assert_contains "line: 'keybind = global:ctrl+space=toggle_quick_terminal'"

echo "Ghostty quick-terminal shortcut contract verified"
```

Make it executable:

```bash
chmod +x tests/ghostty-quick-terminal.sh
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
bash tests/ghostty-quick-terminal.sh
```

Expected: exit 1 with `missing Ghostty quick-terminal config: - name: Configure ghostty quick-terminal shortcut`.

- [ ] **Step 3: Add the idempotent Ansible task**

In `roles/macos/tasks/main.yml`, directly after `Configure ghostty macOS AppleScript support` and before `Configure ghostty command`, add:

```yaml
- name: Configure ghostty quick-terminal shortcut
  lineinfile:
    path: '{{ ansible_facts["user_dir"] }}/Library/Application Support/com.mitchellh.ghostty/config'
    regexp: '^keybind\s*=\s*global:ctrl\+space='
    line: 'keybind = global:ctrl+space=toggle_quick_terminal'
    create: yes
    mode: 0644
```

This regexp replaces only a prior global `Ctrl+Space` binding and does not infer or migrate other shortcuts.

- [ ] **Step 4: Wire the contract test into CI**

In `.github/workflows/integration-test.yml`, directly after `Verify CI test inventory`, add:

```yaml
      - name: Verify Ghostty quick-terminal shortcut
        run: bash tests/ghostty-quick-terminal.sh
```

- [ ] **Step 5: Run focused and syntax verification**

Run:

```bash
bash tests/ghostty-quick-terminal.sh
ansible-playbook playbook.yml --syntax-check
git diff --check
```

Expected:

- Contract test prints `Ghostty quick-terminal shortcut contract verified`.
- Ansible prints `playbook: playbook.yml` with no syntax error.
- `git diff --check` exits 0 with no output.

- [ ] **Step 6: Commit the implementation**

Invoke the `z-commit` skill with these files and a commit message equivalent to `Configure Ghostty quick-terminal shortcut`:

```text
roles/macos/tasks/main.yml
.github/workflows/integration-test.yml
tests/ghostty-quick-terminal.sh
```

- [ ] **Step 7: Deploy and verify the effective Ghostty config**

Run:

```bash
bin/provision
ghostty +show-config | grep -F 'keybind = global:ctrl+space=toggle_quick_terminal'
```

Expected: provisioning succeeds and the second command prints the exact managed binding.

From a non-Ghostty application, press `Ctrl+Space` twice. Expected: the first press opens the quick terminal and the second hides it. If macOS prompts for Accessibility access, grant it to Ghostty and retry; if macOS input-source switching owns `Ctrl+Space`, remove that conflicting system shortcut and retry.
