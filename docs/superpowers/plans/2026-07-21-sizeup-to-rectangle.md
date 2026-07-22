# SizeUp to Rectangle Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace SizeUp with Rectangle while preserving Brian's seven existing window-management shortcuts.

**Architecture:** Keep package ownership and first-run onboarding in the macOS role and settings ownership in its existing defaults configuration. Add a small data table for Rectangle shortcuts, one generic Ansible loop that writes Rectangle shortcut dictionaries, explicit idempotent cleanup for managed and unmanaged SizeUp installations, marker-driven Rectangle onboarding before managed defaults, and an unconditional post-configuration Rectangle restart so runtime settings and native login registration match those defaults.

**Tech Stack:** Ansible YAML, macOS `defaults`, Homebrew casks, Ruby contract tests, GitHub Actions

## Global Constraints

- Work only inside the isolated repository worktree.
- Rectangle shortcut settings use domain `com.knollsoft.Rectangle`.
- SizeUp cleanup targets cask `sizeup` and defaults domain `com.irradiatedsoftware.SizeUp`.
- Half-screen shortcuts use modifier flags `1835008`; display shortcuts use `786432`.
- Set Rectangle `subsequentExecutionMode` to `2` so repeated actions do not cycle sizes.
- macOS Accessibility permission remains a manual one-time authorization.
- Rectangle onboarding uses only the explicit `alternateDefaultShortcuts` marker and waits at most 120 seconds.
- Existing unmanaged Rectangle applications satisfy the dedicated cask installation.

---

### Task 1: Declarative Rectangle migration

**Files:**
- Create: `tests/rectangle-migration-contract.rb`
- Modify: `.github/workflows/integration-test.yml`
- Modify: `roles/macos/tasks/main.yml`
- Modify: `roles/macos/tasks/defaults.yml`
- Modify: `roles/macos/vars/defaults.yml`

**Interfaces:**
- Consumes: Ansible's `homebrew_cask` module, the existing `macos_defaults` scalar loop, and macOS `defaults write/delete`.
- Produces: `rectangle_shortcuts`, an array of hashes with `action`, `key_code`, and `modifier_flags`; an Ansible shortcut-writing task that consumes that array; explicit managed and unmanaged SizeUp cleanup tasks; first-run Rectangle onboarding that completes before managed defaults; a post-configuration stop and relaunch that loads managed runtime bindings and reconciles Rectangle's native login item.

- [ ] **Step 1: Write the failing contract test**

