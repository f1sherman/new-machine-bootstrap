# AI Hero Skills Adoption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install six selected AI Hero skills across Claude Code, Codex, and Pi with reviewable, Renovate-driven upstream updates and documented usage decisions.

**Architecture:** A Node.js generator vendors selected directories from a pinned `mattpocock/skills` tag and applies a small fail-closed patch set. Ansible reconciles generated skill directories into all three harnesses by checksum. Renovate updates the pin and invokes the generator so each dependency PR contains the full behavior diff.

**Tech Stack:** Node.js standard library and test runner, Git, Ansible, Renovate, Markdown

**Spec:** `docs/superpowers/specs/2026-09-17-ai-hero-skills-design.md`

## Global Constraints

- Initial upstream tag: `v1.2.3`.
- Initial annotated tag object: `835450ef244ab7335f75d95b83e7d979eae22a6d`.
- Initial peeled source commit: `6acc160e4e0cd062dbbbd7a1b26ae92855edf07e`.
- Preserve original upstream skill names across all harnesses.
- Deep-design skills must require explicit user invocation in Claude, Codex, and Pi.
- Generated updates must fail closed when local patch preconditions no longer match.
- The complete evaluation remains in `docs/ai-hero-skills-guide.md`.

---

### Task 1: Build the deterministic upstream generator

**Files:**
- Create: `bin/update-ai-hero-skills`
- Create: `tests/update-ai-hero-skills.test.js`
- Modify: `vars/tool_versions.yml`
- Generate: `roles/common/files/vendor/mattpocock-skills/**`

**Interfaces:**
- Consumes: `tool_versions.git_tags.mattpocock_skills` from `vars/tool_versions.yml`; an optional `--source <git-checkout>`; optional `--repo-root <path>` for tests.
- Produces: a complete generated vendor tree; `--check` exits nonzero on drift; `--allow-moved-tag` is the explicit override for a moved existing tag.

- [ ] **Step 1: Write the updater behavior tests**

Use Node's built-in test runner to create a temporary upstream Git repository
with all six skill paths. Assert that a normal generation:

- Copies only the selected complete directories.
- Adds `LICENSE`, `UPSTREAM.md`, and `.managed-checksum` to every skill.
- Enforces `disable-model-invocation: true` for all three deep-design skills.
- Enforces Codex `policy.allow_implicit_invocation: false` for all three.
- Replaces exactly the approved `grill-with-docs` portability preimage.
- Smoke-checks the wrapper fallback for an absent mechanism or inability to load
  either dependency, including invocation-policy rejection; reads both generated
  sibling targets without claiming to test real interactive harness invocation.
- Replaces exactly the approved merge-conflict sentence.
- Removes stale generated files on regeneration.
- Makes `--check` pass when synchronized and fail after drift.
- Rejects a moved existing tag without `--allow-moved-tag`.
- Rejects a symlink in a selected source tree or upstream LICENSE; preserves an
  existing vendor tree on rejection.
- Verifies executable-mode hashing with identical provenance bytes.
- Fails when either content patch preimage is absent or duplicated.

- [ ] **Step 2: Run the updater tests and verify failure**

Run:

```bash
node --test tests/update-ai-hero-skills.test.js
```

Expected: FAIL because `bin/update-ai-hero-skills` does not exist.

- [ ] **Step 3: Add the pinned upstream tag**

Add under `tool_versions.git_tags`:

```yaml
# renovate: datasource=github-tags depName=mattpocock/skills
mattpocock_skills: v1.2.3
```

- [ ] **Step 4: Implement the generator**

Implement an executable Node.js script using only standard-library modules and
Git subprocesses. Keep the selected source path map in one constant. Parse CLI
arguments explicitly. Resolve tags to commits, require a regular non-symlink
upstream LICENSE, reject source symlinks, validate
frontmatter and Codex metadata, apply the exact `grill-with-docs` portability
and merge-conflict preimages, write provenance and license files, calculate
per-skill checksums, and replace the vendor tree through a temporary sibling
directory.

