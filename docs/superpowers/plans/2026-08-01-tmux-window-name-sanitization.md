# Tmux Window Name Sanitization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent valid remote task labels containing periods or colons from causing persistent tmux window rename failures.

**Architecture:** Keep canonical task identity unchanged. Sanitize only the final label inside `tmux-window-label`, immediately before the tmux window-name comparison and mutation.

**Tech Stack:** Bash, tmux command stubs, shell behavior tests.

## Global Constraints

- Replace each `.` with `-` in the final tmux window name.
- Replace each `:`, including adjacent whitespace, with ` - `.
- Collapse repeated spaces created by sanitization.
- Do not alter task goals, remote title metadata, pane-border labels, or cached task identity.
- Continue to report unexpected tmux mutation failures.

---

### Task 1: Sanitize Final Tmux Window Names

**Files:**
- Modify: `tests/tmux-label-contract.sh`
- Modify: `roles/common/files/bin/tmux-window-label`

**Interfaces:**
- Consumes: the existing final shell variable `label` after label selection and host-suffix stripping.
- Produces: `sanitize_window_name <label>`, which writes one tmux-safe window name to standard output.

- [ ] **Step 1: Write the failing behavior test**

Add a table-driven case after the existing remote provisional-label cases in `tests/tmux-label-contract.sh`:

```bash
for sanitization_case in \
  'Replace models with 5.6^Replace models with 5-6^period' \
  'task: v2^task - v2^colon with space' \
  'task:v2^task - v2^colon without space'; do
  input="${sanitization_case%%^*}"
  remainder="${sanitization_case#*^}"
  expected="${remainder%%^*}"
  case_name="${remainder#*^}"
  : > "$window_log"
  TMUX_TEST_TITLE="~ $input · project | remote-host" \
  TMUX_WINDOW_LABEL_LOG="$window_log" PATH="$fake_tmux_dir:$PATH" \
    "$WINDOW_LABEL" "%1"
  assert_file_contains "$window_log" "rename-window -t @1 ~ $expected" \
    "outer window sanitizes $case_name"
done
```

This executes the real production helper and asserts on the tmux mutation boundary.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
bash tests/tmux-label-contract.sh
```

Expected: the three new `outer window sanitizes ...` assertions fail because the current helper forwards periods and colons unchanged.

- [ ] **Step 3: Implement the minimal sanitizer**

Add this focused function near the other label helpers in `roles/common/files/bin/tmux-window-label`:

```bash
sanitize_window_name() {
  local value="${1:-}"
  value="${value//./-}"
  value="${value//:/ - }"
  while [[ "$value" == *"  "* ]]; do
    value="${value//  / }"
  done
  printf '%s\n' "$value"
}
```

After host-suffix stripping and before the final nonempty-label guard, sanitize the selected label:

```bash
label="$(sanitize_window_name "$label")"
[ -n "$label" ] || exit 0
```

Do not change mutation failure handling.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
bash tests/tmux-label-contract.sh
ruby tests/tmux-pane-title-changed.rb
bash -n roles/common/files/bin/tmux-window-label
```

Expected: all commands pass.

- [ ] **Step 5: Run repository verification**

Run:

```bash
bin/test
```

Expected: all CI-safe repository checks pass.

- [ ] **Step 6: Commit the implementation**

Commit only the test and production helper with an imperative message such as:

```text
Sanitize tmux window names before rename
```
