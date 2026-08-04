#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

repo_root = File.expand_path("..", __dir__)
tasks = File.read(File.join(repo_root, "roles/common/tasks/main.yml"))
ruby_tasks = tasks[/^- name: Check if pinned Ruby version is installed\n.*?(?=^- name: Get current global Ruby version)/m]
abort "pinned Ruby check and install tasks are missing" unless ruby_tasks

Dir.mktmpdir("mise-ruby-install") do |dir|
  mise_bin = File.join(dir, "mise")
  calls_file = File.join(dir, "calls")
  playbook = File.join(dir, "playbook.yml")

  File.write(mise_bin, <<~SH)
    #!/bin/sh
    printf '%s\\n' "$*" >> #{calls_file.to_json}
    case "$1" in
      ls)
        printf '%s\\n' \
          'ruby  3.4.9' \
          'ruby  4.0.2 (missing)  ~/.config/mise/config.toml  4.0.2'
        ;;
      where)
        exit 1
        ;;
      install)
        exit 0
        ;;
    esac
  SH
  FileUtils.chmod(0o755, mise_bin)

  play = <<~YAML
    ---
    - hosts: localhost
      gather_facts: false
      vars:
        mise_bin: #{mise_bin.to_json}
        tool_versions:
          runtimes:
            ruby: "4.0.2"
      tasks:
  YAML
  play << ruby_tasks.lines.map { |line| "    #{line}" }.join
  File.write(playbook, play)

  stdout, stderr, status = Open3.capture3(
    {"ANSIBLE_NOCOLOR" => "true"},
    "ansible-playbook", "--inventory", "localhost,", "--connection", "local", playbook
  )
  abort "Ruby install tasks failed under Ansible:\n#{stdout}\n#{stderr}" unless status.success?

  calls = File.readlines(calls_file, chomp: true)
  expected_calls = ["where ruby@4.0.2", "install ruby@4.0.2"]
  abort "missing Ruby did not trigger an explicit install: #{calls.inspect}" unless calls == expected_calls
end

puts "PASS  configured but missing Ruby triggers an explicit install"
