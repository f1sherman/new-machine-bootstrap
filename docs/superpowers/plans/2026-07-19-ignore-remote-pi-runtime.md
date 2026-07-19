# Ignore Remote Pi Runtime State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ignore Remote Pi's repository-local runtime directory globally without hiding other `.pi` project configuration.

**Architecture:** Extend the managed `~/.gitignore` template with one targeted pattern. Protect the contract with a shell test registered in CI.

**Tech Stack:** Git ignore rules, Bash contract test, GitHub Actions.

## Global Constraints

- Ignore `**/.pi/remote-pi/` at repository root and below nested working directories.
- Do not ignore all of `.pi/`.
- Preserve existing Remote Pi configuration files.

---

### Task 1: Add the managed global ignore rule

**Files:**
- Modify: `roles/common/templates/dotfiles/gitignore`
- Create: `tests/gitignore-contract.sh`
- Modify: `.github/workflows/integration-test.yml`

- [ ] Add a failing contract test that requires exactly `**/.pi/remote-pi/`, proves root and nested runtime files are ignored, and rejects a blanket `.pi/` entry.
- [ ] Run `bash tests/gitignore-contract.sh` and confirm it fails.
- [ ] Add the targeted Remote Pi section to the managed global Git ignore template.
- [ ] Register the contract test in the integration workflow.
- [ ] Run the contract and CI inventory tests; confirm both pass.
- [ ] Commit the implementation.

### Task 2: Deploy and verify

- [ ] Run `bin/provision` and require `failed=0`.
- [ ] Remove the temporary repository-local broad `.pi/` exclusion.
- [ ] Verify `git check-ignore -v .pi/remote-pi/config.json` reports `~/.gitignore` and the primary checkout is clean.
- [ ] Open a pull request.
