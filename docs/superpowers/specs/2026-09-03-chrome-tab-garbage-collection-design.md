# Chrome Tab Garbage Collection Design

**Status:** Self-approved

## Goal

Reduce Chrome CPU and memory use on Brian's MacBook Pro by closing abandoned
ChatGPT browsing tabs. Chrome is dedicated to ChatGPT work on this laptop.

An unpinned tab becomes eligible for cleanup after it has not been active for
60 minutes. Active and pinned tabs must be preserved.

## Non-goals

- Manage tabs in Brave, Safari, or other browsers.
- Determine which ChatGPT task opened a tab.
- Synchronize cleanup state between machines.
- Publish an extension to the Chrome Web Store.
- Replace Chrome Memory Saver.

## Assumptions

- All Chrome tabs on this laptop are disposable ChatGPT work unless pinned.
- One-time manual activation of a local unpacked extension is acceptable because
  Chrome does not support silent local extension installation for an unmanaged
  macOS profile.
- A one-minute cleanup interval is sufficient.
- Sleep does not count against the idle limit. The extension grants a fresh
  60-minute grace period after Chrome starts or wakes.
- Activity means selection as the active tab in any Chrome window. Activity that
  begins and ends between Chrome events is still reported by Chrome's
  `lastAccessed` tab property.

## Approaches Considered

### Chrome extension using `chrome.tabs` (recommended)

A Manifest V3 extension uses Chrome's supported `Tab.id`, `Tab.active`,
`Tab.pinned`, and `Tab.lastAccessed` properties. It receives activation and pin
change events without depending on localized browser UI.

This has the strongest safety boundary. Its cost is a one-time manual
"Load unpacked" action because the extension will not be published.

### Hammerspoon with Chrome AppleScript

This matches the existing macOS automation runtime and needs no Chrome
extension. It is rejected because Chrome 152's scripting dictionary does not
expose pinned state. Inferring pinned state from tab position or accessibility
UI would risk closing protected tabs.

### ChatGPT instructions or Chrome Memory Saver

Instructions are best-effort and cannot recover from interrupted tasks. Memory
Saver reduces memory use but intentionally leaves stale tabs open. Neither
satisfies the requested cleanup behavior.

## Architecture

The extension source will live under
`roles/macos/files/chrome-tab-gc-extension/`. The existing laptop-only OmniWM
installation task will copy it to
`~/.local/share/chrome-tab-gc-extension/`. That task is included only when
Ansible reports the host name `Brians-MacBook-Pro`, so other hosts do not install
or enable the extension.

The extension contains:

- A minimal Manifest V3 manifest with `tabs`, `alarms`, and `storage`
  permissions.
- A service worker that starts the controller.
- A controller module with injected Chrome API and clock boundaries so tests
  execute the production state machine.

The controller stores temporary grace timestamps in `chrome.storage.session`.
This storage survives service-worker suspension but clears when Chrome exits.
No browser history or URLs are stored.

## Behavior and Data Flow

1. Extension startup creates a one-minute repeating alarm and records a browser
   grace timestamp if none exists.
2. Tab activation records a per-tab activity timestamp.
3. A transition from pinned to unpinned records a new per-tab grace timestamp.
4. Each alarm compares the current time with the prior sweep time. A gap longer
   than two cleanup intervals is treated as sleep or suspension and records a
   new browser grace timestamp.
5. Each alarm queries all Chrome tabs.
6. The controller computes each tab's effective activity time as the newest of:
   Chrome's `lastAccessed`, the browser grace timestamp, the recorded activation
   timestamp, and the unpin grace timestamp.
7. A tab is eligible only when it is unpinned, inactive, and its effective
   activity time is at least 60 minutes old.
8. Immediately before removal, the controller reads the tab again by stable ID
   and repeats the active, pinned, and age checks. It never closes by tab index.
9. Successfully removed or disappeared tab IDs are removed from session state.

Chrome does not offer an atomic "recheck and remove" API. The immediate
`tabs.get` recheck minimizes the remaining race. Any missing or changed tab
fails open.

## Error Handling

- A failed tab enumeration closes nothing during that pass.
- A failed state read closes nothing during that pass.
- A failed final tab read or removal affects only that candidate.
- Expected disappearance errors are ignored.
- Other errors are written to the extension service-worker console.
- The next alarm retries without notifications or retry loops.
- Clock rollback grants more time instead of causing early closure.

## Installation and Rollout

Provisioning copies the extension only on Brian's MacBook Pro. Initial
activation is one manual action:

1. Open `chrome://extensions`.
2. Enable Developer mode.
3. Select **Load unpacked**.
4. Choose `~/.local/share/chrome-tab-gc-extension`.

Chrome remembers the unpacked extension. Later provisioning updates the files;
Chrome's extension reload control applies an update immediately when needed.
Removing or disabling the extension stops cleanup without changing tabs.

## Testing

Automated tests are justified because a regression could destroy active user
state, the policy has meaningful time and event state, and provisioning alone
cannot verify the destructive boundary.

Node tests will load the production controller with a fake Chrome API and cover:

- first observation and browser startup grace;
- the exact 60-minute threshold;
- active and pinned protection;
- action-time revalidation;
- activation and unpin grace;
- removed and reordered tabs;
- multiple windows;
- enumeration, storage, and removal failures;
- delayed-alarm wake grace and clock rollback.

The integration workflow will run the new test explicitly. Local verification
will also validate the manifest, run the complete relevant Lua tests, run
Ansible syntax/check provisioning, and load the extension on the target laptop
for a non-destructive smoke test before the pull request.