Create `tests/rectangle-migration-contract.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

repo_root = File.expand_path("..", __dir__)
main_tasks = YAML.safe_load_file(File.join(repo_root, "roles/macos/tasks/main.yml"))
default_tasks = YAML.safe_load_file(File.join(repo_root, "roles/macos/tasks/defaults.yml"))
default_vars = YAML.safe_load_file(File.join(repo_root, "roles/macos/vars/defaults.yml"))

stop_sizeup = main_tasks.find { |task| task["name"] == "Stop SizeUp before removal" }
abort "FAIL  missing SizeUp stop task" unless stop_sizeup
abort "FAIL  wrong SizeUp stop command" unless stop_sizeup["command"] == "pkill -x SizeUp"
abort "FAIL  SizeUp stop result is not registered" unless stop_sizeup["register"] == "sizeup_stopped"
abort "FAIL  SizeUp stop is not idempotent" unless stop_sizeup["changed_when"] == "sizeup_stopped.rc == 0" && stop_sizeup["failed_when"] == "sizeup_stopped.rc not in [0, 1]"

remove_sizeup = main_tasks.find { |task| task["name"] == "Remove SizeUp cask" }
abort "FAIL  missing SizeUp cask removal" unless remove_sizeup&.dig("homebrew_cask") == {
  "name" => "sizeup",
  "state" => "absent"
}

remove_unmanaged_sizeup = main_tasks.find { |task| task["name"] == "Remove unmanaged SizeUp application" }
abort "FAIL  missing unmanaged SizeUp cleanup" unless remove_unmanaged_sizeup&.dig("file") == {
  "path" => "/Applications/SizeUp.app",
  "state" => "absent"
}

install_rectangle = main_tasks.find { |task| task["name"] == "Install Rectangle cask" }
abort "FAIL  missing dedicated Rectangle cask installation" unless install_rectangle&.dig("homebrew_cask") == {
  "name" => "rectangle",
  "state" => "present",
  "accept_external_apps" => true
}

onboarding_check = main_tasks.find { |task| task["name"] == "Check whether Rectangle onboarding is complete" }
abort "FAIL  missing or incorrect Rectangle onboarding check" unless onboarding_check == {
  "name" => "Check whether Rectangle onboarding is complete",
  "command" => "defaults read com.knollsoft.Rectangle alternateDefaultShortcuts",
  "register" => "rectangle_onboarding_check",
  "changed_when" => false,
  "failed_when" => false
}

onboarding_launch = main_tasks.find { |task| task["name"] == "Launch Rectangle for first-run onboarding" }
abort "FAIL  missing or incorrect Rectangle onboarding launch" unless onboarding_launch == {
  "name" => "Launch Rectangle for first-run onboarding",
  "command" => "open -a Rectangle",
  "changed_when" => false,
  "when" => "rectangle_onboarding_check.rc != 0"
}

onboarding_wait = main_tasks.find { |task| task["name"] == "Wait for Rectangle first-run onboarding" }
abort "FAIL  missing or incorrect Rectangle onboarding wait" unless onboarding_wait == {
  "name" => "Wait for Rectangle first-run onboarding",
  "command" => "defaults read com.knollsoft.Rectangle alternateDefaultShortcuts",
  "register" => "rectangle_onboarding_result",
  "changed_when" => false,
  "until" => "rectangle_onboarding_result.rc == 0",
  "retries" => 120,
  "delay" => 1,
  "when" => "rectangle_onboarding_check.rc != 0"
}

stop_index = main_tasks.index(stop_sizeup)
remove_index = main_tasks.index(remove_sizeup)
remove_unmanaged_index = main_tasks.index(remove_unmanaged_sizeup)
rectangle_index = main_tasks.index(install_rectangle)
onboarding_check_index = main_tasks.index(onboarding_check)
onboarding_launch_index = main_tasks.index(onboarding_launch)
wait_index = main_tasks.index(onboarding_wait)
install_casks = main_tasks.find { |task| task["name"] == "Install Brew casks" }
install_casks_index = main_tasks.index(install_casks)
configure_defaults = main_tasks.find { |task| task["name"] == "Configure macOS defaults" }
configure_defaults_index = main_tasks.index(configure_defaults)
abort "FAIL  SizeUp cleanup tasks are ordered incorrectly" unless stop_index < remove_index && remove_index < remove_unmanaged_index
abort "FAIL  Rectangle install is not after SizeUp cleanup" unless remove_unmanaged_index < rectangle_index
abort "FAIL  Rectangle onboarding tasks are ordered incorrectly" unless rectangle_index < onboarding_check_index && onboarding_check_index < onboarding_launch_index && onboarding_launch_index < wait_index && wait_index < install_casks_index
abort "FAIL  missing managed defaults include" unless configure_defaults
abort "FAIL  Rectangle onboarding does not precede managed defaults" unless wait_index < configure_defaults_index

managed_casks = install_casks&.dig("homebrew_cask", "name") || []
abort "FAIL  Rectangle remains in general cask installation" if managed_casks.include?("rectangle")
abort "FAIL  SizeUp remains in installed casks" if managed_casks.include?("sizeup")

macos_defaults = default_vars.fetch("macos_defaults")
rectangle_defaults = macos_defaults.select { |item| item["domain"] == "com.knollsoft.Rectangle" }
expected_defaults = {
  "launchOnLogin" => ["bool", true],
  "subsequentExecutionMode" => ["int", 2]
}
actual_defaults = rectangle_defaults.to_h { |item| [item.fetch("key"), [item.fetch("type"), item.fetch("value")]] }
abort "FAIL  Rectangle scalar defaults differ: #{actual_defaults.inspect}" unless actual_defaults == expected_defaults
abort "FAIL  SizeUp defaults remain managed" if macos_defaults.any? { |item| item["domain"] == "com.irradiatedsoftware.SizeUp" }

expected_shortcuts = {
  "leftHalf" => [123, 1_835_008],
  "rightHalf" => [124, 1_835_008],
  "topHalf" => [126, 1_835_008],
  "bottomHalf" => [125, 1_835_008],
  "maximize" => [46, 1_835_008],
  "previousDisplay" => [123, 786_432],
  "nextDisplay" => [124, 786_432]
}
actual_shortcuts = default_vars.fetch("rectangle_shortcuts").to_h do |item|
  [item.fetch("action"), [item.fetch("key_code"), item.fetch("modifier_flags")]]
end
abort "FAIL  Rectangle shortcuts differ: #{actual_shortcuts.inspect}" unless actual_shortcuts == expected_shortcuts

shortcut_task = default_tasks.find { |task| task["name"] == "Rectangle: Configure window shortcuts" }
shortcut_command = shortcut_task&.fetch("command", "")&.split&.join(" ")
expected_command = "defaults write com.knollsoft.Rectangle {{ item.action }} -dict keyCode -int {{ item.key_code }} modifierFlags -int {{ item.modifier_flags }}"
abort "FAIL  Rectangle shortcut writer differs" unless shortcut_command == expected_command
abort "FAIL  Rectangle shortcut writer has wrong loop" unless shortcut_task["loop"] == "{{ rectangle_shortcuts }}"
abort "FAIL  Rectangle shortcut writer is not idempotent" unless shortcut_task["changed_when"] == false

preferences_check = default_tasks.find { |task| task["name"] == "Check for SizeUp preferences" }
abort "FAIL  missing SizeUp preferences check" unless preferences_check
abort "FAIL  wrong SizeUp preferences check command" unless preferences_check["command"] == "defaults read com.irradiatedsoftware.SizeUp"
abort "FAIL  SizeUp preferences check result is not registered" unless preferences_check["register"] == "sizeup_preferences_check"
abort "FAIL  SizeUp preferences check reports changes" unless preferences_check["changed_when"] == false
expected_check_failure = "sizeup_preferences_check.rc != 0 and (sizeup_preferences_check.stderr_lines | last) != 'Domain com.irradiatedsoftware.SizeUp does not exist'"
abort "FAIL  SizeUp preferences check accepts unexpected errors" unless preferences_check["failed_when"] == expected_check_failure

cleanup_task = default_tasks.find { |task| task["name"] == "Remove SizeUp preferences" }
abort "FAIL  missing SizeUp defaults cleanup" unless cleanup_task
abort "FAIL  wrong SizeUp defaults cleanup command" unless cleanup_task["command"] == "defaults delete com.irradiatedsoftware.SizeUp"
abort "FAIL  SizeUp cleanup is not conditional" unless cleanup_task["when"] == "sizeup_preferences_check.rc == 0"
abort "FAIL  SizeUp cleanup overrides default failure handling" if cleanup_task.key?("failed_when")
abort "FAIL  SizeUp cleanup ignores deletion failures" if cleanup_task["ignore_errors"] == true

rectangle_stop = default_tasks.find { |task| task["name"] == "Stop Rectangle to reload managed settings" }
abort "FAIL  missing or incorrect Rectangle stop task" unless rectangle_stop == {
  "name" => "Stop Rectangle to reload managed settings",
  "command" => "pkill -x Rectangle",
  "register" => "rectangle_stopped",
  "changed_when" => "rectangle_stopped.rc == 0",
  "failed_when" => "rectangle_stopped.rc not in [0, 1]"
}

rectangle_relaunch = default_tasks.find { |task| task["name"] == "Relaunch Rectangle with managed settings" }
abort "FAIL  missing or incorrect Rectangle relaunch task" unless rectangle_relaunch == {
  "name" => "Relaunch Rectangle with managed settings",
  "command" => "open -a Rectangle",
  "changed_when" => false
}

shortcut_index = default_tasks.index(shortcut_task)
cleanup_index = default_tasks.index(cleanup_task)
rectangle_stop_index = default_tasks.index(rectangle_stop)
rectangle_relaunch_index = default_tasks.index(rectangle_relaunch)
abort "FAIL  Rectangle reload does not follow managed shortcut writes" unless shortcut_index < rectangle_stop_index
abort "FAIL  Rectangle reload does not follow SizeUp preference cleanup" unless cleanup_index < rectangle_stop_index
abort "FAIL  Rectangle reload tasks are ordered incorrectly" unless rectangle_stop_index < rectangle_relaunch_index

puts "PASS  SizeUp to Rectangle migration contract"
```

