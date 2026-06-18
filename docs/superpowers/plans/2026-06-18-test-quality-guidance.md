# Test Quality Guidance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update durable agent and reviewer guidance so future agents avoid tautological tests and prefer behavior-focused verification.

**Architecture:** This is guidance-only work. `new-machine-bootstrap` owns the deployed Claude/Codex guidance and shared skills; `home-network-provisioning` owns the Codex PR reviewer prompt. Existing test cleanup is intentionally excluded because another session owns it.

**Tech Stack:** Markdown guidance, Ansible-managed agent config files, Ruby-based Codex PR review tooling in `hnp`.

---

### File Map

- Modify: `README.md` - repo-local test policy for `new-machine-bootstrap`.
- Modify: `roles/common/files/claude/CLAUDE.md.d/00-base.md` - deployed base agent instruction copied to Claude/Codex contexts.
- Modify: `roles/common/files/config/skills/common/_validate-plan/SKILL.md` - validation skill guidance that checks test coverage.
- Modify: `roles/common/files/config/skills/common/_spec-to-pr/SKILL.md` if it repeats test expectations that imply ceremonial coverage.
- Modify: `/Users/brian/projects/home-network-provisioning/tools/codex-pr-review/upstream_review_prompt.md` - automated PR reviewer rubric.
- Do not modify existing `tests/` files in this plan.

### Task 1: Update `new-machine-bootstrap` Test Guidance

**Files:**
- Modify: `README.md`
- Modify: `roles/common/files/claude/CLAUDE.md.d/00-base.md`

- [x] **Step 1: Inspect current guidance**

Run:

```bash
sed -n '42,70p' README.md
sed -n '1,35p' roles/common/files/claude/CLAUDE.md.d/00-base.md
```

Expected: the README only says CI is the source of truth, and base guidance only says `Testing: use Red/Green TDD`.

- [x] **Step 2: Replace README testing section**

Edit the `## Testing` section so it keeps the existing command examples and replaces the final paragraph with:

```markdown
CI is the test source of truth. Do not add standalone test files unless `.github/workflows/integration-test.yml` invokes them directly. The CI inventory check fails when tracked test-like files are not referenced by a workflow run step.

Tests must prove behavior that can break. A useful test fails for a plausible regression, survives harmless refactors, and asserts behavior, generated structure, or an external contract. Do not add tests that only assert exact prose, YAML snippets, install-loop entries, README wording, skill text, or command strings unless that literal text is itself a user-facing compatibility contract. No automated test is better than a tautological test; use focused manual or end-to-end verification when no useful automated test exists.
```

- [x] **Step 3: Replace base agent testing bullet**

In `roles/common/files/claude/CLAUDE.md.d/00-base.md`, replace:

```markdown
* Testing: use Red/Green TDD.
```

with:

```markdown
* Testing: use Red/Green TDD only for meaningful behavior tests. A useful test fails for a plausible regression and survives harmless refactors. Do not add tautological tests that merely assert exact prose, YAML snippets, install-loop entries, docs wording, skill text, or command strings. No test is better than a tautological test; use manual or end-to-end verification when no useful automated test exists.
```

- [x] **Step 4: Verify guidance directly**

Run:

```bash
rg -n "tautological|plausible regression|No automated test is better|No test is better" README.md roles/common/files/claude/CLAUDE.md.d/00-base.md
```

Expected: matches in both files.

- [x] **Step 5: Commit Task 1**

Run:

```bash
git add README.md roles/common/files/claude/CLAUDE.md.d/00-base.md
git commit -m "Clarify meaningful test guidance"
```

### Task 2: Update Shared Skill Guidance

**Files:**
- Modify: `roles/common/files/config/skills/common/_validate-plan/SKILL.md`
- Modify if needed: `roles/common/files/config/skills/common/_spec-to-pr/SKILL.md`

- [x] **Step 1: Inspect skill guidance**

Run:

```bash
rg -n "test coverage|Tests pass|automated|verification|test" roles/common/files/config/skills/common/_validate-plan/SKILL.md roles/common/files/config/skills/common/_spec-to-pr/SKILL.md
```

Expected: `_validate-plan` contains test coverage and automated verification guidance; `_spec-to-pr` may only mention verification generically.

- [x] **Step 2: Update validation guidance**

In `_validate-plan/SKILL.md`, revise the test coverage guidance so it says:

```markdown
Check whether meaningful tests were added or modified as specified. A meaningful test proves behavior that can break: it fails for a plausible regression, survives harmless refactors, and asserts behavior, generated structure, or an external contract. Do not treat tautological string-presence checks over prose, install lists, docs, or skill text as useful coverage unless the exact string is a user-facing compatibility contract. If no useful automated test exists, verify with focused manual or end-to-end steps and say why no test was added.
```

