# Pi Attention-Worthy Stops Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Status:** Self-approved for implementation

**Goal:** Make personal-development Pi sessions continue through safe,
immediate task actions and add a local tool that measures avoidable stops.

**Architecture:** NMB will add a concrete continuation contract to the managed
Pi instruction fragment and make `z-quick-pr` the default route for clear
first-party implementation requests. A standalone Ruby helper will parse local
Pi JSONL history, classify advisory stop candidates, redact excerpts, and emit
text or JSON. Ansible will install the helper in `~/.local/bin`; Herdr and PR
monitor behavior remain unchanged in this slice.

**Tech Stack:** Markdown guidance, Ruby 3 standard library, Ansible, GitHub
Actions, Pi JSONL session files

**Spec:**
`docs/superpowers/specs/2026-09-02-pi-attention-worthy-stops-design.md`

## Global Constraints

- PR monitor delivery, wakeups, deduplication, and notification behavior are out
  of scope.
- Do not modify Herdr or its installed Pi lifecycle integration.
- Do not add a general command firewall or production capability sandbox.
- Do not merge protected pull requests.
- The audit helper is local-only and must not upload session content.
- Candidate classification is advisory. It must not declare every candidate a
  defect.
- Use registered delegated work and blocking `subagent_wait` when a result is
  required for a run-to-completion request.
- Do not add tests that only grep or restate managed prose or Ansible YAML.
- Use ASD-STE100 style in managed guidance and user-facing output.

---

## File Map

- Modify `roles/common/files/pi/AGENTS.md.d/00-base.md` to define the global
  continuation, stop, failure, compaction, delegation, and background-process
  rules.
- Modify `roles/common/files/config/skills/pi/z-quick-pr/SKILL.md` to make its
  discovery description and entry conditions match the default first-party
  autopilot route.
- Create `roles/common/files/bin/pi-stop-audit` as the local session-history
  parser and report generator.
- Create `tests/pi-stop-audit.rb` as behavioral coverage for parsing,
  deduplication, exclusions, classification, filtering, and redaction.
- Modify `.github/workflows/integration-test.yml` to run the retained behavioral
  test.
- Modify `roles/common/tasks/main.yml` to install `pi-stop-audit` with mode
  `0755`.
- Update this plan's checkboxes during execution. The design spec remains the
  source for rollout and post-release monitoring.

### Task 1: Managed continuation and autopilot guidance

**Files:**
- Modify: `roles/common/files/pi/AGENTS.md.d/00-base.md`
- Modify: `roles/common/files/config/skills/pi/z-quick-pr/SKILL.md`

**Interfaces:**
- Consumes: Pi's managed global `AGENTS.md` assembly and Pi skill discovery.
- Produces: a continuation contract applied to every personal-development Pi
  turn, plus default `z-quick-pr` routing for eligible first-party changes.

- [x] **Step 1: Record the no-test decision**

Do not add an automated test for this task. The changed artifacts are managed
prose. A source assertion would only restate prompt text and would fail NMB's
test-quality rules. Verify the assembled production artifact in Step 4.

- [x] **Step 2: Add the continuation contract to the base guidance**

Append a focused `## Run-to-completion turns` section to
`roles/common/files/pi/AGENTS.md.d/00-base.md`. Use this exact policy structure:

```markdown
## Run-to-completion turns

- Do not end a turn while an immediate safe action can advance the request. A
  progress report is not a completion condition.
- If you say that you will do, are checking, or are proceeding with an action,
  call the corresponding tool in the same turn.
- For a clear first-party request to change code, configuration, documentation,
  or tests, use `z-quick-pr` by default. The user does not need to request the
  skill or approve process phases.
- Continue through worktree creation, investigation, specification, planning,
  implementation, verification, commit, and pull request creation unless a
  blocking human decision is required.
- Ask one blocking question only when the correct result cannot be discovered,
  two material interpretations remain incompatible, required access is
  unavailable, a physical or GUI action is required, or a security, privacy,
  credential, destructive, legal, billing, or third-party publication decision
  needs authorization.
- Treat compaction and summary injection as continuation events. Recover the
  objective and pending next action, verify stale state when needed, and resume.
- Investigate a baseline or transient failure before stopping. Classify it as
  related, unrelated, transient, or uncertain. Continue after a proved
  unrelated failure, use a bounded retry for a supported transient failure, and
  ask only when uncertainty makes further work wrong or unsafe.
- When a delegated result is required for a run-to-completion request, keep
  parent ownership and wait through the registered subagent interface. Consume
  the result without requiring a human `continue` message.
- Do not launch task-owned work as an untracked shell background process. Use a
  foreground command, registered subagent or provider job, or a managed durable
  service with explicit completion and cleanup ownership.
- Return control only for a blocking human action or a terminal outcome. State
  the exact required action when blocked.
```

