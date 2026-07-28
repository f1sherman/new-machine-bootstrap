# Retire `.coding-agent` Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove repository-owned `.coding-agent` artifacts and active workflow support while migrating local handoffs to `.superpowers/handoffs/`.

**Architecture:** Delete the retired tracked artifact tree, remove lifecycle copy/sync behavior at its source, and update managed handoff skills to one local ignored location. Preserve historical `docs/superpowers/` references and avoid destructive cleanup of unrelated repositories.

**Tech Stack:** Bash, Ruby tests, Ansible-managed skills/configuration, Pi/Claude/Codex guidance

## Global Constraints

- Delete every tracked file under `.coding-agent/`.
- Preserve historical `.coding-agent` references inside pre-existing `docs/superpowers/` documents.
- Do not find, migrate, or delete `.coding-agent` directories in unrelated repositories or deployed workspaces.
- Store new handoffs under `.superpowers/handoffs/YYYY-MM-DD_HH-MM-SS_<description>.md`.
- Remove ticket-specific handoff directory and identifier conventions.
- Preserve `.repo.yml` propagation and `.claude/settings.local.json` copying.
- Do not change `.superpowers/` behavior outside the new `handoffs/` subtree.
- Make source changes only in this repository; deploy through `bin/provision`.

---

## File Structure

- `.coding-agent/**` — delete all 29 retired tracked artifacts.
- `roles/common/files/bin/repo-lib.sh`, `repo-start`, `worktree-lib.sh`, `worktree-start`, `worktree-done` — remove `.coding-agent` copy/sync behavior.
- `tests/repo-lifecycle.sh` — assert linked worktrees do not receive `.coding-agent` content.
- `roles/common/files/config/skills/{common/_create-handoff,pi/z-create-handoff}/SKILL.md` — create local handoffs under `.superpowers/handoffs/`.
- `roles/common/files/config/skills/{claude,codex}/_resume-handoff/SKILL.md`, `roles/common/files/config/skills/pi/z-resume-handoff/SKILL.md` — resume explicit or newest local handoff without retired-path assumptions.
- `roles/common/files/bin/{codex-bind-tmux-pane,tmux-claude-session-start}` — remove retired recovery source.
- `roles/dev_host/tasks/main.yml` — replace retired write permissions with precise `.superpowers/handoffs/**` permission.
- `.claude/settings.local.json` — remove stale command permission mentioning a retired artifact.
- `tests/paranoid-package-tools.rb` — remove the deleted tree from skip patterns.

### Task 1: Remove worktree lifecycle synchronization

**Files:**
- Modify: `roles/common/files/bin/repo-lib.sh`
- Modify: `roles/common/files/bin/repo-start`
- Modify: `roles/common/files/bin/worktree-lib.sh`
- Modify: `roles/common/files/bin/worktree-start`
- Modify: `roles/common/files/bin/worktree-done`
- Modify: `tests/repo-lifecycle.sh`

**Interfaces:**
- Consumes: current `repo-start`, `repo-end`, `worktree-start`, and `worktree-done` CLIs.
- Produces: unchanged lifecycle CLIs that no longer copy or sync `.coding-agent` state.

- [ ] **Step 1: Change the lifecycle test to express retirement**

Keep the disposable source fixture:

```bash
mkdir -p "$worktree_repo/.coding-agent" "$worktree_repo/.claude"
printf 'note\n' >"$worktree_repo/.coding-agent/note.txt"
```

Replace the positive copy assertion with a negative behavior assertion:

```bash
[ ! -e "$worktree_path/.coding-agent" ] || \
  fail_case "worktree mode leaves retired .coding-agent state behind" \
    "unexpected .coding-agent at $worktree_path"
```

Retain the existing positive assertions for `.repo.yml`, `.claude/settings.local.json`, and the requested branch.

Add or extend the existing worktree-finish fixture so a `.coding-agent` file created only in the linked worktree is not copied back to the main checkout when the lifecycle command completes.

- [ ] **Step 2: Run the lifecycle test to verify RED**

Run:

```bash
bash tests/repo-lifecycle.sh
```

Expected: FAIL because `repo-start` still copies `.coding-agent` into the linked worktree.

- [ ] **Step 3: Remove synchronization helpers and calls**

Delete `_worktree_sync_coding_agent_new_files` from both `repo-lib.sh` and `worktree-lib.sh`.

Delete the dedicated calls from:

```text
repo-start
worktree-start
worktree-done
```

Do not alter `_worktree_copy_new_files`, `.repo.yml` copying, Claude local-settings copying, or unrelated warning behavior.

- [ ] **Step 4: Run lifecycle and syntax checks**

Run:

