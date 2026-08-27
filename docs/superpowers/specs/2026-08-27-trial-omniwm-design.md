# Trial OmniWM on Brian's MacBook Pro

**Status:** Self-approved

## Goal

Install a Renovate-managed OmniWM release on Brian's current MacBook Pro and
launch it at login. Keep the trial isolated from other managed machines.

## Non-goals

- Do not install OmniWM on other macOS or Linux hosts.
- Do not configure OmniWM behavior or key bindings.
- Do not remove, disable, or reconfigure Rectangle.
- Do not generalize host selection until the trial is successful.

## Assumptions

- The target host reports `ansible_hostname` as `brian-macbook-pro`.
- The target is Apple Silicon and runs macOS 26 or later, as OmniWM requires.
- Brian will grant Accessibility permission when macOS requests it.
- Launching OmniWM during provisioning is acceptable because it starts the
  trial and permits the required macOS approval flow.

## Recommended approach

Pin the OmniWM GitHub release in `vars/tool_versions.yml` with a Renovate
`github-releases` annotation. Add a focused macOS task file that downloads the
matching signed release ZIP, installs `OmniWM.app` in `/Applications`, and
links `omniwmctl` into `~/.local/bin`. Include that task file only when
`ansible_hostname == 'brian-macbook-pro'`.

Install a per-user LaunchAgent with `RunAtLoad` enabled. Load it in the current
GUI session so OmniWM starts now and at later logins. Use the app executable
inside the installed bundle. Do not use UI automation to toggle OmniWM's own
`SMAppService` setting because that interface requires interaction inside the
application.

## Alternatives considered

1. **Homebrew tap and cask.** This is the upstream convenience path, but the
   repository would not control the selected version directly. Renovate could
   not update the installed version pin in `vars/tool_versions.yml`.
2. **OmniWM's Start at Login toggle.** This uses `SMAppService.mainApp` and is
   the native user-facing path, but Ansible cannot invoke it from outside the
   app without fragile UI automation.
3. **System Events login item.** This is shorter than a LaunchAgent, but it uses
   an older login-item interface and is harder to inspect and manage
   declaratively.

## Components

- `vars/tool_versions.yml`: owns the OmniWM release pin and Renovate metadata.
- `roles/macos/tasks/install_omniwm.yml`: owns download, installation, CLI
  linking, and LaunchAgent lifecycle.
- `roles/macos/templates/launchd/com.user.omniwm.plist`: defines login launch.
- `roles/macos/tasks/main.yml`: applies the trial task only to the exact host.

## Error handling

Provisioning must fail if the pinned asset cannot download, the application
cannot install, or the LaunchAgent cannot load. Existing GitHub download retry
behavior remains in use. The host condition prevents unsupported machines from
reaching these tasks.

## Verification

No automated test is added. A static configuration test would not meet this
repository's material-value test gate. Verify with:

1. Ansible syntax checking.
2. Renovate configuration validation.
3. `bin/provision` on `brian-macbook-pro`.
4. Confirm `/Applications/OmniWM.app` exists and has the pinned version.
5. Confirm `~/.local/bin/omniwmctl` resolves to the app bundle command.
6. Confirm the LaunchAgent is loaded in the current GUI domain.
7. Confirm the OmniWM process starts.

## Rollout

This PR is intentionally limited to `brian-macbook-pro`. A later change can
replace the exact hostname condition with a normal macOS-wide setting after the
trial succeeds.
