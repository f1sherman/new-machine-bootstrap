# Pi Package Ownership Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give retained Pi packages one repository owner, pin all retained packages, and remove unused personal packages.

**Architecture:** NMB will own the Pi CLI, generic Pi resources, and the pinned `pi-session-manager` package. HNP will own personal-development package choices, including `pi-subdir-context` and compaction, and will remove unused packages during provisioning. Each repository will produce its own commit and pull request.

**Tech Stack:** Ansible YAML, Pi package settings, npm and Git package sources, Renovate custom managers, shell-based end-to-end verification.

## Global Constraints

- Keep `pi-session-manager` in NMB and pin it initially to `0.1.0` with Renovate npm coverage.
- Move `pi-subdir-context` ownership to HNP and pin it initially to `1.1.7` with Renovate npm coverage.
- Keep `@ogulcancelik/pi-codex-compaction` only in HNP.
- Remove `pi-intercom` and `pi-prompt-template-model` from HNP-managed personal-development hosts.
- Keep `pi-codex-limit` because Pi uses the `openai-codex` provider.
- NMB must preserve HNP-owned package entries and must not recreate removed personal packages.
- Do not add static configuration tests. Use syntax checks, provisioning, and live `pi list` verification.
- Make all source changes in repository worktrees. Do not edit deployed files directly.

---

### Task 1: Make NMB own only the pinned session manager package

**Files:**
- Modify: `vars/tool_versions.yml`
- Modify: `roles/common/tasks/main.yml:1327-1405`
- Modify: `roles/common/tasks/pi_main_worktree_guard_settings.yml:40-68`

**Interfaces:**
- Consumes: Pi user package settings at `~/.pi/agent/settings.json`.
- Produces: `tool_versions.pi_packages.session_manager`, used by both NMB session-manager installation tasks.
- Produces: NMB package reconciliation that preserves all active package entries except the retired Algal compaction source.

- [ ] **Step 1: Add the versioned session-manager source**

Add this mapping near the runtime tool pins in `vars/tool_versions.yml`:

```yaml
  pi_packages:
    # renovate: datasource=npm depName=pi-session-manager
    session_manager: 0.1.0
```

Change both session-manager installation commands to use:

```yaml
pi install npm:pi-session-manager@{{ tool_versions.pi_packages.session_manager }}
```

- [ ] **Step 2: Remove the NMB `pi-subdir-context` install tasks**

Delete the macOS and Debian tasks named:

```text
Install pi-subdir-context plugin for pi-coding-agent (macOS)
Install pi-subdir-context plugin for pi-coding-agent (Linux)
```

Do not add removal logic. HNP will replace the preserved unversioned entry with its versioned source.

- [ ] **Step 3: Remove active NMB compaction ownership**

Delete the macOS and Debian tasks that install `npm:@ogulcancelik/pi-codex-compaction@0.1.3`. Keep cleanup for the retired source and checkout:

```text
git:github.com/algal/pi-openai-server-compaction
~/.pi/agent/git/github.com/algal/pi-openai-server-compaction
```

In `pi_main_worktree_guard_settings.yml`, preserve every package except the retired Algal source. Remove the filter for `npm:@ogulcancelik/pi-codex-compaction` and set:

```yaml
'packages': pi_preserved_packages,
```

- [ ] **Step 4: Verify NMB source and syntax**

Run:

```bash
rg -n 'pi-subdir-context|npm:@ogulcancelik/pi-codex-compaction' \
  roles/common/tasks vars
ansible-playbook playbook.yml --syntax-check
git diff --check
```

Expected: no active install or forced settings entry remains for either package. References to the retired Algal cleanup can remain. The syntax check and diff check pass.

- [ ] **Step 5: Provision NMB and verify preservation**

Capture `pi list`, run `bin/provision`, then run `pi list` again. Confirm:

- `pi-session-manager@0.1.0` is present;
- the current HNP-owned packages remain present;
- NMB does not re-add a removed personal package;
- the provision recap reports zero failures.

- [ ] **Step 6: Commit the NMB implementation**

Commit exactly:

```text
vars/tool_versions.yml
roles/common/tasks/main.yml
roles/common/tasks/pi_main_worktree_guard_settings.yml
```

Use commit message:

```text
Consolidate NMB Pi package ownership
```

---

### Task 2: Reconcile the HNP personal package set

**Files:**
- Modify: `roles/personal-dev/defaults/main.yml:10-52`
- Modify: `roles/personal-dev/tasks/main.yml:69-123`

