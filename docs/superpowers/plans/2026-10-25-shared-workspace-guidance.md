# Shared Workspace Guidance Implementation Plan

> Execution: Native with `superpowers:executing-plans`. Self-approved; continue without another approval gate.

**Goal:** Align always-loaded instructions with the shared lifecycle guards.

**Architecture:** Update the Pi and Claude base fragments. Codex inherits the Claude fragment. Keep helper behavior unchanged.

**Tech stack:** Markdown, Bash lifecycle helpers, bounded model calls.

**Spec:** `docs/superpowers/specs/2026-10-25-shared-workspace-guidance-design.md`

## Constraints and review focus

Preserve generated-state exceptions, repository isolation preferences, helper safety checks, and environment ownership. No new discard flag. No private repository names in public evidence. No native Pi sessions or ASR registration.

Check existing isolation, helper failure, unpublished unique commits, published closed work, and externally owned worktrees. Evidence must distinguish model decisions, script behavior, and live deployment.

## Task 1: Shared instructions and verification

Files: `roles/common/files/pi/AGENTS.md.d/00-base.md`, `roles/common/files/claude/CLAUDE.md.d/00-base.md`.

- [x] Freeze sanitized replay inputs, common tools, model settings, scoring, and component ablations before model generation.
- [x] Add the setup and cleanup components to both fragments. Replace the older Claude lifecycle rule rather than duplicate it.
- [x] Run the complete matched comparison. Record every response and usage; preserve failures rather than reroll them.
- [x] Exercise actual scripts in disposable repositories. Require successful integrated cleanup and preserved unpublished unique work after normal and closed cleanup fail.
- [x] Record results and limitations. Run `git diff --check` and review all changed prose for permission changes.
- [ ] Commit, obtain one fresh-context branch review, address material findings, and open the pull request through `z-pull-request`.
