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
onboarding_wait_index = main_tasks.index(onboarding_wait)
install_casks = main_tasks.find { |task| task["name"] == "Install Brew casks" }
install_casks_index = main_tasks.index(install_casks)
abort "FAIL  SizeUp cleanup tasks are ordered incorrectly" unless stop_index < remove_index && remove_index < remove_unmanaged_index
abort "FAIL  Rectangle install is not after SizeUp cleanup" unless remove_unmanaged_index < rectangle_index
abort "FAIL  Rectangle onboarding tasks are ordered incorrectly" unless rectangle_index < onboarding_check_index && onboarding_check_index < onboarding_launch_index && onboarding_launch_index < onboarding_wait_index && onboarding_wait_index < install_casks_index

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

puts "PASS  SizeUp to Rectangle migration contract"