**Interfaces:**
- Consumes: `personal_dev_pi_packages`, the exact desired personal package registry.
- Produces: `personal_dev_pi_subdir_context_version: '1.1.7'` and its versioned npm package source.
- Produces: retired-package cleanup for both versioned and unversioned `pi-intercom` and `pi-prompt-template-model` entries.

- [ ] **Step 1: Add the Renovate-managed subdirectory-context pin**

Add to `roles/personal-dev/defaults/main.yml`:

```yaml
# renovate: datasource=npm depName=pi-subdir-context
personal_dev_pi_subdir_context_version: '1.1.7'
```

Add this item to `personal_dev_pi_packages`:

```yaml
  - source: "npm:pi-subdir-context@{{ personal_dev_pi_subdir_context_version }}"
    list_match: "npm:pi-subdir-context@{{ personal_dev_pi_subdir_context_version }}"
```

- [ ] **Step 2: Remove unused packages from desired state**

Remove these version variables, Renovate annotations, and package-list entries:

```text
personal_dev_pi_intercom_version
personal_dev_pi_prompt_template_model_version
npm:pi-intercom@...
npm:pi-prompt-template-model@...
```

Keep all other current package entries, including `pi-codex-limit` and compaction.

- [ ] **Step 3: Add explicit retired-package cleanup**

After the generic package installation loop, inspect the captured `pi list` output for these identities with optional versions:

```regex
(?m)^\s*npm:pi-intercom(?:@[^\s]+)?\s*$
(?m)^\s*npm:pi-prompt-template-model(?:@[^\s]+)?\s*$
```

Run the corresponding unversioned identity removal command when present:

```yaml
command: "mise exec -- pi remove {{ item }}"
loop:
  - npm:pi-intercom
  - npm:pi-prompt-template-model
```

Use a loop structure that pairs each source with its regex. Accept only successful removal. Do not suppress unexpected errors.

- [ ] **Step 4: Verify HNP source, Renovate matching, and syntax**

Run from the HNP worktree:

```bash
rg -n 'pi-subdir-context|pi-intercom|pi-prompt-template-model' \
  roles/personal-dev renovate.json
ruby -rjson -e 'JSON.parse(File.read("renovate.json"))'
ansible-playbook playbook.yml --syntax-check
git diff --check
```

Expected: `pi-subdir-context` has a versioned desired source and Renovate annotation. The two removed packages appear only in explicit cleanup logic or documentation. All checks pass.

- [ ] **Step 5: Provision the HNP personal-development role**

Run:

```bash
bin/provision --limit localhost --tags personaldev_role
```

Confirm the recap reports zero failures. Run `pi list` and confirm:

- `npm:pi-subdir-context@1.1.7` is present;
- `npm:pi-intercom` is absent;
- `npm:pi-prompt-template-model` is absent;
- every other desired HNP package remains at its exact source.

- [ ] **Step 6: Verify live Pi behavior**

Start a non-interactive Pi proof that loads the package registry, then use a fresh interactive session for the UI-only checks. Confirm:

- Pi starts without extension-load errors;
- nested `AGENTS.md` context loads;
- `/session-manager` remains available from NMB;
- `/codex-limit` remains available;
- a small pi-subagents worker run completes;
- a fresh Pi session does not start a new `pi-intercom` broker.

- [ ] **Step 7: Commit the HNP implementation**

Commit exactly:

```text
roles/personal-dev/defaults/main.yml
roles/personal-dev/tasks/main.yml
```

Use commit message:

```text
Consolidate personal Pi package ownership
```

---

### Task 3: Review, publish, and verify both pull requests

**Files:**
- Review the complete NMB branch diff.
- Review the complete HNP branch diff.

**Interfaces:**
- Consumes: the clean, committed branches from Tasks 1 and 2.
- Produces: one GitHub PR for NMB and one Forgejo PR for HNP, each with its own monitor handoff.

- [ ] **Step 1: Run independent review on both branches**

Review each complete merge-base diff. Fix only valid findings in the repository that owns the affected file. Repeat targeted verification after any fix.

- [ ] **Step 2: Push and open the NMB pull request**

Use the repository PR workflow. The PR description must state that NMB now owns only the versioned session-manager package and preserves HNP package choices.

- [ ] **Step 3: Push and open the HNP pull request**

Use the repository PR workflow. The PR description must state that HNP adds the versioned subdirectory-context package and removes the two unused packages.

- [ ] **Step 4: Arm both PR monitors**

Arm the GitHub monitor for the NMB branch and the Forgejo monitor for the HNP branch. Report both PR URLs, verification results, and any remaining rollout dependency.
