# Pi Attention Bell Design

## Problem

Pi should make Brian's terminal ask for attention whenever it is waiting for input, including when Pi is running on a remote SSH host inside the same Ghostty tab. The desired behavior is the Codex-like Ghostty bounce/attention signal, not a macOS Notification Center banner.

## Goals

- Emit a terminal-native attention signal whenever Pi needs user input.
- Work across SSH and tmux by writing to the terminal stream.
- Apply globally to every Pi session managed by this bootstrap repo.
- Avoid macOS notification APIs and desktop notification OSC sequences.
- Include end-to-end validation that the signal is emitted for both normal turn completion and extension prompts.

## Non-goals

- Add macOS `osascript`, `display notification`, `terminal-notifier`, `notify-send`, or similar desktop notification integration.
- Add terminal-specific detection for Ghostty. Non-Ghostty terminals may handle or ignore the bell according to their own configuration.
- Modify Pi core as part of this change.

## Research Summary

Ghostty documents the BEL control character (`0x07`, `\a`) as the terminal control for raising user attention. Depending on Ghostty configuration, BEL can produce an app icon bounce, visual flash, sound, focus behavior, or notification. This is the best fit for “bounce without Notification Center.”

Codex has a similar split between turn-completion hooks and terminal notifications. Its terminal notification path can use `bel`, and community guidance recommends that path for approval/wait states because it is terminal-native and survives SSH/tmux better than desktop hooks.

Pi's public extension API exposes lifecycle events such as `agent_end`, but no first-class “awaiting input,” “dialog opened,” or “attention needed” event. Extension prompts are shown directly through `ctx.ui.select`, `ctx.ui.confirm`, `ctx.ui.input`, `ctx.ui.editor`, and `ctx.ui.custom`.

## Recommended Approach

Implement a small global Pi extension managed by NMB and deployed into `~/.pi/agent/extensions/`.

The extension emits BEL (`\x07`) at two kinds of attention points:

1. `agent_end`, for the normal state where an agent turn has finished and Pi is waiting at the editor.
2. Calls to input-blocking `ctx.ui` methods, for extension dialogs and custom UI that wait for keyboard input.

Wrapping the UI methods is not ideal, but it is the least invasive extension-only option available today. It is limited to Pi's documented extension UI surface and should be written to be idempotent and fail-open. If Pi later adds a first-class awaiting-input event, this extension should switch to that event and remove the wrapper.

## Alternatives Considered

### Agent-end only

Use Pi's documented `agent_end` event and emit BEL there.

- Pros: simple and idiomatic.
- Cons: misses extension confirmations, selectors, inputs, editors, and custom UI prompts.

Rejected because Brian wants attention whenever Pi awaits input, not only after assistant turns.

### Desktop notification hook

Use OSC 9/777, `osascript`, `notify-send`, or another desktop notification path.

- Pros: visible and familiar.
- Cons: not the requested behavior; may create Notification Center banners; less terminal-native over SSH/tmux.

Rejected because the desired behavior is Ghostty/Codex-style bounce/attention, not desktop toasts.

### Terminal/tmux heuristic watcher

Watch Pi/tmux output or process state and ring when Pi appears idle.

- Pros: avoids touching Pi extension UI objects.
- Cons: brittle, hard to test, and likely to misfire.

Rejected in favor of using Pi's extension API surface.

## Runtime Design

Create a global extension named `pi-attention-bell.ts`.

The extension should:

- Define `requestAttention()` that writes `\x07` to the terminal stream.
- Prefer a direct write to `process.stdout`, because the signal must travel through SSH/tmux to the attached terminal.
- Skip the write when stdout is not a TTY so non-interactive `pi --print` output remains machine-readable.
- Register `pi.on("agent_end", ...)` and call `requestAttention()`.
- On `session_start`, wrap the current shared `ctx.ui` methods:
  - `select`
  - `confirm`
  - `input`
  - `editor`
  - `custom`
- Each wrapper calls `requestAttention()` once immediately before delegating to the original method.
- Mark the UI object with a private symbol or property so wrapping is idempotent across reloads/session starts.
- Catch and ignore wrapper setup errors so Pi remains usable if the UI object changes.

The extension should not emit OSC 9, OSC 777, or run platform notification commands.

## Provisioning Design

NMB owns the source. Do not edit deployed files in `~/.pi/agent/extensions/` directly.

Implementation should add the extension source at:

```text
roles/common/files/pi/extensions/pi-attention-bell.ts
```

and add or extend an Ansible task to install it into:

```text
~/.pi/agent/extensions/pi-attention-bell.ts
```

This should be part of the shared common role so it applies to macOS and Linux dev hosts where Pi is provisioned.

If Ghostty does not bounce after deployment, the next fix should be Ghostty configuration such as `bell-features`, not changing Pi to emit desktop notifications.

## Testing Design

Add both static/provisioning coverage and end-to-end coverage.

### Static/provisioning test

Add a CI-safe NMB test that verifies:

- the extension is part of the managed Pi extension set,
- the extension emits BEL (`\x07`), and
- the extension does not contain desktop notification commands or OSC notification sequences such as OSC 9 or OSC 777.

This catches accidental drift toward Notification Center or desktop-toaster implementations.

### End-to-end test

Add an E2E test that runs Pi with the extension in a pseudo-terminal and captures raw terminal output.

The test should cover:

1. **Agent turn completion**: run a minimal Pi turn with the extension loaded and assert the captured output contains `\x07` after the agent finishes.
2. **Extension prompt coverage**: load a tiny temporary test extension/command that calls one blocking UI method such as `ctx.ui.confirm` or `ctx.ui.input`, invoke that command in TUI mode, and assert the captured output contains `\x07` while the prompt is displayed.

If the full TUI interaction is too brittle for normal CI, keep the E2E test in an explicit local/manual lane, but implement it as an executable test and run it before the PR. The PR description should state the exact command and result.

## Error Handling

The attention feature must never break Pi interaction.

- If stdout is not attached to a TTY, skip BEL.
- If writing BEL fails, ignore the error.
- If UI wrapping fails, leave Pi unmodified and continue.
- If a method has already been wrapped, do not wrap it again.
- If Pi's UI API changes, the failure mode should be “no bell,” not “Pi cannot prompt.”

## Rollout

1. Add and test the extension in an NMB worktree.
2. Run the static/provisioning test and the E2E test locally.
3. Open a PR from the feature branch.
4. After merge, provision the relevant local/dev hosts with `bin/provision`.
5. If the Ghostty tab does not bounce, inspect Ghostty `bell-features` configuration.

## Open Questions

None. The design intentionally uses BEL as the attention primitive and accepts the contained UI-method wrapper until Pi exposes a better hook.
