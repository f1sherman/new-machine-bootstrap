# SizeUp to Rectangle Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace SizeUp with Rectangle while preserving Brian's seven existing window-management shortcuts.

**Architecture:** Keep package ownership in the macOS role and settings ownership in its existing defaults configuration. Add a small data table for Rectangle shortcuts, one generic Ansible loop that writes Rectangle shortcut dictionaries, and explicit idempotent cleanup for the retired SizeUp cask and defaults domain.

**Tech Stack:** Ansible YAML, macOS `defaults`, Homebrew casks, Ruby contract tests, GitHub Actions

## Global Constraints

- Work only inside the isolated repository worktree.
- Rectangle shortcut settings use domain `com.knollsoft.Rectangle`.
- SizeUp cleanup targets cask `sizeup` and defaults domain `com.irradiatedsoftware.SizeUp`.
- Half-screen shortcuts use modifier flags `1835008`; display shortcuts use `786432`.
- Set Rectangle `subsequentExecutionMode` to `2` so repeated actions do not cycle sizes.
- macOS Accessibility permission remains a manual one-time authorization.

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
- Produces: `rectangle_shortcuts`, an array of hashes with `action`, `key_code`, and `modifier_flags`; an Ansible shortcut-writing task that consumes that array; explicit SizeUp cleanup tasks.

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

remove_sizeup = main_tasks.find { |task| task["name"] == "Remove SizeUp cask" }
abort "FAIL  missing SizeUp cask removal" unless remove_sizeup&.dig("homebrew_cask") == {
  "name" => "sizeup",
  "state" => "absent"
}

install_casks = main_tasks.find { |task| task["name"] == "Install Brew casks" }
managed_casks = install_casks&.dig("homebrew_cask", "name") || []
abort "FAIL  Rectangle cask is not installed" unless managed_casks.include?("rectangle")
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

cleanup_task = default_tasks.find { |task| task["name"] == "Remove SizeUp preferences" }
abort "FAIL  missing SizeUp defaults cleanup" unless cleanup_task
abort "FAIL  wrong SizeUp defaults cleanup command" unless cleanup_task["command"] == "defaults delete com.irradiatedsoftware.SizeUp"
abort "FAIL  SizeUp cleanup is not idempotent" unless cleanup_task["changed_when"] == "sizeup_preferences_removed.rc == 0" && cleanup_task["failed_when"] == "sizeup_preferences_removed.rc not in [0, 1]"

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

Expected: exits nonzero with `FAIL  missing SizeUp cask removal`.

- [ ] **Step 3: Implement package replacement**

In `roles/macos/tasks/main.yml`, add before `Install Brew casks`:

```yaml
- name: Remove SizeUp cask
  homebrew_cask:
    name: sizeup
    state: absent
```

In the existing cask list, replace:

```yaml
      'sizeup',
```

with:

```yaml
      'rectangle',
```

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

- name: Remove SizeUp preferences
  command: defaults delete com.irradiatedsoftware.SizeUp
  register: sizeup_preferences_removed
  changed_when: sizeup_preferences_removed.rc == 0
  failed_when: sizeup_preferences_removed.rc not in [0, 1]
```

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

Expected: exits zero, removes the SizeUp cask, installs Rectangle, writes Rectangle defaults, and removes the SizeUp defaults domain.

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

Grant Rectangle Accessibility access if macOS prompts. Using a normal application window, exercise all seven actions and verify half-screen placement, maximize, and previous/next display movement match the table in the design spec.
