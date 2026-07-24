# Authoritative Remote Tmux Title Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate nested tmux tab-title flicker by adopting a valid remote provisional agent subject into canonical outer task state before one visible render.

**Architecture:** Add one canonical-subject mode to the existing `tmux-task-label` parser, preserving the current decorated/truncated extraction mode for display consumers. Route structured provisional titles through `tmux-agent-state set-provisional` before rendering; retain the existing direct synchronization path for non-provisional structured titles and preserve active branch authority through `tmux-agent-state`'s existing guard.

**Tech Stack:** Bash helper scripts, Ruby integration-style shell stubs, tmux format/options contract tests.

## Global Constraints

- A valid structured remote task title is authoritative over an outer provisional agent-owned task.
- Active branch-backed outer labels remain authoritative.
- Arbitrary, malformed, or degraded terminal titles must not mutate canonical task state.
- Canonical subjects remain untruncated; truncation is rendering-only.
- No timing delays or debounce-based symptom masking.
- Public repository content must contain no private organization, repository, ticket, employee, or environment-specific references.

---

### Task 1: Canonical provisional subject extraction

**Files:**
- Modify: `roles/common/files/bin/tmux-task-label`
- Test: `tests/tmux-label-contract.sh`

**Interfaces:**
- Consumes: the existing `structured_remote_label(title)` normalized-title contract.
- Produces: `tmux-task-label extract-remote-provisional <structured-title>`, printing one raw, untruncated provisional subject and exiting zero only for valid `~ <subject> · <context> | <host>` titles.

- [ ] **Step 1: Write failing parser contract tests**

Add focused assertions beside the existing `extract-remote` cases:

```bash
assert_equals \
  "$($TASK_LABEL extract-remote-provisional '~ investigate title race · project | remote-host [nmb-ind=waiting,] [nmb-edge=hj]')" \
  'investigate title race' \
  'remote parser extracts raw provisional subject'
assert_equals \
  "$($TASK_LABEL extract-remote-provisional '~ auth · billing | migration · project | remote-host')" \
  'auth · billing | migration' \
  'remote parser preserves subject separators'
long_remote_subject="$(printf '界%.0s' {1..60})"
assert_equals \
  "$($TASK_LABEL extract-remote-provisional "~ $long_remote_subject · project | remote-host")" \
  "$long_remote_subject" \
  'remote parser keeps canonical subject untruncated'
if "$TASK_LABEL" extract-remote-provisional 'plain project | remote-host' >/dev/null 2>&1; then
  fail_case 'remote parser rejects non-provisional title' 'unexpected successful extraction'
fi
pass_case 'remote parser rejects non-provisional title'
```

- [ ] **Step 2: Run the parser tests and verify red**

Run: `bash tests/tmux-label-contract.sh`

Expected: FAIL because `extract-remote-provisional` is not a recognized command.

- [ ] **Step 3: Implement canonical extraction in the shared parser**

Add a function using the existing structured-title normalization, without calling `truncate_label`:

```bash
extract_remote_provisional() {
  local label local_label subject
  label="$(structured_remote_label "$1")" || return 1
  local_label="${label% | *}"
  [[ "$local_label" =~ ^~\ (.*)\ ·\ (.+)$ ]] || return 1
  subject="${BASH_REMATCH[1]}"
  [[ -n "$subject" ]] || return 1
  printf '%s\n' "$subject"
}
```

Add the dispatch branch and update usage:

```bash
  extract-remote-provisional)
    shift
    extract_remote_provisional "$*"
    ;;
```

- [ ] **Step 4: Run the parser contract and verify green**

Run: `bash tests/tmux-label-contract.sh`

Expected: exit 0 ending with `tmux label contract checks complete`.

- [ ] **Step 5: Commit the parser contract**

```bash
~/.pi/agent/skills/z-commit/commit.sh \
  -m "Extract canonical remote tmux subjects" \
  roles/common/files/bin/tmux-task-label \
  tests/tmux-label-contract.sh
```

---

### Task 2: Adopt remote identity before rendering

**Files:**
- Modify: `roles/common/files/bin/tmux-pane-title-changed`
- Test: `tests/tmux-pane-title-changed.rb`

**Interfaces:**
- Consumes: `tmux-task-label extract-remote-provisional <title>` from Task 1 and existing `tmux-agent-state set-provisional <subject>` authority guards.
- Produces: a structured-title path that never invokes `tmux-sync-remote-title` before restoring stale provisional state; valid provisional titles update canonical task state first.

- [ ] **Step 1: Extend the pane-title test harness with parser and state stubs**

Add `TMUX_TEST_TASK_STATE`, `TMUX_TEST_TASK_SOURCE`, and `TMUX_TEST_TASK_LABEL` to `run_helper`. Add executable stubs that log calls and return a canonical subject only when the title begins with the structured provisional form:

```ruby
write_executable(File.join(bin, "tmux-task-label"), <<~'RUBY')
  #!/usr/bin/env ruby
  File.open(ENV.fetch("TMUX_TEST_LOG"), "a") { |f| f.puts((["tmux-task-label"] + ARGV).join("\t")) }
  exit 1 unless ARGV.first == "extract-remote-provisional"
  title = ARGV.drop(1).join(" ")
  match = title.match(/^~ (.*) · .* \| /)
  exit 1 unless match
  puts match[1]
RUBY

write_executable(File.join(bin, "tmux-agent-state"), <<~'RUBY')
  #!/usr/bin/env ruby
  File.open(ENV.fetch("TMUX_TEST_LOG"), "a") { |f| f.puts((["tmux-agent-state"] + ARGV).join("\t")) }
RUBY
```

