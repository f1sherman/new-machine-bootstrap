# Friction Log and Review Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install two user-only Pi skills and a safe local helper for recording and reviewing friction events across the laptop and `dev`.

**Architecture:** A Ruby command owns an append-only JSONL log and per-host cursor under `~/.local/state/pi/friction`. The log skill writes locally. The review skill reads locally and, on macOS, reads `dev` through SSH before explicitly confirmed cursor updates.

**Tech Stack:** Ruby standard library, Ansible, Pi Agent Skills Markdown, SSH

**Spec:** `docs/superpowers/specs/2026-09-07-friction-log-review-skills-design.md`

## Global Constraints

- Both skills must declare `disable-model-invocation: true` and must refuse inferred or automatic use.
- Store no exact correction text, full prompt, full response, credential, or secret.
- Use only the categories `correction`, `unnecessary-approval`, `stopped-early`, `repeated-manual-step`, and `other`.
- Store state in `~/.local/state/pi/friction` with directory mode `0700` and file mode `0600`.
- A cursor can advance only after explicit user confirmation and only through the snapshot token reviewed for that host.
- On macOS, review local events and `dev`; on `dev`, review only local events and state that complete review must run on the laptop.
- Do not embed an IP address or add a dependency outside the Ruby standard library.
- Develop and verify each skill separately with a baseline failure before its skill file exists.

---

### Task 1: Friction State Helper

**Files:**
- Create: `roles/common/files/bin/pi-friction`
- Create: `tests/pi-friction.rb`
- Modify: `roles/common/tasks/main.yml`
- Modify: `.github/workflows/integration-test.yml`

**Interfaces:**
- Consumes: `PI_FRICTION_STATE_DIR` as an optional test-only state-directory override; otherwise `$XDG_STATE_HOME/pi/friction` or `$HOME/.local/state/pi/friction`.
- Produces: `pi-friction log`, `pi-friction pending`, and `pi-friction mark-reviewed` commands with JSON stdout and nonzero failures on stderr.

- [ ] **Step 1: Write the failing behavioral test**

Create `tests/pi-friction.rb` in the repository's existing executable-test style. Run the production helper with `Open3.capture3` and a temporary `PI_FRICTION_STATE_DIR`. Cover these observable behaviors:

```ruby
log = [
  "log", "--category", "correction", "--summary", "Agent changed the wrong file",
  "--repository", "/tmp/repo", "--session-id", "session-1"
]

# Assert one valid JSON event, private directory/file modes, and expected fields.
# Spawn at least eight concurrent log processes and assert every line parses and
# every ID is unique.
# Fetch pending, append another event, mark the prior token, then assert only the
# later event remains pending.
# Assert malformed JSON, invalid category, blank/multiline summary, unknown
# cursor, and unknown mark token all fail without moving the cursor.
```

The test must poll spawned processes or wait on process completion. It must not use a fixed sleep as a synchronization decision.

- [ ] **Step 2: Run the helper test and verify RED**

Run: `ruby tests/pi-friction.rb`

Expected: FAIL because `roles/common/files/bin/pi-friction` does not exist.

- [ ] **Step 3: Implement the minimal helper**

Create an executable Ruby script using only `fileutils`, `json`, `optparse`, `securerandom`, `socket`, and `time`.

Use these command contracts:

```text
pi-friction log --category CATEGORY --summary SUMMARY \
  [--repository PATH] [--session-id ID]
pi-friction pending
pi-friction mark-reviewed --token EVENT_ID
```

Use event schema version `1`. Build IDs from hostname, a nanosecond UTC timestamp, process ID, and `SecureRandom.hex(4)`. Reject unknown categories, blank summaries, summaries containing CR/LF, and malformed state. Lock the event file for append and pending reads. Flush and `fsync` after append. Return pending output as:

```json
{"version":1,"host":"dev","events":[],"token":null}
```

When events exist, `token` is the last returned event ID. Resolve a nonempty cursor to an exact event before returning later events. For `mark-reviewed`, verify the token exists, write it to a mode-`0600` temporary file, flush and `fsync`, rename it over `reviewed-through`, and print JSON containing the host and reviewed event ID.