Add this step after the CI inventory step in `.github/workflows/integration-test.yml`:

```yaml
      - name: Verify Rectangle migration
        run: ruby tests/rectangle-migration-contract.rb
```

- [ ] **Step 2: Run the contract test and verify it fails**

Run:

```bash
ruby tests/rectangle-migration-contract.rb
```

Expected: exits nonzero with `FAIL  missing unmanaged SizeUp cleanup`.

- [ ] **Step 3: Implement package replacement**

In `roles/macos/tasks/main.yml`, add before `Install Brew casks`:

```yaml
- name: Stop SizeUp before removal
  command: pkill -x SizeUp
  register: sizeup_stopped
  changed_when: sizeup_stopped.rc == 0
  failed_when: sizeup_stopped.rc not in [0, 1]

- name: Remove SizeUp cask
  homebrew_cask:
    name: sizeup
    state: absent

- name: Remove unmanaged SizeUp application
  file:
    path: /Applications/SizeUp.app
    state: absent

- name: Install Rectangle cask
  homebrew_cask:
    name: rectangle
    state: present
    accept_external_apps: true

- name: Check whether Rectangle onboarding is complete
  command: defaults read com.knollsoft.Rectangle alternateDefaultShortcuts
  register: rectangle_onboarding_check
  changed_when: false
  failed_when: false

- name: Launch Rectangle for first-run onboarding
  command: open -a Rectangle
  changed_when: false
  when: rectangle_onboarding_check.rc != 0

- name: Wait for Rectangle first-run onboarding
  command: defaults read com.knollsoft.Rectangle alternateDefaultShortcuts
  register: rectangle_onboarding_result
  changed_when: false
  until: rectangle_onboarding_result.rc == 0
  retries: 120
  delay: 1
  when: rectangle_onboarding_check.rc != 0
```

