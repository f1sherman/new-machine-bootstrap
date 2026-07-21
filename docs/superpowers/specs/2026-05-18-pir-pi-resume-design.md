# pir — resume last Pi session

## Goal

Add a `pir` command mirroring `cldr` (Claude) and `cdxr` (Codex) that resumes
the most recent Pi session for the current directory.

Multiple Pi sessions often run from the same directory, so `pi --continue`
alone would resume the wrong session. Like `cldr`, `pir` binds each tmux pane
to its Pi session.

## Design

- `roles/common/files/pi/extensions/managed-hooks.ts`: on `session_start`
  (startup, `/new`, `/resume`, fork), set the pane option
  `@persist_pi_session_file` to `ctx.sessionManager.getSessionFile()`.
  Guarded by `process.stdout.isTTY` so nested / non-interactive pi
  invocations (subagent children, `pi -p`) that inherit `TMUX_PANE` do not
  clobber the pane binding — analogous to `tmux-claude-session-start`'s
  nested-hook guard. Ephemeral sessions (`--no-session`) are skipped.
- `roles/common/files/bin/pir`: reads `@persist_pi_session_file`; when set
  and the file exists, `exec pi --session <file>`. Otherwise falls back to
  `pi --continue` (most recent session in cwd), same as `cldr`'s fallback.
- `roles/common/files/bin/tmux-restore-handler-pi_session_file`: after a
  tmux-resurrect restore, relaunches `pi --session <file>` in the restored
  pane. The `@persist_` prefix means tmux-resurrect-save-extra captures the
  option automatically; the handler mirrors
  `tmux-restore-handler-claude_session_id`.
- Deployed via the common role (`Install pir script` task + scripts list)
  to `~/.local/bin`, same pattern as `cldr`/`cdxr`.

## Out of scope

- Worktree cwd resolution (cdxr-style); the pane binding covers the
  multi-session-per-directory case and `pi --continue` covers the rest.
