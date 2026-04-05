# Zoxide + Data-Driven macOS Defaults Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install zoxide across macOS/Linux, refactor macOS defaults into a data-driven vars file, add animation-disabling and reduce-motion settings, and exclude ~/projects from Spotlight.

**Architecture:** Three independent changes: (1) zoxide install + shell integration, (2) extract macOS defaults from inline commands to a vars file with a loop task, adding new animation/accessibility settings, (3) Spotlight exclusion via `.metadata_never_index`. Changes 2 and 3 are macOS-only; change 1 is cross-platform.

**Tech Stack:** Ansible, zsh, Homebrew, GitHub Releases

---

### Task 1: Install zoxide on macOS

**Files:**
- Modify: `roles/macos/tasks/install_packages.yml:19-56`

- [ ] **Step 1: Add zoxide to Homebrew package list**

In `roles/macos/tasks/install_packages.yml`, add `'zoxide'` to the `homebrew` name array (alphabetical order, after `'yq'`):

```yaml
      'yq',
      'yt-dlp',
      'zoxide',
      'zsh'
```

- [ ] **Step 2: Verify on macOS**

Run: `bin/provision --check --diff 2>&1 | grep -i zoxide`

Expected: A task showing zoxide would be installed (or already present if you've installed it manually).

- [ ] **Step 3: Commit**

```
Add zoxide to macOS Homebrew packages
```

Files: `roles/macos/tasks/install_packages.yml`

---

### Task 2: Install zoxide on Linux

**Files:**
- Modify: `roles/linux/tasks/install_packages.yml` (insert after the yq install block, around line 167)

- [ ] **Step 1: Add zoxide install task**

Add after the yq install block (after line 167) in `roles/linux/tasks/install_packages.yml`:

```yaml
- name: Install zoxide
  include_tasks: '{{ playbook_dir }}/roles/common/tasks/install_github_binary.yml'
  vars:
    github_repo: ajeetdsouza/zoxide
    binary_name: zoxide
    asset_pattern: "zoxide-{version}-{arch}-unknown-linux-musl.tar.gz"
    install_dest: '{{ ansible_facts["user_dir"] }}/.local/bin'
    download_type: tarball
    tarball_extra_args:
      - --wildcards
      - 'zoxide'
    arch_map:
      x86_64: x86_64
      aarch64: aarch64
      arm64: aarch64
```

The tarball contains `zoxide` at the root alongside docs/completions. The `--wildcards` + `'zoxide'` args extract only the binary.

- [ ] **Step 2: Commit**

```
Add zoxide to Linux GitHub Release packages
```

Files: `roles/linux/tasks/install_packages.yml`

---

### Task 3: Add zoxide shell integration

**Files:**
- Modify: `roles/common/templates/dotfiles/zshrc:462` (after the fzf sourcing line)

- [ ] **Step 1: Add zoxide init to zshrc**

In `roles/common/templates/dotfiles/zshrc`, after line 462 (`[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh`), add:

```zsh

# Initialize zoxide (smarter cd with frecency-based directory jumping)
# --cmd cd replaces the cd builtin; cdi opens interactive fzf picker
if command -v zoxide > /dev/null; then eval "$(zoxide init zsh --cmd cd)"; fi
```

The `command -v` guard ensures the zshrc doesn't error if zoxide isn't installed yet (e.g., on a fresh machine before provisioning completes).

- [ ] **Step 2: Verify syntax**

Run: `zsh -n roles/common/templates/dotfiles/zshrc`

Expected: No output (no syntax errors). Note: Jinja2 template variables will cause zsh parse errors, so if this file uses `{{ }}` syntax you may see warnings -- that's expected for a template.

- [ ] **Step 3: Commit**

```
Add zoxide shell integration to zshrc
```

Files: `roles/common/templates/dotfiles/zshrc`

---

### Task 4: Create data-driven macOS defaults vars file

**Files:**
- Create: `roles/macos/vars/defaults.yml`

- [ ] **Step 1: Create the vars directory**

Run: `mkdir -p roles/macos/vars`

- [ ] **Step 2: Create `roles/macos/vars/defaults.yml`**

This file contains every `defaults write` setting currently in `roles/macos/tasks/main.yml` lines 221-340, converted to the data-driven format. New animation and accessibility settings are added at the top.

```yaml
---
macos_defaults:
  # ── Animations ──
  # New: disable all macOS animations for a snappier feel
  - { domain: NSGlobalDomain, key: NSAutomaticWindowAnimationsEnabled, type: int, value: 0 }
  - { domain: NSGlobalDomain, key: NSScrollAnimationEnabled, type: int, value: 0 }
  - { domain: NSGlobalDomain, key: QLPanelAnimationDuration, type: int, value: 0 }
  - { domain: NSGlobalDomain, key: NSScrollViewRubberbanding, type: int, value: 0 }
  - { domain: NSGlobalDomain, key: NSDocumentRevisionsWindowTransformAnimation, type: int, value: 0 }
  - { domain: NSGlobalDomain, key: NSToolbarFullScreenAnimationDuration, type: int, value: 0 }
  - { domain: NSGlobalDomain, key: NSBrowserColumnAnimationSpeedMultiplier, type: int, value: 0 }
  - { domain: NSGlobalDomain, key: NSUseAnimatedFocusRing, type: bool, value: false }
  - { domain: com.apple.dock, key: springboard-show-duration, type: int, value: 0 }
  - { domain: com.apple.dock, key: springboard-hide-duration, type: int, value: 0 }
  - { domain: com.apple.dock, key: springboard-page-duration, type: int, value: 0 }
  - { domain: com.apple.dock, key: mineffect, type: string, value: scale }
  - { domain: com.apple.dock, key: launchanim, type: bool, value: false }
  - { domain: com.apple.dock, key: autohide-delay, type: float, value: 0 }
  - { domain: com.apple.dock, key: autohide-time-modifier, type: float, value: 0 }
  - { domain: com.apple.finder, key: DisableAllAnimations, type: bool, value: true }

  # ── Accessibility ──
  # New: reduce motion system-wide
  - { domain: com.apple.Accessibility, key: ReduceMotionEnabled, type: int, value: 1 }

  # ── General UI ──
  - { domain: NSGlobalDomain, key: AppleShowScrollBars, type: string, value: '"Always"' }
  - { domain: NSGlobalDomain, key: NSWindowResizeTime, type: float, value: 0.001 }
  - { domain: NSGlobalDomain, key: NSDisableAutomaticTermination, type: bool, value: true }
  - { domain: com.apple.LaunchServices, key: LSQuarantine, type: bool, value: false }
  - { domain: NSGlobalDomain, key: AppleFontSmoothing, type: int, value: 2 }
  - { domain: NSGlobalDomain, key: WebKitDeveloperExtras, type: bool, value: true }
  - { domain: NSGlobalDomain, key: NSNavPanelExpandedStateForSaveMode, type: bool, value: true }
  - { domain: NSGlobalDomain, key: NSNavPanelExpandedStateForSaveMode2, type: bool, value: true }
  - { domain: NSGlobalDomain, key: PMPrintingExpandedStateForPrint, type: bool, value: true }
  - { domain: NSGlobalDomain, key: PMPrintingExpandedStateForPrint2, type: bool, value: true }
  - { domain: NSGlobalDomain, key: NSDocumentSaveNewDocumentsToCloud, type: bool, value: false }
  - { domain: com.apple.print.PrintingPrefs, key: '"Quit When Finished"', type: bool, value: true }
  - { domain: NSGlobalDomain, key: NSAutomaticQuoteSubstitutionEnabled, type: bool, value: false }
  - { domain: NSGlobalDomain, key: NSAutomaticDashSubstitutionEnabled, type: bool, value: false }

  # ── Security ──
  - { domain: com.apple.screensaver, key: askForPassword, type: int, value: 1 }
  - { domain: com.apple.screensaver, key: askForPasswordDelay, type: int, value: 3 }

  # ── Finder ──
  - { domain: NSGlobalDomain, key: AppleShowAllExtensions, type: bool, value: true }
  - { domain: com.apple.finder, key: ShowStatusBar, type: bool, value: true }
  - { domain: com.apple.finder, key: _FXShowPosixPathInTitle, type: bool, value: true }
  - { domain: com.apple.finder, key: ShowPathbar, type: bool, value: true }
  - { domain: com.apple.finder, key: NewWindowTarget, type: string, value: '"PfLo"' }
  - { domain: com.apple.finder, key: NewWindowTargetPath, type: string, value: '"file://{{ ansible_facts["user_dir"] }}/Downloads/"' }
  - { domain: com.apple.finder, key: FXEnableExtensionChangeWarning, type: bool, value: false }
  - { domain: com.apple.Finder, key: AppleShowAllFiles, type: string, value: "YES" }
  - { domain: com.apple.finder, key: FXPreferredViewStyle, type: string, value: '"Nlsv"' }
  - { domain: com.apple.finder, key: QLEnableTextSelection, type: bool, value: true }
  - { domain: com.apple.finder, key: ShowExternalHardDrivesOnDesktop, type: bool, value: true }
  - { domain: com.apple.finder, key: ShowHardDrivesOnDesktop, type: bool, value: true }
  - { domain: com.apple.finder, key: ShowMountedServersOnDesktop, type: bool, value: true }
  - { domain: com.apple.finder, key: ShowRemovableMediaOnDesktop, type: bool, value: true }

  # ── Dock ──
  - { domain: com.apple.dock, key: dashboard-in-overlay, type: bool, value: true }
  - { domain: com.apple.dashboard, key: mcx-disabled, type: bool, value: true }
  - { domain: com.apple.dock, key: autohide, type: bool, value: true }
  - { domain: com.apple.dock, key: showhidden, type: bool, value: true }
  - { domain: com.apple.dock, key: static-only, type: bool, value: true }
  - { domain: com.apple.spaces, key: spans-displays, type: bool, value: false }

  # ── Screenshots ──
  - { domain: com.apple.screencapture, key: type, type: string, value: '"png"' }

  # ── Keyboard & Trackpad ──
  - { domain: NSGlobalDomain, key: com.apple.swipescrolldirection, type: bool, value: false }
  - { domain: com.apple.driver.AppleBluetoothMultitouch.trackpad, key: Clicking, type: bool, value: true }
  - { domain: NSGlobalDomain, key: com.apple.mouse.tapBehavior, type: int, value: 1 }
  - { domain: NSGlobalDomain, key: com.apple.mouse.tapBehavior, type: int, value: 1, currentHost: true }
  - { domain: com.apple.BluetoothAudioAgent, key: '"Apple Bitpool Min (editable)"', type: int, value: 40 }
  - { domain: NSGlobalDomain, key: AppleKeyboardUIMode, type: int, value: 3 }
  - { domain: NSGlobalDomain, key: ApplePressAndHoldEnabled, type: bool, value: false }
  - { domain: NSGlobalDomain, key: KeyRepeat, type: int, value: 2 }
  - { domain: NSGlobalDomain, key: InitialKeyRepeat, type: int, value: 15 }
  - { domain: .GlobalPreferences, key: com.apple.mouse.scaling, type: int, value: 5 }

  # ── Software Update ──
  - { domain: com.apple.SoftwareUpdate, key: AutomaticCheckEnabled, type: bool, value: true }
  - { domain: com.apple.SoftwareUpdate, key: ScheduleFrequency, type: int, value: 1 }
  - { domain: com.apple.SoftwareUpdate, key: AutomaticDownload, type: int, value: 1 }
  - { domain: com.apple.SoftwareUpdate, key: CriticalUpdateInstall, type: int, value: 1 }
  - { domain: com.apple.commerce, key: AutoUpdate, type: bool, value: true }
  - { domain: com.apple.commerce, key: AutoUpdateRestartRequired, type: bool, value: true }

  # ── Network & Privacy ──
  - { domain: com.apple.desktopservices, key: DSDontWriteNetworkStores, type: bool, value: true }
  - { domain: com.apple.TimeMachine, key: DoNotOfferNewDisksForBackup, type: bool, value: true }
  - { domain: com.apple.NetworkBrowser, key: BrowseAllInterfaces, type: bool, value: true }
  - { domain: com.apple.networkConnect, key: VPNShowTime, type: int, value: 1 }
  - { domain: com.apple.Siri, key: TypeToSiriEnabled, type: bool, value: false }

  # ── Photos ──
  - { domain: com.apple.ImageCapture, key: disableHotPlug, type: bool, value: true, currentHost: true }

  # ── Safari ──
  - { domain: NSGlobalDomain, key: AppleEnableSwipeNavigateWithScrolls, type: bool, value: false }

  # ── Browser (Brave/Chrome) ──
  - { domain: com.brave.Browser, key: AppleEnableSwipeNavigateWithScrolls, type: bool, value: false }
  - { domain: com.google.Chrome, key: AppleEnableSwipeNavigateWithScrolls, type: bool, value: false }
  - { domain: com.google.Chrome.canary, key: AppleEnableSwipeNavigateWithScrolls, type: bool, value: false }
  - { domain: com.brave.Browser, key: AppleEnableMouseSwipeNavigateWithScrolls, type: bool, value: false }
  - { domain: com.google.Chrome, key: AppleEnableMouseSwipeNavigateWithScrolls, type: bool, value: false }
  - { domain: com.google.Chrome.canary, key: AppleEnableMouseSwipeNavigateWithScrolls, type: bool, value: false }
  - { domain: com.brave.Browser, key: DisablePrintPreview, type: bool, value: true }
  - { domain: com.google.Chrome, key: DisablePrintPreview, type: bool, value: true }
  - { domain: com.google.Chrome.canary, key: DisablePrintPreview, type: bool, value: true }
  - { domain: com.brave.Browser, key: PMPrintingExpandedStateForPrint2, type: bool, value: true }
  - { domain: com.google.Chrome, key: PMPrintingExpandedStateForPrint2, type: bool, value: true }
  - { domain: com.google.Chrome.canary, key: PMPrintingExpandedStateForPrint2, type: bool, value: true }

  # ── SizeUp ──
  - { domain: com.irradiatedsoftware.SizeUp, key: StartAtLogin, type: bool, value: true }
  - { domain: com.irradiatedsoftware.SizeUp, key: ShowPrefsOnNextStart, type: bool, value: false }

  # ── Activity Monitor ──
  - { domain: com.apple.ActivityMonitor, key: OpenMainWindow, type: bool, value: true }
  - { domain: com.apple.ActivityMonitor, key: IconType, type: int, value: 5 }
  - { domain: com.apple.ActivityMonitor, key: ShowCategory, type: int, value: 0 }
```

- [ ] **Step 3: Validate YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('roles/macos/vars/defaults.yml'))"`

