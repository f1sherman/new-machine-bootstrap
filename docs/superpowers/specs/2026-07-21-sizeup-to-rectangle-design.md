# SizeUp to Rectangle Migration Design

## Goal

Replace the managed SizeUp installation with Rectangle while preserving the
window-management shortcuts currently used on this Mac. Provisioning must remove
SizeUp and its preferences, configure Rectangle reproducibly, and leave repeated
half-screen commands at exactly one half instead of cycling through other sizes.

## Managed behavior

Rectangle will use these SizeUp-compatible shortcuts:

| Action | Shortcut | Key code | Modifier flags |
| --- | --- | ---: | ---: |
| Left half | Control-Option-Command-Left | 123 | 1835008 |
| Right half | Control-Option-Command-Right | 124 | 1835008 |
| Top half | Control-Option-Command-Up | 126 | 1835008 |
| Bottom half | Control-Option-Command-Down | 125 | 1835008 |
| Maximize | Control-Option-Command-M | 46 | 1835008 |
| Previous display | Control-Option-Left | 123 | 786432 |
| Next display | Control-Option-Right | 124 | 786432 |

Rectangle will start at login. Its `subsequentExecutionMode` will be `2`, which
disables repeated-command cycling and matches SizeUp's stable half-screen
behavior.

## Provisioning changes

The macOS role will:

1. Stop SizeUp, remove the `sizeup` Homebrew cask when present, and remove an
   unmanaged `/Applications/SizeUp.app` left by an installation outside Homebrew.
2. Install the `rectangle` Homebrew cask, accepting an existing unmanaged
   `/Applications/Rectangle.app` as satisfying the install.
3. Check Rectangle's `alternateDefaultShortcuts` onboarding marker. If it is
   absent, launch Rectangle and wait up to 120 seconds for the user to grant
   Accessibility access and complete the welcome dialog by choosing a default
   shortcut set.
4. Delete the `com.irradiatedsoftware.SizeUp` defaults domain when present.
5. Write Rectangle's scalar settings to `com.knollsoft.Rectangle`.
6. Write shortcut dictionaries for `leftHalf`, `rightHalf`, `topHalf`,
   `bottomHalf`, `maximize`, `previousDisplay`, and `nextDisplay` using the
   key codes and modifier flags above.
7. Stop and relaunch Rectangle after SizeUp preference cleanup so its runtime
   bindings and native login registration match the managed defaults.

The SizeUp cleanup remains an idempotent provisioning task so machines that have
not provisioned recently are migrated when they next run the playbook. Missing
SizeUp preferences are treated as already clean rather than as an error.
Existing onboarded Rectangle installations skip the onboarding launch and wait.
On fresh installations, provisioning waits for the explicit onboarding marker
before the managed defaults overwrite the welcome dialog's execution mode and
shortcuts. Every provisioning run then restarts Rectangle after writing settings,
which applies the exact shortcuts and `subsequentExecutionMode = 2` at runtime
and lets `launchOnLogin = true` reconcile Rectangle's native login item.

## Verification

A focused contract test will inspect the macOS role files and assert:

- Rectangle installation tolerates an unmanaged app and both managed and
  unmanaged SizeUp installations are explicitly removed.
- Fresh Rectangle installations complete marker-driven onboarding before the
  aggregate cask and managed-defaults tasks; onboarded installations skip it.
- All seven shortcut actions have the expected key codes and modifiers.
- Rectangle starts at login and repeated-command cycling is disabled.
- The obsolete SizeUp defaults domain is deleted.
- Rectangle is stopped after shortcut writing and SizeUp preference cleanup,
  then relaunched with managed settings.
- The old SizeUp defaults are no longer present in the managed defaults list.

Run the focused test, the CI test inventory, Ansible syntax checking, and local
macOS provisioning. During a fresh install, grant Rectangle Accessibility
access and complete its welcome dialog within the 120-second wait. After
provisioning, verify the Rectangle defaults domain, confirm SizeUp is absent and
Rectangle is installed, then exercise each shortcut against a normal application
window. Accessibility authorization remains a manual one-time action because it
is controlled by macOS and is not safely provisioned here.
