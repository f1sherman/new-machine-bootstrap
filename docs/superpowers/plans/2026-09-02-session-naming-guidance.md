# Session Naming Guidance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use engineering:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make generated Pi session names front-load a recognizable subject and describe the broad session outcome instead of the current task.

**Architecture:** Align the existing automatic child prompt, main-agent tool description, and manual rename skill around one naming contract. Keep the existing naming runtime and lifecycle unchanged; only model guidance changes.

**Tech Stack:** TypeScript Pi extension, Markdown Pi skill, shell-based integration verification, Ansible provisioning.

## Global Constraints

- Use `[recognizable subject] + [broad outcome]` as the preferred name form.
- Make the first 31 characters useful for finding the session.
- Prefer at most 40 characters and enforce the existing hard 80-character limit.
- The main agent names each new top-level objective once and does not rename related follow-up work.
- Do not add runtime heuristics, extra model calls, compatibility behavior, or low-value static tests.

---

### Task 1: Align Pi Session Naming Guidance

**Files:**
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts:14,1427-1434`
- Modify: `roles/common/files/config/skills/pi/z-update-session-name/SKILL.md:9-18`
- Add: `docs/superpowers/specs/2026-09-02-session-naming-guidance-design.md`
- Add: `docs/superpowers/plans/2026-09-02-session-naming-guidance.md`
- Verify: `tests/pi-managed-hooks.sh`

**Interfaces:**
- Consumes: the existing automatic `SESSION_GOAL_CHILD_SYSTEM_PROMPT`, `set_session_name({ name })` tool, and user-invoked `z-update-session-name` skill.
- Produces: aligned natural-language guidance for automatic, deliberate, and manual session naming. No function signatures or runtime data change.

**Reviewer Verification:**
- Run the exact `SESSION_GOAL_CHILD_SYSTEM_PROMPT` with representative prompts through `pi --mode text --print --no-session`. Expected output starts with a recognizable subject and states a broad outcome rather than a narrow implementation detail.

- [ ] **Step 1: Capture the baseline**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: exit 0. This protects the existing session naming runtime before prompt-only changes.

- [ ] **Step 2: Update the automatic child prompt**

Replace `SESSION_GOAL_CHILD_SYSTEM_PROMPT` with concise instructions that:

- identify why the session exists;
- use `[recognizable subject] + [broad outcome]`;
- preserve the user's central terms;
- front-load distinctive subject terms and make the first 31 characters useful;
- reject symptoms, implementation details, identifiers, phases, workflows, and next actions;
- use the breadth check from the design;
- prefer 40 characters and emit only one unquoted line.

Keep `SESSION_GOAL_MAX_LENGTH` at 80.

- [ ] **Step 3: Update the main-agent tool guidance**

Change the `set_session_name` description to require one deliberate call after the agent understands each new top-level objective, even when a provisional automatic name exists. Require the shared naming form and discovery-prefix rule. Tell the agent to preserve the name for all related work and call again only for a clearly unrelated objective.

Change the `name` parameter description to summarize the same subject-first broad-outcome contract, 31-character discovery target, 40-character preference, and 80-character hard limit.

- [ ] **Step 4: Update the manual rename skill**

Revise `z-update-session-name/SKILL.md` to use the shared naming contract. Keep its existing one-call mutation rule and prohibition against direct session-file, tmux, or branch changes. Do not add the automatic lifecycle threshold because invocation is an explicit user rename request.

- [ ] **Step 5: Run the managed extension suite**

Run:

```bash
bash tests/pi-managed-hooks.sh
```

Expected: exit 0 with all assertions passing.

- [ ] **Step 6: Apply the managed configuration**

Run:

```bash
bin/provision
```

Expected: exit 0. The changed Pi extension and skill are deployed from this worktree.

- [ ] **Step 7: Verify the deployed guidance**

Run repository and deployed-file comparisons for the extension and skill:

```bash
extension=roles/common/files/pi/extensions/managed-hooks.ts
skill=roles/common/files/config/skills/pi/z-update-session-name/SKILL.md
cmp "$extension" "$HOME/.pi/agent/extensions/managed-hooks.ts"
cmp "$skill" "$HOME/.pi/agent/skills/z-update-session-name/SKILL.md"
rg -n 'new top-level objective|first 31|clearly unrelated' \
  "$extension" "$HOME/.pi/agent/extensions/managed-hooks.ts"
rg -n 'recognizable subject|first 31|exactly once' \
  "$skill" "$HOME/.pi/agent/skills/z-update-session-name/SKILL.md"
```

Expected: deployed files match the feature worktree sources. Inspection shows
that the tool guidance requires one decision for a new objective, retains the
name during related work, and permits another call only for an unrelated
objective. The manual skill uses the same subject-first naming contract and
exactly one mutation call for an explicit rename.

- [ ] **Step 8: Exercise automatic naming end to end**

Extract the exact automatic system prompt from the source and invoke `pi` with representative prompts:

```bash
source_file=roles/common/files/pi/extensions/managed-hooks.ts
prompt=$(
  node -e '
const fs = require("fs");
const source = fs.readFileSync(process.argv[1], "utf8");
const match = source.match(
  /const SESSION_GOAL_CHILD_SYSTEM_PROMPT = ("(?:[^"\\\\]|\\\\.)*");/,
);
if (!match) process.exit(1);
process.stdout.write(JSON.parse(match[1]));
' "$source_file"
)
tasks=(
  "Make Pi OpenAI compaction reliable while fixing overlay replay."
  "Improve Safari URL routing while ignoring companion panels."
  "Make repository cleanup safe while repairing merge proof."
  "Improve workspace restoration while debugging stale manifests."
)
for task in "${tasks[@]}"; do
  name=$(
    pi --mode text --print --no-session \
      --model openai/gpt-5.6-luna --thinking off \
      --system-prompt "$prompt" "$task"
  )
  printf 'name=%s\nlength=%s\nfirst31=%.31s\n\n' \
    "$name" "${#name}" "$name"
  test "${#name}" -le 80
done
```

Record all four outputs. Expected: each one-line result starts with recognizable
system or capability terms, states a broad outcome, does not use the narrow
implementation detail as its main subject, and passes the hard 80-character
check. Inspect `first31` to confirm that the discovery prefix is useful. Treat
40 characters and fitting the outcome within `first31` as preferences, not
hard assertions, because model output is nondeterministic.

- [ ] **Step 9: Review the final diff**

Run:

```bash
git diff --check
git diff -- roles/common/files/pi/extensions/managed-hooks.ts \
  roles/common/files/config/skills/pi/z-update-session-name/SKILL.md \
  docs/superpowers/specs/2026-09-02-session-naming-guidance-design.md \
  docs/superpowers/plans/2026-09-02-session-naming-guidance.md
```

Expected: no whitespace errors; the diff contains only the approved guidance, design, and plan changes.

- [ ] **Step 10: Commit the coherent change**

Stage only the four intended files and create one conventional commit:

```bash
git add roles/common/files/pi/extensions/managed-hooks.ts \
  roles/common/files/config/skills/pi/z-update-session-name/SKILL.md \
  docs/superpowers/specs/2026-09-02-session-naming-guidance-design.md \
  docs/superpowers/plans/2026-09-02-session-naming-guidance.md
git commit -m "fix(pi): improve session naming guidance"
```
