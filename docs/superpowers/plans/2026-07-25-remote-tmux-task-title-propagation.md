# Remote tmux task title propagation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Propagate durable remote goals to the local tmux tab and show one clean detailed pane label during nested tmux use.

**Architecture:** Extend the existing OSC title wire contract with a validated `nmb-task` marker and centralize marker consumption in `tmux-task-label`, so the producer sends identity/context/state while local helpers own visible formatting. Extend the locked per-session client reconciler to hide both inner chrome rows for nested-only sessions and publish a session option that prevents later pane-label refresh hooks from re-enabling the duplicate row.

**Tech Stack:** Bash 3.2-compatible helpers, Python 3 standard library, tmux formats/options, Ruby and shell behavior tests, Ansible-managed files.

## Global Constraints

- Active remote goal tab: `Fix stale tmux feedback indicator`.
- Single visible bottom label: `(Fix stale tmux feedback indicator) new-machine-bootstrap | dev`.
- No visible `[nmb-*]` metadata.
- Goal completion or remote exit restores repository/path identity.
- No polling or timers.
- Remote producers publish state names, never glyphs or local tmux formatting.
- Malformed and unknown markers fail closed.
- Provisional remote adoption retains single-render and failure-atomic ownership.
- Direct clients win over nested clients; `@managed-bars=off` remains a complete opt-out.

---

### Task 1: Explicit remote task-title contract and clean local rendering

**Files:**
- Modify: `roles/common/files/bin/tmux-remote-title`
- Modify: `roles/common/files/bin/tmux-task-label`
- Modify: `roles/common/files/bin/tmux-pane-label`
- Modify: `tests/tmux-label-contract.sh`
- Modify: `tests/tmux-pane-title-changed.rb`

**Interfaces:**
- Produces wire titles of the form `<subject> · <context> | <host> [nmb-task=goal|manual]`, followed by optional validated `nmb-ind` and `nmb-edge` suffixes.
- `tmux-task-label extract-remote <title>` returns the capped task-only top label. For a valid `nmb-task` wire title, the subject is opaque and legacy-looking prefixes such as `~ ` and `12: ` are preserved exactly.
- `tmux-task-label extract-remote-provisional <title>` retains its existing raw provisional-subject contract but rejects any valid `nmb-task` marker.
- New `tmux-task-label render-remote <title>` returns a marker-free detailed pane label, converting a task wire title to `(<subject>) <context> | <host>` while preserving the opaque marked subject.
- `tmux-pane-label` consumes `render-remote`; callers and argument order remain unchanged.

- [ ] **Step 1: Add failing contract tests for publication, extraction, rendering, and rejection**

In `tests/tmux-label-contract.sh`, replace the active goal/manual task-only publication expectations with explicit structured wire expectations:

```bash
assert_equals "$remote_goal_title" "A durable goal that is intentionally longer than forty characters · project | remote-host [nmb-task=goal] [nmb-ind=waiting,merged]" "remote active goal publishes explicit task identity"
assert_equals "$remote_manual_title" "Manual task identity · project | remote-host [nmb-task=manual]" "remote active manual publishes explicit task identity"
```

Add direct parser assertions using the existing task-label helper variables and assertion functions:

```bash
assert_equals "$("$TASK_LABEL" extract-remote 'Fix stale tmux feedback indicator · new-machine-bootstrap | dev [nmb-task=goal] [nmb-ind=working,merged] [nmb-edge=hjkl]')" "Fix stale tmux feedback indicator" "remote parser extracts explicit goal identity"
assert_equals "$("$TASK_LABEL" render-remote 'Fix stale tmux feedback indicator · new-machine-bootstrap | dev [nmb-task=goal] [nmb-ind=working,merged] [nmb-edge=hjkl]')" "(Fix stale tmux feedback indicator) new-machine-bootstrap | dev" "remote renderer hides task transport metadata"
```

Add rejection assertions for an unmarked bare goal, invalid `nmb-task` source, malformed missing context, and unknown marker. Record the marker-authoritative decision with assertions that marked subjects beginning `~ ` or a numeric prefix such as `12: ` extract and render unchanged, while `extract-remote-provisional` rejects the task-marked title and malformed marked titles cannot fall through to legacy branch/provisional parsing. Add rejection assertions for duplicate or unordered edge flags such as `hh`, `kh`, and `lh`. Add a pane-label fixture whose remote `pane_title` is the explicit goal wire title and assert that its output is exactly the detailed marker-free label.

