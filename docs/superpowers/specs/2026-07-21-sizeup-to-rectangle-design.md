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

1. Remove the `sizeup` Homebrew cask when present.
2. Install the `rectangle` Homebrew cask with the other managed applications.
3. Delete the `com.irradiatedsoftware.SizeUp` defaults domain when present.
4. Write Rectangle's scalar settings to `com.knollsoft.Rectangle`.
5. Write shortcut dictionaries for `leftHalf`, `rightHalf`, `topHalf`,
   `bottomHalf`, `maximize`, `previousDisplay`, and `nextDisplay` using the
   key codes and modifier flags above.

The SizeUp cleanup remains an idempotent provisioning task so machines that have
not provisioned recently are migrated when they next run the playbook. Missing
SizeUp preferences are treated as already clean rather than as an error.

## Verification

A focused contract test will inspect the macOS role files and assert:

- Rectangle is installed and SizeUp is explicitly removed.
- All seven shortcut actions have the expected key codes and modifiers.
- Rectangle starts at login and repeated-command cycling is disabled.
- The obsolete SizeUp defaults domain is deleted.
- The old SizeUp defaults are no longer present in the managed defaults list.

Run the focused test, the CI test inventory, Ansible syntax checking, and local
macOS provisioning. After provisioning, verify the Rectangle defaults domain,
confirm SizeUp is absent and Rectangle is installed, then exercise each shortcut
against a normal application window. Rectangle may still require one-time macOS
Accessibility permission because that authorization is controlled by macOS and
is not safely provisioned here.
