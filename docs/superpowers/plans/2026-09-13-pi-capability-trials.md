# Pi Capability Trials Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Roll out structured Pi tools, cache diagnostics, a narrow scout model route, and reviewable session-only watchdog and cache-retention trials.

**Architecture:** Extend NMB's existing recursive Pi settings merge with three explicit managed policies. Keep costly or uncertain features session-scoped and document their evidence gates in one operator runbook.

**Tech Stack:** Ansible YAML, Bash behavioral tests, JSON settings, Markdown

**Spec:** `docs/superpowers/specs/2026-09-13-pi-capability-trials-design.md`

## Global Constraints

- Preserve existing packages, unrelated Pi settings, and every managed main-worktree guard extension.
- Manage the complete built-in tool list because `defaultTools` has replacement semantics.
- Route only `scout`; do not change other subagent role models.
- Do not persist watchdog enablement or `PI_CACHE_RETENTION=long`.
- Do not load a generated pi-subagents profile.
- Do not add schedules, telemetry collectors, or raw transcript storage.

---

### Task 1: Manage tools, diagnostics, and the scout trial route

**Files:**
- Modify: `tests/pi-main-worktree-guard-provisioning.sh`
- Modify: `roles/common/tasks/pi_main_worktree_guard_settings.yml`

**Interfaces:**
- Consumes: Existing recursive `pi_settings | combine(..., recursive=True)` merge.
- Produces: Deployed `defaultTools`, `showCacheMissNotices`, and
  `subagents.agentOverrides.scout` settings with guard preservation.

- [ ] **Step 1: Add failing behavioral assertions**

Seed these conflicting values in the test fixture:

```json
"defaultTools": ["read", "bash", "edit", "write"],
"showCacheMissNotices": false
```

Give the existing `scout` override a preserved field:

```json
"scout": {"description":"existing scout description"}
```

Add exact post-provision assertions:

```bash
jq -e '.defaultTools ==
  ["read", "bash", "edit", "write", "grep", "find", "ls"]' \
  "$settings" >/dev/null
jq -e '.showCacheMissNotices == true' "$settings" >/dev/null
jq -e '.subagents.agentOverrides.scout.model ==
  "openai-codex/gpt-5.6-luna"' "$settings" >/dev/null
jq -e '.subagents.agentOverrides.scout.fallbackModels ==
  ["openai-codex/gpt-5.6-sol"]' "$settings" >/dev/null
jq -e '.subagents.agentOverrides.scout.thinking == "low"' \
  "$settings" >/dev/null
jq -e '.subagents.agentOverrides.scout.description ==
  "existing scout description"' "$settings" >/dev/null
```

- [ ] **Step 2: Run the focused test to verify RED**

Run:

```bash
bash tests/pi-main-worktree-guard-provisioning.sh
```

Expected: nonzero exit because the new managed values are absent.

- [ ] **Step 3: Add the managed settings**

Add these top-level values to the existing managed dictionary:

```yaml
'defaultTools': ['read', 'bash', 'edit', 'write', 'grep', 'find', 'ls'],
'showCacheMissNotices': true,
```

Extend only the `scout` object built by `Build Pi subagent main worktree guard
overrides` with:

```yaml
model: openai-codex/gpt-5.6-luna
fallbackModels:
  - openai-codex/gpt-5.6-sol
thinking: low
```

Keep its existing `subagentOnlyExtensions` expression unchanged.

- [ ] **Step 4: Run the focused test to verify GREEN**

Run:

```bash
bash tests/pi-main-worktree-guard-provisioning.sh
```

Expected: exit 0 and `Pi main worktree guard merge behavior passed`.

- [ ] **Step 5: Validate syntax and formatting**

Run:

```bash
ansible-playbook playbook.yml --syntax-check
git diff --check
```

Expected: both commands exit 0.

- [ ] **Step 6: Commit the managed settings**

Commit only the task and focused behavioral test with message:

