# ChatGPT Chrome Window ID Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Normalize valid Chrome AppleScript window IDs before exact-window link routing.

**Architecture:** Put strict ID normalization in the existing pure URL-source module. The Hammerspoon adapter will use the normalized numeric ID and keep its current fallback behavior for invalid values.

**Tech Stack:** Lua, Hammerspoon, AppleScript

**Spec:** `docs/superpowers/specs/2026-09-06-chatgpt-chrome-window-id-design.md`

## Global Constraints

- Accept only positive integer IDs.
- Do not move any window.
- Do not provision or restart Hammerspoon without user approval.

---

### Task 1: Normalize Chrome window IDs

**Files:**
- Modify: `roles/macos/files/hammerspoon/omniwm_url_source.lua`
- Modify: `roles/macos/files/hammerspoon/omniwm.lua`
- Modify: `tests/omniwm-url-source.lua`

**Interfaces:**
- Produces: `normalizeChromeWindowID(value) -> number|nil`

- [ ] Add failing tests for a decimal string, number, empty string, text, zero,
  negative value, and fractional value.
- [ ] Run `lua tests/omniwm-url-source.lua` and confirm failure.
- [ ] Implement strict normalization in the production helper.
- [ ] Use the helper in `chromeFrontWindowID`.
- [ ] Run focused tests, Lua syntax, Ruby settings tests, Ansible syntax, and
  `git diff --check`.
- [ ] Commit the fix.

### Task 2: Review and pull request

- [ ] Run independent review against `origin/main`.
- [ ] Fix valid findings and repeat verification.
- [ ] Push the clean branch and open a GitHub pull request.
