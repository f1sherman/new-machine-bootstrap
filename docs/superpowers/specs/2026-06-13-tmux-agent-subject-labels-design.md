---
date: 2026-06-13
topic: tmux agent subject labels
status: approved
---

# Design: tmux agent subject labels

## Goal

Make tmux window names identify what an active Claude Code or Codex session is
doing even before `repo-start` has published worktree state and after
`repo-end` has cleared it.

The user should be able to glance at the tmux window list and distinguish:

- which windows are Claude or Codex agent sessions
- the current task subject for each agent session
- the repo or worktree context when that context exists

The subject is explicit agent-maintained state. Hooks may remind the agent to
set it, but hooks should not guess the subject from arbitrary prompt text.

## Non-goals

- No upstream Superpowers skill checkout edits.
- No direct edits to deployed files under `~`, except through normal
  provisioning output.
- No attempt to infer task subjects from every prompt.
- No visible stale marker after `repo-end`.
- No requirement for this to work outside tmux. Helpers should quietly no-op
  when tmux context is absent.

## Background

Current tmux labeling is already repo-aware once `repo-start` or
`tmux-agent-worktree set` publishes pane-local state. The key state today is:

- `@agent_worktree_path`
- `@agent_worktree_pid`
- `@pane-label`

`tmux-agent-worktree` writes that state, `tmux-window-label` consumes the cached
`@pane-label`, and `repo-end` clears the explicit worktree state.

The missing cases are outside that repo lifecycle:

1. A newly started Claude or Codex pane has only a generic cwd-derived window
   name.
2. A pane after `repo-end` loses the worktree-derived name even though the user
   may still want to remember what the session had been doing.
3. A long-running agent can switch from one task to another without an obvious
   tmux window-name update unless a repo lifecycle helper is called.

Claude has a `PostToolUse` `Skill` hook path, so it can be reminded exactly
when `superpowers:brainstorming` or `superpowers:systematic-debugging` is
invoked. Codex hooks support lifecycle events such as `UserPromptSubmit`,
`SessionStart`, `PreToolUse`, and `PostToolUse`, but current Codex
documentation and local configuration do not show a native `Skill` tool matcher
equivalent to Claude's. Codex therefore needs prompt-hook coverage plus
model-visible instructions.

## Design Summary

Introduce a shared tmux agent-state helper that owns agent subject state and the
final pane/window label composition. Existing repo lifecycle helpers should use
the same helper path instead of having repo-start/repo-end and subject labels
compose tmux labels independently.

Pane-local state stays separated:

- `@agent_kind`: `claude` or `codex`
- `@agent_subject`: short task subject, set explicitly by the agent
- `@agent_subject_stale`: set when the subject was retained after a finished
  repo lifecycle
- `@agent_worktree_path`: explicit repo/worktree path
- `@agent_worktree_pid`: active agent pid associated with the worktree path
- `@pane-label`: rendered pane-border label cache
- `@window-label`: rendered window-name label cache

`repo-start` and `tmux-agent-worktree set` update the worktree fields and then
ask the shared helper to render the label. `repo-end` clears worktree fields,
keeps `@agent_subject`, sets `@agent_subject_stale=1`, and re-renders the label.

The stale flag is intentionally invisible in tmux. The next prompt hook uses it
only to remind the agent to update or clear the subject.

## Label Shape

When an agent subject exists, the tmux window name should lead with agent kind
and subject:

```text
codex: tmux subject labels
claude: debug shell startup
```

When no subject exists but the pane is known to be an agent session, the label
should still identify the agent and cwd/repo fallback:

```text
codex new-machine-bootstrap
claude new-machine-bootstrap
```

When worktree state exists, the pane border can keep showing the richer
repo/worktree label already used today. The shared renderer should preserve
that existing branch/repo label behavior instead of replacing it with only the
subject.

Pane-border and window labels should be composed separately:

- `@pane-label` keeps the current branch/repo/host-oriented label.
- `@window-label` favors the agent subject when one exists.

`tmux-window-label` should prefer `@window-label` when present, then fall back
to existing `@pane-label` and cwd behavior. This keeps the window list focused
on task identity without removing repo context from pane borders.

## Components

### `tmux-agent-state`

File: `roles/common/files/bin/tmux-agent-state`

This is the shared state and label helper. It should provide these commands:

- `set-kind <claude|codex>`: stores `@agent_kind`
- `set-subject <subject>`: stores a sanitized/truncated `@agent_subject`,
  clears `@agent_subject_stale`, and refreshes labels
- `clear-subject`: clears subject and stale flag, then refreshes labels
- `mark-subject-stale`: keeps subject but stores `@agent_subject_stale=1`
- `set-worktree <absolute-path>`: stores existing worktree state and refreshes
  labels
- `clear-worktree`: clears worktree fields, keeps subject, and refreshes labels
- `refresh`: recomputes `@pane-label` and `@window-label`, then calls
  `tmux-window-label` and remote title publishing where appropriate

The helper should be idempotent. Missing tmux context, invalid paths, missing
agent process information, or missing optional helper dependencies should not
break agent work.

### Compatibility wrappers

Keep `tmux-agent-worktree` available as the public worktree helper. Its
worktree validation and PR-link behavior may remain local to that script, but
its final pane/window label rendering should delegate to `tmux-agent-state` so
there is only one label-composition path.

Existing call sites that use:

```bash
tmux-agent-worktree set <path>
tmux-agent-worktree sync-current
tmux-agent-worktree clear
```

must keep working.

Add `tmux-agent-subject` as a small user-facing wrapper:

```bash
tmux-agent-subject set "tmux subject labels"
tmux-agent-subject clear
tmux-agent-subject status
```

The reminder text should mention `tmux-agent-subject`, not the lower-level
state helper.

### Session-start binding

`tmux-claude-session-start` and `codex-bind-tmux-pane` should set
`@agent_kind` through the shared helper during `SessionStart`.

They should continue to bind session metadata exactly as they do today and
should continue to refresh labels after successful binding.

### Repo lifecycle integration

`repo-start` should keep publishing worktree state after a worktree or branch
context is selected, but the label composition should route through the shared
helper.

`repo-end` should:

1. clear `@agent_worktree_path`, `@agent_worktree_pid`, PR pane links, and any
   other worktree-specific pane options
2. keep `@agent_subject`
3. set `@agent_subject_stale=1` when a subject exists
4. refresh labels without showing a stale marker

### Reminder hooks

#### Claude Code

Add or extend a Claude hook for `PostToolUse` with `matcher: "Skill"`.

When the invoked skill is:

- `superpowers:brainstorming`
- `superpowers:systematic-debugging`

and the pane has no `@agent_subject`, emit `additionalContext` telling the
agent to call:

```bash
tmux-agent-subject set "<short subject>"
```

If `@agent_subject_stale=1`, emit a similar reminder to update or clear the
subject before continuing.

This can live in a new hook script or be combined carefully with the existing
main-branch initiation-skill reminder, as long as the concerns stay testable.

#### Codex

Codex does not currently provide a confirmed native `Skill` hook matcher.
Provide the best available coverage:

1. A `UserPromptSubmit` hook detects explicit prompt text containing
   `$superpowers:brainstorming`, `superpowers:brainstorming`,
   `$superpowers:systematic-debugging`, or `superpowers:systematic-debugging`.
2. If there is no subject, or if `@agent_subject_stale=1`, it emits
   `additionalContext` telling Codex to call `tmux-agent-subject set
   "<short subject>"` or clear it.
3. Managed Codex instructions should also tell Codex to call
   `tmux-agent-subject set` when it invokes those skills implicitly.

This is intentionally a reminder, not a blocker.

## Data Flow

### New session

1. Claude/Codex `SessionStart` hook runs.
2. Hook binds session metadata and `@agent_kind`.
3. Shared helper renders a fallback agent label from kind plus cwd/repo.
4. Window name becomes agent-aware before any `repo-start`.

### Subject set

1. Agent calls `tmux-agent-subject set "short subject"`.
2. Helper writes `@agent_subject`, clears stale flag, recomputes `@pane-label`
   and `@window-label`, and renames the window.
3. Window name reflects the subject immediately.

### Repo start

1. `repo-start` creates/selects branch or worktree.
2. Worktree state is published through the shared helper.
3. The subject, if present, remains.
4. Worktree/repo context remains available in pane border and fallback labels.

### Repo end

1. `repo-end` clears worktree state through the shared helper.
2. Existing subject is retained.
3. `@agent_subject_stale=1` is stored, but no stale marker is rendered.
4. Next prompt hook reminds the agent to update or clear the stale subject.

## Error Handling

Helpers should prefer successful no-op behavior over user-visible failure for
missing tmux context, missing pane id, absent optional helper binaries, and
invalid state.

Invalid or overlong subjects should be sanitized before storage:

- trim leading/trailing whitespace
- collapse control characters
- cap display length to a small fixed limit

If a hook cannot read tmux state, it should emit no reminder. Agent work should
never be blocked by this feature.

## Testing

Add focused shell/Ruby tests matching existing repo style:

1. `tmux-agent-subject` stores subject, clears stale flag, and triggers label
   refresh.
2. `tmux-agent-state` composes fallback agent labels when only kind/cwd exist,
   including both pane and window label caches.
3. Worktree publication still produces the existing branch/repo pane-label
   behavior while preserving subject-first window labels.
4. `tmux-window-label` prefers `@window-label` and falls back to existing
   behavior when it is absent.
5. `repo-end` clears worktree state, retains subject, sets stale flag, and does
   not render a visible stale marker.
6. Claude skill hook emits subject reminder only for brainstorming and
   systematic-debugging when subject is missing or stale.
7. Codex prompt hook emits reminder for explicit brainstorming and
   systematic-debugging prompt text when subject is missing or stale.
8. Existing tests for `tmux-agent-worktree`, `tmux-window-label`,
   `tmux-claude-session-start`, `codex-bind-tmux-pane`, and repo lifecycle keep
   passing.

Manual verification after provisioning:

1. Start a new Claude Code pane and a new Codex pane inside tmux; confirm window
   names identify the agent before `repo-start`.
2. Invoke brainstorming/systematic-debugging and confirm the reminder appears
   when no subject is set.
3. Run `tmux-agent-subject set "test subject"` and confirm the window name
   changes.
4. Run `repo-start <branch>` and confirm repo/worktree context still appears.
5. Run `repo-end` after merge and confirm the subject remains visually
   unchanged.
6. Submit a new prompt and confirm stale-subject reminder appears.

## Rollback

Remove the new helper installation and hook registrations. Keep
`tmux-agent-worktree` compatibility behavior so existing repo-start/repo-end
labeling can fall back to the current `@pane-label` path.