```text
Manage initial Pi capability trials
```

### Task 2: Add the real-use review runbook

**Files:**
- Create: `docs/pi-capability-trials.md`

**Interfaces:**
- Consumes: The managed settings from Task 1 and pi-subagents watchdog commands.
- Produces: Bounded trial steps, evidence fields, decision gates, and rollback
  instructions without persistent runtime state.

- [ ] **Step 1: Write the runbook**

Include these sections and exact bounds:

1. Structured tools: review 5-10 representative new sessions. Compare successful
   native discovery calls with shell-only discovery and verify original tools remain
   available.
2. Scout route: review after 30 completed scout uses or 30 days, whichever comes
   first. Record resolved model, fallback use, duration, corrections, terminal
   state, and whether required context was found. Review immediately after two
   fallbacks in ten uses or a failure rate above 5%.
3. Watchdog: run in 3-5 normal feature-worktree implementation sessions with:

```text
/subagents-watchdog recommend-model
/subagents-watchdog session model recommended
/subagents-watchdog session on
/subagents-watchdog status
```

   Record unique actionable findings, false positives, latency, cost, provider
   failures, and LSP availability. Confirm a fresh Pi process is off afterward.
4. Cache notices: keep enabled unless they are materially distracting.
5. Extended retention: compare at least three similar sessions per condition by
   launching the trial process with:

```bash
env PI_CACHE_RETENTION=long pi
```

   Record provider/model, idle-gap bucket, significant miss notices, cache read/write
   usage, compaction events, and cost. Do not export the variable globally.
6. Give keep, adjust, and rollback rules for every capability. Exclude credentials,
   raw source, prompts, command arguments, and full private transcripts.

- [ ] **Step 2: Self-review the runbook**

Run:

```bash
! rg -n 'T[B]D|FIXM[E]|PLACEHOLDE[R]|implement late[r]' \
  docs/pi-capability-trials.md
git diff --check -- docs/pi-capability-trials.md
```

Expected: both commands exit 0.

- [ ] **Step 3: Commit the runbook**

Commit only `docs/pi-capability-trials.md` with message:

```text
Document Pi capability trial reviews
```

### Task 3: Provision and verify the rollout

**Files:**
- Verify only; no planned modifications.

**Interfaces:**
- Consumes: Tasks 1 and 2.
- Produces: End-to-end deployed-state and idempotence evidence.

- [ ] **Step 1: Run focused and repository checks**

Run:

```bash
bash tests/pi-main-worktree-guard-provisioning.sh
ansible-playbook playbook.yml --syntax-check
git diff --check
```

Expected: all commands exit 0.

- [ ] **Step 2: Apply from the feature worktree**

Run:

```bash
bin/provision
```

Expected: exit 0. The provision log identifies this feature worktree and branch.

- [ ] **Step 3: Verify deployed values**

Run bounded `jq` checks against `~/.pi/agent/settings.json` for the exact tool list,
cache-notice boolean, scout model, fallback, low thinking, and guard extension.
Do not print unrelated settings or credentials.

Expected: every check exits 0.

- [ ] **Step 4: Verify idempotence**

Run:

```bash
bin/provision --check
```

Expected: exit 0 with no failed tasks and no changes.

- [ ] **Step 5: Perform fresh-session smoke checks**

Start a new temporary Pi process from a safe non-main worktree. Confirm native
`grep`, `find`, and `ls` are exposed. Run one bounded `scout` task and confirm its
resolved model is Luna, or that a fallback to Sol is explicitly recorded.

- [ ] **Step 6: Request independent review**

Use fresh reviewers for settings correctness and trial/runbook quality. Fix only
concrete findings, rerun affected checks, and keep the worktree clean.

- [ ] **Step 7: Create the pull request**

Push the branch and create a GitHub pull request through `z-pull-request`. Include
an author-initiated `## Verification` section according to repository policy.