In check mode, generate to a temporary directory and compare recursively without
modifying the repository. When the existing generated metadata records the same
tag with another commit, fail unless `--allow-moved-tag` is present.

- [ ] **Step 5: Run tests and fix until green**

Run:

```bash
node --test tests/update-ai-hero-skills.test.js
```

Expected: PASS.

- [ ] **Step 6: Generate the pinned upstream copies**

Run:

```bash
bin/update-ai-hero-skills
bin/update-ai-hero-skills --check
```

Expected: both commands exit 0; the second reports synchronized content.

- [ ] **Step 7: Commit the generator slice**

Use `z-commit` with a commit message such as:

```text
feat(skills): vendor selected AI Hero skills
```

### Task 2: Reconcile the selected skills into all harnesses

**Files:**
- Modify: `roles/common/tasks/main.yml`

**Interfaces:**
- Consumes: each generated skill directory and `.managed-checksum`.
- Produces: identical named skill directories under `~/.claude/skills`, `~/.codex/skills`, and `~/.pi/agent/skills`, with stale upstream files removed when the checksum changes.

- [ ] **Step 1: Add the selected skill and harness-root variables**

Define the six selected names once near the existing skill installation tasks.
Define the three destination roots once. Use their Cartesian product for marker
checks, outdated-directory removal, and copy operations.

- [ ] **Step 2: Add checksum-driven reconciliation**

For each skill and harness root:

1. Read the deployed `.managed-checksum` without failing when absent.
2. Remove the whole destination directory when the marker is absent or differs.
3. Copy the generated skill directory with preserved file modes and `0755`
   directories.

A same-version provision must report no skill changes. Keep future retired skill
cleanup consistent with the existing explicit deleted-managed-skill lists.

- [ ] **Step 3: Validate Ansible syntax**

Run:

```bash
ansible-playbook --syntax-check playbook.yml
```

Expected: exit 0.

- [ ] **Step 4: Commit the installation slice**

Use `z-commit` with a commit message such as:

```text
feat(skills): install AI Hero skills across harnesses
```

### Task 3: Automate tagged upstream refreshes

**Files:**
- Modify: `renovate.json`
- Modify: `.github/workflows/renovate.yml`

**Interfaces:**
- Consumes: new `mattpocock/skills` tags older than the repository's seven-day minimum release age.
- Produces: a Renovate PR containing the pin update and regenerated vendor tree.

- [ ] **Step 1: Add the bounded package rule**

Add a package rule matching only `mattpocock/skills`. Give it a stable commit
topic and label. Configure one `postUpgradeTasks` command:

```text
bin/update-ai-hero-skills
```

Bound its file filters to `vars/tool_versions.yml` and
`roles/common/files/vendor/mattpocock-skills/**`. Use update execution mode.

- [ ] **Step 2: Permit only the updater command**

Add this environment variable to the Renovate action step:

```yaml
RENOVATE_ALLOWED_COMMANDS: '^bin/update-ai-hero-skills$'
```

- [ ] **Step 3: Validate configuration syntax and generator check**

Run:

```bash
node -e 'JSON.parse(require("fs").readFileSync("renovate.json", "utf8"))'
bin/update-ai-hero-skills --check
```

Expected: both exit 0.

- [ ] **Step 4: Commit the update automation slice**

Use `z-commit` with a commit message such as:

```text
chore(skills): automate AI Hero updates
```

### Task 4: Apply retained improvements to current workflows

**Files:**
- Modify: `roles/common/files/config/skills/common/_fix/SKILL.md`
- Modify: `roles/common/files/config/skills/pi/z-fix/SKILL.md`
- Modify: `roles/common/files/config/skills/common/_create-handoff/SKILL.md`
- Modify: `roles/common/files/config/skills/pi/z-create-handoff/SKILL.md`

