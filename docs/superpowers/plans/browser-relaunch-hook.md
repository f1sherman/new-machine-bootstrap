# Browser Relaunch Hook Implementation Plan

Execution: Native execution in the current session.

Goal: Let local configuration reopen companion applications after a successful scheduled browser relaunch.

Architecture: Add an optional `controller.afterRelaunch(bundleID)` callback. The existing local-init hook registers it on the retained controller. Invoke it only after successful launch; catch and log callback errors so other browsers remain independent.

## Steps

- [x] Extend `tests/browser-update-restart.lua` with callback ordering, skipped callbacks on launch failure/timeout, and callback error isolation. Run `lua tests/browser-update-restart.lua` and confirm the missing-hook failure.
- [x] Add the optional protected callback in `roles/macos/files/hammerspoon/browser_update_restart.lua`. Run all Hammerspoon Lua tests and syntax checks.
- [x] In the private provisioning repository, register a callback in `roles/common/files/hammerspoon/init.local.lua` that launches Google Tasks only for Brave. Verify through the real Hammerspoon runtime; do not add a static-configuration test.
- [x] Run both repositories' `bin/provision` directly. Trigger the restart controller and inspect the browser and companion application's running state and windows. Record observed evidence in the PRs.
- [ ] Review the diffs, commit, push, and create draft PRs. Keep personal app selection out of the generic repository.

Observed verification: The callback ran after a real Brave restart. Both configured companion apps had one window. Chrome kept the same process ID. Both provisioners completed. The URL-source Lua test also fails on unchanged main; all other Lua tests passed. The private provisioner reruns the upstream source, so deploy the upstream hook last when testing unmerged branches.

Reviewer verification: Run `lua tests/browser-update-restart.lua` from this worktree. On the provisioned machine, inspect the registered callback and the running companion app after invoking the retained controller's `runNow()`.
