# _find-agent-sessions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a shared `_find-agent-sessions` skill and helper command that show recent Claude and Codex sessions in one recency-sorted list with progress summaries, conservative status guesses, and resume commands that always use `codex-yolo` or `claude-yolo`.

**Architecture:** Lock the contract first with one packaging regression and one helper-behavior regression. Then add the shared skill and helper, wire the helper into provisioning, rerun the focused tests, and finish with a real local end-to-end verification against installed copies and live session data.

**Tech Stack:** Bash shell scripts, jq, Ansible provisioning, Markdown skills, repo-local shell regressions, Git

**Spec:** `docs/superpowers/specs/2026-04-21-find-agent-sessions-design.md`

**File map:**
- `tests/_find-agent-sessions-skill.sh` — packaging and wording regression for the shared skill and helper source.
- `roles/common/files/bin/_find-agent-sessions` — new shared helper command that merges Claude and Codex session data, filters by duration, infers progress fields, and prints resume commands.
- `roles/common/files/bin/_find-agent-sessions.test` — focused behavior regression for duration parsing, mixed recency ordering, status classification, and resume command formatting.
- `roles/common/files/config/skills/common/_find-agent-sessions/SKILL.md` — shared skill installed into both Claude and Codex.
- `roles/common/tasks/main.yml` — Ansible install step for the helper command.
- `docs/superpowers/plans/2026-04-21-find-agent-sessions.md` — living implementation record for this work.

---

## Phase 1 — Lock the shared-skill and helper contract with failing regressions

### Task 1: Add the packaging regression for the shared skill and helper

**Files:**
- Create: `tests/_find-agent-sessions-skill.sh`
- Test: `bash tests/_find-agent-sessions-skill.sh`

- [ ] **Step 1.1: Create the packaging regression**

Create `tests/_find-agent-sessions-skill.sh` with a pass/fail harness matching the repo’s other top-level skill tests. Assert all of the following:

```text
- roles/common/files/config/skills/common/_find-agent-sessions/SKILL.md exists
- roles/common/files/config/skills/claude/_find-agent-sessions does not exist
- roles/common/files/config/skills/codex/_find-agent-sessions does not exist
- roles/common/files/bin/_find-agent-sessions exists
- the shared skill contains "name: _find-agent-sessions"
- the shared skill mentions the default 24h window
- the shared skill says resume commands should use codex-yolo and claude-yolo
- roles/common/tasks/main.yml installs roles/common/files/bin/_find-agent-sessions into ~/.local/bin
```

Mark the script executable:

```bash
chmod +x tests/_find-agent-sessions-skill.sh
```

- [ ] **Step 1.2: Run the packaging regression and confirm it fails**

Run:

```bash
bash tests/_find-agent-sessions-skill.sh
```

Expected: FAIL because the new skill, helper, and install task do not exist yet.

### Task 2: Add the helper behavior regression

**Files:**
- Create: `roles/common/files/bin/_find-agent-sessions.test`
- Test: `bash roles/common/files/bin/_find-agent-sessions.test`

- [ ] **Step 2.1: Create the helper regression with synthetic Claude and Codex sessions**

Create `roles/common/files/bin/_find-agent-sessions.test` as a temp-dir integration test similar to the existing adjacent `.test` files. In the test:

1. Create temp `HOME`, `~/.claude/projects`, and `~/.codex/sessions` trees
2. Write minimal Claude `*.jsonl` and Codex `*.jsonl` files with timestamps, cwd, branch, session id, and enough transcript content to exercise status inference
3. Set file mtimes explicitly with `touch -t` or `touch -d`
4. Provide stub `list-claude-sessions`, `list-codex-sessions`, `read-claude-session`, and `read-codex-session` commands in a temp `PATH` when needed so the new helper is tested through its public dependencies

Use at least these synthetic sessions:

```text
- codex-active: implemented change, no PR evidence -> status active
- claude-blocked: PR opened and waiting for review -> status blocked
- codex-done: PR created, PR merged, cleanup command recorded -> status done
- claude-old: older than requested duration -> filtered out
```

- [ ] **Step 2.2: Run the helper regression and confirm it fails**

Run:

```bash
bash roles/common/files/bin/_find-agent-sessions.test
```

