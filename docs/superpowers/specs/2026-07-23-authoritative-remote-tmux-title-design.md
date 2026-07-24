---
date: 2026-07-23
topic: Make remote task titles authoritative without transient tmux renames
status: approved
---

# Design: Authoritative remote tmux task titles

## Goal

When a managed agent runs inside a nested or remote tmux session, its current task title should become the outer tmux window title without briefly showing an older outer title. A structured remote title must update the outer pane's canonical provisional task state before the outer label pipeline renders.

Active branch-backed labels remain authoritative and must not be replaced by an agent conversation title.

## Root cause

A structured remote title currently triggers this sequence in `tmux-pane-title-changed`:

1. `tmux-sync-remote-title` extracts the remote task display label and immediately renames the outer window.
2. `tmux-update-pane-label` sees the outer pane's existing managed task state and invokes `tmux-agent-state refresh`.
3. That refresh renders the older outer `@task_label` and renames the same window again.

The two names can legitimately differ. For example, the remote agent may have refined its conversation title while the outer pane still stores the provisional launch subject. Both renames complete within one hook invocation, so polling may miss the intermediate state while a user still sees a visible flash. Agent activity and status updates republish the structured remote title, repeatedly retriggering the sequence.

The bug is therefore not a tmux redraw problem. It is two title authorities writing sequentially: the remote structured title first, then stale outer task state.

## Authority rules

The title pipeline will use these rules:

1. A valid structured remote task title is authoritative over an outer **provisional agent-owned** task.
2. An outer active branch-backed task remains authoritative.
3. Persistent explicit identities, such as locally managed goal or manual identities, retain their existing protection unless they are explicitly designed to follow the remote session.
4. Malformed or unrecognized remote titles do not mutate canonical task state.
5. A degraded bare-host or spinner title does not replace the last valid structured identity.

This change is intentionally limited to the existing structured remote-title contract. Arbitrary terminal titles do not become trusted task identity.

## Design

### Canonical adoption before rendering

Extend the shared remote task parser so the pane-title handler can recover the canonical provisional subject from a valid structured title rather than only the decorated window label. The parser must distinguish the display marker (`~`) from the raw subject and preserve valid subject punctuation.

When `tmux-pane-title-changed` receives a valid structured remote provisional title:

1. Read the outer pane's current task state and source.
2. If it is provisional and agent-owned, adopt the parsed remote subject through `tmux-agent-state`.
3. Let `tmux-agent-state` update `@task_label`, `@pane-label`, and `@window-label` together.
4. Render the window once from that canonical state.

The handler must not first perform the current direct rename and then restore another label. Canonical state changes before visible rendering.

### Protected labels

If the outer pane owns an active branch task, the handler keeps that task and renders it normally. The remote conversation title remains available as pane context, but it does not replace the branch-based window title.

Existing sticky behavior for transient degraded titles remains unchanged.

### Shared parsing contract

Remote subject extraction belongs in `tmux-task-label`, alongside the existing structured-title parsing and truncation behavior. Callers should not independently strip prefixes or parse separators. This keeps support for spaces, middle dots, pipes, Unicode, and length limits consistent across outer-window synchronization and normal label rendering.

The canonical extraction path returns an untruncated raw subject suitable for `@task_label`. Truncation remains a rendering concern handled when `@window-label` is produced.

## Error handling

All title synchronization remains best effort:

- missing pane or remote title: no-op;
- malformed structured title: preserve current task state;
- protected active branch identity: preserve current task state;
- helper failure: preserve the last valid window and pane labels;
- transient degraded remote title: preserve the structured marker and cached identity.

A title update must never interrupt the foreground remote command or agent session.

## Testing

### Parser tests

Extend the label contract tests to prove canonical remote subject extraction:

- removes the provisional display marker without storing it in the subject;
- preserves spaces, Unicode, pipes, middle dots, and literal punctuation;
- returns the full canonical subject before window-label truncation;
- rejects malformed or non-structured titles.

### Pane-title handler regression

Extend `tests/tmux-pane-title-changed.rb` with a reproduction containing:

- a structured remote provisional title;
- a different stale outer provisional agent task;
- instrumented rename and state-helper calls.

Assert that:

1. the remote subject is adopted before rendering;
2. only the remote-derived window label is rendered;
3. the stale outer label is never used for an intermediate rename;
4. a repeated activity-driven publication is idempotent;
5. active branch-backed outer state is not replaced;
6. degraded-title stickiness still passes.

### Regression suite

Run:

```bash
bash tests/tmux-label-contract.sh
bash tests/tmux-agent-state.sh
ruby tests/tmux-pane-title-changed.rb
bash tests/tmux-managed-bars-contract.sh
```

After provisioning, verify with a nested tmux session whose remote agent title differs from its outer launch label. Trigger working/waiting transitions and confirm the outer tab changes directly to the remote title and remains stable.

## Non-goals

- Do not make arbitrary terminal titles authoritative.
- Do not replace active branch-backed window labels with conversation names.
- Do not change agent activity or pull-request indicator colors or glyphs.
- Do not disable structured remote-title publication.
- Do not alter terminal-emulator tab naming.
- Do not add timing delays or debounce the visible symptom.

## Files

Expected implementation scope:

- Modify: `roles/common/files/bin/tmux-task-label`
- Modify: `roles/common/files/bin/tmux-pane-title-changed`
- Modify as needed: `roles/common/files/bin/tmux-agent-state`
- Modify: `tests/tmux-label-contract.sh`
- Modify: `tests/tmux-pane-title-changed.rb`
- Modify as needed: `tests/tmux-agent-state.sh`
