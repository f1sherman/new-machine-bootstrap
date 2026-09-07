# OmniWM Safari Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Navigate to the exact Safari window that receives a normal application link.

**Architecture:** Resolve Safari’s front native ID to one OmniWM window after URL opening. A tested state machine then navigates to that opaque window ID and confirms focus without moving or summoning it.

**Tech Stack:** Lua, Hammerspoon, Safari AppleScript, OmniWM IPC, Ansible

**Spec:** `docs/superpowers/specs/2026-09-07-omniwm-safari-navigation-design.md`

## Global Constraints

- Open each URL once.
- Do not move or summon windows.
- Preserve Ghostty and ChatGPT routing.
- Do not provision without explicit approval.

---

### Task 1: Exact Safari target resolution

**Files:**
- Modify: `roles/macos/files/hammerspoon/omniwm_url_source.lua`
- Modify: `tests/omniwm-url-source.lua`

**Interfaces:**
- Produces: `resolveSafariWindowByNativeID(windows, nativeID, decoder)`

- [ ] Add failing cases for one match, no match, a titleless panel, and duplicate
  matches.
- [ ] Implement fail-closed resolution through the supplied opaque-ID decoder.
- [ ] Run the URL-source test and commit the resolver.

### Task 2: Normal Safari route state machine

**Files:**
- Create: `roles/macos/files/hammerspoon/omniwm_safari_router.lua`
- Create: `tests/omniwm-safari-router.lua`
- Modify: `roles/macos/files/hammerspoon/omniwm.lua`
- Modify: `roles/macos/tasks/install_omniwm.yml`
- Modify: `.github/workflows/integration-test.yml`
- Modify: `docs/omniwm-cheatsheet.md`

**Interfaces:**
- Produces: `safariRouter.route(url, deps)`

- [ ] Add failing state-machine cases for success, URL-open failure, ID failure,
  match failure, navigation failure, and focus failure.
- [ ] Verify every post-open failure focuses Safari without reopening the URL.
- [ ] Implement delayed capture, resolution, exact navigation, and focus checks.
- [ ] Wire the production route into `openNormallyInSafari`.
- [ ] Deploy the module and add its test to CI.
- [ ] Update the cheat sheet.
- [ ] Run all focused tests, Lua syntax checks, Ruby settings tests, Ansible
  syntax, and `git diff --check`.
- [ ] Commit the route.

### Task 3: Review and pull request

- [ ] Confirm the route contains no move or summon command.
- [ ] Run independent review and fix valid findings.
- [ ] Repeat verification and confirm a clean worktree.
- [ ] Push and open a GitHub pull request.