Keep the repository's existing rules unchanged. Do not add PR-monitor-specific
instructions.

- [x] **Step 3: Make the quick-PR skill discoverable as the default route**

Change the managed skill description to this meaning:

```yaml
description: >
  Default autopilot path for clear first-party code, configuration,
  documentation, or test changes. Also use when the user asks to skip
  questions, approvals, or execution-choice prompts.
```

Add this sentence after the opening autopilot paragraph:

```markdown
Use this skill by default when a first-party implementation request has a clear
or discoverable target and expected behavior, is reversible through a branch
and pull request, and has no unresolved safety decision.
```

Do not weaken the existing hard gates for a written spec, plan, verification,
or a clean branch.

- [x] **Step 4: Verify the assembled managed guidance**

Run:

```bash
tmp_dir="$(mktemp -d)"
mkdir -p "$tmp_dir/AGENTS.md.d"
cp roles/common/files/pi/AGENTS.md.d/00-base.md \
  "$tmp_dir/AGENTS.md.d/00-base.md"
PI_AGENT_DIR="$tmp_dir" \
  roles/common/files/bin/pi-agent-assemble-agents
cp roles/common/files/pi/AGENTS.md.d/00-base.md "$tmp_dir/expected"
printf '\n' >> "$tmp_dir/expected"
cmp "$tmp_dir/expected" "$tmp_dir/AGENTS.md"
rm -rf "$tmp_dir"
```

Expected: `cmp` exits 0. The assembler adds one separator newline after each
fragment. Review the assembled file and confirm it contains no PR-monitor policy
and does not remove any existing authorization boundary.

- [x] **Step 5: Commit the guidance change**

Run the managed commit helper with these exact files:

```bash
bash ~/.local/share/skills/_commit/commit.sh \
  -m "Keep Pi tasks active through safe next actions" \
  roles/common/files/pi/AGENTS.md.d/00-base.md \
  roles/common/files/config/skills/pi/z-quick-pr/SKILL.md
```

### Task 2: Behavioral stop-audit helper

**Files:**
- Create: `tests/pi-stop-audit.rb`
- Create: `roles/common/files/bin/pi-stop-audit`
- Modify: `.github/workflows/integration-test.yml`

**Interfaces:**
- Consumes: Pi session JSONL files containing message rows with `id`,
  `parentId`, `timestamp`, `message.role`, `message.content`, and
  `message.stopReason`.
- Produces: CLI
  `pi-stop-audit [WINDOW] [--root DIR] [--session TEXT] [--repository TEXT]
  [--limit N] [--json]`.
- Produces: text aggregates followed by bounded candidate records, or JSON with
  `window`, `files`, `unique_stops`, `excluded_pr_monitor`, `counts`, and
  `candidates`.
- Produces candidate fields: `id`, `timestamp`, `session_path`, `categories`,
  `stop_excerpt`, and `following_excerpt`.

- [x] **Step 1: Write a failing production-artifact test**

Create `tests/pi-stop-audit.rb` using the repository's direct Ruby test style:
`Dir.mktmpdir`, `Open3.capture3`, a local assertion lambda, and final nonzero
exit on failure.

Build two fixture session files with shared message IDs. Include these message
chains:

```ruby
human = {
  "type" => "message", "id" => "u1", "parentId" => nil,
  "timestamp" => recent_time,
  "message" => {"role" => "user", "content" => [
    {"type" => "text", "text" => "Deploy the selected fix."}
  ]}
}
stop = {
  "type" => "message", "id" => "a1", "parentId" => "u1",
  "timestamp" => recent_time,
  "message" => {"role" => "assistant", "stopReason" => "stop",
    "content" => [{"type" => "text", "text" =>
      "Proceeding with deployment now. token: super-secret-value"}]}
}
continuation = {
  "type" => "message", "id" => "u2", "parentId" => "a1",
  "timestamp" => recent_time,
  "message" => {"role" => "user", "content" => [
    {"type" => "text", "text" => "continue"}
  ]}
}
```

Also include:

- A duplicate copy of `a1` in the second file.
- A process-approval chain where the assistant asks only for design approval and
  the next user message is `approved`.
- A compaction-generated user ancestor followed by an assistant stop.
- A PR-monitor-generated user ancestor containing
  `Pi extension-generated PR monitor`, followed by an assistant stop.
