# Zoxide + Data-Driven macOS Defaults

## Summary

Two independent changes:

1. Install zoxide and replace `cd` with it across macOS and Linux
2. Refactor macOS `defaults write` settings from a 120-line command loop into a data-driven vars file, adding animation-disabling and reduce-motion settings

## 1. Zoxide

### Install

- **macOS**: Add `zoxide` to the Homebrew package list in `roles/macos/tasks/install_packages.yml`
- **Linux**: Install via GitHub Release binary using the existing `install_github_binary.yml` pattern in `roles/linux/tasks/install_packages.yml`. Repo: `ajeetdsouza/zoxide`, asset pattern: `zoxide-{version}-{arch}-unknown-linux-musl.tar.gz`

### Shell Integration

Add to `roles/common/templates/dotfiles/zshrc`, after the fzf sourcing line (`[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh`):

```zsh
eval "$(zoxide init zsh --cmd cd)"
```

The `--cmd cd` flag replaces `cd` with zoxide, so frecency-based jumping is the default behavior. Full paths still work normally. `cdi` is created automatically as the interactive (fzf) variant.

## 2. Data-Driven macOS Defaults

### New File: `roles/macos/vars/defaults.yml`

A flat list of defaults entries, organized by category via YAML comments. Each entry:

```yaml
- { domain: <domain>, key: <key>, type: <type>, value: <value> }
```

Two entries use `defaults -currentHost write` instead of `defaults write`:
- `com.apple.ImageCapture disableHotPlug`
- `NSGlobalDomain com.apple.mouse.tapBehavior`

These get a `currentHost: true` field:

```yaml
- { domain: com.apple.ImageCapture, key: disableHotPlug, type: bool, value: true, currentHost: true }
```

Categories (matching existing settings, plus new ones marked with *):

- **Animations** -- *NEW*: `NSAutomaticWindowAnimationsEnabled`, `NSScrollAnimationEnabled`, `QLPanelAnimationDuration`, `NSScrollViewRubberbanding`, `NSDocumentRevisionsWindowTransformAnimation`, `NSToolbarFullScreenAnimationDuration`, `NSBrowserColumnAnimationSpeedMultiplier` (all NSGlobalDomain, int 0); `springboard-show-duration`, `springboard-hide-duration`, `springboard-page-duration` (com.apple.dock, int 0); `mineffect` (com.apple.dock, string "scale"). EXISTING moved here: `NSUseAnimatedFocusRing` (NSGlobalDomain), `DisableAllAnimations` (com.apple.finder), `launchanim` (com.apple.dock), `autohide-delay` (com.apple.Dock), `autohide-time-modifier` (com.apple.dock)
- **Accessibility** -- *NEW*: `ReduceMotionEnabled` (com.apple.Accessibility, int 1)
- **General UI** -- scrollbars, window resize speed, auto-termination, LaunchServices quarantine, font smoothing, save/print panel expansion, save-to-disk default, smart quotes/dashes, web inspector
- **Security** -- screensaver password, screensaver delay
- **Finder** -- extensions, status bar, path bar, POSIX title, default location, list view, Quick Look text selection, desktop icons, show all files, disable extension change warning
- **Dock** -- clear persistent-apps, auto-hide, no dashboard, show only open apps, hidden apps translucent, spans-displays false
- **Keyboard & Trackpad** -- press-and-hold disabled, key repeat rate, initial repeat rate, full keyboard access, tap to click, clicking enabled, mouse speed, reverse scrolling disabled
- **Screenshots** -- PNG format
- **Software Update** -- auto-check, daily frequency, auto-download, critical updates, app auto-update, reboot allowed
- **Terminal** -- UTF-8, Pro theme default/startup
- **Network & Privacy** -- no .DS_Store on network volumes, Time Machine prompt disabled, AirDrop over Ethernet, VPN connection time, Type to Siri disabled
- **Menubar** -- system UI server menuExtras array
- **Photos** -- disable hot plug (currentHost)
- **Messages** -- disable emoji substitution, smart quotes, spell checking
- **Browser** -- Brave/Chrome backswipe disabled (trackpad + mouse), print preview disabled, print dialog expanded
- **Safari** -- swipe navigation disabled
- **Bluetooth** -- audio agent bitpool quality
- **SizeUp** -- start at login, hide prefs
- **Activity Monitor** -- show main window, CPU icon, all processes, columns, column sorts

### New File: `roles/macos/tasks/defaults.yml`

```yaml
- name: Load macOS defaults configuration
  include_vars: defaults.yml

- name: Configure macOS defaults
  command: >-
    defaults {{ '-currentHost' if item.currentHost | default(false) else '' }}
    write {{ item.domain }} {{ item.key }}
    -{{ item.type }} {{ item.value }}
  changed_when: false
  loop: "{{ macos_defaults }}"
  loop_control:
    label: "{{ item.domain }} {{ item.key }}"
```

### Modified: `roles/macos/tasks/main.yml`

The "Configure user preferences" block (lines 217-342) is replaced with:

```yaml
- name: Configure macOS defaults
  include_tasks: defaults.yml
```

The following non-`defaults write` commands remain as individual tasks:
- `systemsetup -settimezone "America/Chicago"` (different command syntax)
- `hidutil property --set` for caps lock remap (not a defaults command)
- `chflags nohidden ~/Library` (not a defaults command)

### Bug Fix

The current config has contradictory `spans-displays` entries (line 323 sets `true`, line 338 sets `false`). Resolved to a single entry: `false`.

### Special Cases

These settings don't fit the simple `{ domain, key, type, value }` pattern and stay as individual command tasks in `defaults.yml`:

- **Activity Monitor columns/sorts** -- use `-dict` with complex multi-line values
- **Messages settings** (3 entries) -- use `-dict-add` to add keys to an existing dict
- **Menubar** -- uses `-array` with multiple path values
- **Dock persistent-apps** -- uses `-array` with no values (clears the dock)
- **Terminal StringEncodings** -- uses `-array 4` (array with a single element)

## 3. Spotlight Exclusion

Create `.metadata_never_index` in `~/projects` during provisioning to exclude it from Spotlight indexing. This is a single Ansible task in `roles/macos/tasks/main.yml`:

```yaml
- name: Exclude ~/projects from Spotlight indexing
  file:
    path: '{{ ansible_facts["user_dir"] }}/projects/.metadata_never_index'
    state: touch
    modification_time: preserve
    access_time: preserve
```

Uses `touch` with preserved timestamps so it's idempotent (won't trigger changed on every run).

## Success Criteria

1. `bin/provision` runs cleanly on macOS with no errors
2. `zoxide` is installed and `cd` uses frecency after shell restart
3. All existing macOS defaults are preserved (no settings lost in migration)
4. New animation-disabling defaults are applied
5. `ReduceMotionEnabled` is set to 1
6. `bin/provision` runs cleanly on Linux with zoxide installed
7. `~/projects/.metadata_never_index` exists after macOS provisioning
