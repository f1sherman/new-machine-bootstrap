# Pi Subagent Runtime State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep pi-subagents runtime state out of Git worktrees and store normal artifacts with Pi sessions.

**Architecture:** Extend the managed global Git ignore template with the current runtime path. Add the explicit artifact storage policy to the existing recursive Pi settings merge so unrelated settings and agent overrides remain intact.

**Tech Stack:** Ansible, Jinja/YAML, Git ignore patterns, JSON

**Spec:** `docs/superpowers/specs/2026-08-23-pi-subagent-runtime-state-design.md`

## Global Constraints

- Preserve the legacy `**/.pi-subagents/` ignore rule.
- Manage `subagents.artifactDir` with the exact value `session`.
- Preserve unrelated Pi settings and existing `subagents.agentOverrides`.
- Do not delete existing runtime data during provisioning.
- Do not add an automated test for declarative configuration.

---

### Task 1: Manage runtime state policy

**Files:**
- Modify: `roles/common/templates/dotfiles/gitignore`
- Modify: `roles/common/tasks/pi_main_worktree_guard_settings.yml`

**Interfaces:**
- Consumes: the existing global Git ignore template and recursive `pi_settings | combine(..., recursive=True)` merge.
- Produces: a global ignore rule for `.pi/subagents/` and `subagents.artifactDir: session` in managed Pi settings.

- [x] **Step 1: Add the current pi-subagents runtime path**

Add `**/.pi/subagents/` below the existing `**/.pi-subagents/` rule. Keep both patterns.

- [x] **Step 2: Add explicit session artifact storage**

Change the managed subagent settings map to include the exact value below while retaining `agentOverrides`:

```yaml
'subagents': {
  'artifactDir': 'session',
  'agentOverrides': pi_subagent_main_worktree_guard_overrides
}
```

- [x] **Step 3: Verify the ignore rule behavior**

Create a temporary excludes file from the managed template and run:

```bash
git -c core.excludesFile="$temporary_file" \
  check-ignore -v .pi/subagents/artifacts/example.json
```

Expected: the command identifies `**/.pi/subagents/` as the matching rule.

- [x] **Step 4: Verify the settings merge behavior**

Use an Ansible debug expression with representative settings that contain an unrelated top-level key and an existing subagent override. Confirm the merged value contains:

```json
{
  "unrelated": true,
  "subagents": {
    "artifactDir": "session",
    "agentOverrides": {
      "worker": {
        "subagentOnlyExtensions": ["existing", "guard"]
      }
    }
  }
}
```

- [x] **Step 5: Run repository validation**

Run:

```bash
ansible-playbook playbook.yml --syntax-check
git diff --check
```

Expected: both commands exit successfully.

- [x] **Step 6: Commit the implementation**

Commit the two managed configuration files and this completed plan with an imperative message.
