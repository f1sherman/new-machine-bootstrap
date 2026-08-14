# Restore SSH tmux Outside Herdr

**Status:** Self-approved

## Goal

Restore automatic tmux attachment for interactive SSH logins on Linux development
hosts. Do not start nested tmux inside a Herdr-managed pane.

## Non-goals

- Change tmux session selection or restoration behavior.
- Change Herdr startup, provisioning, or remote mirroring.
- Start tmux for non-interactive SSH commands or local console shells.

## Assumptions

- Herdr-managed panes set the explicit `HERDR_ENV=1` marker.
- `tmux-attach-or-new` remains the owned helper for session restoration and
  attachment.
- The `dev_host` role owns the Linux development-host `.zprofile` block.

## Approaches

### Recommended: explicit Herdr environment guard

Restore the managed `.zprofile` block. Start `tmux-attach-or-new` only when the
shell is an interactive SSH login, is not already in tmux, is not a tmux startup
fallback, and does not have `HERDR_ENV=1`.

This uses Herdr's explicit pane marker. It is direct and follows the repository
rule to prefer one explicit marker over inference.

### Alternative: process ancestry detection

Inspect parent processes for Herdr. This is fragile because Herdr can change its
process structure and intermediate shells can hide ancestry.

### Alternative: custom suppression marker

Change every Herdr launcher to set a new variable. This duplicates the existing
`HERDR_ENV` contract and risks missing entry paths.

## Design

The `roles/dev_host/tasks/main.yml` task will configure the tmux auto-launch
block instead of removing it. The condition will require all of these states:

- `TMUX` is empty.
- `TMUX_ATTACH_FALLBACK` is empty.
- `HERDR_ENV` is not `1`.
- `SSH_CONNECTION` is set.
- Standard input is a terminal.

When all conditions are true, the shell replaces itself with
`~/.local/bin/tmux-attach-or-new`. Otherwise, normal shell startup continues.
The role documentation will again describe automatic tmux attachment, with the
Herdr exception.

## Error handling

The existing helper owns tmux startup failures and fallback-shell behavior. The
profile condition adds no new fallback or compatibility inference.

## Testing and verification

A retained automated test is not justified by the repository's material-value
gates. This is a small shell preference whose failure is immediate and easy to
diagnose. Verification will instead execute the production behavior:

1. Run Ansible syntax validation for the worktree.
2. Provision the Linux development host from the worktree.
3. Confirm a plain interactive SSH login enters tmux.
4. Confirm a forced interactive login with `HERDR_ENV=1` stays outside tmux.
5. Confirm a non-interactive SSH command stays outside tmux.
6. Run provisioning a second time and require no unexpected changes.

## Rollout

Provision the `dev` host after the pull request branch is ready. Existing SSH
sessions and tmux sessions remain unchanged. New logins use the restored rule.