**Interfaces:**
- Consumes: difficult bug reports and user-requested handoffs.
- Produces: stronger diagnosis evidence and safer, less duplicated handoffs.

- [ ] **Step 1: Add the difficult-bug diagnosis contract**

Add the same concise guidance to both fix skills. For difficult, intermittent,
or performance bugs, require a named command that can detect the exact symptom,
a minimized reproduction, multiple ranked falsifiable hypotheses, uniquely
tagged temporary instrumentation, redaction before output is shown, and a
regression test only at a seam that reproduces the real failure.

Do not replace or duplicate the full systematic-debugging skill.

- [ ] **Step 2: Add handoff redaction and reference rules**

Add the same concise guidance to both handoff skills. Require secret and
personal-information redaction. Require existing specs, plans, ADRs, issues,
commits, and diffs to be referenced instead of copied.

- [ ] **Step 3: Review the four skill edits against `writing-for-agents`**

Confirm that each new instruction changes behavior, appears once, and sits in
the smallest on-demand skill rather than always-loaded global guidance.

- [ ] **Step 4: Commit the retained workflow improvements**

Use `z-commit` with a commit message such as:

```text
refactor(skills): tighten debugging and handoffs
```

### Task 5: Complete the durable usage guide

**Files:**
- Modify: `docs/ai-hero-skills-guide.md`

**Interfaces:**
- Consumes: the approved decisions and installed skill behavior.
- Produces: a complete install/skip ledger, usage guide, update instructions, retained-principle list, and follow-up recommendations.

- [ ] **Step 1: Add an installed-skills quick reference**

For each installed skill, state the exact trigger, whether it is user-only, and
when not to use it. Include explicit invocation syntax for Claude, Codex, and Pi
where it differs.

- [ ] **Step 2: Add maintenance instructions**

Document the pin, generated directory, manual update command, check command,
Renovate behavior, local patch policy, and how to review an upstream update.

- [ ] **Step 3: Preserve the post-merge confirmation follow-up**

Keep the separate recommendation for a selective post-merge workflow that
defines the intended effect before merge and verifies it in the relevant live
environment afterward.

- [ ] **Step 4: Check all 25 decisions and prose**

Run:

```bash
rg '^\| `' docs/ai-hero-skills-guide.md
rg -n 'TBD|TODO|Not evaluated|Deferred' docs/ai-hero-skills-guide.md
```

Expected: 25 decision rows and no unfinished state.

- [ ] **Step 5: Commit the guide**

Use `z-commit` with a commit message such as:

```text
docs(skills): add AI Hero usage guide
```

### Task 6: End-to-end verification and pull request

**Files:**
- Verify all modified and generated files.

**Interfaces:**
- Consumes: the complete feature branch.
- Produces: a clean, provisioned branch and an open pull request.

- [ ] **Step 1: Run focused and static checks**

Run:

```bash
node --test tests/update-ai-hero-skills.test.js
bin/update-ai-hero-skills --check
ansible-playbook --syntax-check playbook.yml
git diff --check
```

Expected: all exit 0.

- [ ] **Step 2: Provision from the feature worktree**

Run:

```bash
bin/provision
```

Expected: exit 0 with provenance naming this worktree and branch.

- [ ] **Step 3: Inspect deployed skill contracts**

Confirm all six names exist in each harness directory. Confirm all three
deep-design `SKILL.md` files contain `disable-model-invocation: true`, all three
Codex metadata files disable implicit invocation, and representative supporting
files exist.

- [ ] **Step 4: Verify idempotence**

Run:

```bash
bin/provision --check
```

Expected: exit 0 with no unexpected skill changes.

- [ ] **Step 5: Review and commit any final fixes**

Invoke `z-review`, address worthwhile findings, and use `z-commit` for final
changes. Confirm the worktree is clean.

- [ ] **Step 6: Create the pull request**

Invoke `z-pull-request`. The PR body must contain a `## Verification` section
that follows repository guidance.
