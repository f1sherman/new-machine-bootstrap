# Descriptive Session Names Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make issue-driven Pi session names describe the referenced work instead of relying on opaque identifiers.

**Architecture:** The tool-free automatic naming child returns a reserved insufficient-context marker for identifier-only prompts, and the hook leaves the session unnamed. The main-agent tool and manual skill require inspection of accessible referenced content before they choose a descriptive name.

**Tech Stack:** TypeScript Pi extension, Markdown Pi skill, shell-based behavior checks

**Spec:** `docs/superpowers/specs/2026-09-21-descriptive-session-names-design.md`

## Global Constraints

- Do not add tracker access, credentials, or network calls to the automatic hook.
- Preserve existing session naming length, lifecycle, and broad-outcome rules.
- Use the issue subject and broad outcome as the name; keep an identifier only as optional secondary context.

---

### Task 1: Handle insufficient automatic naming context

**Files:**
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts`

**Interfaces:**
- Consumes: Initial user prompt supplied to `evaluateInitialSessionGoal`.
- Produces: A reserved `NEEDS_CONTEXT` child result that causes no automatic rename and no failure warning.

- [ ] **Step 1: Record the failing behavior check**

Run the current automatic child prompt five times with `Fix HNP issue 1822` and
record that every output depends on the opaque identifier.

- [ ] **Step 2: Add the minimal insufficient-context contract**

Update the child prompt to return `NEEDS_CONTEXT` when the prompt gives only an
opaque reference. Handle that exact marker before ordinary output validation and
return without applying a session name.

- [ ] **Step 3: Verify the prompt behavior**

Run five fresh child evaluations for the identifier-only prompt. Require
`NEEDS_CONTEXT` each time. Run five more with the issue title and expected
outcome in the prompt. Require descriptive names each time.

### Task 2: Require referenced-content inspection in naming guidance

**Files:**
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts`
- Modify: `roles/common/files/config/skills/pi/z-update-session-name/SKILL.md`

**Interfaces:**
- Consumes: An issue, ticket, PR, branch, commit, or similar reference in the
  conversation.
- Produces: A session name whose recognizable subject and broad outcome come
  from inspected reference content.

- [ ] **Step 1: Update the tool contract**

Add a positive recipe: inspect accessible referenced content first, name its
recognizable subject and broad outcome, and use the identifier only as optional
secondary context.

- [ ] **Step 2: Update the manual skill**

Add the same decision rule to `z-update-session-name` without duplicating
unrelated lifecycle guidance.

- [ ] **Step 3: Review wording against the observed failure**

Confirm that `HNP issue 1822 fix` fails the contract and that a descriptive name
such as `Provisioning identity safety` passes it.

### Task 3: Verify, deploy, and publish

**Files:**
- Verify: `tests/pi-managed-hooks.sh`
- Deploy: `bin/provision`

**Interfaces:**
- Consumes: The completed source changes.
- Produces: Verified and deployed Pi naming guidance, plus an open pull request.

- [ ] **Step 1: Run the managed-hook test**

Run `tests/pi-managed-hooks.sh` and require exit status 0.

- [ ] **Step 2: Provision from the worktree**

Run `bin/provision` and require successful completion.

- [ ] **Step 3: Inspect deployed artifacts**

Confirm the deployed managed hook and `z-update-session-name` skill contain the
new insufficient-context and reference-inspection rules.

- [ ] **Step 4: Commit and open the pull request**

Use the repository commit and pull-request workflows. Include verification that
is not duplicated by normal PR automation.

## Status

Self-reviewed and self-approved for execution.
