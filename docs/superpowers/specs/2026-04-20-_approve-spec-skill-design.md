---
date: 2026-04-20
topic: Add shared _approve-spec skill for Claude and Codex
status: approved
---

# Design: _approve-spec skill

## Goal

Add a minimal shared skill that lets the user tell Claude or Codex:

- the spec is approved
- proceed with implementation
- open a pull request when complete

The skill should be a lightweight reminder and trigger, not a second workflow system.

## Current State

- This repo provisions managed skills from `roles/common/files/config/skills/`.
- `common/` skills are copied into both `~/.claude/skills/` and `~/.codex/skills/`.
- Runtime-specific overrides exist under `claude/` and `codex/` when behavior must differ.
- Deprecated slash command files under `~/.claude/commands/` and `~/.codex/commands/` are explicitly removed during provisioning.

That means the existing repo direction favors skills, not slash commands.

## Desired Behavior

After a spec is approved, the user can invoke `$_approve-spec` or plain `_approve-spec`, and the agent receives a short instruction that:

- states the spec is approved
- tells the agent to proceed with implementation without asking for another implementation approval
- tells the agent to open a pull request when the work is complete

The trigger should behave the same in Claude and Codex.

## Design Summary

Add one shared skill at:

- `roles/common/files/config/skills/common/_approve-spec/SKILL.md`

The skill should be installed through the existing shared-skill copy path, with no Claude-specific or Codex-specific variant.

The `SKILL.md` content should stay minimal and operational:

- name: `_approve-spec`
- short description explaining that it marks the current spec as approved and instructs the agent to continue to implementation and open a PR when complete
- body text telling the agent that the spec is approved, implementation should proceed immediately, and a PR should be opened after verification passes and the work is complete

## Why Shared Skill

A shared skill is the best fit here because:

- the requested wording is identical for Claude and Codex
- existing Ansible tasks already copy shared skills to both runtimes
- adding runtime-specific copies would duplicate content without adding value
- restoring slash commands would go against the current repo direction

## Non-goals

- adding `.claude/commands` or `.codex/commands` slash command files
- automatic implementation plan lookup or plan parsing
- automatic commit creation inside the skill
- automatic PR scripting inside the skill
- runtime-specific variants unless a real divergence appears later

## Implementation Notes

- No Ansible task changes should be needed if the skill is added under `roles/common/files/config/skills/common/`.
- The invocation target should be the skill name `_approve-spec`.
- The wording should align with the repo-level agent policy that spec approval is the gate and implementation should proceed without another approval prompt.

## Verification Strategy

Implementation should verify at two levels:

1. Repo source
   - confirm `roles/common/files/config/skills/common/_approve-spec/SKILL.md` exists with the expected name and wording
2. Provisioned install
   - run `bin/provision`
   - confirm the skill is installed to both `~/.claude/skills/_approve-spec/` and `~/.codex/skills/_approve-spec/`
   - confirm the installed copies preserve the intended wording

## Risks

- If the wording is too long or policy-heavy, the skill becomes redundant with the global instructions instead of acting as a quick approval trigger.
- If implementation quietly adds runtime-specific copies or slash-command wrappers, the feature becomes more complex than the use case requires.
