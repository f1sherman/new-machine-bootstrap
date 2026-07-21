# pir — resume last Pi session

## Goal

Add a `pir` command mirroring `cldr` (Claude) and `cdxr` (Codex) that resumes
the most recent Pi session for the current directory.

## Design

- `roles/common/files/bin/pir`: thin bash wrapper, `exec pi --continue "$@"`.
  Pi's `--continue` flag resumes the previous session scoped to the project
  directory, so no session-id lookup is needed.
- Unlike `cldr`/`cdxr`, there is no tmux pane session binding for Pi yet, so
  `pir` has no pane-option branch. If Pi pane binding lands later, `pir` can
  grow a `--session <id>` path the same way `cldr` uses
  `@persist_claude_session_id`.
- Deployed via the common role (`Install pir script` task) to
  `~/.local/bin/pir`, same pattern as `cldr`/`cdxr`.

## Out of scope

- tmux pane binding / session-id persistence for Pi.
- Worktree cwd resolution (cdxr-style); `pi --continue` already keys off cwd.