Expected: No output (valid YAML).

- [ ] **Step 4: Commit**

```
Extract macOS defaults to data-driven vars file

Add animation-disabling and reduce-motion settings. Fix contradictory
spans-displays entries (was set to both true and false, now just false).
```

Files: `roles/macos/vars/defaults.yml`

---

### Task 5: Create defaults task file and update main.yml

**Files:**
- Create: `roles/macos/tasks/defaults.yml`
- Modify: `roles/macos/tasks/main.yml:217-342`

- [ ] **Step 1: Create `roles/macos/tasks/defaults.yml`**

```yaml
---
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

# Special cases that don't fit the { domain, key, type, value } pattern

- name: "Terminal: Only use UTF-8"
  command: defaults write com.apple.terminal StringEncodings -array 4
  changed_when: false

- name: "Terminal: Set Pro theme by default"
  command: defaults write com.apple.Terminal "Default Window Settings" -string "Pro"
  changed_when: false

- name: "Terminal: Set Pro theme on startup"
  command: defaults write com.apple.Terminal "Startup Window Settings" -string "Pro"
  changed_when: false

- name: "Menubar: Configure system menu extras"
  command: >-
    defaults write com.apple.systemuiserver menuExtras -array
    "/Applications/Utilities/Keychain Access.app/Contents/Resources/Keychain.menu"
    "/System/Library/CoreServices/Menu Extras/Bluetooth.menu"
    "/System/Library/CoreServices/Menu Extras/AirPort.menu"
    "/System/Library/CoreServices/Menu Extras/Volume.menu"
    "/System/Library/CoreServices/Menu Extras/Battery.menu"
    "/System/Library/CoreServices/Menu Extras/Clock.menu"
    "/System/Library/CoreServices/Menu Extras/User.menu"
  changed_when: false

- name: "Messages: Disable automatic emoji substitution"
  command: defaults write com.apple.messageshelper.MessageController SOInputLineSettings -dict-add "automaticEmojiSubstitutionEnablediMessage" -bool false
  changed_when: false

- name: "Messages: Disable smart quotes"
  command: defaults write com.apple.messageshelper.MessageController SOInputLineSettings -dict-add "automaticQuoteSubstitutionEnabled" -bool false
  changed_when: false

- name: "Messages: Disable continuous spell checking"
  command: defaults write com.apple.messageshelper.MessageController SOInputLineSettings -dict-add "continuousSpellCheckingEnabled" -bool false
  changed_when: false

- name: "Dock: Remove all default app icons"
  command: defaults write com.apple.dock persistent-apps -array
  changed_when: false

- name: "Activity Monitor: Set columns"
  command: >-
    defaults write com.apple.ActivityMonitor "UserColumnsPerTab v6.0" -dict
    '0' '( Command, CPUUsage, CPUTime, Threads, IdleWakeUps, PID, UID )'
    '1' '( Command, ResidentSize, anonymousMemory, compressedMemory, PurgeableMem, Threads, Ports, PID, UID)'
    '2' '( Command, PowerScore, 12HRPower, AppSleep, graphicCard, powerAssertion, UID )'
    '3' '( Command, bytesWritten, bytesRead, Architecture, PID, UID )'
    '4' '( Command, txBytes, rxBytes, txPackets, rxPackets, PID, UID )'
    '5' '( Name, LastHour, LastDay, LastWeek, LastMonth )'
    '6' '( Command, GPUUsage, GPUTime, PID, UID )'
  changed_when: false

- name: "Activity Monitor: Set column sorts"
  command: >-
    defaults write com.apple.ActivityMonitor "UserColumnSortPerTab" -dict
    '0' '{ direction = 0; sort = CPUUsage; }'
    '1' '{ direction = 0; sort = ResidentSize; }'
    '2' '{ direction = 0; sort = 12HRPower; }'
    '3' '{ direction = 0; sort = bytesWritten; }'
    '4' '{ direction = 0; sort = txBytes; }'
    '5' '{ direction = 0; sort = Name; }'
    '6' '{ direction = 0; sort = GPUUsage; }'
  changed_when: false
```