- An old stop outside the requested window.
- A malformed JSON line.
- Session paths or metadata that let `--session` and `--repository` select one
  retained candidate.

Run the helper with `7d --json --root FIXTURE_ROOT` and assert observable
behavior:

```ruby
report = JSON.parse(stdout)
assert.call(status.success?, "audit succeeds", stderr)
assert.call(report["unique_stops"] == 3,
  "deduplicates and excludes monitor and old stops", report.inspect)
assert.call(report.dig("counts", "future_action") == 1,
  "finds future-action stop", report.inspect)
assert.call(report.dig("counts", "short_continuation") == 1,
  "finds continue response", report.inspect)
assert.call(report.dig("counts", "process_approval") == 1,
  "finds process approval", report.inspect)
assert.call(report.dig("counts", "compaction_adjacent") == 1,
  "finds compaction-adjacent stop", report.inspect)
assert.call(!stdout.include?("super-secret-value"),
  "redacts credential-like excerpts", stdout)
```

Also assert:

- Text mode prints aggregate counts before candidate details.
- `--limit 1` returns one candidate without changing aggregate counts.
- `--session` and `--repository` filter the fixture set.
- Invalid windows and missing roots fail with concise usage errors.
- No network command is invoked; run with a minimal fixture `HOME` and `PATH`.

- [x] **Step 2: Run the new test and confirm failure**

Run:

```bash
ruby tests/pi-stop-audit.rb
```

Expected: FAIL because
`roles/common/files/bin/pi-stop-audit` does not exist or is not executable.

- [x] **Step 3: Implement argument parsing and bounded input selection**

Create executable `roles/common/files/bin/pi-stop-audit` with Ruby standard
library only. Define these interfaces:

```ruby
DEFAULT_ROOT = File.expand_path("~/.pi/agent/sessions")
DEFAULT_LIMIT = 25
MAX_EXCERPT = 180

def parse_args(argv)
  # => {window:, root:, session_filter:, repository_filter:, limit:, json:}
end

def cutoff_for(window, now = Time.now)
  # Accept only positive values matching /\A\d+[hd]\z/.
end

def candidate_files(options, cutoff)
  # Return sorted *.jsonl paths. Exclude paths containing
  # /subagent-artifacts/ or /run- and apply path filters.
end
```

Use `OptionParser`. Reject zero windows, zero limits, unknown options, and a root
that is not a directory. Do not follow non-JSONL files. Do not execute any
content from a transcript.

- [x] **Step 4: Implement graph parsing, deduplication, and exclusions**

Define:

```ruby
def load_nodes(paths)
  # Return [nodes_by_id, source_paths_by_id, malformed_line_count].
  # Keep the first valid row for each message ID.
end

def message_text(row)
  # Join only text content entries and normalize whitespace.
end

def nearest_user_ancestor(row, nodes)
  # Follow parentId at most 500 links and stop on cycles.
end

def direct_user_children(row, children)
  # Return direct child rows whose message role is user.
end
```

Create the child index after deduplication. Select assistant messages where
`message.role == "assistant"`, `message.stopReason == "stop"`, and the parsed
timestamp is inside the requested window. Exclude a stop when its nearest user
ancestor contains `Pi extension-generated PR monitor` case-insensitively. Count
that exclusion separately.

Treat malformed lines as skipped local evidence. Include their aggregate count
in JSON and text output; do not print their content.

- [x] **Step 5: Implement advisory categories and privacy redaction**

Use explicit, conservative regex constants:

```ruby
FUTURE_ACTION = /\b(?:I(?:'ll| will| am|'m)\s+(?:check|inspect|run|deploy|verify|proceed|continue)|next\s+I(?:'ll| will)|proceeding)\b/i
SHORT_CONTINUATION = /\A(?:continue|proceed|go ahead|do it|move forward|resume)\W*\z/i
SHORT_APPROVAL = /\A(?:approved?|yes|y|ok(?:ay)?|[abc])\W*\z/i
COMPACTION_MARKER = /(?:compaction completed|compaction|summary injection|weighted tokens left)/i
```

Define:

```ruby
def categories_for(stop, direct_users, nearest_user)
  # Return a sorted array containing any of:
  # future_action, short_continuation, process_approval,
  # compaction_adjacent.
end

def redact_excerpt(text, max_length = MAX_EXCERPT)
  # Normalize whitespace, redact sensitive forms, then truncate.
end
```

Redact, before truncation:

- PEM private-key blocks.
- `Bearer VALUE` tokens.
- URL user information before `@`.
- Values assigned after case-insensitive keys containing `token`, `password`,
  `secret`, `api_key`, `authorization`, or `credential` in JSON-, YAML-, or
  shell-like syntax.