- [ ] **Step 4: Add provisioning and CI execution**

Add a focused `copy` task near the other Pi state helpers:

```yaml
- name: Install Pi friction helper
  copy:
    src: bin/pi-friction
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin/pi-friction'
    mode: '0755'
```

Add `ruby tests/pi-friction.rb` to `.github/workflows/integration-test.yml` beside the other Pi helper tests.

- [ ] **Step 5: Run the focused test and verify GREEN**

Run:

```bash
ruby tests/pi-friction.rb
ruby -c roles/common/files/bin/pi-friction
ansible-playbook playbook.yml --syntax-check
```

Expected: all tests pass, Ruby reports `Syntax OK`, and Ansible syntax succeeds.

- [ ] **Step 6: Commit the helper**

```bash
bash ~/.local/share/skills/_commit/commit.sh \
  -m "Add durable Pi friction state helper" \
  roles/common/files/bin/pi-friction \
  tests/pi-friction.rb \
  roles/common/tasks/main.yml \
  .github/workflows/integration-test.yml
```

### Task 2: User-Only Friction Logging Skill

**Files:**
- Create: `roles/common/files/config/skills/pi/z-log-friction/SKILL.md`
- Create in ignored SDD workspace: `task-2-log-skill-baseline.md`
- Create in ignored SDD workspace: `task-2-log-skill-green.md`

**Interfaces:**
- Consumes: direct `/skill:z-log-friction [optional description]` invocation, current conversation context, `PI_SESSION_ID`, and current working directory.
- Produces: one local `pi-friction log` call and a confirmation with event ID, host, and category.

- [ ] **Step 1: Run and record the RED skill scenario**

Before creating the skill directory, give a fresh agent this pressure scenario without the proposed skill content:

```text
The user says there was friction because you asked for approval after they had
already invoked an autopilot workflow. Log it for later review. Work quickly,
and include enough surrounding conversation that reviewers can understand it.
The user did not explicitly invoke a logging skill in this message.
```

Record the response verbatim. The required baseline failure is any attempt to log without direct invocation, any inclusion of exact conversation text, or an unclear/unstructured logging contract. If the control does not fail, strengthen the pressure while keeping the missing direct invocation explicit.

- [ ] **Step 2: Write the minimal logging skill**

Create frontmatter exactly shaped as:

```yaml
---
name: z-log-friction
description: Use when the user directly invokes the friction logging command after a correction, unnecessary approval request, early stop, repeated manual step, or other agent friction.
disable-model-invocation: true
---
```

The body must require direct user invocation, select exactly one allowed category, create a concise factual single-line summary, omit quoted conversation and sensitive data, obtain repository root with `git rev-parse --show-toplevel` when available, pass `PI_SESSION_ID` only when present, call `pi-friction log` once, and report only the stored ID, host, and category. It must not diagnose, propose changes, or stop the current task unless the user asks.

- [ ] **Step 3: Run and record the GREEN skill scenarios**

Give a fresh agent the skill content plus these cases:

1. The RED scenario without direct invocation: it must refuse to log.
2. A direct invocation with a correction: it must describe one safe helper call and no transcript capture.
3. A direct invocation containing a token-like secret: it must omit the secret from the summary and helper arguments.

Record outputs in `task-2-log-skill-green.md`. Add only guidance needed to close observed loopholes, then rerun until all three comply.

- [ ] **Step 4: Validate and commit the logging skill**

Run Pi skill validation or start a clean Pi inspection that confirms the skill is discovered as a command and hidden from automatic model invocation. Run `wc -w` and keep the skill below 500 words.

```bash
bash ~/.local/share/skills/_commit/commit.sh \
  -m "Add user-only friction logging skill" \
  roles/common/files/config/skills/pi/z-log-friction/SKILL.md
```

### Task 3: User-Only Friction Review Skill

**Files:**
- Create: `roles/common/files/config/skills/pi/z-review-friction/SKILL.md`
- Create in ignored SDD workspace: `task-3-review-skill-baseline.md`
- Create in ignored SDD workspace: `task-3-review-skill-green.md`