In `tests/tmux-pane-title-changed.rb`, add a behavior scenario with a stale local `window_name`/`@pane-label` and the explicit goal wire title. Assert one `tmux-sync-remote-title`, one `tmux-update-pane-label`, one `tmux-window-label`, the concise renamed window, and the detailed marker-free cached pane label. Follow it with an ordinary `home-network-provisioning | dev` title and assert repository identity replaces the goal.

- [ ] **Step 2: Run the focused tests and confirm the intended failures**

Run:

```bash
tests/tmux-label-contract.sh
ruby tests/tmux-pane-title-changed.rb
```

Expected: failures show active goal/manual titles remain bare, `render-remote` is unavailable, explicit task extraction fails, and the stale outer identity is not replaced. Existing unrelated assertions must remain green.

- [ ] **Step 3: Publish explicit goal/manual task wire titles**

In `roles/common/files/bin/tmux-remote-title`, add a formatter that uses canonical task fields rather than the cached visible window label:

```bash
formatted_remote_task_title() {
  local task_label="$1" task_context="$2" host="$3" task_source="$4" context
  [ -n "$task_label" ] && [ -n "$task_context" ] || return 1
  case "$task_source" in goal|manual) ;; *) return 1 ;; esac
  context="$task_context"
  if [ "${context##* | }" != "$host" ]; then
    context="$context | $host"
  fi
  printf '%s · %s [nmb-task=%s]\n' "$task_label" "$context" "$task_source"
}
```

For active `goal` and `manual` sources, call this formatter before the generic `managed_task_title` fallback. Keep `append_ind_marker` and `append_edge_marker` after it so marker order is task, indicator, edge. Remove the task-only `@window-label` publication shortcut; `@window-label` remains the local renderer's cache and is not a wire-format source.

- [ ] **Step 4: Centralize validation and visible rendering in `tmux-task-label`**

Extend `strip_title_markers` to consume suffixes in exact reverse publication order: optional valid edge, optional valid indicator containing one comma, then optional `nmb-task=goal|manual`. A valid edge is exactly a canonical ordered nonempty subset of `h`, `j`, `k`, `l`; duplicates and out-of-order combinations are rejected. Reject any remaining `[nmb-` text. Preserve the validated task source in parsing paths rather than accepting arbitrary values.

A valid `nmb-task` marker is authoritative. Treat its subject as opaque after field normalization: do not apply provisional/branch recognition or numeric/named nested-title normalization to it. If marked-task field parsing fails, fail closed rather than trying legacy extract/render paths. Direct provisional extraction must reject marked titles.

Add task-wire parsing after `structured_remote_label` normalization:

```bash
extract_marked_task_fields() {
  local title="$1" stripped local_label subject context
  task_source="$(task_marker_source "$title")" || return 1
  stripped="$(structured_remote_label "$title")" || return 1
  local_label="${stripped% | *}"
  [[ "$local_label" =~ ^(.*)[[:space:]]·[[:space:]](.*)$ ]] || return 1
  subject="$(normalize_field "${BASH_REMATCH[1]}")"
  context="$(normalize_field "${BASH_REMATCH[2]}")"
  [[ -n "$subject" && -n "$context" ]] || return 1
}
```

Implement the behavior, not necessarily these local variable mechanics, so Bash subshell scope cannot discard parsed fields. `extract-remote` must prefer a validated marked task and return `truncate_label "$subject"`; only unmarked titles may continue to existing provisional/branch behavior. Add `render-remote` to output `($subject) $context | $host` for a marked task and the stripped structured label for existing unmarked provisional/branch titles.

- [ ] **Step 5: Make pane rendering consume the shared parser**

In `roles/common/files/bin/tmux-pane-label`, resolve `tmux-task-label` beside the script with the same deployed fallback pattern used by other helpers. Replace `strip_edge_marker`/raw structured-label marker handling with `tmux-task-label render-remote`. Keep numeric/named nested-title normalization in one place: either move it fully into `tmux-task-label` or call the helper before returning the normalized nested title, but never render raw `[nmb-*]` suffixes.

The remote-host fallback comparison must compare against the host suffix of the marker-free rendered label. Ordinary `repo | host` and existing provisional/branch labels must remain byte-for-byte compatible.