- Long opaque strings of 32 or more URL-safe token characters.

Use `[REDACTED]` as the only replacement marker. Never include full message
content in the report object.

A stop can have more than one category. Keep only stops with at least one
candidate category in `candidates`, but report `unique_stops` for all retained
non-monitor stops.

- [x] **Step 6: Implement stable text and JSON reports**

Sort candidates by timestamp and ID. Calculate category counts before applying
`--limit`.

JSON output must use `JSON.pretty_generate` on this shape:

```ruby
{
  "window" => options[:window],
  "files" => paths.length,
  "unique_stops" => retained_stops.length,
  "excluded_pr_monitor" => excluded_count,
  "malformed_lines" => malformed_count,
  "counts" => {
    "future_action" => 0,
    "short_continuation" => 0,
    "process_approval" => 0,
    "compaction_adjacent" => 0
  },
  "candidates" => limited_candidates
}
```

Text output must start with `Pi stop audit (<window>)`, print all aggregate
fields, then print `Candidates:` and bounded numbered records. State
`Candidates require human review.` before excerpts.

- [x] **Step 7: Run the behavioral test and fix only implementation defects**

Run:

```bash
chmod +x roles/common/files/bin/pi-stop-audit
ruby tests/pi-stop-audit.rb
```

Expected: all assertions pass. Do not loosen redaction or exclusion assertions
to make the test pass.

- [x] **Step 8: Add the behavioral test to CI**

Add this step after the existing Pi session tests in
`.github/workflows/integration-test.yml`:

```yaml
      - name: Verify Pi stop audit behavior
        run: ruby tests/pi-stop-audit.rb
```

Run:

```bash
ruby tests/pi-stop-audit.rb
```

Expected: PASS from the production helper.

- [x] **Step 9: Commit the audit helper**

Run:

```bash
bash ~/.local/share/skills/_commit/commit.sh \
  -m "Add local Pi stop behavior audit" \
  roles/common/files/bin/pi-stop-audit \
  tests/pi-stop-audit.rb \
  .github/workflows/integration-test.yml
```

### Task 3: Provision the audit helper

**Files:**
- Modify: `roles/common/tasks/main.yml`

**Interfaces:**
- Consumes: `roles/common/files/bin/pi-stop-audit` from Task 2.
- Produces: executable `~/.local/bin/pi-stop-audit` with mode `0755` on managed
  personal-development machines.

- [x] **Step 1: Record the no-test decision**

Do not add a test that greps the Ansible task or restates the path and mode.
This declarative install is caught by Ansible syntax validation and focused
provisioning.

- [x] **Step 2: Add the focused install task**

Add this task near the other Pi session helpers in
`roles/common/tasks/main.yml`:

```yaml
- name: Install Pi stop audit helper
  copy:
    src: bin/pi-stop-audit
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin/pi-stop-audit'
    mode: '0755'
```

Do not add a schedule, upload destination, state directory, or network access.

- [x] **Step 3: Validate Ansible syntax and the focused copy action**

Run:

```bash
ansible-playbook playbook.yml --syntax-check
check_dest="$PWD/.superpowers/sdd/2026-09-02-pi-attention-worthy-stops/"\
"pi-stop-audit-check"
ansible localhost \
  --inventory localhost, \
  --connection local \
  --module-name ansible.builtin.copy \
  --args "src=roles/common/files/bin/pi-stop-audit \
dest=$check_dest mode=0755" \
  --check \
  --diff
test ! -e "$check_dest"
```

Expected: syntax validation exits 0. The focused copy action reports `changed`
and confirms that the production source is readable. Check mode does not create
the temporary destination.

- [x] **Step 4: Commit the provisioning task**

Run:

```bash
bash ~/.local/share/skills/_commit/commit.sh \
  -m "Install the Pi stop audit helper" \
  roles/common/tasks/main.yml
```

### Task 4: Full verification and historical canary preparation

**Files:**
- Modify: `docs/superpowers/plans/2026-09-02-pi-attention-worthy-stops.md`
  only to check completed steps and record concise verification results.

**Interfaces:**
- Consumes: all artifacts from Tasks 1 through 3 and local Pi session history.
- Produces: verified branch ready for pull request and a reproducible baseline
  command for post-merge monitoring.

- [x] **Step 1: Run focused behavioral verification**

Run:

```bash
ruby tests/pi-stop-audit.rb
```

Expected: PASS.

- [x] **Step 2: Run repository-level verification**

Run:

