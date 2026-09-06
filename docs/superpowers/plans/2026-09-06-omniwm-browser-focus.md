# OmniWM Browser Focus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Focus Safari for normal links and remove transient Safari window movement from Ghostty routing.

**Architecture:** Add a tested browser opener for open-then-focus behavior. Resolve the Ghostty Safari target by its Development profile title across workspaces, reuse or summon that window, and fall back without creating or moving a window.

**Tech Stack:** Lua, Hammerspoon, OmniWM IPC, Ansible, Markdown

**Spec:** `docs/superpowers/specs/2026-09-06-omniwm-browser-focus-design.md`

## Global Constraints

- Do not move any live window.
- Do not change ChatGPT-to-Chrome routing behavior.
- Do not provision or restart OmniWM without user approval.
- Keep the existing exact-host OmniWM gate.

---

### Task 1: Browser open-and-focus helper

**Files:**
- Create: `roles/macos/files/hammerspoon/omniwm_browser_opener.lua`
- Create: `tests/omniwm-browser-opener.lua`
- Modify: `roles/macos/tasks/install_omniwm.yml`
- Modify: `.github/workflows/integration-test.yml`

**Interfaces:**
- Produces: `browserOpener.open(url, bundleID, browserName, deps) -> boolean`

- [ ] Write failing cases for open success, open failure, and focus failure.
- [ ] Run `lua tests/omniwm-browser-opener.lua` and confirm the missing module failure.
- [ ] Implement open-then-focus behavior with one notification per failed step.
- [ ] Deploy the module and run its test in CI.
- [ ] Run the focused test and commit `Add focused browser URL opener`.

### Task 2: Stable Ghostty Safari routing

**Files:**
- Modify: `roles/macos/files/hammerspoon/omniwm_url_source.lua`
- Modify: `roles/macos/files/hammerspoon/omniwm.lua`
- Modify: `tests/omniwm-url-source.lua`
- Modify: `docs/omniwm-cheatsheet.md`

**Interfaces:**
- Produces: `isDevelopmentSafariWindow(window) -> boolean`
- Produces: `resolveDevelopmentSafariWindow(windows) -> window|nil, error|string|nil`
- Consumes: `browserOpener.open`

- [ ] Add failing cases for exact Development title prefix, wrong profile,
  titleless panels, absent target, one target across workspaces, and ambiguity.
- [ ] Implement the pure Development Safari resolver.
- [ ] Replace normal Safari and Chrome fallback bodies with the tested opener.
- [ ] Make Ghostty reuse the unique Development Safari target across workspaces.
- [ ] Remove Safari window creation and `move-to-workspace` from Ghostty routing.
- [ ] Update the cheat sheet with browser focus and fallback behavior.
- [ ] Run both focused Lua tests, both existing routing tests, Lua syntax checks,
  Ruby settings tests, Ansible syntax, and `git diff --check`.
- [ ] Commit `Stabilize OmniWM Safari link routing`.

### Task 3: Review and pull request

**Files:**
- Review: complete branch against `origin/main`

**Interfaces:**
- Produces: a clean branch and GitHub pull request

- [ ] Confirm tests pass and the worktree is clean.
- [ ] Confirm the Ghostty route contains no window creation or movement.
- [ ] Run independent branch review and fix valid findings.
- [ ] Push and create the pull request with a `## Verification` section.
