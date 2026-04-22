---
name: _recover-agent-sessions
description: >
  Find recent Claude and Codex sessions updated in a relative duration window.
  Use when the user is recovering after a restart, browsing recent agent work,
  or deciding which session to resume.
---

# Recover Agent Sessions

Run `_recover-agent-sessions` with the user-provided duration, or no argument for
the default 24h window.

Examples:

```bash
_recover-agent-sessions
_recover-agent-sessions 4h
_recover-agent-sessions today
_recover-agent-sessions yesterday
```

Use it as a browsing and triage tool first.

The human-readable output prints grouped YAML-like blocks with `session`,
`location`, `work`, and `resume` sections so multiple sessions stay readable.

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