Expected: FAIL because `_find-agent-sessions` does not exist yet.

- [ ] **Step 2.3: Commit the red regressions and plan**

Run:

```bash
git add tests/_find-agent-sessions-skill.sh \
  roles/common/files/bin/_find-agent-sessions.test \
  docs/superpowers/plans/2026-04-21-find-agent-sessions.md
git commit -m "Add _find-agent-sessions regression plan"
```

Expected: one commit containing the red regressions plus this implementation plan.

## Phase 2 — Add the shared helper and make the regressions pass

### Task 3: Implement the `_find-agent-sessions` helper command

**Files:**
- Create: `roles/common/files/bin/_find-agent-sessions`
- Test: `bash roles/common/files/bin/_find-agent-sessions.test`

- [ ] **Step 3.1: Create the helper skeleton and CLI parsing**

Create `roles/common/files/bin/_find-agent-sessions` as an executable Bash script with:

```bash
#!/usr/bin/env bash
set -euo pipefail

window="${1:-24h}"
json_output=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      json_output=true
      shift
      ;;
    today|yesterday|[0-9]*h|[0-9]*d)
      window="$1"
      shift
      ;;
    *)
      echo "Usage: _find-agent-sessions [24h|4h|2d|today|yesterday] [--json]" >&2
      exit 1
      ;;
  esac
done
```

Add helpers for:

```text
- parsing the requested relative window into start/end epochs
- computing a coarse --days value for the existing list-* scripts
- reading portable file mtimes on macOS and Linux
- formatting an ISO-like updated timestamp for display
```

- [ ] **Step 3.2: Implement mixed collection through the existing helpers**

Inside the new helper, call:

```bash
list-codex-sessions --json --days "$coarse_days" --limit 500
list-claude-sessions --json --days "$coarse_days" --limit 500
```

Normalize each entry into a common JSON object with:

```json
{
  "tool": "Codex or Claude",
  "session_id": "...",
  "file": "...",
  "cwd": "...",
  "git_branch": "...",
  "updated_epoch": 0,
  "updated_at": "...",
  "preview": "..."
}
```

Filter on `updated_epoch`, not the session start timestamp, then sort descending by `updated_epoch`.

- [ ] **Step 3.3: Implement conservative summary and status inference**

For each kept session:

1. call `read-codex-session --json` or `read-claude-session --json`
2. inspect the returned summary arrays
3. inspect the raw session file tail for merge / cleanup / blocked clues

Implement the status heuristics exactly as the spec requires:

```text
done:
  requires PR-created evidence
  requires PR-merged evidence
  requires branch/worktree cleanup evidence

blocked:
  use when review/manual/credential/external waiting evidence exists

active:
  everything else
```

Detect cleanup from concrete evidence such as:

```text
- worktree-done
- worktree-delete
- git worktree remove
- git branch -d
- tmux-agent-worktree clear
- explicit assistant text saying cleanup completed
```

Detect merge from concrete evidence such as:

```text
- merge pull request / merged PR text
- git merge into main followed by PR-complete wording
- tool or shell output explicitly saying the PR merged
```

Detect “PR created” from concrete evidence such as:

```text
- pull request created/opened text
- create-pull-request / draft-pr / PR URL output
- tool output that includes a PR number or PR URL
```

When any `done` requirement is missing, never emit `done`.

- [ ] **Step 3.4: Implement output formatting and resume commands**

Print one mixed list in recency order. Each entry should include:

```text
tool
updated_at
cwd or repo
branch
summary
last completed step
likely next step
status
resume command
```

Generate resume commands with exact CLI syntax:

```bash
cd "<cwd>" && codex-yolo resume <session_id>
cd "<cwd>" && claude-yolo -r <session_id>
```

- [ ] **Step 3.5: Re-run the helper regression and confirm it passes**

Run:

```bash
bash roles/common/files/bin/_find-agent-sessions.test
```

Expected: PASS for:

```text
- default 24h filtering
- explicit 4h / 2d / today / yesterday parsing
- mixed recency ordering
- active / blocked / done classification
- codex-yolo and claude-yolo resume commands
```

## Phase 3 — Add the shared skill and wire the helper into provisioning

