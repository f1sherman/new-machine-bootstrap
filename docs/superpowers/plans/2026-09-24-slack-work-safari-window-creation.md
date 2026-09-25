# Slack Work Safari Window Creation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Open Slack links only in a confirmed Safari Work profile window, creating one if missing.

**Architecture:** The existing profile router receives an optional asynchronous window creator and a fail-closed option. The Slack adapter selects Safari's known Work window menu item and polls OmniWM for the created Work window. Other profile routes retain their old behavior.

**Tech Stack:** Lua, Hammerspoon, Ansible, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-24-slack-work-safari-window-creation-design.md`

## Global Constraints

- Do not route Slack links into Personal or another Safari profile after any error.
- Create a Work window only if none exists; reject ambiguous targets.
- Do not move, summon, close, or resize windows.
- No provisioning, reload, or live window test without explicit approval.

---

### Task 1: Router state machine

**Files:** Modify `roles/macos/files/hammerspoon/omniwm_slack_router.lua`, `tests/omniwm-slack-router.lua`.

**Interfaces:** `route(url, target, deps)` accepts optional `deps.createTarget(callback)` and `deps.failClosed = true`. The callback receives `(target, error)`.

- [ ] Add tests for no-target creation then exact tab opening and navigation; creation failure or nil result must notify without fallback; tab creation failure with `failClosed` must notify without fallback. Existing generic routes must still fall back once. Run `lua tests/omniwm-slack-router.lua`, expect failures on new cases.
- [ ] Implement only the optional create-target state and fail-closed behavior. Run `lua tests/omniwm-slack-router.lua`, expect PASS.

### Task 2: Connect Safari Work window creation

**Files:** Modify `roles/macos/files/hammerspoon/omniwm.lua`, `docs/omniwm-cheatsheet.md`; create `tests/omniwm-slack-window.lua`; modify `.github/workflows/integration-test.yml`.

**Interfaces:** `routeSlackURL(url)` calls `hs.application.get("com.apple.Safari"):selectMenuItem({"File", "New Window", "New Work Window"})` only on missing Work target, then uses `M.poll` and `M.windows` to wait for exactly one Work window.

- [ ] Add a callback-level Lua test that loads production `omniwm.lua` with controlled Hammerspoon boundaries. Test missing Work window creates and confirms the target before opening the tab; existing Work window skips creation; ambiguous Work windows reject the link; failed menu selection or query rejects the link without Safari fallback. Run the new test, expect failure on missing-target case.
- [ ] Wire the menu selection and polling into Slack-only routing. Pass `failClosed` and avoid normal Safari fallback for Slack. Run the new test, expect PASS.
- [ ] Update the cheat sheet and add the test to the existing Integration Test workflow. Run all OmniWM Lua tests; expect PASS.

### Task 3: Verify and publish

**Files:** All changed files.

- [ ] Run Lua syntax checks, all OmniWM Lua tests, `ruby tests/configure-omniwm-settings.rb`, `ansible-playbook playbook.yml --syntax-check`, workflow YAML parse, and `git diff --check`.
- [ ] Review the complete diff, commit, and open a PR. Do not deploy or live-test this change without explicit approval.
