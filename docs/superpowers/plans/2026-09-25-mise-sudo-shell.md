# Mise sudo shell compatibility implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the managed mise config from setting an unsupported package-manager enum in older mise processes.

**Architecture:** Remove the global setting in the common role template. The existing explicit environment in both managed npm tool installation tasks continues to select aube.

**Tech Stack:** Ansible template, mise CLI.

**Spec:** `docs/superpowers/specs/2026-09-25-mise-sudo-shell-design.md`

## Global Constraints

- Do not grant root trust in a user-writable repository.
- Do not edit deployed dotfiles directly; use `bin/provision`.
- Do not add a static configuration assertion as an automated test.

---

### Task 1: Remove incompatible global setting

**Files:**
- Modify: `roles/common/templates/dotfiles/mise/config.toml:10`

**Interfaces:** The template renders to `~/.config/mise/config.toml`; the install tasks in `roles/common/tasks/main.yml` set `MISE_NPM_PACKAGE_MANAGER: aube` independently.

- [ ] **Step 1: Capture the failing boundary.** Confirm the live config has `npm.package_manager = "aube"` and record the user-reported older mise error. Run `ssh dev 'grep -nF "npm.package_manager" ~/.config/mise/config.toml'`.
- [ ] **Step 2: Make the minimal edit.** Delete only the `npm.package_manager = "aube"` line from the template. Leave the `[settings]` section and the installer task environment unchanged.
- [ ] **Step 3: Verify.** Render or copy the non-interpolated settings section into a temporary mise config and run `mise settings ls` with it. Check that `npm.package_manager` resolves to `auto` in a clean home; run `MISE_NPM_PACKAGE_MANAGER=aube mise settings get npm.package_manager` with the live mise version to confirm explicit override. Validate Ansible syntax and run `bin/provision` to apply when safe. A password-protected root shell is not a valid automated verification boundary.
- [ ] **Step 4: Commit.** Use `z-commit` to commit the template and this plan. Do not commit temporary config or deployed files.

### Task 2: Publish and report remaining root trust warning

**Files:** None.

- [ ] **Step 1: Verify the branch is clean and invoke `z-pull-request`.** Include a `## Verification` section with manual evidence or `Not performed.`
- [ ] **Step 2: State the unresolved root-shell trust warning.** `sudo -i` starts in root's home and avoids the inherited project directory; do not run `mise trust` as root on a user-writable repo. Do not claim `sudo su` succeeds without a real root-shell run.