```bash
bash tests/repo-lifecycle.sh
bash -n \
  roles/common/files/bin/repo-lib.sh \
  roles/common/files/bin/repo-start \
  roles/common/files/bin/worktree-lib.sh \
  roles/common/files/bin/worktree-start \
  roles/common/files/bin/worktree-done \
  tests/repo-lifecycle.sh
git diff --check
```

Expected: all commands pass.

- [ ] **Step 5: Commit lifecycle retirement**

Invoke `z-commit` for the six files with message `Stop syncing retired coding-agent state`.

### Task 2: Migrate handoff skills to `.superpowers/handoffs`

**Files:**
- Modify: `roles/common/files/config/skills/common/_create-handoff/SKILL.md`
- Modify: `roles/common/files/config/skills/pi/z-create-handoff/SKILL.md`
- Modify: `roles/common/files/config/skills/claude/_resume-handoff/SKILL.md`
- Modify: `roles/common/files/config/skills/codex/_resume-handoff/SKILL.md`
- Modify: `roles/common/files/config/skills/pi/z-resume-handoff/SKILL.md`

**Interfaces:**
- Consumes: create/resume handoff skill triggers and existing handoff document schema.
- Produces: local files matching `.superpowers/handoffs/YYYY-MM-DD_HH-MM-SS_<description>.md`; resume accepts an explicit path or chooses the newest local Markdown handoff.

- [ ] **Step 1: Establish behavior-shaping RED evidence before edits**

Run at least five fresh-context create-handoff pressure samples against the current Pi skill. Scenario: the agent must choose an output path without being given one. Record whether it selects `.coding-agent`.

Run at least five fresh-context resume-handoff samples against the current Pi skill. Scenario: no explicit path is supplied and both retired and proposed locations are described. Record which directory it searches.

Save the control results in this plan's ignored SDD workspace.

- [ ] **Step 2: Micro-test proposed create/resume contracts**

Against the full current skills with the relevant path sections mentally replaced, run at least five fresh-context samples per proposed contract:

```text
Create: write .superpowers/handoffs/YYYY-MM-DD_HH-MM-SS_<description>.md.
Resume: when no explicit path is supplied, locate the newest *.md beneath .superpowers/handoffs; never search or recreate .coding-agent.
```

Expected: every proposed-guidance sample chooses `.superpowers/handoffs/` and none chooses `.coding-agent`.

- [ ] **Step 3: Update create-handoff guidance**

In both create-handoff skills:

- replace ticket-specific nested paths with `.superpowers/handoffs/YYYY-MM-DD_HH-MM-SS_<description>.md`;
- create `.superpowers/handoffs/` as needed;
- retain ISO metadata, branch/repository context, concise content sections, and the user review step;
- remove ticket identifiers from examples, headings, and confirmation output;
- preserve only generic public-repository-safe examples.

Keep the two files semantically identical except for harness-specific names or tool wording.

- [ ] **Step 4: Update resume-handoff guidance**

In all three resume skills:

- explicit path: read the file fully, then read every critical linked artifact regardless of its ordinary repository path;
- no explicit path: enumerate Markdown files recursively beneath `.superpowers/handoffs/`, select the newest timestamped file, and report clearly if none exists;
- remove ticket-number lookup branches and `.coding-agent/plans`, `.coding-agent/research`, and `.coding-agent/handoffs` assumptions;
- replace obsolete examples with `.superpowers/handoffs/...` examples;
- preserve the existing verification, synthesis, and continuation process.

- [ ] **Step 5: Verify revised skill behavior and references**

Repeat the pressure scenarios against the edited skills. Run:

```bash
rg -n '\.coding-agent|ENG-[A-Z0-9-]+' \
  roles/common/files/config/skills/common/_create-handoff/SKILL.md \
  roles/common/files/config/skills/pi/z-create-handoff/SKILL.md \
  roles/common/files/config/skills/claude/_resume-handoff/SKILL.md \
  roles/common/files/config/skills/codex/_resume-handoff/SKILL.md \
  roles/common/files/config/skills/pi/z-resume-handoff/SKILL.md
```

Expected: no matches. Revised fresh-context samples consistently use `.superpowers/handoffs/`.

- [ ] **Step 6: Commit handoff migration**

Invoke `z-commit` for the five skill files with message `Move local handoffs under superpowers`.

### Task 3: Delete retired artifacts and remaining active references

**Files:**
- Delete: `.coding-agent/**`
- Modify: `.claude/settings.local.json`
- Modify: `roles/common/files/bin/codex-bind-tmux-pane`
- Modify: `roles/common/files/bin/tmux-claude-session-start`
- Modify: `roles/dev_host/tasks/main.yml`
- Modify: `tests/paranoid-package-tools.rb`

