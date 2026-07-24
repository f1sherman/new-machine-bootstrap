# tmux 3.7 Field Parsing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep outer tmux labels synchronized when tmux 3.7 sanitizes control-character delimiters in format output.

**Architecture:** The four metadata-reading helpers will delimit tmux fields with one explicit printable marker. Each helper will translate that marker to ASCII Unit Separator locally and parse with the non-whitespace separator so empty fields remain positional.

**Tech Stack:** Bash, tmux formats, shell contract tests, Ansible provisioning.

## Global Constraints

- Preserve existing label selection, indicator, active-pane, and remote-command behavior.
- Use the exact internal marker `__NMB_TMUX_FIELD__`.
- Preserve empty metadata fields and punctuation inside titles, paths, and names.
- Keep one `tmux display-message` metadata query per helper invocation.
- Do not edit deployed files under `~/.local/bin`; change repository sources only.

---

### Task 1: Make metadata parsing tmux 3.7-safe

**Files:**
- Modify: `tests/tmux-label-contract.sh`
- Modify: `roles/common/files/bin/tmux-pane-label`
- Modify: `roles/common/files/bin/tmux-pane-title-changed`
- Modify: `roles/common/files/bin/tmux-sync-remote-title`
- Modify: `roles/common/files/bin/tmux-window-label`

**Interfaces:**
- Consumes: tmux format fields returned by `tmux display-message -p -t <pane> <format>`.
- Produces: the same existing helper outputs and tmux side effects, with metadata fields separated by `__NMB_TMUX_FIELD__` in the query and parsed through ASCII Unit Separator locally.

- [ ] **Step 1: Write the failing tmux 3.7 regression**

Add a focused fake `tmux` block to `tests/tmux-label-contract.sh`. Its `display-message` implementation must take the requested format, substitute fixture values for every requested `#{...}` field, and execute:

```bash
output="${output//$'\t'/_}"
```

before printing. Assert that:

```bash
assert_equals "$pane_label" '(feature/tmux-37) project | remote-host' \
  'tmux 3.7 parsing preserves structured remote pane label'
assert_file_contains "$hook_log" 'tmux-sync-remote-title %37' \
  'tmux 3.7 parsing dispatches structured pane title synchronization'
assert_file_contains "$sync_log" 'rename-window -t @37 feature/tmux-37' \
  'tmux 3.7 parsing synchronizes remote window title'
assert_file_contains "$window_log" 'rename-window -t @37 feature/tmux-37' \
  'tmux 3.7 parsing renders remote window label'
```

Use empty fixture values for at least one field before the title (for example `window_name`) so the assertions also protect positional empty-field parsing.

- [ ] **Step 2: Run the regression and verify RED**

Run:

```bash
bash tests/tmux-label-contract.sh
```

Expected: the new tmux 3.7 assertions fail because literal tabs become underscores and existing `IFS=$'\t' read` calls cannot recover the fields.

- [ ] **Step 3: Implement explicit marker parsing**

In each affected helper, define:

```bash
field_separator='__NMB_TMUX_FIELD__'
parse_separator=$'\x1f'
```

Construct the existing tmux format with `${field_separator}` between fields, capture `pane_info`, then translate and parse:

```bash
pane_info="${pane_info//$field_separator/$parse_separator}"
IFS="$parse_separator" read -r ... <<< "$pane_info"
```

Retain each script's current field order, guards, fallbacks, and side effects unchanged.

- [ ] **Step 4: Run focused and syntax verification**

Run:

```bash
bash tests/tmux-label-contract.sh
bash -n roles/common/files/bin/tmux-pane-label \
  roles/common/files/bin/tmux-pane-title-changed \
  roles/common/files/bin/tmux-sync-remote-title \
  roles/common/files/bin/tmux-window-label
shellcheck -x roles/common/files/bin/tmux-pane-label \
  roles/common/files/bin/tmux-pane-title-changed \
  roles/common/files/bin/tmux-sync-remote-title \
  roles/common/files/bin/tmux-window-label
```

Expected: all contract checks pass; Bash syntax and ShellCheck exit zero.

- [ ] **Step 5: Run repository verification**

Run:

```bash
ansible-playbook --inventory localhost, --connection local playbook.yml --syntax-check
git diff --check
git status --short
```

Expected: syntax check and diff check exit zero; status lists only the approved spec, plan, four helpers, and contract test.

- [ ] **Step 6: Commit the implementation**

```bash
git add docs/superpowers/specs/2026-07-24-tmux-3-7-field-parsing-design.md \
  docs/superpowers/plans/2026-07-24-tmux-3-7-field-parsing.md \
  tests/tmux-label-contract.sh \
  roles/common/files/bin/tmux-pane-label \
  roles/common/files/bin/tmux-pane-title-changed \
  roles/common/files/bin/tmux-sync-remote-title \
  roles/common/files/bin/tmux-window-label
git commit -m "Handle tmux 3.7 field sanitization"
```
