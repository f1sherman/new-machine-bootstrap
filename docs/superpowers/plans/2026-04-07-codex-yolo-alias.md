# Codex YOLO Alias Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a shared `codex-yolo` zsh alias that expands to `codex --dangerously-bypass-approvals-and-sandbox`.

**Architecture:** Keep the change confined to the shared zsh template at `roles/common/templates/dotfiles/zshrc`, adjacent to the existing `claude-yolo` alias. Use a temporary repo-local shell test to establish a Red/Green cycle on the template content, then run Ansible syntax validation and a real `bin/provision` to confirm the alias deploys into the managed `~/.zshrc`.

**Tech Stack:** Zsh, Bash, ripgrep, Ansible

**Spec:** `docs/superpowers/specs/2026-04-07-codex-yolo-alias-design.md`

---

## File Structure

- **Modify:** `roles/common/templates/dotfiles/zshrc` — add one alias line in the existing alias block, immediately after `alias claude-yolo='claude --dangerously-skip-permissions'`.
- **Create (temporary):** `tmp/test-codex-yolo-alias.sh` — one-off Red/Green verification script that asserts the exact alias line exists in the shared zsh template.

No new permanent tests or helper scripts are needed. Remove the temporary test script before finishing the task.

### Task 1: Add the shared `codex-yolo` alias

**Files:**
- Create: `tmp/test-codex-yolo-alias.sh`
- Modify: `roles/common/templates/dotfiles/zshrc:531-535`

- [ ] **Step 1: Write the failing test**

Create `tmp/test-codex-yolo-alias.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

template="roles/common/templates/dotfiles/zshrc"
expected="alias codex-yolo='codex --dangerously-bypass-approvals-and-sandbox'"

if rg -Fx "$expected" "$template" >/dev/null; then
  echo "PASS: codex-yolo alias present in shared zshrc template"
else
  echo "FAIL: codex-yolo alias missing from shared zshrc template"
  exit 1
fi
```

- [ ] **Step 2: Make the test executable**

Run:

```bash
chmod +x tmp/test-codex-yolo-alias.sh
```

Expected: no output, exit code 0.

- [ ] **Step 3: Run the test to verify Red**

Run:

```bash
tmp/test-codex-yolo-alias.sh
```

Expected output:

```text
FAIL: codex-yolo alias missing from shared zshrc template
```

Expected exit code: `1`

- [ ] **Step 4: Add the minimal implementation**

In `roles/common/templates/dotfiles/zshrc`, update the alias block so this section:

```zsh
# Show Disk Use of subdirectories, sort by size
alias duss="du -d 1 -h 2>/dev/null | sort -hr"

alias claude-yolo='claude --dangerously-skip-permissions'

### End Alias ###
```

becomes:

```zsh
# Show Disk Use of subdirectories, sort by size
alias duss="du -d 1 -h 2>/dev/null | sort -hr"

alias claude-yolo='claude --dangerously-skip-permissions'
alias codex-yolo='codex --dangerously-bypass-approvals-and-sandbox'

### End Alias ###
```

Do not modify any other aliases or comments.

- [ ] **Step 5: Run the test to verify Green**

Run:

```bash
tmp/test-codex-yolo-alias.sh
```

Expected output:

```text
PASS: codex-yolo alias present in shared zshrc template
```

Expected exit code: `0`

- [ ] **Step 6: Run the repo baseline validation**

Run:

```bash
ansible-playbook playbook.yml --syntax-check
```

Expected output ends with:

```text
playbook: playbook.yml
```

Warnings about the implicit localhost inventory are acceptable in this repository.

- [ ] **Step 7: Provision the local machine with the updated template**

Run:

```bash
bin/provision
```

Expected: the playbook completes successfully. Any changed tasks should be limited to the managed shell configuration or other unrelated machine drift already present on the host.

- [ ] **Step 8: Verify the deployed zsh config contains the alias**

Run:

```bash
rg -n "^alias codex-yolo='codex --dangerously-bypass-approvals-and-sandbox'$" "$HOME/.zshrc"
```

Expected output:

```text
<line-number>:alias codex-yolo='codex --dangerously-bypass-approvals-and-sandbox'
```

Any positive line number is acceptable. If no match is found, stop and investigate whether the provisioning task that manages `~/.zshrc` failed or writes to a different path on this platform.

- [ ] **Step 9: Inspect the diff**

Run:

```bash
git diff -- roles/common/templates/dotfiles/zshrc
```

Expected: one added line for `alias codex-yolo='codex --dangerously-bypass-approvals-and-sandbox'` adjacent to the existing `claude-yolo` alias, with no unrelated edits.

- [ ] **Step 10: Remove the temporary test script**

Run:

```bash
rm tmp/test-codex-yolo-alias.sh
```

Expected: no output, exit code 0.

- [ ] **Step 11: Verify the temporary file is gone and only the intended repo file remains**

Run:

```bash
git status --short
```

Expected: `tmp/test-codex-yolo-alias.sh` is absent from status output. The worktree should still show `roles/common/templates/dotfiles/zshrc` as modified, plus any pre-existing plan/spec artifacts that are intentionally part of this worktree.

- [ ] **Step 12: Commit**

Stage the template change:

```bash
git add roles/common/templates/dotfiles/zshrc
```

Then ask the user for explicit approval before creating the commit. Suggested commit message:

```text
Add codex-yolo zsh alias
```

Do not commit without that approval.

## Verification Summary

When this plan is complete:

1. `roles/common/templates/dotfiles/zshrc` contains the exact `codex-yolo` alias line.
2. `ansible-playbook playbook.yml --syntax-check` succeeds.
3. `bin/provision` completes successfully on the local machine.
4. The deployed `~/.zshrc` contains `alias codex-yolo='codex --dangerously-bypass-approvals-and-sandbox'`.
5. No unrelated shell files, scripts, or profiles are changed.
