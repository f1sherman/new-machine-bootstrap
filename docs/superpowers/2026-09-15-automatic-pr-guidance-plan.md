# Automatic Pull Request Guidance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use engineering:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make automatic pull request creation the default completion step for verified code changes in first-party repositories.

**Architecture:** Update the existing base instruction fragment for each agent. Keep the existing external-contribution rule as the publication guard, then use the existing Ansible assembly tasks to deploy both files.

**Tech Stack:** Markdown, Ansible provisioning

## Global Constraints

- The existing external-contribution rule remains authoritative for repositories that Brian and his employer do not own.
- The change applies to the managed Claude and Pi global instruction files.
- Do not add an automated test that only asserts exact instruction prose.

---

### Task 1: Add and deploy automatic pull request guidance

**Files:**
- Modify: `roles/common/files/pi/AGENTS.md.d/00-base.md`
- Modify: `roles/common/files/claude/CLAUDE.md.d/00-base.md`
- Create: `docs/superpowers/2026-09-15-automatic-pr-guidance-design.md`
- Create: `docs/superpowers/2026-09-15-automatic-pr-guidance-plan.md`

**Interfaces:**
- Consumes: Existing Ansible copy and assembly tasks for both base fragments.
- Produces: Equivalent first-party pull request authorization in the assembled global instruction files.

**Reviewer Verification:**
- Run `bin/provision`, then use `grep -F` on the two assembled home-directory files. Expected output from each file includes `A request to make code changes in a first-party repository authorizes you to create the pull request.`

- [ ] **Step 1: Update both managed base fragments**

Add this instruction to each file, replacing the weaker Claude pull request instruction:

```markdown
* Pull requests: A request to make code changes in a first-party repository authorizes you to create the pull request. After verification passes and the work is committed, create or update the pull request automatically. Do not stop after local changes or a commit, and do not ask for separate pull request approval. The external-contribution rule still applies to other repositories, including public repositories not owned by the user or the user's employer.
```

- [ ] **Step 2: Review the source diff**

Run: `git diff --check && git diff -- roles/common/files`

Expected: `git diff --check` reports no errors. The diff shows equivalent pull request guidance in both base fragments.

- [ ] **Step 3: Provision the managed files**

Run: `bin/provision`

Expected: Ansible completes with `failed=0`.

- [ ] **Step 4: Verify the assembled files**

Run:

```bash
grep -F \
  'A request to make code changes in a first-party repository authorizes you to create the pull request.' \
  "$HOME/.pi/agent/AGENTS.md" "$HOME/.claude/CLAUDE.md"
```

Expected: One matching line from each assembled file.

- [ ] **Step 5: Verify idempotence**

Run: `bin/provision --check`

Expected: Ansible completes with `failed=0` and reports no pending change for either managed base fragment or assembled instruction file.

- [ ] **Step 6: Commit the change**

```bash
git add docs/superpowers/2026-09-15-automatic-pr-guidance-design.md \
  docs/superpowers/2026-09-15-automatic-pr-guidance-plan.md \
  roles/common/files/pi/AGENTS.md.d/00-base.md \
  roles/common/files/claude/CLAUDE.md.d/00-base.md
git commit -m "docs: create pull requests for code changes"
```

Expected: One commit contains the two managed guidance updates and their design and plan.