- [ ] **Step 2: Add the failing single-authority regression**

Exercise a remote title different from the stale local launch label and assert canonical adoption without direct remote rename:

```ruby
File.write(File.join(tmpdir, "calls.log"), "")
_out, err, status, log = run_helper(
  tmpdir,
  "%95",
  title: "~ refined remote task · project | remote-host [nmb-ind=waiting,]",
  structured: true
)
assert("remote provisional title updates canonical state before rendering", err) do
  status.success? &&
    log.include?("tmux-task-label\textract-remote-provisional") &&
    log.include?("tmux-agent-state\tset-provisional\trefined remote task")
end
assert("remote provisional title avoids intermediate direct rename", log) do
  !log.include?("tmux-sync-remote-title\t%95")
end
```

Retain and update the existing structured non-provisional assertion so `repo | remote-host` still calls `tmux-sync-remote-title`, `tmux-sync-pane-border-status`, and `tmux-update-pane-label`.

- [ ] **Step 3: Run the focused handler test and verify red**

Run: `ruby tests/tmux-pane-title-changed.rb`

Expected: FAIL because the handler does not call the parser or state helper and still calls `tmux-sync-remote-title` for provisional titles.

- [ ] **Step 4: Implement canonical-first routing**

Resolve helpers relative to the installed script, parse the title once, and branch before direct synchronization:

```bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
task_label_helper="${TMUX_TASK_LABEL_BIN:-$script_dir/tmux-task-label}"
agent_state_helper="${TMUX_AGENT_STATE_BIN:-$script_dir/tmux-agent-state}"
[ -x "$task_label_helper" ] || task_label_helper="${HOME:-}/.local/bin/tmux-task-label"
[ -x "$agent_state_helper" ] || agent_state_helper="${HOME:-}/.local/bin/tmux-agent-state"
```

Inside the structured-title branch, adopt before rendering and keep the existing path as fallback:

```bash
subject="$("$task_label_helper" extract-remote-provisional "$title" 2>/dev/null || true)"
if [ -n "$subject" ] && [ -x "$agent_state_helper" ]; then
  TMUX_PANE="$pane_id" "$agent_state_helper" set-provisional "$subject" >/dev/null 2>&1 || true
  tmux-sync-pane-border-status "$pane_id"
  tmux-window-label "$pane_id"
else
  tmux-sync-remote-title "$pane_id"
  tmux-sync-pane-border-status "$pane_id"
  tmux-update-pane-label "$pane_id"
fi
```

Do not change degraded-title or same-pane remote-exit behavior.

- [ ] **Step 5: Add idempotence and branch-authority assertions**

Invoke the provisional case twice and assert each invocation uses canonical adoption and never calls direct synchronization. Configure the state stub to represent an active branch and assert the handler still delegates authority to `tmux-agent-state set-provisional` rather than directly renaming; `tmux-agent-state` is the component that refuses replacement.

- [ ] **Step 6: Run focused tests and verify green**

Run:

```bash
ruby tests/tmux-pane-title-changed.rb
bash tests/tmux-label-contract.sh
bash tests/tmux-agent-state.sh
```

Expected: all exit 0; Ruby summary reports zero failures and both shell suites print their completion messages.

- [ ] **Step 7: Commit canonical-first title handling**

```bash
~/.pi/agent/skills/z-commit/commit.sh \
  -m "Adopt remote tmux titles before rendering" \
  roles/common/files/bin/tmux-pane-title-changed \
  tests/tmux-pane-title-changed.rb
```

---

### Task 3: Full verification and live reproduction

**Files:**
- No source changes expected.
- Update tests only if verification exposes a missing assertion directly related to the approved behavior.

**Interfaces:**
- Consumes: canonical parser and canonical-first pane-title route from Tasks 1–2.
- Produces: verified provisioned behavior and PR-ready evidence.

- [ ] **Step 1: Run the complete relevant regression set**

```bash
bash tests/tmux-label-contract.sh
bash tests/tmux-agent-state.sh
ruby tests/tmux-pane-title-changed.rb
bash tests/tmux-managed-bars-contract.sh
```

Expected: every command exits 0.

- [ ] **Step 2: Provision from the feature worktree**

Run: `bin/provision`

Expected: Ansible recap reports `failed=0` and the log records branch `fix/remote-title-flicker` with a clean repository state.

- [ ] **Step 3: Verify installed artifacts match source**

```bash
cmp roles/common/files/bin/tmux-task-label "$HOME/.local/bin/tmux-task-label"
cmp roles/common/files/bin/tmux-pane-title-changed "$HOME/.local/bin/tmux-pane-title-changed"
```

Expected: both commands exit 0.

- [ ] **Step 4: Re-run the exact flicker regression against installed helpers**

Temporarily point the Ruby test's `HELPER` constant at `$HOME/.local/bin/tmux-pane-title-changed` without editing the repository, then run the same stubbed two-authority sequence:

```bash
ruby -e '
path = "tests/tmux-pane-title-changed.rb"
source = File.read(path)
source.sub!(
  %r{HELPER = File\.join\(REPO_ROOT, "roles/common/files/bin/tmux-pane-title-changed"\)},
  "HELPER = File.expand_path(\"~/.local/bin/tmux-pane-title-changed\")"
)
eval(source, TOPLEVEL_BINDING, path)
'
```

Expected: zero failures, including `remote provisional title avoids intermediate direct rename` and the repeated-publication idempotence assertion.

- [ ] **Step 5: Review final diff and repository state**

```bash
git diff main...HEAD --check
git status --short --branch
git log --oneline main..HEAD
```

Expected: no whitespace errors; only approved spec, plan, parser, handler, and tests differ; worktree is clean.
