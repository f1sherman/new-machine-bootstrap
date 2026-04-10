# Remove Codex API Auth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clarify in the repo that Codex uses subscription auth while preserving the existing wrapper that prevents exported `OPENAI_API_KEY` from overriding it.

**Architecture:** The implementation is a narrow text-only change in `roles/common/templates/dotfiles/zshrc`. A temporary shell verifier in `/tmp` defines the desired repo state, fails before the change, then passes after the wrapper comment is updated. Final verification uses the same verifier plus `ansible-playbook playbook.yml --syntax-check`.

**Tech Stack:** zsh, bash, ripgrep, Ansible

**Spec:** `docs/superpowers/specs/2026-04-10-remove-codex-api-auth-design.md`

---

## File Map

- `/tmp/remove-codex-api-auth-check.sh`:
  Temporary verification script. It asserts the new Codex wrapper comment is present, the old wording is absent, and no live implementation file still references Codex `auth.json` provisioning.
- `roles/common/templates/dotfiles/zshrc`:
  The only repo file expected to change. It keeps the `codex()` wrapper behavior exactly as-is and only clarifies the comment above it.

### Task 1: Create the red/green verifier

**Files:**
- Create: `/tmp/remove-codex-api-auth-check.sh`
- Verify: `roles/common/templates/dotfiles/zshrc`

- [ ] **Step 1: Write the verifier script**

Create `/tmp/remove-codex-api-auth-check.sh` with exactly this content:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

new_comment='# Prevent exported OPENAI_API_KEY from overriding Codex subscription auth'
old_comment='# Wrap codex to unset OPENAI_API_KEY so it can use subscription auth'

if ! grep -Fqx "$new_comment" roles/common/templates/dotfiles/zshrc; then
  printf 'FAIL: expected new Codex wrapper comment is missing\n' >&2
  exit 1
fi

if grep -Fqx "$old_comment" roles/common/templates/dotfiles/zshrc; then
  printf 'FAIL: old Codex wrapper comment is still present\n' >&2
  exit 1
fi

if rg -n '\.codex/auth\.json|Configure Codex CLI auth\.json' roles macos README.md bin >/dev/null 2>&1; then
  printf 'FAIL: live Codex API-auth provisioning wording is still present\n' >&2
  exit 1
fi

printf 'PASS: Codex subscription-auth wording is correct and no live auth.json provisioning remains\n'
```

- [ ] **Step 2: Make the verifier executable**

Run:

```bash
chmod +x /tmp/remove-codex-api-auth-check.sh
```

- [ ] **Step 3: Run the verifier to confirm RED**

Run:

```bash
/tmp/remove-codex-api-auth-check.sh
```

Expected: exit code `1` with `FAIL: expected new Codex wrapper comment is missing`. This proves the desired wording is not present yet.

### Task 2: Clarify the Codex wrapper comment and verify GREEN

**Files:**
- Modify: `roles/common/templates/dotfiles/zshrc`

- [ ] **Step 1: Replace the Codex wrapper comment**

Update the Codex wrapper block in `roles/common/templates/dotfiles/zshrc` so it reads exactly like this:

```zsh
# Wrap gsd to unset ANTHROPIC_API_KEY (it uses its own key)
alias gsd > /dev/null && unalias gsd
function gsd() {
  ANTHROPIC_API_KEY= command gsd "$@"
}

# Prevent exported OPENAI_API_KEY from overriding Codex subscription auth
alias codex > /dev/null && unalias codex
function codex() {
  env -u OPENAI_API_KEY command codex "$@"
}
```

Do not change the `codex()` function body. Only the comment above it should change.

- [ ] **Step 2: Run the verifier to confirm GREEN**

Run:

```bash
/tmp/remove-codex-api-auth-check.sh
```

Expected: exit code `0` with `PASS: Codex subscription-auth wording is correct and no live auth.json provisioning remains`.

- [ ] **Step 3: Run a focused search to confirm only the new wording remains**

Run:

```bash
rg -n 'Prevent exported OPENAI_API_KEY from overriding Codex subscription auth|Wrap codex to unset OPENAI_API_KEY so it can use subscription auth' roles/common/templates/dotfiles/zshrc
```

Expected:

```text
roles/common/templates/dotfiles/zshrc:<line>:# Prevent exported OPENAI_API_KEY from overriding Codex subscription auth
```

The old `Wrap codex to unset ...` wording must not appear.

- [ ] **Step 4: Run the repo syntax check**

Run:

```bash
ansible-playbook playbook.yml --syntax-check
```

Expected: exit code `0` and output ending with:

```text
playbook: playbook.yml
```

- [ ] **Step 5: Inspect the diff to confirm the scope stayed narrow**

Run:

```bash
git diff -- roles/common/templates/dotfiles/zshrc
```

Expected: a one-line comment replacement above the unchanged `codex()` wrapper.

- [ ] **Step 6: Commit only if the user has explicitly approved committing in this session**

If commit approval has been granted, run:

```bash
git add roles/common/templates/dotfiles/zshrc
git -c commit.gpgsign=false commit -m "Clarify Codex subscription auth wrapper"
```

If commit approval has not been granted, stop after verification and report that the change is complete but uncommitted.
