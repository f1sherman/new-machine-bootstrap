# Ghostty Manifest Saving Through tmux Hooks

## Problem

The deterministic Ghostty restore path needs a recent manifest of regular Ghostty tabs and their tmux sessions. The current implementation runs `ghostty-session-manifest-save` every 60 seconds through a user LaunchAgent plist. Some endpoint security software objects to agents editing plist files, even under `~/Library/LaunchAgents`.

Cron is not an acceptable replacement because a cron process does not reliably inherit the logged-in macOS GUI session or Apple Events authorization needed to query Ghostty through AppleScript.

## Goals

- Remove the Ghostty manifest LaunchAgent and its plist from the managed machine.
- Save the manifest in response to tmux client lifecycle events instead of a timer.
- Preserve deterministic Ghostty restart behavior and the last-good manifest safety rules.
- Capture regular-tab additions, removals, session changes, and best-effort selected-tab changes.
- Keep saving asynchronous from tmux's perspective and prevent concurrent saver processes from racing manifest writes.

## Non-Goals

- Replace other unrelated LaunchAgents.
- Guarantee selected-tab capture when macOS or Ghostty emits no terminal focus event.
- Add cron, a persistent debounce daemon, or another scheduler.
- Change the manifest schema or deterministic tab builder.

## Design

### tmux Event Hooks

The macOS tmux configuration will add stable indexed hooks that invoke `ghostty-session-manifest-save` in the background for:

- `client-attached`: capture a newly opened regular tab.
- `client-detached`: capture a closed regular tab when Ghostty still exposes its remaining windows; an empty result during application quit preserves the last-good manifest.
- `client-session-changed`: capture a tab switched to another tmux session.
- `client-focus-in`: capture the currently selected Ghostty tab when terminal focus events are delivered.

Each hook waits 200 milliseconds before invoking the saver so Ghostty's AppleScript window/tab model can settle. The hooks are macOS-only because only `roles/macos/templates/dotfiles/tmux.conf` receives them. They use explicit hook index `95`, avoiding replacement of existing primary hooks and status reconciliation hooks.

### Saver Serialization

`ghostty-session-manifest-save` will acquire a dedicated state-directory lock before querying Ghostty or replacing the manifest. Concurrent hook invocations wait for at most five seconds. Failure to acquire the lock logs a bounded `manifest_rejected` event with `reason=lock_timeout` and exits successfully so manifest maintenance can never disrupt tmux.

Once locked, the existing AppleScript query, candidate validation, exact tmux-session validation, new-process mismatch protection, atomic replacement, and optional diagnostics remain unchanged. Serial execution means a burst of tab events is processed in order; the final queued hook observes the stable final Ghostty state.

Tests may override the lock path with `TMUX_GHOSTTY_MANIFEST_LOCK`. Manual saver invocation uses the same serialization path.

### LaunchAgent Removal

Provisioning will:

1. Stat `~/Library/LaunchAgents/com.user.ghostty-session-manifest-save.plist`.
2. Attempt to unload it when present, without failing provisioning if it is already unloaded.
3. Delete the plist.

The repository plist template will be deleted. The saver executable remains installed because tmux hooks, diagnostics, tests, and manual pre-reboot saves use it.

## Failure Handling

- AppleScript failure, empty Ghostty state, invalid rows, duplicate sessions, missing tmux sessions, and new-process session mismatch continue preserving the last-good manifest.
- Lock timeout preserves the last-good manifest and returns success.
- During full Ghostty quit, `client-detached` hooks may run after windows disappear; the saver produces no candidate and leaves the last-good manifest intact.
- tmux uses background `run-shell` commands, so saving cannot block client attachment, detachment, focus, or session switching.

## Testing

Automated coverage will verify:

- macOS tmux config declares exactly one index-95 manifest saver hook for each required event.
- Hooks include the 200-millisecond settle delay and do not appear in the Linux tmux config.
- Provisioning unloads and removes the old plist rather than installing or loading it.
- The plist template no longer exists.
- Concurrent saver invocations serialize through the configured lock.
- Lock timeout preserves the previous manifest and exits successfully.
- Existing manifest validation and deterministic restore suites remain green.
- CI inventory continues running the manifest contract tests.

## Acceptance

After provisioning:

1. The Ghostty manifest LaunchAgent plist is absent and its launchd job is not loaded.
2. Opening, closing, focusing, and changing the tmux session of regular Ghostty tabs refreshes the manifest without manual invocation.
3. A `Cmd-Q` and reopen reconstructs the intended distinct regular tabs, exhausts the restore queue, and produces no blank or numeric regular tabs.
4. A later full reboot remains the final cold-start acceptance test for the broader deterministic restore feature.
