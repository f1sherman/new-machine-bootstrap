# macOS Keychain Secrets Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a shared docs-only skill for safe macOS Keychain secret setup and debugging.

**Architecture:** Create one common skill under `roles/common/files/config/skills/common/`. Existing Ansible copy tasks already deploy common skills to both Claude and Codex skill directories, so implementation does not touch provisioning logic.

**Tech Stack:** Markdown skill file, existing Ansible role copy tasks, `ansible-playbook --syntax-check` verification.

---

## File Structure

- Create: `roles/common/files/config/skills/common/macos-keychain-secrets/SKILL.md`
  - Owns all runtime guidance for this shared skill.
  - Uses standard skill frontmatter.
  - Contains no scripts and performs no Keychain mutations itself.

No tests are created because the approved scope is docs-only.

### Task 1: Add Shared macOS Keychain Skill

**Files:**
- Create: `roles/common/files/config/skills/common/macos-keychain-secrets/SKILL.md`

- [ ] **Step 1: Create the shared skill file**

Use `apply_patch` from the repo root:

```bash
apply_patch <<'PATCH'
*** Begin Patch
*** Add File: roles/common/files/config/skills/common/macos-keychain-secrets/SKILL.md
+---
+name: macos-keychain-secrets
+description: >
+  Use when setting up or debugging local macOS Keychain secrets for app
+  integrations, CLI tokens, or provider credentials.
+---
+
+# macOS Keychain Secrets
+
+Use this skill when setting up or debugging local macOS Keychain secrets for
+app integrations, CLI tokens, or provider credentials.
+
+## Diagnose
+
+Check the keychain search list, default keychain, and login keychain file:
+
+```bash
+security list-keychains
+security default-keychain
+test -f "$HOME/Library/Keychains/login.keychain-db"
+```
+
+The default keychain should be the file
+`~/Library/Keychains/login.keychain-db`, not the directory
+`~/Library/Keychains`.
+
+## Prefer Existing App Wrappers
+
+Before direct `security` commands, search for app-specific Keychain wrappers
+and service/account naming:
+
+```bash
+rg -n "Keychain|add-generic-password|find-generic-password|keychain" .
+```
+
+Use the wrapper if available.
+
+## Direct Security Commands
+
+For lookup commands, always pass the explicit keychain path as the final
+argument:
+
+```bash
+security find-generic-password -s "$service" -a "$account" "$HOME/Library/Keychains/login.keychain-db" >/dev/null
+```
+
+For direct writes, use the prompt form only after verifying the default keychain
+is `~/Library/Keychains/login.keychain-db`. `security` treats `-p` and
+`-w password` as insecure because they expose the secret as an argument; bare
+`-w` as the last option prompts for the secret and writes to the default
+keychain:
+
+```bash
+security add-generic-password -U -s "$service" -a "$account" -w
+```
+
+Do not combine a keychain path with prompt-form direct writes because
+`security add-generic-password` expects options before the optional keychain
+argument. If the default keychain is wrong and the user does not approve
+repairing it, stop or use an app-specific wrapper.
+
+Do not put literal secret values in commands, transcripts, or shell history.
+Disable xtrace before handling secrets and unset secret variables after use. If
+non-interactive writes are required, prefer an app-specific wrapper or private
+local tooling that avoids exposing the secret in process arguments.
+
+Do not use `find-generic-password -w` for agent verification because it prints
+the secret. Verify item presence only.
+
+## Default Keychain Repair
+
+If `security default-keychain` points at a directory or bad path, ask before
+mutating. With approval:
+
+```bash
+security default-keychain -s "$HOME/Library/Keychains/login.keychain-db"
+```
+
+## Secret Handling
+
+Never print secrets. Prefer reading from existing authenticated tools or
+private files. Avoid shell history exposure. Verification should prove
+presence, not value.
+
+## Failure Handling
+
+If macOS shows "Keychain Not Found", inspect `security default-keychain`. If
+prompts repeat or the user cancels, stop. Distinguish missing item from
+Keychain failure.
*** End Patch
PATCH
```

Expected: `Success. Updated the following files:` with the new `SKILL.md` path.

- [ ] **Step 2: Verify the file exists and contains the critical rules**

Run:

```bash
test -f roles/common/files/config/skills/common/macos-keychain-secrets/SKILL.md
rg -n 'login\.keychain-db|final argument|ask before|Never print secrets|Keychain Not Found|Verify item presence only|prompt form|process arguments' roles/common/files/config/skills/common/macos-keychain-secrets/SKILL.md
! rg -n '^security find-generic-password -w' roles/common/files/config/skills/common/macos-keychain-secrets/SKILL.md
! rg -n '^security add-generic-password .* -w "\$secret"' roles/common/files/config/skills/common/macos-keychain-secrets/SKILL.md
! rg -n '^security add-generic-password .*login\.keychain-db.* -w$' roles/common/files/config/skills/common/macos-keychain-secrets/SKILL.md
```

Expected: `test` exits 0, the first `rg` prints matching lines for all listed safety rules, and the negated `rg` commands exit 0 by finding no secret-printing lookup command line, no direct write example that exposes `$secret` as a process argument, and no prompt-form direct write that puts the keychain path before `-w`.

- [ ] **Step 3: Run playbook syntax verification**

Run:

```bash
ansible-playbook playbook.yml --syntax-check
```

Expected: exits 0 and prints `playbook: playbook.yml`.

- [ ] **Step 4: Review the implementation diff**

Run:

```bash
git diff -- roles/common/files/config/skills/common/macos-keychain-secrets/SKILL.md
```

Expected: diff contains only the new docs-only shared skill.

- [ ] **Step 5: Commit the implementation**

Run:

```bash
git add roles/common/files/config/skills/common/macos-keychain-secrets/SKILL.md
git commit -m "Add macOS keychain secrets skill"
```

Expected: commit succeeds with one new file.

## Plan Self-Review

- Spec coverage: Task 1 creates the shared skill, includes diagnose, wrapper preference, explicit keychain path, presence-only lookup verification, prompt-based direct writes, repair approval, secret handling, failure handling, and syntax verification.
- Placeholder scan: no placeholders remain.
- Scope check: one docs-only implementation task; no tests or Ansible changes are included.