Remove `sizeup` from the existing aggregate cask list. Keep both `sizeup` and `rectangle` out of that list. The onboarding tasks must remain between the dedicated Rectangle install and aggregate cask install so the later defaults tasks overwrite onboarding's shortcut choices.

- [ ] **Step 4: Implement Rectangle settings and SizeUp preference cleanup**

Replace the SizeUp section in `roles/macos/vars/defaults.yml` with:

```yaml
  # ── Rectangle ──
  - { domain: com.knollsoft.Rectangle, key: launchOnLogin, type: bool, value: true }
  - { domain: com.knollsoft.Rectangle, key: subsequentExecutionMode, type: int, value: 2 }
```

Append this top-level variable after `macos_defaults` in the same file:

```yaml
rectangle_shortcuts:
  - { action: leftHalf, key_code: 123, modifier_flags: 1835008 }
  - { action: rightHalf, key_code: 124, modifier_flags: 1835008 }
  - { action: topHalf, key_code: 126, modifier_flags: 1835008 }
  - { action: bottomHalf, key_code: 125, modifier_flags: 1835008 }
  - { action: maximize, key_code: 46, modifier_flags: 1835008 }
  - { action: previousDisplay, key_code: 123, modifier_flags: 786432 }
  - { action: nextDisplay, key_code: 124, modifier_flags: 786432 }
```

In `roles/macos/tasks/defaults.yml`, add immediately after the scalar defaults loop:

