#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"
require "yaml"

repo_root = File.expand_path("..", __dir__)
task_files = {
  "Linux" => "roles/linux/tasks/install_packages.yml",
  "macOS" => "roles/macos/tasks/install_packages.yml"
}

Dir.mktmpdir("mise-install-download") do |dir|
  fake_curl = File.join(dir, "curl")
  File.write(fake_curl, "#!/bin/sh\nexit 22\n")
  FileUtils.chmod(0o755, fake_curl)

  task_files.each do |platform, relative_path|
    tasks = YAML.safe_load_file(File.join(repo_root, relative_path))
    install_task = tasks.find { |task| task["name"]&.start_with?("Install mise") }
    abort "missing #{platform} mise install task" unless install_task

    _stdout, _stderr, status = Open3.capture3(
      {"PATH" => "#{dir}:/usr/bin:/bin"},
      "/bin/bash", "-c", install_task.fetch("shell")
    )
    if status.success?
      abort "#{platform} mise install swallowed the curl failure"
    end
  end
end

puts "mise install download failure behavior passed"