- [ ] **Step 2: Replace the mega-loop in `roles/macos/tasks/main.yml`**

Remove lines 217-342 (the entire "Configure user preferences" block from `- name: Configure user preferences` through the `loop_control` and `label` line). Replace with:

```yaml
- name: Configure macOS defaults
  include_tasks: defaults.yml

- name: Set timezone
  command: systemsetup -settimezone "America/Chicago" > /dev/null
  changed_when: false

- name: Show the ~/Library folder
  command: chflags nohidden ~/Library
  changed_when: false
```

The caps lock remap tasks (lines 344-364) remain unchanged after this block.

- [ ] **Step 3: Run provisioning in check mode to verify**

Run: `bin/provision --check 2>&1 | tail -30`

Expected: No errors. Tasks should show as "changed" (since `changed_when: false` makes them always report ok, not changed, on real runs -- but in check mode the command tasks will show as changed because they haven't actually run).

- [ ] **Step 4: Run provisioning for real to verify all defaults apply**

Run: `bin/provision 2>&1 | tail -50`

Expected: Clean run with no errors. Each default should appear in the output with its `domain key` label.

- [ ] **Step 5: Spot-check a few defaults were applied**

Run these commands to verify:

```bash
defaults read NSGlobalDomain NSAutomaticWindowAnimationsEnabled
# Expected: 0

defaults read com.apple.Accessibility ReduceMotionEnabled
# Expected: 1

defaults read com.apple.dock mineffect
# Expected: scale

defaults read com.apple.spaces spans-displays
# Expected: 0 (false)
```

- [ ] **Step 6: Commit**

```
Refactor macOS defaults to data-driven vars file with loop task

Extract 90+ defaults write commands from main.yml into
roles/macos/vars/defaults.yml with a single loop task. Add new
animation-disabling and reduce-motion settings. Fix contradictory
spans-displays bug.
```

Files: `roles/macos/vars/defaults.yml`, `roles/macos/tasks/defaults.yml`, `roles/macos/tasks/main.yml`

---

### Task 6: Add Spotlight exclusion for ~/projects

**Files:**
- Modify: `roles/macos/tasks/main.yml` (add after the defaults include, before caps lock remap)

- [ ] **Step 1: Add Spotlight exclusion task**

In `roles/macos/tasks/main.yml`, after the "Show the ~/Library folder" task and before the "Remap Caps Lock to Control" task, add:

```yaml
- name: Exclude ~/projects from Spotlight indexing
  file:
    path: '{{ ansible_facts["user_dir"] }}/projects/.metadata_never_index'
    state: touch
    modification_time: preserve
    access_time: preserve
```

- [ ] **Step 2: Verify with provision**

Run: `bin/provision 2>&1 | grep -i spotlight`

Expected: Task shows as ok or changed.

- [ ] **Step 3: Verify the file exists**

Run: `ls -la ~/projects/.metadata_never_index`

Expected: File exists.

- [ ] **Step 4: Verify idempotency**

Run: `bin/provision 2>&1 | grep -A1 spotlight`

Expected: Task shows as "ok" (not "changed") on second run, since timestamps are preserved.

- [ ] **Step 5: Commit**

```
Exclude ~/projects from Spotlight indexing
```

Files: `roles/macos/tasks/main.yml`

---

### Task 7: Final verification

- [ ] **Step 1: Full provision run**

Run: `bin/provision`

Expected: Clean run, no errors.

- [ ] **Step 2: Verify zoxide works**

Open a new terminal (or `exec zsh`), then:

```bash
which cd
# Expected: cd is a shell function (zoxide's replacement)

cd /tmp
cd ~/projects
cd tmp
# Expected: jumps to /tmp (frecency)
```

- [ ] **Step 3: Verify all success criteria**

Run the following checks:

```bash
# Zoxide installed
command -v zoxide

# Animation defaults applied
defaults read NSGlobalDomain NSAutomaticWindowAnimationsEnabled  # 0
defaults read NSGlobalDomain NSScrollAnimationEnabled            # 0

# Reduce motion
defaults read com.apple.Accessibility ReduceMotionEnabled        # 1

# Spotlight exclusion
test -f ~/projects/.metadata_never_index && echo "OK" || echo "MISSING"

# No duplicate spans-displays
grep -c spans-displays roles/macos/vars/defaults.yml  # 1
```
