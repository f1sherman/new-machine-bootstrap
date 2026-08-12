#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"
require "yaml"

repo_root = File.expand_path("..", __dir__)
tasks = YAML.safe_load_file(
  File.join(repo_root, "roles/linux/tasks/install_packages.yml")
)
selection_task = tasks.find { |task| task["name"] == "Check for existing mise binary" }
abort "missing Linux mise selection task" unless selection_task

Dir.mktmpdir("mise-selection") do |dir|
  user_dir = File.join(dir, "home")
  managed_mise = File.join(user_dir, ".local/bin/mise")
  system_bin = File.join(dir, "system-bin")
  system_mise = File.join(system_bin, "mise")
  FileUtils.mkdir_p([File.dirname(managed_mise), system_bin])

  [managed_mise, system_mise].each do |path|
    File.write(path, "#!/bin/sh\nexit 0\n")
    FileUtils.chmod(0o755, path)
  end

  shell = selection_task.fetch("shell").gsub(
    "{{ ansible_facts['user_dir'] }}", user_dir
  )
  stdout, stderr, status = Open3.capture3(
    {"PATH" => "#{system_bin}:/usr/bin:/bin"},
    "/bin/bash", "-c", shell
  )

  abort "mise selection failed: #{stderr}" unless status.success?
  selected = stdout.strip
  unless selected == managed_mise
    abort "selected #{selected.inspect}, expected managed mise #{managed_mise.inspect}"
  end
end

puts "mise install selection behavior passed"
