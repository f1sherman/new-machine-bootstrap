# Ghostty Herdr First Tab Design

## Goal

Make the first tab in each Ghostty app process run Herdr. Make all later tabs
and windows in that Ghostty app process use the existing tmux startup command.
If the Herdr tab exits, the next new tab must start Herdr again.

## Current Behavior

Ghostty runs `tmux-attach-or-new` for each new surface. That helper restores tmux
sessions when necessary, assigns an available session, and attaches the surface.
The separate `herdr-launch` helper starts the pinned Herdr version through mise.
The `herdr-tab` helper can manually create a Ghostty tab that runs Herdr.

The change must preserve the existing tmux helper without adding Herdr-specific
logic to its restore and session-assignment behavior.

## Design

Add a macOS helper named `ghostty-tab-launch`. Configure Ghostty's `command`
setting to run this helper instead of `tmux-attach-or-new` directly.

For each invocation, the helper finds the owning Ghostty app PID by walking its
process ancestors. It uses that PID as the scope for a state marker. Thus, one
Herdr tab applies across all windows owned by the same Ghostty app process.
Different Ghostty app processes have independent state.

The helper takes a short exclusive file lock before it reads or changes state.
If no live Herdr owner exists for the Ghostty PID, the helper records its own PID
as the owner, releases the lock, and runs `herdr-launch` as a child process. The
helper remains alive while Herdr runs. This makes the owner PID a direct liveness
signal and lets the helper remove its marker when Herdr exits.

If a live owner exists, the helper releases the lock and replaces itself with
`tmux-attach-or-new`. This keeps the existing tmux restore, reservation, and
attachment behavior unchanged.

## State and Concurrency

Store the coordination lock and marker files in
`$HOME/.local/state/ghostty-tab-launch`, with user-only directory permissions.
Marker file names include the Ghostty app PID. Each marker contains the launcher
owner PID.

While holding the lock, the helper validates that the marker contains a numeric,
live PID whose process command is `ghostty-tab-launch`. It removes an invalid or
stale marker before it claims Herdr. The lock makes simultaneous new-tab
requests deterministic: exactly one request claims Herdr and all other requests
select tmux.

The Herdr-owning helper installs exit and signal cleanup. Cleanup takes the lock
and removes the marker only if the marker still names that helper. This prevents
an old process from deleting a newer claim.

## Failure Behavior

If the owning Ghostty process cannot be identified, the helper prints a clear
error and exits. It does not use a global marker because that could incorrectly
share Herdr state between Ghostty app processes.

If `herdr-launch` is missing or Herdr fails to start, the helper clears its
marker and returns the failure status. The next new tab can try Herdr again.

If `tmux-attach-or-new` is missing, the later tab reports the normal command
execution failure. Herdr state remains unchanged.

## Deployment

Install `ghostty-tab-launch` through the existing macOS script fileglob. Change
the managed Ghostty `command` line to point to it. Keep `herdr-launch`,
`herdr-tab`, and `tmux-attach-or-new` available for their existing direct uses.

## Verification

Use an isolated temporary state directory and command stubs to verify the
production helper's observable behavior:

- the first invocation selects `herdr-launch`;
- a later invocation with a live Herdr owner selects `tmux-attach-or-new`;
- concurrent invocations produce one Herdr owner;
- a stale marker is reclaimed;
- Herdr exit and startup failure remove the marker;
- separate Ghostty PIDs have separate Herdr ownership.

Run shell syntax checks on the new helper. Run Ansible syntax validation for the
managed Ghostty command. Provision the macOS role, then verify in Ghostty that
the first tab runs Herdr, later tabs attach tmux, and closing Herdr makes the
next new tab run Herdr.

No permanent automated test is planned unless implementation reveals complex
behavior that meets the repository's test-value requirements. The concurrency
and lifecycle checks will execute the production helper through temporary
fixtures during end-to-end verification.
