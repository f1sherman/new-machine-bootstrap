# Stop Slop Skill Installation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use engineering:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Vendor and provision the pinned Stop Slop skill for Claude Code, Codex, and Pi.

**Architecture:** Store one `_stop-slop` copy in the existing shared Claude Code and Codex skill source and one `z-stop-slop` copy in the existing Pi skill source. Existing Ansible directory-copy tasks deploy both trees without new task logic.

**Tech Stack:** Ansible file provisioning, Markdown skill files, shell verification

## Global Constraints

- Pin upstream repository `https://github.com/hardikpandya/stop-slop` at commit `8da1f030185bdfe8471220585162991eaeb970e9`.
- Install `_stop-slop` for Claude Code and Codex.
- Install `z-stop-slop` for Pi.
- Preserve the upstream author metadata and complete MIT license.
- Keep upstream instructions and references unchanged except for each `SKILL.md` `name` field and the corrected output in Example 4.
- Do not fetch upstream content during provisioning.
- Do not add a static configuration test that duplicates provisioning checks.

---

### Task 1: Vendor and provision Stop Slop

**Files:**
- Create: `roles/common/files/config/skills/common/_stop-slop/SKILL.md`
- Create: `roles/common/files/config/skills/common/_stop-slop/README.md`
- Create: `roles/common/files/config/skills/common/_stop-slop/LICENSE`
- Create: `roles/common/files/config/skills/common/_stop-slop/UPSTREAM.md`
- Create: `roles/common/files/config/skills/common/_stop-slop/references/examples.md`
- Create: `roles/common/files/config/skills/common/_stop-slop/references/phrases.md`
- Create: `roles/common/files/config/skills/common/_stop-slop/references/structures.md`
- Create: `roles/common/files/config/skills/pi/z-stop-slop/SKILL.md`
- Create: `roles/common/files/config/skills/pi/z-stop-slop/README.md`
- Create: `roles/common/files/config/skills/pi/z-stop-slop/LICENSE`
- Create: `roles/common/files/config/skills/pi/z-stop-slop/UPSTREAM.md`
- Create: `roles/common/files/config/skills/pi/z-stop-slop/references/examples.md`
- Create: `roles/common/files/config/skills/pi/z-stop-slop/references/phrases.md`
- Create: `roles/common/files/config/skills/pi/z-stop-slop/references/structures.md`

**Interfaces:**
- Consumes: Existing recursive copy tasks in `roles/common/tasks/main.yml`.
- Produces: `_stop-slop` skill directories for Claude Code and Codex, and a `z-stop-slop` skill directory for Pi.

**Reviewer Verification:**
- Run `bin/provision`, then compare all three deployed trees with their source trees. Expected result: all comparisons pass, all three metadata names match their directory names, and no em dash remains in either installed skill tree.

- [ ] **Step 1: Confirm the skill is not present**

Run:

```bash
test ! -e roles/common/files/config/skills/common/_stop-slop
test ! -e roles/common/files/config/skills/pi/z-stop-slop
```

Expected: both commands exit 0, which confirms the requested installation is absent.

- [ ] **Step 2: Add the shared Claude Code and Codex skill**

Copy the upstream `SKILL.md`, `README.md`, `LICENSE`, and `references/` files from commit `8da1f030185bdfe8471220585162991eaeb970e9` into `roles/common/files/config/skills/common/_stop-slop/`. Change the frontmatter line `name: stop-slop` to `name: _stop-slop` in `SKILL.md`. In the corrected output for Example 4, replace `Speed, quality, cost—pick two.` with `Pick two: speed, quality, or cost.` so the example follows the skill's ban on em dashes.

Create `UPSTREAM.md` with this exact content:

```markdown
# Upstream Source

- Repository: https://github.com/hardikpandya/stop-slop
- Commit: `8da1f030185bdfe8471220585162991eaeb970e9`
- Author: Hardik Pandya
- License: MIT; see `LICENSE`

This vendored copy changes the `name` field in `SKILL.md` so it matches the
agent-specific installation name. It also removes the em dash from the corrected
output in Example 4 so the example follows the skill's core rules.
```

- [ ] **Step 3: Add the Pi skill**

Copy the shared tree to `roles/common/files/config/skills/pi/z-stop-slop/`.
Change only the frontmatter line `name: _stop-slop` to `name: z-stop-slop` in
the Pi `SKILL.md`.

- [ ] **Step 4: Verify vendored content and attribution**

Fetch upstream files through read-only GitHub API calls into a temporary
comparison directory. Compare `README.md`, `LICENSE`, and the reference files
other than `examples.md` byte-for-byte against both vendored trees. Compare
`SKILL.md` after normalizing the agent-specific `name` to `stop-slop`. Compare
`examples.md` after restoring the upstream Example 4 output. Check both
`UPSTREAM.md` files for the full commit, MIT license reference, and documented
Example 4 correction.

Expected: every comparison exits 0. The shared skill reports
`name: _stop-slop`; the Pi skill reports `name: z-stop-slop`; and neither tree
contains an em dash.

- [ ] **Step 5: Provision and verify all agent destinations**

Run:

```bash
bin/provision
```

Expected: provisioning succeeds and installs the skill at:

```text
~/.claude/skills/_stop-slop
~/.codex/skills/_stop-slop
~/.pi/agent/skills/z-stop-slop
```

Compare each deployed tree with its matching repository source using
`diff -ru`. Expected: all three comparisons produce no output and exit 0.

- [ ] **Step 6: Validate dry-run compatibility**

Run:

```bash
bin/provision --check
```

Expected: the playbook succeeds. Recursive Ansible copy tasks can report
changes in check mode even when deployed file content and modes match their
sources, so verify idempotence through the source-to-destination comparisons in
Step 5.

- [ ] **Step 7: Commit**

Stage the two skill trees and both `docs/superpowers/` documents by explicit
path. Commit with:

```text
feat: install Stop Slop agent skill
```
