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
- The existing macOS-wide default `com.apple.spaces spans-displays=false`
  enables **Displays have separate Spaces** and satisfies OmniWM's Mission
  Control prerequisite.
- Launching OmniWM during provisioning is acceptable because it starts the
  trial and permits the required macOS approval flow.

## Recommended approach

Pin the OmniWM GitHub release in `vars/tool_versions.yml` with a Renovate
`github-releases` annotation. Add a focused macOS task file that downloads the
matching signed release ZIP, extracts it with macOS `/usr/bin/ditto -x -k`,
verifies the staged bundle with `codesign --verify --deep --strict`, installs
`OmniWM.app` in `/Applications`, and links `omniwmctl` into `~/.local/bin`.
Include that task file only when `ansible_hostname == 'brian-macbook-pro'`.

Install a per-user LaunchAgent with `RunAtLoad` enabled. Load it in the current
GUI session so OmniWM starts now and at later logins. Before an app upgrade,
inspect the loaded job and stop it only after the staged replacement passes all
validation. This prevents an interrupted provision from leaving the old process
running against a new bundle. A later provision sees the absent job and loads it
after the app, CLI link, and plist are ready. Use the app executable inside the
installed bundle. Do not use UI automation to toggle OmniWM's own
`SMAppService` setting because that interface requires interaction inside the
application.

The installed-version and launchd-status probes must execute in Ansible check
mode because they do not mutate state. If the app is absent or outdated, check
mode reports a pending change but skips staging, download, extraction,
replacement, and launchd mutations.

Keep the existing **Displays have separate Spaces** management unchanged.
`roles/macos/vars/defaults.yml` already declares
`com.apple.spaces spans-displays=false`, and `roles/macos/tasks/defaults.yml`
applies it to all managed macOS hosts. Do not add a duplicate OmniWM-specific
setting or narrow its existing macOS-wide scope.

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
4. **Ansible `unarchive`.** Its macOS ZIP extraction materializes AppleDouble
   `._*` entries as sealed resources inside the signed app. This invalidates
   the strict code signature. macOS `ditto -x -k` preserves the release bundle
   without those files.

## Components

- `vars/tool_versions.yml`: owns the OmniWM release pin and Renovate metadata.
- `roles/macos/tasks/install_omniwm.yml`: owns download, installation, CLI
  linking, and LaunchAgent lifecycle.
- `roles/macos/templates/launchd/com.user.omniwm.plist`: defines login launch.
- `roles/macos/tasks/main.yml`: applies the trial task only to the exact host.
- Existing `roles/macos/vars/defaults.yml` and
  `roles/macos/tasks/defaults.yml`: continue to manage the macOS-wide Mission
  Control prerequisite without changes.

## Error handling

Provisioning must fail if the pinned asset cannot download, `ditto` cannot
extract it, the staged app fails strict code-signature verification, the
application cannot install, or the LaunchAgent cannot load. The existing app
and process must remain in place until extraction and signature verification
both pass. A loaded process is then stopped before app replacement. If a later
task fails, the next provision observes the absent job and loads it after all
prerequisites succeed. Existing GitHub download retry behavior remains in use.
Check mode must not create staging state or mutate launchd. The host condition
prevents unsupported machines from reaching these tasks.

## Verification

No automated test is added. A static configuration test would not meet this
repository's material-value test gate. Verify with:

1. Ansible syntax checking.
2. Renovate configuration validation.
3. A focused repo-local extraction test that uses `/usr/bin/ditto -x -k`,
   confirms no `._*` files exist, and passes
   `codesign --verify --deep --strict` on the staged app.
4. A focused check-mode run with an intentionally different pinned version.
   Confirm it reports a pending change without entering staging, download,
   extraction, app replacement, or launchd mutation tasks.
5. A lifecycle truth-table check for first install, app update, plist update,
   unchanged state, and recovery after interruption.
6. `bin/provision` on `brian-macbook-pro`.
7. Confirm `/Applications/OmniWM.app` exists and has the pinned version.
8. Confirm `~/.local/bin/omniwmctl` resolves to the app bundle command.
9. Confirm the LaunchAgent is loaded in the current GUI domain.
10. Confirm the OmniWM process starts.
11. Run `defaults read com.apple.spaces spans-displays` and confirm it returns
   `0`, which means **Displays have separate Spaces** is enabled.

## Rollout

This PR is intentionally limited to `brian-macbook-pro`. A later change can
replace the exact hostname condition with a normal macOS-wide setting after the
trial succeeds.
