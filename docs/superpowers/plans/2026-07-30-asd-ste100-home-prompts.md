# ASD-STE100 Home Prompts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace telegraph-style response guidance in provisioned HOME agent instructions with ASD-STE100 Simplified Technical English principles.

**Architecture:** Change the first line of the existing Claude/Codex and Pi managed base fragments. Keep all current Ansible assembly tasks and the Codex symlink unchanged, then use provisioning to verify the generated HOME files.

**Tech Stack:** Markdown instruction fragments, Ansible provisioning, shell verification

## Global Constraints

- Use ASD-STE100 principles; do not claim strict ASD-STE100 compliance.
- Use this exact instruction: `User name: Brian. Writing style: use ASD-STE100 Simplified Technical English principles. Use short, clear sentences and consistent terminology.`
- Do not change fragment assembly or symlink architecture.
- Do not add a tautological automated test for prose; verify the user-facing literal and provisioned outputs directly.

---

### Task 1: Update and provision HOME agent instructions

**Files:**
- Modify: `roles/common/files/claude/CLAUDE.md.d/00-base.md:1`
- Modify: `roles/common/files/pi/AGENTS.md.d/00-base.md:1`

**Interfaces:**
- Consumes: Existing Ansible tasks that install and assemble both base fragments and link Codex `AGENTS.md` to Claude `CLAUDE.md`.
- Produces: Provisioned Claude, Codex, and Pi HOME instruction files with the approved writing-style rule.

- [ ] **Step 1: Confirm the old rule exists in both source fragments**

Run:

```bash
rg -n -F 'Work style: telegraph; noun-phrases ok; drop grammar; min tokens.' \
  roles/common/files/claude/CLAUDE.md.d/00-base.md \
  roles/common/files/pi/AGENTS.md.d/00-base.md
```

Expected: one match at line 1 in each file.

- [ ] **Step 2: Replace the first line in both fragments**

Set line 1 in each file to:

```text
User name: Brian. Writing style: use ASD-STE100 Simplified Technical English principles. Use short, clear sentences and consistent terminology.
```

- [ ] **Step 3: Verify both source fragments**

Run:

```bash
expected='User name: Brian. Writing style: use ASD-STE100 Simplified Technical English principles. Use short, clear sentences and consistent terminology.'
for file in \
  roles/common/files/claude/CLAUDE.md.d/00-base.md \
  roles/common/files/pi/AGENTS.md.d/00-base.md; do
  [[ "$(head -n 1 "$file")" == "$expected" ]]
done
! rg -n -i 'telegraph|noun-phrases|drop grammar' \
  roles/common/files/claude/CLAUDE.md.d/00-base.md \
  roles/common/files/pi/AGENTS.md.d/00-base.md
```

Expected: exit status 0 and no output.

- [ ] **Step 4: Run the Pi fragment assembly test**

Run:

```bash
tests/pi-agent-assemble-agents.sh
```

Expected: all checks print `PASS` and the command exits 0.

- [ ] **Step 5: Apply provisioning**

Run:

```bash
bin/provision
```

Expected: Ansible completes with `failed=0` and updates the managed HOME fragments and assembled files.

- [ ] **Step 6: Verify provisioned HOME outputs**

Run:

```bash
expected='User name: Brian. Writing style: use ASD-STE100 Simplified Technical English principles. Use short, clear sentences and consistent terminology.'
for file in \
  "$HOME/.claude/CLAUDE.md.d/00-base.md" \
  "$HOME/.claude/CLAUDE.md" \
  "$HOME/.codex/AGENTS.md" \
  "$HOME/.pi/agent/AGENTS.md.d/00-base.md" \
  "$HOME/.pi/agent/AGENTS.md"; do
  grep -Fxq "$expected" "$file"
done
! rg -n -i 'telegraph|noun-phrases|drop grammar' \
  "$HOME/.claude/CLAUDE.md.d/00-base.md" \
  "$HOME/.claude/CLAUDE.md" \
  "$HOME/.codex/AGENTS.md" \
  "$HOME/.pi/agent/AGENTS.md.d/00-base.md" \
  "$HOME/.pi/agent/AGENTS.md"
```

Expected: exit status 0 and no output.

- [ ] **Step 7: Confirm provisioning is idempotent**

Run:

```bash
bin/provision --check
```

Expected: Ansible completes with `failed=0` and `changed=0`.

- [ ] **Step 8: Commit the implementation**

Run:

```bash
~/.pi/agent/skills/z-commit/commit.sh \
  -m 'Use ASD-STE100 principles for agent responses' \
  roles/common/files/claude/CLAUDE.md.d/00-base.md \
  roles/common/files/pi/AGENTS.md.d/00-base.md \
  docs/superpowers/plans/2026-07-30-asd-ste100-home-prompts.md
```

Expected: one commit containing the two source-fragment changes and this plan.
