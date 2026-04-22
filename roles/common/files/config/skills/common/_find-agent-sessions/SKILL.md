---
name: _find-agent-sessions
description: >
  Find recent Claude and Codex sessions updated in a relative duration window.
  Use when the user is recovering after a restart, browsing recent agent work,
  or deciding which session to resume.
---

# Find Agent Sessions

Run `_find-agent-sessions` with the user-provided duration, or no argument for
the default 24h window.

Examples:

```bash
_find-agent-sessions
_find-agent-sessions 4h
_find-agent-sessions today
_find-agent-sessions yesterday
```

Use it as a browsing and triage tool first.

For each result, surface:

1. what the session was working on
2. the last completed step
3. the likely next step
4. the conservative status guess
5. the generated resume command

Do not automatically resume a session just because it appears in the list.

Use the generated resume command only if the user explicitly wants to continue a
specific session. Resume commands must use:

- `codex-yolo` for Codex sessions
- `claude-yolo` for Claude sessions

Keep the status semantics strict:

- `done` only when the session shows PR creation, PR merge, and branch/worktree
  cleanup
- `blocked` when the session is waiting on review, manual work, credentials, or
  another external dependency
- `active` otherwise
