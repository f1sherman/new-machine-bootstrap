# `cdxr` Codex pane resume command

**Date:** 2026-05-02
**Status:** Approved
**Repo:** `new-machine-bootstrap`

## Goal

Add a short `cdxr` command that resumes the most relevant Codex session for the
current tmux pane using `codex-yolo`.

Brian currently has a `cr` alias for the zsh-only `codex-resume-pane` function,
but `cr` is ambiguous next to Claude commands. `cdxr` should be the Codex
counterpart to `cldr`, and `cr` should be removed.

## Approach

Create a managed executable at `roles/common/files/bin/cdxr`, install it with
the common role, and move the existing `codex-resume-pane` behavior into that
script. The script will:

- resolve the pane's agent worktree path first, then pane current path, then
  `$PWD`;
- prefer a pane-bound Codex session id from tmux options;
- verify pane-bound session cwd and transcript when available;
- clear stale pane-bound session options;
- fall back to the newest Codex session for the resolved cwd;
- run `codex-yolo resume <session-id>` from the resolved cwd.

This keeps current multi-pane/worktree safeguards while making the command a
first-class installed tool like `cldr`.

## Alternatives

- Keep `codex-resume-pane` as a zsh function and alias `cdxr` to it. This is a
  smaller diff, but it does not match `cldr` and only works after interactive
  zsh startup.
- Make `cdxr` only read `@codex_session_id` and otherwise fall back to Codex's
  default latest-session behavior. This is simpler but loses existing cwd and
  stale-session protection.

## Files

| Action | Path | Responsibility |
|---|---|---|
| Create | `roles/common/files/bin/cdxr` | Codex pane resume command. |
| Modify | `roles/common/tasks/main.yml` | Install `cdxr` into `~/.local/bin`. |
| Modify | `roles/common/templates/dotfiles/zshrc.d/50-personal-dev-shell.zsh` | Remove zsh-only resume helpers and `cr` alias. |
| Modify | `tests/codex-resume-pane-shorthand.sh` | Assert `cdxr` behavior and `cr` removal. |

## Testing

Update the existing shell regression to prove:

1. `cdxr` resumes the newest Codex session in the current pane worktree with
   `codex-yolo`.
2. `cdxr` prefers valid pane-bound Codex session metadata.
3. `cdxr` ignores and clears stale pane-bound metadata.
4. `cr` is not defined after sourcing the managed zsh fragment.
5. Provisioning installs `cdxr`.

Run the focused regression and an Ansible check/diff dry run for empirical
verification.
