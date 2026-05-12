# SessionStart worktree reminder resume gate - Design

## Goal

Prevent the worktree rebinding reminder from appearing when Claude Code or
Codex starts a brand-new session. The reminder should be emitted only for an
actual SessionStart resume, and only when the tmux pane has no
`@agent_worktree_path`.

The specific user-facing symptom is the injected hook context:

```text
You are resuming a session in a tmux pane that has no active worktree bound to it...
```

That text is useful when continuing an old session in a fresh pane. It is noise
on a new session.

## Non-goals

- Do not remove the SessionStart hooks themselves.
- Do not stop startup-time session-id binding. `cldr` depends on
  `@persist_claude_session_id`; `cdxr` depends on `@codex_session_id`,
  `@codex_session_cwd`, and `@codex_session_transcript`.
- Do not stop the label refresh on startup. It is idempotent and keeps the
  window label pipeline consistent.
- Do not add persistent session-to-worktree state.
- Do not change `tmux-agent-worktree`, `repo-start`, `repo-end`, `cldr`, or
  `cdxr`.

## Assumptions

- The user objection is to the visible injected worktree reminder on startup,
  not to the invisible pane-state binding that the same SessionStart hook also
  performs.
- Claude and Codex both provide a `source` field for SessionStart payloads.
  Existing Claude code already parses `source`. Official Codex hook docs say
  SessionStart exposes `source` and that the matcher is applied to that source:
  <https://developers.openai.com/codex/hooks#sessionstart>.
- A missing or unknown `source` should not emit the reminder. This favors no
  false positives on startup over trying to support old ambiguous payloads.
- `/clear` and `/compact` are not resume events for this feature. They may keep
  the existing session-id binding behavior, but they should not inject the
  worktree reminder.
- Same-pane resumes with `@agent_worktree_path` already set should still emit no
  reminder.

## Recommended approach

Gate only the reminder path inside the two existing hook scripts:

- `roles/common/files/bin/tmux-claude-session-start`
- `roles/common/files/bin/codex-bind-tmux-pane`

The hook scripts should continue to parse payloads, write pane session metadata,
and refresh labels as they do today. The only behavioral change is the final
additionalContext block:

```bash
if [ "$source" = "resume" ]; then
  worktree_path="$(tmux show-options -pqv -t "$TMUX_PANE" @agent_worktree_path 2>/dev/null || true)"
  if [ -z "$worktree_path" ]; then
    emit_worktree_rebind_reminder
  fi
fi
```

For Codex, `codex-bind-tmux-pane` should start parsing:

```bash
source="$(printf '%s' "$payload" | jq -r '.source // empty' 2>/dev/null || true)"
```

For Claude, reuse the existing `source` variable already parsed near the nested
startup guard.

### Why this approach

- It fixes the false positive without weakening startup session binding.
- It keeps the previous cross-pane resume recovery path intact.
- It follows the documented Codex hook contract instead of inferring resume from
  cwd, transcript path, or tmux state.
- It is a narrow change in two small scripts plus their tests.
- It avoids adding a second hook entry whose ordering and duplicate output would
  need its own tests.

## Alternatives considered

### Alternative A - change Codex matcher to `resume`

Update the managed Codex hook entry in `roles/common/tasks/main.yml` from
`startup|resume` to `resume`.

Rejected. That would stop `codex-bind-tmux-pane` from recording new Codex
session metadata on startup. `cdxr` would lose exact pane-bound session resume
for fresh sessions unless another startup hook replaced that responsibility.

### Alternative B - split reminder into a separate resume-only hook

Keep `codex-bind-tmux-pane` and `tmux-claude-session-start` for metadata, then
add a new `tmux-agent-worktree-resume-reminder` hook registered only for resume.

Rejected for this slice. It adds a script, ansible registration logic, and hook
ordering surface area for behavior that can be expressed as a small conditional
inside the current scripts.

### Alternative C - derive resume from existing pane options

Treat absence of an existing pane session id as startup and presence as resume.

Rejected. Cross-pane resume is exactly the case where the new pane often has no
session id or worktree option yet. Source-based gating is the only reliable
signal available in the hook payload.

## Component boundaries

### `tmux-claude-session-start`

Responsibilities that stay:

- Validate `TMUX_PANE`, `jq`, `tmux`, and payload shape.
- Parse and store `session_id`.
- Preserve the existing nested-startup guard so nested `claude -p` calls do not
  overwrite the outer pane's session id.
- Refresh `@pane-label` and window name after successful binding.

New boundary:

- The worktree reminder block runs only when `source == resume`.

### `codex-bind-tmux-pane`

Responsibilities that stay:

- Validate `TMUX`, `TMUX_PANE`, `jq`, `tmux`, `session_id`, and `cwd`.
- Store `@codex_session_id`, `@codex_session_cwd`, and
  `@codex_session_transcript`.
- Refresh `@pane-label` and window name after successful binding.

New boundary:

- Parse `source`.
- The worktree reminder block runs only when `source == resume`.

### `roles/common/tasks/main.yml`

No recommended change. The managed Codex hook entry remains
`matcher: "startup|resume"` because the script still has useful startup work.

## Data flow

```text
SessionStart payload
  |
  |-- startup
  |     hook binds pane session metadata
  |     hook refreshes label
  |     hook emits no worktree reminder
  |
  |-- resume
        hook binds pane session metadata
        hook refreshes label
        if @agent_worktree_path is missing:
          hook emits additionalContext reminder
```

Missing, empty, `clear`, `compact`, or unknown `source` values follow the
startup branch for the reminder decision: metadata behavior remains whatever
the script already supports, but no worktree reminder is emitted.

## Error handling

- Bad JSON or missing required fields should keep the current early-exit
  behavior.
- `jq` failure while parsing `source` should produce an empty source and suppress
  the reminder.
- If `tmux show-options` fails on resume, treat the worktree path as missing and
  emit the reminder. That matches current behavior for a pane without state.
- Reminder JSON emission should still be best-effort with `jq -n ... || true`.

## Testing and verification plan

Update the existing shell tests instead of adding a new harness:

- `tests/tmux-claude-session-start.sh`
- `tests/codex-bind-tmux-pane.sh`

Required regression cases:

1. Startup with no `@agent_worktree_path` binds metadata, refreshes labels, and
   emits no stdout.
2. Resume with no `@agent_worktree_path` emits SessionStart
   `hookSpecificOutput.additionalContext` mentioning `tmux-agent-worktree set`.
3. Resume with `@agent_worktree_path` set emits no stdout.
4. Missing or empty source with no `@agent_worktree_path` emits no stdout.
5. Claude nested startup with an existing outer session id still bails before
   label refresh or reminder output.

Verification commands:

```bash
bash tests/tmux-claude-session-start.sh
bash tests/codex-bind-tmux-pane.sh
bash tests/ci-test-inventory.sh
```

If implementation touches `roles/common/tasks/main.yml` despite this design,
also run:

```bash
ansible-playbook playbook.yml --check
```

## Rollout

Single small implementation branch. No migration is needed. Existing deployed
hooks will update on the next `bin/provision`.

Expected visible behavior:

- Brand-new Codex or Claude sessions no longer receive the worktree rebinding
  reminder.
- Cross-pane resumes still receive the reminder when the new pane lacks active
  worktree state.
- Same-pane resumes remain quiet because `@agent_worktree_path` is already set.