- [ ] **Step 6: Run focused tests and syntax checks**

Run:

```bash
bash -n roles/common/files/bin/tmux-remote-title roles/common/files/bin/tmux-task-label roles/common/files/bin/tmux-pane-label roles/common/files/bin/tmux-pane-title-changed
ruby tests/tmux-pane-title-changed.rb
tests/tmux-label-contract.sh
```

Expected: all checks pass; the new goal scenario renames the stale outer tab once, renders the exact detailed label without markers, and later restores repository identity.

- [ ] **Step 7: Commit the task-title contract**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Propagate durable remote tmux task titles" \
  roles/common/files/bin/tmux-remote-title \
  roles/common/files/bin/tmux-task-label \
  roles/common/files/bin/tmux-pane-label \
  tests/tmux-label-contract.sh \
  tests/tmux-pane-title-changed.rb
```

---

### Task 2: Hide the duplicate inner pane-label row

**Files:**
- Modify: `roles/common/files/bin/tmux-reconcile-status-bars`
- Modify: `roles/common/files/bin/tmux-sync-pane-border-status`
- Modify: `tests/tmux-managed-bars-contract.sh`
- Modify: `roles/linux/files/dotfiles/tmux.conf`
- Modify: `roles/macos/templates/dotfiles/tmux.conf`

**Interfaces:**
- Session option `@nested-client-only` is `1` only while every attached client terminal starts with `tmux` or `screen`; it is unset for direct, mixed, and zero-client sessions. It controls only that session's top status.
- Window option `@nested-window-only` is `1` only while every session owning that window is nested-only. A direct, mixed, or zero-client owner wins and leaves the marker unset, independent of session listing order.
- Reconciler discovers the complete server session/client/window ownership topology before mutation, then applies session status once per session and pane-border status plus aggregate marker once per unique window.
- `tmux-sync-pane-border-status <pane-id>` resolves the pane's window and applies `off` when `@nested-window-only=1`, otherwise `bottom`.
- `@managed-bars=off` bypasses all reads/writes that mutate status, pane-border status, session markers, or window markers.

- [ ] **Step 1: Add failing managed-bars behavior tests**

Extend `tests/tmux-managed-bars-contract.sh` so each existing client topology asserts both properties:

```text
no clients                 status=on  pane-border-status=bottom  marker unset
direct only                status=on  pane-border-status=bottom  marker unset
nested only                status=off pane-border-status=off     marker=1
mixed direct+nested        status=on  pane-border-status=bottom  marker unset
last nested client detaches status=on pane-border-status=bottom  marker unset
```

Create at least two windows in the nested session and assert reconciliation changes every existing window, not only the current window. After nested reconciliation, invoke `tmux-sync-pane-border-status` for a pane and assert it remains `off`. After a direct attach, invoke it again and assert `bottom`.

Use real linked-window topology in both session listing orders. Link a window between a nested-only session and a direct or zero-client session and assert window-level direct-wins keeps `bottom` with `@nested-window-only` unset. Invoke `tmux-sync-pane-border-status` from the nested owner and prove it cannot override aggregate `bottom`. Unlink the direct/zero owner and prove the `window-unlinked` hook converges the remaining nested-only window to `off` with marker `1`.

Expand `@managed-bars=off` stability sampling to assert the chosen `pane-border-status`, `@nested-client-only`, and `@nested-window-only` values remain unchanged across attach, detach, session-change, creation, link, and unlink hooks.

- [ ] **Step 2: Run the managed-bars contract and confirm failure**

Run:

```bash
tests/tmux-managed-bars-contract.sh
```

Expected: nested sessions still report `pane-border-status=bottom`, no nested marker exists, and the sync helper re-enables the duplicate row.

- [ ] **Step 3: Extend locked reconciliation to pane-label visibility**

In `roles/common/files/bin/tmux-reconcile-status-bars`, discover every session's clients and windows before the first mutation. Abort the pass if any topology read fails. Record each session's nested-only state and aggregate the owner states for every unique window ID.

Under the same lock, set or unset session option `@nested-client-only` and apply that session's status. Then mutate each unique window exactly once: use `pane-border-status off` plus `@nested-window-only=1` only when all owning sessions are nested-only; otherwise use `bottom` and unset the window marker. Retain best-effort behavior for individual mutations after complete discovery.

This full-topology snapshot makes shared-window direct-wins independent of tmux session listing order and avoids partially derived mutations.

- [ ] **Step 4: Prevent refresh hooks from restoring nested labels**

In `roles/common/files/bin/tmux-sync-pane-border-status`, resolve `#{window_id}` in one `display-message` read. Read `@nested-window-only` on that window and choose:

```bash
pane_border_status=bottom
[ "$nested_window_only" = "1" ] && pane_border_status=off
tmux set-window-option -q -t "$window_id" pane-border-status "$pane_border_status"
```

Retain the global `@managed-bars=off` early return and quiet behavior for missing pane/window targets. Never infer the policy from one ambiguous owning session.

- [ ] **Step 5: Update config comments to describe both managed bars**

In both managed tmux configs, update the nearby reconciliation comments to distinguish session status from shared-window aggregate pane labels. Keep the indexed attach/detach/session-change and after-new-window/window-linked paths, and add portable indexed `window-unlinked[90]` reconciliation so removing the last direct/zero owner converges immediately. Do not add timers or inline client-detection logic.

- [ ] **Step 6: Run managed-bar and full focused contracts**

Run:

```bash
python3 -m py_compile roles/common/files/bin/tmux-reconcile-status-bars
bash -n roles/common/files/bin/tmux-sync-pane-border-status
tests/tmux-managed-bars-contract.sh
tests/tmux-label-contract.sh
ruby tests/tmux-pane-title-changed.rb
```

Expected: all checks pass, nested-only sessions retain `off` after label refreshes, direct/mixed/zero-client sessions show `bottom`, and marker/title behavior from Task 1 remains green.

- [ ] **Step 7: Commit nested pane-label reconciliation**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Hide duplicate pane labels in nested tmux" \
  roles/common/files/bin/tmux-reconcile-status-bars \
  roles/common/files/bin/tmux-sync-pane-border-status \
  tests/tmux-managed-bars-contract.sh \
  roles/linux/files/dotfiles/tmux.conf \
  roles/macos/templates/dotfiles/tmux.conf
```

---

### Task 3: Integrated verification and live nested proof

**Files:**
- Verify only; no production files expected.

**Interfaces:**
- Consumes the explicit task-title contract and nested bar reconciliation from Tasks 1 and 2.
- Produces reviewer-facing evidence for the pull request.

- [ ] **Step 1: Run fresh repository verification**

Run:

```bash
ruby tests/tmux-pane-title-changed.rb
tests/tmux-label-contract.sh
tests/tmux-managed-bars-contract.sh
git diff --check origin/main...HEAD
git status --short
```

Expected: all behavior contracts pass, diff check is clean, and only intentionally ignored reviewer artifacts are untracked (otherwise clean them before continuing).

- [ ] **Step 2: Review the whole branch**

Review `origin/main...HEAD` against the design. Treat malformed marker acceptance, duplicate renders, nested/direct visibility regressions, and `@managed-bars=off` mutation as blocking findings. Fix and repeat verification before proceeding.

- [ ] **Step 3: Provision from the feature worktree where each environment permits**

On macOS, run `bin/provision` from this worktree. On the Linux dev host, run the same command only when passwordless sudo is available; otherwise retain the exact sudo boundary as a documented deployment gap rather than editing deployed files directly.

Expected: managed helpers and tmux config deploy from the feature commit without direct edits outside the repository.

- [ ] **Step 4: Verify the live nested UI**

From the macOS outer tmux attached to the Linux dev tmux, publish an active goal and confirm:

```text
local tab:        Fix stale tmux feedback indicator
single bottom:    (Fix stale tmux feedback indicator) new-machine-bootstrap | dev
hidden metadata:  no [nmb-*] text
```

Trigger working/waiting transitions while the local tab is inactive and confirm indicators update immediately without changing the clean text. End the goal or exit the remote command and confirm repository/path identity returns. Directly attached tmux must still show its own bottom pane label.

If live proof cannot run because one host cannot provision, state which host and boundary in the PR instead of claiming end-to-end deployment.

- [ ] **Step 5: Create the pull request**

Use the repository pull-request workflow. The PR body must summarize the two confirmed production symptoms, the explicit marker contract, the nested-only pane-label policy, focused verification, live proof or its exact deployment gap, and relation to PR #378.
