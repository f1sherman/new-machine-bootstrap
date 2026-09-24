# ChatGPT Fastmail Personal Safari Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route ChatGPT Fastmail links to the existing Safari Personal window without changing other ChatGPT links.

**Architecture:** A URL classifier in `omniwm_url_source.lua` reads the host through an injected parser and returns the ChatGPT destination. `omniwm.lua` passes `hs.http.urlParts` and dispatches the Personal Safari path before Chrome. The existing profile-Safari router owns tab creation and fallback.

**Tech Stack:** Lua, Hammerspoon, Ansible.

**Spec:** `docs/superpowers/specs/2026-09-24-chatgpt-fastmail-personal-safari-design.md`

## Global Constraints

- Exact ChatGPT bundle ID: `com.openai.codex`.
- Fastmail host: `fastmail.com` or its subdomains, case-insensitive.
- No live window changes, provisioning, or Hammerspoon reload without separate approval.
- Keep normal Chrome behavior for all other ChatGPT URLs.
- Fall back to Safari at most once, before confirmed tab creation.

---

### Task 1: Classify Fastmail destinations

**Files:**
- Modify: `tests/omniwm-url-source.lua`
- Modify: `roles/macos/files/hammerspoon/omniwm_url_source.lua`

**Interfaces:**
- Produces: `chatGPTDestination(senderBundle, url, parseURL)` returning `"personal-safari"`, `"chrome"`, or `nil`. `parseURL(url)` returns a parts table with `host`, or nil. Parser errors select Chrome.

- [ ] Add tests that call `source.chatGPTDestination` with exact sender and URL parser fixtures. Apex, subdomain, and mixed-case hosts select Personal Safari. Non-Fastmail, `fastmail.com.example.test`, `notfastmail.com`, malformed or nil parts, and other senders do not select Personal Safari. Include URL-with-userinfo and URL-with-path fixtures whose parsed host is not Fastmail.
- [ ] Run `lua tests/omniwm-url-source.lua`; expect a failure because the classifier does not exist.
- [ ] Implement the classifier using `pcall(parseURL, url)`, `string.lower(host)`, and an exact apex or `".fastmail.com"` suffix check. Only parse for the exact ChatGPT bundle.
- [ ] Run `lua tests/omniwm-url-source.lua`; expect PASS.

### Task 2: Dispatch to existing Personal Safari routing

**Files:**
- Modify: `roles/macos/files/hammerspoon/omniwm.lua`
- Create: `tests/omniwm-chatgpt-fastmail.lua`
- Modify: `tests/omniwm-slack-router.lua`
- Modify: `roles/macos/files/hammerspoon/omniwm_slack_router.lua`
- Modify: `docs/omniwm-cheatsheet.md`

**Interfaces:**
- Consumes: `urlSource.chatGPTDestination(senderBundle, fullURL, hs.http.urlParts)` and `routeProfileSafariURL(url, urlSource.resolvePersonalSafariWindow, errorMessage)`.

- [ ] Add a callback-level test loading the production `omniwm.lua` with Hammerspoon boundary doubles. Invoke `hs.urlevent.httpCallback` with ChatGPT sender and Fastmail URL, assert exact Personal Safari tab creation and navigation; with a non-Fastmail URL, assert the Chrome path. Check absent and ambiguous Personal targets fall back to Safari once. Check that navigation failure after successful tab creation never falls back. Run `lua tests/omniwm-chatgpt-fastmail.lua`; expect a failure on the Fastmail branch before implementing it.
- [ ] In the HTTP callback, use the classifier to route ChatGPT Fastmail URLs to the existing Personal Safari helper before the Chrome branch. Pass `hs.http.urlParts`; preserve the other ChatGPT route and sender precedence. Log the new decision.
- [ ] Add a failing test for Safari tab selection failure after tab creation. Split Safari tab creation from selection, returning `true` with an error after creation; let the shared profile router notify without reopening the URL. Run the callback and shared-router tests; expect PASS.
- [ ] Document ChatGPT Fastmail behavior and absent/ambiguous Safari fallback in the cheat sheet.
- [ ] Run all `tests/omniwm-*.lua` with `lua` and `luac -p` on the changed Lua files; expect PASS.

### Task 3: Verify and publish

**Files:** The files above.

- [ ] Run `ruby tests/configure-omniwm-settings.rb` and `ansible-playbook playbook.yml --syntax-check`; confirm both pass.
- [ ] Run `git diff --check`, review the full diff and `git status`, then commit implementation files with the commit helper.
- [ ] Open a GitHub pull request using `z-pull-request`. State that no live deployment or live-link check was performed; do not provision or reload Hammerspoon.
