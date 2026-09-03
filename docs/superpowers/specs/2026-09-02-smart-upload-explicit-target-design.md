# Smart Upload Explicit Target Design

## Status

Self-approved for implementation.

## Goal

Let a local caller upload clipboard files to a known SSH target without relying
on tmux pane process detection. Preserve the current tmux behavior and command
interface.

## Non-goals

- Do not add Herdr-specific logic or inventory identities to NMB.
- Do not change the tmux Option+U binding.
- Do not add directory uploads or transfer progress.

## Assumptions

- The caller owns target selection and supplies a normal OpenSSH target.
- Existing local-path, clipboard-image, Codespace, DevPod, and tmux status
  behavior must remain unchanged when no explicit target is supplied.
- A non-tmux caller needs a way to suppress tmux status messages.

## Approaches

### Recommended: additive command options

Add `--ssh-target TARGET` after the two existing positional arguments to bypass
pane process detection and use the existing SSH upload path. Add
`--quiet-status` after the positional arguments to suppress tmux messages. Keep
the two existing positional arguments valid, including an empty pane TTY and
clipboard text that starts with `-`.

This keeps transfer logic in its current source of truth and gives callers a
small, explicit interface.

### Alternative: synthesize a pane process

A caller could create or inspect a terminal whose process tree contains SSH.
This is brittle and couples upload behavior to terminal implementation details.

### Alternative: duplicate upload behavior in each caller

A Herdr helper could implement its own clipboard image conversion, SSH setup,
and SCP transfer. This would drift from the tmux behavior and is rejected.

## Design

`smart-upload` will preserve its first two arguments as the existing positional
arguments, then parse optional flags only from the remaining arguments. The
supported interface is
`smart-upload <local-path-or-empty> <pane-tty> --ssh-target TARGET --quiet-status`.
When `--ssh-target` is present, it will not inspect `pane-tty`; it will call the
existing SSH upload function with that exact target. When `--quiet-status` is
present, status reporting becomes a no-op while command results and exit
statuses remain unchanged.

The explicit target is passed to `ssh` and `scp` as one argument. It is never
interpolated into a shell command.

## Error handling

Missing option values, missing positional arguments, or an empty explicit target
produce usage failure. Upload failures continue to print the local path and exit
nonzero. Clipboard text that is not a local file continues to pass through.

## Testing and verification

Add a behavioral Ruby test that executes the production script with fake `ssh`,
`scp`, `tmux`, and clipboard commands. It will prove that explicit target mode:

- uploads to the exact supplied target without pane process detection;
- prints the remote path;
- suppresses tmux status calls with `--quiet-status`;
- rejects an empty target; and
- passes through legacy clipboard text that starts with `-` unchanged.

Run the focused test, Ruby syntax validation, and NMB provisioning checks.
