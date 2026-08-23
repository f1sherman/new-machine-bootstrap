# Pi Subagent Runtime State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep pi-subagents runtime state out of Git worktrees and store normal artifacts with Pi sessions.

**Architecture:** Extend the managed global Git ignore template with the current runtime path. Add the explicit artifact storage policy to the managed pi-subagents extension configuration while preserving scheduled runs.

**Tech Stack:** Ansible, Jinja/YAML, Git ignore patterns, JSON

**Spec:** `docs/superpowers/specs/2026-08-23-pi-subagent-runtime-state-design.md`

## Global Constraints

- Preserve the legacy `**/.pi-subagents/` ignore rule.
- Manage `subagents.artifactDir` with the exact value `session`.
- Preserve the existing `scheduledRuns.enabled: true` extension setting.
- Do not delete existing runtime data during provisioning.
- Do not add an automated test for declarative configuration.

---

### Task 1: Manage runtime state policy

**Files:**
- Modify: `roles/common/templates/dotfiles/gitignore`
- Modify: `roles/common/files/pi/extensions/subagent/config.json`
- Modify: `roles/common/tasks/main.yml`

**Interfaces:**
- Consumes: the existing global Git ignore template and managed pi-subagents extension configuration.
- Produces: a global ignore rule for `.pi/subagents/` and `artifactDir: session` in the deployed extension configuration.

- [x] **Step 1: Add the current pi-subagents runtime path**

Add `**/.pi/subagents/` below the existing `**/.pi-subagents/` rule. Keep both patterns.

- [x] **Step 2: Add explicit session artifact storage**

Add the exact top-level value below to `roles/common/files/pi/extensions/subagent/config.json` while retaining `scheduledRuns.enabled: true`:

```json
"artifactDir": "session"
```

Rename the copy task to describe the complete Pi subagent configuration.

- [x] **Step 3: Verify the ignore rule behavior**

Create a temporary excludes file from the managed template and run:

```bash
git -c core.excludesFile="$temporary_file" \
  check-ignore -v .pi/subagents/artifacts/example.json
```

Expected: the command identifies `**/.pi/subagents/` as the matching rule.

- [x] **Step 4: Verify the extension configuration**

Parse the managed JSON and require both settings:

```bash
jq -e \
  '.artifactDir == "session" and .scheduledRuns.enabled == true' \
  roles/common/files/pi/extensions/subagent/config.json
```

Expected: the command exits successfully.

- [x] **Step 5: Run repository validation**

Run:

```bash
ansible-playbook playbook.yml --syntax-check
git diff --check
```

Expected: both commands exit successfully.

- [x] **Step 6: Commit the implementation**

Commit the managed configuration files, task label, and this completed plan with an imperative message.