**Interfaces:**
- Consumes: current session-recovery reminders, dev-host project permissions, and package safety scan.
- Produces: no active `.coding-agent` references; handoff write permission targets `.superpowers/handoffs/**` only.

- [ ] **Step 1: Delete the tracked artifact tree**

Run:

```bash
git rm -r .coding-agent
```

Expected: all 29 tracked artifacts are staged for deletion. Do not delete similarly named directories anywhere else.

- [ ] **Step 2: Remove remaining helper and configuration references**

- In both tmux session helpers, change the recovery source phrase from `conversation history, plan files, or .coding-agent state` to `conversation history or current plan files`.
- In `roles/dev_host/tasks/main.yml`, replace the three `.coding-agent` write permissions with one precise entry:

```text
Write(.superpowers/handoffs/**)
```

- Remove the stale `.coding-agent` command entry from `.claude/settings.local.json`.
- Remove `%r{\A\.coding-agent/}` from `SKIP_PATH_PATTERNS` in `tests/paranoid-package-tools.rb` because the tracked tree no longer exists.

- [ ] **Step 3: Verify active-reference retirement**

Run:

```bash
if rg -n --hidden \
  --glob '!.git/**' \
  --glob '!.worktrees/**' \
  --glob '!.pi-subagents/**' \
  --glob '!docs/superpowers/**' \
  '\.coding-agent' .; then
  echo 'active .coding-agent references remain' >&2
  exit 1
fi

test -z "$(git ls-files '.coding-agent/**')"
```

Expected: no active matches and no tracked `.coding-agent` files.

- [ ] **Step 4: Run affected helper/config tests**

Run:

```bash
ruby tests/paranoid-package-tools.rb
bash tests/tmux-claude-session-start.sh
bash tests/codex-bind-tmux-pane.sh
bash tests/ci-test-inventory.sh
bash -n \
  roles/common/files/bin/codex-bind-tmux-pane \
  roles/common/files/bin/tmux-claude-session-start
git diff --check
```

Expected: all commands pass.

- [ ] **Step 5: Commit artifact and reference removal**

Invoke `z-commit` for the deleted tree and five modified files with message `Remove retired coding-agent artifacts`.

### Task 4: Verify and deploy the complete retirement

**Files:**
- Modify only if verification exposes a defect in Tasks 1-3.

**Interfaces:**
- Consumes: retired lifecycle behavior, migrated handoff skills, and cleaned source tree.
- Produces: provisioned managed files and end-to-end evidence for the pull request.

- [ ] **Step 1: Run the complete focused suite**

Run:

```bash
bash tests/repo-lifecycle.sh
ruby tests/paranoid-package-tools.rb
bash tests/tmux-claude-session-start.sh
bash tests/codex-bind-tmux-pane.sh
bash tests/pi-shared-skills.rb
bash tests/ci-test-inventory.sh
```

If `tests/pi-shared-skills.rb` is not executable through Bash, run it with Ruby. Expected: all suites pass.

- [ ] **Step 2: Run source consistency checks**

Run the active-reference scan from Task 3, then:

```bash
test -z "$(git ls-files '.coding-agent/**')"
git diff --check origin/main...HEAD
git status --short
```

Expected: no active references, no tracked retired files, no whitespace errors, and a clean worktree.

- [ ] **Step 3: Provision from the feature worktree**

Run:

```bash
bin/provision
```

Expected: zero failed Ansible tasks, with log provenance naming `retire-coding-agent-support` and the current commit.

- [ ] **Step 4: Verify deployed handoff guidance**

Check the deployed Pi, Claude, and Codex create/resume skill files. Expected:

- `.superpowers/handoffs/` appears in every relevant deployed skill;
- `.coding-agent` appears in none;
- deployed files compare equal to their repository sources where provisioning uses direct copies.

Do not delete any pre-existing `.coding-agent` data from this or other repositories during this check.

- [ ] **Step 5: Review final scope**

Run:

```bash
git status --short
git diff --stat origin/main...HEAD
git diff --name-status origin/main...HEAD
git log --oneline origin/main..HEAD
```

Expected: the branch contains the approved spec/plan, lifecycle changes/tests, handoff migration, active-reference cleanup, and deletion of the tracked `.coding-agent` tree. Pre-existing historical `docs/superpowers/` files remain unchanged.

- [ ] **Step 6: Push and open the pull request**

Push `retire-coding-agent-support` and open a PR against `main`. Report artifact deletion, lifecycle simplification, handoff migration, pressure-test evidence, focused tests, provisioning provenance, and deployed checks.