```bash
ansible-playbook playbook.yml --check
```

If the full check fails before the changed task, reproduce the failure on the
base branch and classify it as related, unrelated, transient, or uncertain.
Do not report the check as passed.

Also run `ansible-playbook playbook.yml --syntax-check`. Use Ansible's `copy`
module in check mode with the production
`roles/common/files/bin/pi-stop-audit` source, a temporary destination, and
mode `0755`. Confirm that Ansible reports the pending copy and does not create
the destination.

Inspect `.github/workflows/integration-test.yml` and confirm
`tests/pi-stop-audit.rb` is invoked directly, as required by the repository's
test inventory policy. Expected: syntax validation, the focused copy check, and
the behavioral test pass. A full-check failure is acceptable only when the same
unrelated baseline failure is reproduced before the changed task.

- [x] **Step 3: Validate the audit against local historical sessions**

Run the production artifact without installing it:

```bash
roles/common/files/bin/pi-stop-audit 14d --limit 50 --json \
  > /tmp/pi-stop-audit-14d.json
ruby -rjson -e '
  report = JSON.parse(File.read(ARGV.fetch(0)))
  abort "missing future-action candidates" unless
    report.dig("counts", "future_action").to_i.positive?
  abort "missing continuation candidates" unless
    report.dig("counts", "short_continuation").to_i.positive?
  abort "candidate over limit" unless report.fetch("candidates").length <= 50
' /tmp/pi-stop-audit-14d.json
```

Review the bounded report. Confirm it finds the historical
`Proceeding with the laptop deployment` then `continue` case, excludes
PR-monitor-started turns, and shows `[REDACTED]` instead of credential-like
values. Do not commit the report.

- [x] **Step 4: Review the scope boundary**

Inspect against the current remote base because another worktree can leave the
local `main` ref behind `origin/main`:

```bash
git diff origin/main...HEAD --stat
git diff origin/main...HEAD
git status --short
```

Confirm:

- No Herdr file changed.
- No PR-monitor file changed.
- No persistent schedule was added.
- No broad command safety layer was added.
- The branch contains only the spec, plan, guidance, audit helper, behavioral
  test, CI registration, and Ansible install task.

- [x] **Step 5: Update and commit the completed plan**

Check completed boxes and add a short `## Verification Results` section with
commands and outcomes. Commit only the plan:

```bash
bash ~/.local/share/skills/_commit/commit.sh \
  -m "Record Pi stop change verification" \
  docs/superpowers/plans/2026-09-02-pi-attention-worthy-stops.md
```

- [x] **Step 6: Request independent code review**

Invoke `requesting-code-review` on `main...HEAD`. Address correctness, privacy,
or scope findings that are worth fixing. Re-run affected verification after any
change.

- [ ] **Step 7: Create the pull request**

Confirm `git status --short` is empty. Invoke `z-pull-request` from the NMB
worktree. The PR description must contain `## Verification` and must not claim
CI as author-initiated evidence.

- [ ] **Step 8: Keep this owner session open for post-release monitoring**

Do not mark this Pi session done. After Brian merges the PR, provision one
personal-development canary host through NMB's focused provisioning path. Then
run the seven controlled scenarios and the 10-session, seven-day observation
plan in the design spec.

Run `pi-stop-audit 7d` after every five eligible sessions. Keep the monitoring
session open until every confidence gate in the design spec passes and Brian
agrees to close it.

## Verification Results

- `ruby tests/pi-stop-audit.rb`: 29 passed, 0 failed.
- `ruby -c roles/common/files/bin/pi-stop-audit`: syntax OK.
- `ansible-playbook playbook.yml --syntax-check`: passed.
- Focused Ansible `copy` check with mode `0755`: reported `changed: true` and
  created no destination.
- Full check mode exited 2 on both the branch and base checkout at the existing
  Linux apt-cache task with `sudo: a password is required`. This reproduced
  unrelated baseline environment failure occurred before the changed task.
- CI invokes `ruby tests/pi-stop-audit.rb` directly.
- The follow-up 14-day local audit read 120 files modified in the window,
  retained 528 non-monitor stops, excluded 131 PR-monitor stops, and found 27
  future-action candidates after preserving non-message graph rows.
- The historical deployment stop followed by `continue` was found with both
  `future_action` and `short_continuation` categories.
- The bounded historical report included redaction markers and was not
  committed.
- `git diff origin/main...HEAD` contains only the approved eight task files. It
  contains no Herdr, PR-monitor, schedule, or command-firewall change.
- Independent whole-branch review found no Critical, Important, or Minor
  findings and marked the branch ready for a pull request.