### Task 4: Add the shared `_find-agent-sessions` skill and install step

**Files:**
- Create: `roles/common/files/config/skills/common/_find-agent-sessions/SKILL.md`
- Modify: `roles/common/tasks/main.yml`
- Test: `bash tests/_find-agent-sessions-skill.sh`

- [ ] **Step 4.1: Create the shared skill**

Create `roles/common/files/config/skills/common/_find-agent-sessions/SKILL.md` with wording that tells the agent to:

```text
- run the _find-agent-sessions helper with the provided duration or default 24h
- treat the output as a browsing/triage tool first, not an auto-resume tool
- present the mixed Claude/Codex list to the user
- use the generated resume command only when the user explicitly wants to continue a session
- keep the strict done semantics: merged PR plus cleanup only
```

Include quick examples:

```bash
_find-agent-sessions
_find-agent-sessions 4h
_find-agent-sessions today
```

- [ ] **Step 4.2: Add the provisioning task for the helper**

In `roles/common/tasks/main.yml`, add a dedicated copy task alongside the other session helpers:

```yaml
- name: Install _find-agent-sessions helper
  copy:
    backup: yes
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin/_find-agent-sessions'
    src: '{{ playbook_dir }}/roles/common/files/bin/_find-agent-sessions'
    mode: 0755
```

Keep the task near `list-codex-sessions`, `list-claude-sessions`, `read-codex-session`, and `read-claude-session`.

- [ ] **Step 4.3: Re-run the packaging regression and confirm it passes**

Run:

```bash
bash tests/_find-agent-sessions-skill.sh
```

Expected: PASS for shared skill existence, helper existence, common-skill packaging, and install-task wiring.

- [ ] **Step 4.4: Commit the green helper and skill changes**

Run:

```bash
git add \
  roles/common/files/bin/_find-agent-sessions \
  roles/common/files/bin/_find-agent-sessions.test \
  roles/common/files/config/skills/common/_find-agent-sessions/SKILL.md \
  roles/common/tasks/main.yml \
  tests/_find-agent-sessions-skill.sh \
  docs/superpowers/plans/2026-04-21-find-agent-sessions.md
git commit -m "Add _find-agent-sessions helper"
```

Expected: one commit containing the new helper, skill, wiring, and passing regressions.

## Phase 4 — Provision, run the real end-to-end smoke, and prepare the PR

### Task 5: Verify installed copies and real local-session behavior

**Files:**
- Reference: `~/.local/bin/_find-agent-sessions`
- Reference: `~/.claude/skills/_find-agent-sessions/SKILL.md`
- Reference: `~/.codex/skills/_find-agent-sessions/SKILL.md`

- [ ] **Step 5.1: Provision the local machine**

Run:

```bash
bin/provision
```

Expected: provisioning succeeds and installs the helper plus the shared skill copies.

- [ ] **Step 5.2: Verify the installed files exist**

Run:

```bash
test -x ~/.local/bin/_find-agent-sessions
test -f ~/.claude/skills/_find-agent-sessions/SKILL.md
test -f ~/.codex/skills/_find-agent-sessions/SKILL.md
```

Expected: all three commands exit `0`.

- [ ] **Step 5.3: Run the real end-to-end smoke tests**

Run:

```bash
~/.local/bin/_find-agent-sessions
~/.local/bin/_find-agent-sessions 4h
~/.local/bin/_find-agent-sessions today
```

Check the real output for:

```text
- mixed Claude/Codex results when both exist
- summaries populated
- last completed step populated
- likely next step populated
- resume commands use codex-yolo / claude-yolo
- no session marked done unless merged-plus-cleanup evidence exists
```

If only one tool has recent sessions, note that explicitly and rely on the red/green regression for the mixed-tool path.

- [ ] **Step 5.4: Run final verification and confirm the tree is clean**

Run:

```bash
bash tests/_find-agent-sessions-skill.sh
bash roles/common/files/bin/_find-agent-sessions.test
git status --short
```

Expected:

```text
- both regressions exit 0
- git status --short prints nothing
```

## Follow-ups

- [ ] If the helper proves useful, consider teaching the existing `_resume-*` skills to recommend `_find-agent-sessions` when the user has multiple recent sessions.