Keep the rest of the validation workflow intact.

- [x] **Step 3: Update spec-to-PR guidance only if needed**

If `_spec-to-pr/SKILL.md` contains language that broadly requires tests for all changes, replace it with the same meaningful-test standard. If it only says to verify work, leave it unchanged.

- [x] **Step 4: Verify no placeholder language**

Run:

```bash
rg -n "appropriate tests|write tests for|test coverage" roles/common/files/config/skills/common/_validate-plan/SKILL.md roles/common/files/config/skills/common/_spec-to-pr/SKILL.md
```

Expected: no new placeholder-style guidance; remaining `test coverage` wording must be tied to meaningful tests.

- [x] **Step 5: Commit Task 2**

Run:

```bash
git add roles/common/files/config/skills/common/_validate-plan/SKILL.md roles/common/files/config/skills/common/_spec-to-pr/SKILL.md
git commit -m "Teach validation to reject tautological tests"
```

If `_spec-to-pr/SKILL.md` was not changed, omit it from `git add`.

### Task 3: Update `hnp` Codex Reviewer Prompt

**Files:**
- Modify: `/Users/brian/projects/home-network-provisioning/tools/codex-pr-review/upstream_review_prompt.md`

- [ ] **Step 1: Start or reuse an `hnp` feature worktree**

Run from `/Users/brian/projects/home-network-provisioning`:

```bash
repo-start test-quality-reviewer-guidance
```

Expected: prints a non-main worktree path. Use that path for all `hnp` edits. If `repo-start` reports an existing branch/worktree, use the printed path.

- [ ] **Step 2: Add reviewer rubric guidance**

In `tools/codex-pr-review/upstream_review_prompt.md`, add this under the repository-specific `GUIDELINES:` list:

```markdown
- Treat newly added tautological tests as actionable maintainability bugs when they create false confidence or lock implementation text. Flag tests that only assert exact strings, config snippets, prose, install-list membership, or other implementation text when behavior could be verified by running the system or parsing generated structure. Do not demand tests for every change; if existing end-to-end checks or manual verification are more useful, accept that. Prefer findings that ask the author to delete unhelpful tests, replace them with behavior tests, or document manual verification. Do not flag pre-existing bad tests unless the PR adds to them or relies on them as proof.
```

- [ ] **Step 3: Verify prompt text directly**

Run in the `hnp` worktree:

```bash
rg -n "tautological tests|false confidence|manual verification|pre-existing bad tests" tools/codex-pr-review/upstream_review_prompt.md
```

Expected: one guideline block contains all phrases.

- [ ] **Step 4: Run narrow reviewer tests if prompt tests exist**

Run in the `hnp` worktree:

```bash
ruby -Itest test/codex_pr_review_test.rb
```

Expected: pass. If it fails only because an existing test asserts prompt text, update that test only if it verifies behavior or prompt assembly rather than exact wording.

- [ ] **Step 5: Commit Task 3 in `hnp`**

Run in the `hnp` worktree:

```bash
git add tools/codex-pr-review/upstream_review_prompt.md
git commit -m "Guide reviewer away from tautological tests"
```

### Task 4: Final Verification and PRs

**Files:**
- Read: all modified files in both repos

- [ ] **Step 1: Verify `nmb` guidance and status**

Run in the `nmb` worktree:

```bash
rg -n "tautological|plausible regression|manual or end-to-end verification|meaningful tests" README.md roles/common/files/claude/CLAUDE.md.d/00-base.md roles/common/files/config/skills/common/_validate-plan/SKILL.md
git status --short
```

Expected: guidance matches are present; status is clean.

- [ ] **Step 2: Verify `hnp` reviewer guidance and status**

Run in the `hnp` worktree:

```bash
rg -n "tautological tests|false confidence|manual verification|pre-existing bad tests" tools/codex-pr-review/upstream_review_prompt.md
git status --short
```

Expected: reviewer prompt matches are present; status is clean.

- [ ] **Step 3: Re-check memento for concrete terms**

Run in each repo:

```bash
memento context "tautological tests meaningful behavior tests reviewer guidance"
```

Expected: either relevant entries are reviewed and annotated if needed, or the command failure is reported in the final answer.

- [ ] **Step 4: Open pull requests**

Run PR creation from each worktree after verification passes:

```bash
create-pull-request
```

Expected: one PR for `nmb`, one PR for `hnp`.
