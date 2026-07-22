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

install_rectangle = main_tasks.find { |task| task["name"] == "Install Rectangle cask" }
abort "FAIL  missing dedicated Rectangle cask installation" unless install_rectangle&.dig("homebrew_cask") == {
  "name" => "rectangle",
  "state" => "present"
}

stop_index = main_tasks.index(stop_sizeup)
remove_index = main_tasks.index(remove_sizeup)
rectangle_index = main_tasks.index(install_rectangle)
install_casks = main_tasks.find { |task| task["name"] == "Install Brew casks" }
install_casks_index = main_tasks.index(install_casks)
abort "FAIL  SizeUp is not stopped before cask removal" unless stop_index < remove_index
abort "FAIL  Rectangle dedicated install is ordered incorrectly" unless remove_index < rectangle_index && rectangle_index < install_casks_index

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

cleanup_task = default_tasks.find { |task| task["name"] == "Remove SizeUp preferences" }
abort "FAIL  missing SizeUp defaults cleanup" unless cleanup_task
abort "FAIL  wrong SizeUp defaults cleanup command" unless cleanup_task["command"] == "defaults delete com.irradiatedsoftware.SizeUp"
abort "FAIL  SizeUp cleanup is not idempotent" unless cleanup_task["changed_when"] == "sizeup_preferences_removed.rc == 0"
abort "FAIL  SizeUp cleanup accepts unexpected errors" unless cleanup_task["failed_when"] == "sizeup_preferences_removed.rc != 0 and 'Domain (com.irradiatedsoftware.SizeUp) not found.' not in sizeup_preferences_removed.stderr"

puts "PASS  SizeUp to Rectangle migration contract"