```yaml
- name: "Rectangle: Configure window shortcuts"
  command: >-
    defaults write com.knollsoft.Rectangle {{ item.action }}
    -dict keyCode -int {{ item.key_code }}
    modifierFlags -int {{ item.modifier_flags }}
  changed_when: false
  loop: "{{ rectangle_shortcuts }}"
  loop_control:
    label: "{{ item.action }}"

- name: Check for SizeUp preferences
  command: defaults read com.irradiatedsoftware.SizeUp
  register: sizeup_preferences_check
  changed_when: false
  failed_when: >-
    sizeup_preferences_check.rc != 0 and
    (sizeup_preferences_check.stderr_lines | last) !=
    'Domain com.irradiatedsoftware.SizeUp does not exist'

- name: Remove SizeUp preferences
  command: defaults delete com.irradiatedsoftware.SizeUp
  when: sizeup_preferences_check.rc == 0

- name: Stop Rectangle to reload managed settings
  command: pkill -x Rectangle
  register: rectangle_stopped
  changed_when: rectangle_stopped.rc == 0
  failed_when: rectangle_stopped.rc not in [0, 1]

- name: Relaunch Rectangle with managed settings
  command: open -a Rectangle
  changed_when: false
```

The restart runs on every macOS provision after settings and SizeUp preference
cleanup. It makes Rectangle load the managed runtime bindings and execution mode
and reconcile its native login item from `launchOnLogin = true`.

- [ ] **Step 5: Run focused tests and syntax checks**

Run:

```bash
ruby tests/rectangle-migration-contract.rb
bash tests/ci-test-inventory.sh
ruby -e 'require "yaml"; Dir["roles/macos/{tasks,vars}/*.yml"].each { |path| YAML.load_file(path) }; puts "YAML parses"'
ansible-playbook playbook.yml --syntax-check
```

Expected: the contract reports `PASS  SizeUp to Rectangle migration contract`, inventory reports `1 passed, 0 failed`, YAML reports `YAML parses`, and Ansible syntax check exits zero.

- [ ] **Step 6: Commit the migration**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Replace SizeUp with Rectangle" \
  tests/rectangle-migration-contract.rb \
  .github/workflows/integration-test.yml \
  roles/macos/tasks/main.yml \
  roles/macos/tasks/defaults.yml \
  roles/macos/vars/defaults.yml
```

### Task 2: Apply and verify the migration

**Files:**
- Verify only; no planned file changes.

**Interfaces:**
- Consumes: the Ansible migration from Task 1 and the locally installed Homebrew/macOS defaults tools.
- Produces: empirical proof that provisioning installed/configured Rectangle and removed SizeUp.

- [ ] **Step 1: Apply provisioning**

Run:

```bash
bin/provision
```

Expected: exits zero, removes managed and unmanaged SizeUp applications, accepts an existing unmanaged Rectangle application or installs its cask, waits up to 120 seconds for fresh-install onboarding, writes Rectangle defaults, removes the SizeUp defaults domain, and restarts Rectangle so runtime bindings and native login registration match the managed settings.

- [ ] **Step 2: Verify installed applications and preferences**

Run:

```bash
brew list --cask | rg '^(rectangle|sizeup)$'
defaults read com.knollsoft.Rectangle launchOnLogin
defaults read com.knollsoft.Rectangle subsequentExecutionMode
defaults read com.knollsoft.Rectangle leftHalf
defaults read com.knollsoft.Rectangle rightHalf
defaults read com.knollsoft.Rectangle topHalf
defaults read com.knollsoft.Rectangle bottomHalf
defaults read com.knollsoft.Rectangle maximize
defaults read com.knollsoft.Rectangle previousDisplay
defaults read com.knollsoft.Rectangle nextDisplay
! defaults read com.irradiatedsoftware.SizeUp
```

Expected: only `rectangle` appears; scalar values are `1` and `2`; each shortcut dictionary contains the planned `keyCode` and `modifierFlags`; SizeUp defaults read fails.

- [ ] **Step 3: Verify idempotence**

Run:

```bash
bin/provision --check
```

Expected: exits zero without a SizeUp cleanup error. Any check-mode changes caused by modules that cannot fully predict Homebrew/defaults state must be inspected and documented before completion.

- [ ] **Step 4: Exercise GUI shortcuts**

On a fresh install, grant Rectangle Accessibility access and complete the welcome dialog before the 120-second wait expires. Using a normal application window, exercise all seven actions and verify half-screen placement, maximize, and previous/next display movement match the table in the design spec.
