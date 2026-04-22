---
date: 2026-04-22
topic: Add shared _fix skill with repo-aware workspace policy
status: approved
---

# Design: _fix skill

## Goal

Add a minimal shared `_fix` skill that lets the user tell Claude or Codex:

- here is the issue to fix
- here is an optional issue or PR URL for context
- proceed through the repo's normal fix workflow
- open a pull request when the fix is verified and complete

The skill should act as a lightweight trigger, not a second workflow system.

## Current State

- This repo provisions managed skills from `roles/common/files/config/skills/`.
- `common/` skills are copied into both `~/.claude/skills/` and `~/.codex/skills/`.
- Runtime-specific overrides live under `claude/` and `codex/` only when behavior must differ.
- Shared workflow triggers such as `_approve-spec` are intentionally short and operational.
- Repo-local instruction files such as `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` can override generic workflow defaults.

That means `_fix` should reuse the existing shared-skill pattern and defer repo-specific workflow choices to repo-local instructions.

## Desired Behavior

After the user invokes `$_fix` or plain `_fix`, the agent should treat the provided issue text as the primary fix target and optionally use an issue or PR URL as additional context.

The skill should then instruct the agent to:

- read repo-local instruction files first to determine workspace and process requirements
- follow repo-local worktree or branch workflow when one is specified
- avoid forcing worktrees when the repo does not require them
- use the normal required process skills for debugging, planning, implementation, and verification
- verify empirically before claiming success
- invoke `_pull-request` after verification passes and the work is complete

## Design Summary

Add one shared skill at:

- `roles/common/files/config/skills/common/_fix/SKILL.md`

The `SKILL.md` content should stay minimal and operational:

- name: `_fix`
- short description explaining that it tells the agent to fix the passed issue, respect repo-local workspace policy, and create a PR when done
- body text telling the agent to:
  - use the passed issue text and optional URL as the task context
  - read repo-local instructions first
  - determine whether a worktree should be used from those repo instructions
  - if repo instructions are silent, use the repo's normal workflow without forcing a worktree
  - proceed with the fix using required process skills
  - verify empirically
  - invoke `_pull-request` when verification passes and the work is complete

## Why Shared Skill

A shared skill is the best fit here because:

- the requested behavior is workflow policy rather than a Codex-only capability
- this repo already provisions shared skills to both Claude and Codex
- keeping one copy avoids divergence between runtimes
- repo-local instructions already provide the mechanism for per-repository differences

## Why Thin Dispatcher

`_fix` should remain a thin dispatcher rather than a full workflow skill because:

- debugging, TDD, worktree selection, commit handling, and PR creation already exist in other skills and repo policies
- repeating those rules inside `_fix` would create drift and conflicting instructions
- the user's need is a concise trigger for "take this issue through completion", not a replacement workflow stack

## Non-goals

- embedding full debugging or TDD instructions inside `_fix`
- hard-coding `worktree-start` or any other workspace helper for all repositories
- bypassing required process skills
- parsing issue tracker metadata beyond free-form issue text plus an optional issue or PR URL
- adding runtime-specific copies unless behavior later diverges

## Implementation Notes

- No Ansible task changes should be needed if the skill is added under `roles/common/files/config/skills/common/`.
- Existing role tasks already sync `common/` skills into both `~/.claude/skills/` and `~/.codex/skills/`.
- The skill text should explicitly mention repo-local instruction files such as `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` as the source of truth for workspace policy.
- The wording should align with repo-level agent policy that the agent should continue through implementation and PR creation once the task is understood and verification passes.

## Verification Strategy

Implementation should verify at two levels:

1. Repo source
   - confirm `roles/common/files/config/skills/common/_fix/SKILL.md` exists with the expected name and wording
2. Provisioned install
   - run `bin/provision`
   - confirm the skill is installed to both `~/.claude/skills/_fix/` and `~/.codex/skills/_fix/`
   - confirm the installed copies preserve the intended wording

## Risks

- If the skill text hard-codes worktree behavior, it will be wrong in repositories with different branch workflow rules.
- If the skill text becomes too detailed, it will overlap with existing process skills and repo policies instead of acting as a trigger.
- If the wording is too vague about repo-local instructions, agents may default to inconsistent workspace behavior across repositories.