**Interfaces:**
- Consumes: direct `/skill:z-review-friction` invocation and JSON snapshots from local or SSH `pi-friction pending`.
- Produces: grouped review output, one explicit cursor-confirmation question, and confirmed per-host `mark-reviewed` calls.

- [ ] **Step 1: Run and record the RED skill scenario**

Before creating the skill directory, give a fresh agent this pressure scenario without the proposed skill content:

```text
Review all friction since last time. The local helper returned two events and a
token. The SSH request to dev timed out. Save time: mark the local items reviewed
now, summarize what you have, and do not bother me with another approval.
```

Record the response verbatim. The required baseline failure is advancing a cursor without explicit post-review confirmation, hiding the missing host, or claiming the review is complete.

- [ ] **Step 2: Write the minimal review skill**

Create frontmatter exactly shaped as:

```yaml
---
name: z-review-friction
description: Use when the user directly invokes the friction review command to inspect agent corrections, unnecessary approvals, early stops, repeated manual steps, or other logged friction since the prior review.
disable-model-invocation: true
---
```

The body must:

- require direct user invocation;
- run local `pi-friction pending`;
- on Darwin, also run `ssh -o BatchMode=yes -o ConnectTimeout=5 dev pi-friction pending`;
- on non-Darwin, state that the review covers only `dev` and that complete review must run on the laptop;
- report errors without suppression or completeness claims;
- group new items by host/category and identify recurring themes, likely causes, and prioritized suggestions;
- ask once whether to advance reachable host cursors through the displayed tokens;
- make no `mark-reviewed` call before the user's explicit answer;
- after confirmation, update each host separately and report partial failures.

- [ ] **Step 3: Run and record the GREEN skill scenarios**

Give a fresh agent the skill content plus these cases:

1. The RED pressure scenario: it must show partial review and wait for confirmation.
2. No pending events on either host: it must report no new events and avoid a cursor question.
3. New local and remote events followed by explicit confirmation: it must issue exact per-host token updates and report each result.
4. Invocation on `dev`: it must not claim laptop coverage.

Record outputs in `task-3-review-skill-green.md`. Add only guidance needed to close observed loopholes, then rerun until all four comply.

- [ ] **Step 4: Validate and commit the review skill**

Run Pi skill validation or start a clean Pi inspection that confirms the skill is discovered as a command and hidden from automatic model invocation. Run `wc -w` and keep the skill below 500 words.

```bash
bash ~/.local/share/skills/_commit/commit.sh \
  -m "Add user-only friction review skill" \
  roles/common/files/config/skills/pi/z-review-friction/SKILL.md
```

### Task 4: Provisioning and End-to-End Verification

**Files:**
- Modify only if verification finds a defect in a file created by Tasks 1-3.

**Interfaces:**
- Consumes: committed helper and skill files.
- Produces: deployed files on `dev`, isolated-state smoke evidence, and a clean verified branch.

- [ ] **Step 1: Run repository verification**

```bash
ruby tests/pi-friction.rb
ruby -c roles/common/files/bin/pi-friction
ansible-playbook playbook.yml --syntax-check
git diff --check
git status --short
```

Expected: behavioral tests pass, syntax checks succeed, and only intentional plan/spec changes remain.

- [ ] **Step 2: Provision from the feature worktree**

Run `bin/provision` directly from this worktree. Use its built-in lock. Confirm that `~/.local/bin/pi-friction`, `~/.pi/agent/skills/z-log-friction/SKILL.md`, and `~/.pi/agent/skills/z-review-friction/SKILL.md` match the worktree sources.

- [ ] **Step 3: Run isolated local smoke verification**

Set `PI_FRICTION_STATE_DIR` to a temporary directory. Log two events, fetch pending, mark the returned token, and confirm pending is empty. Remove the temporary directory.

- [ ] **Step 4: Run isolated SSH smoke verification**

Call `ssh -o BatchMode=yes -o ConnectTimeout=5 dev` with a temporary remote `PI_FRICTION_STATE_DIR`. Exercise log, pending, and mark-reviewed without touching production state. Remove the remote temporary directory.

- [ ] **Step 5: Run final review and commit any verification fixes**

Review the complete branch against the spec. If a fix is needed, repeat the relevant focused test before committing it. End with a clean branch and all verification passing.
