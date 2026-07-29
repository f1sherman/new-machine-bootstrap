#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

repo_root = File.expand_path("..", __dir__)
tasks = File.read(File.join(repo_root, "roles/common/tasks/main.yml"))
task = tasks[/^- name: Install managed mise npm tools through aube\n.*?(?=^- name: |\z)/m]
abort "managed npm install task is missing" unless task

Dir.mktmpdir("managed-mise-npm-install") do |dir|
  mise_bin = File.join(dir, "mise")
  args_file = File.join(dir, "args")
  env_file = File.join(dir, "env")
  home_dir = File.join(dir, "home")
  playbook = File.join(dir, "playbook.yml")

  FileUtils.mkdir_p(home_dir)
  File.write(mise_bin, <<~SH)
    #!/bin/sh
    printf '%s\n' "$@" > #{args_file.to_json}
    printf '%s\n' "$AUBE_PARANOID" "$AUBE_MINIMUM_RELEASE_AGE_EXCLUDE" "$MISE_NPM_PACKAGE_MANAGER" > #{env_file.to_json}
  SH
  FileUtils.chmod(0o755, mise_bin)

  play = <<~YAML
    ---
    - hosts: localhost
      gather_facts: false
      vars:
        mise_bin: #{mise_bin.to_json}
        ansible_facts:
          user_dir: #{home_dir.to_json}
          env:
            PATH: #{ENV.fetch("PATH").to_json}
        tool_versions:
          runtimes:
            pi_coding_agent: "9.8.7"
      tasks:
  YAML
  play << task.lines.map { |line| "    #{line}" }.join
  File.write(playbook, play)

  stdout, stderr, status = Open3.capture3(
    {"ANSIBLE_NOCOLOR" => "true"},
    "ansible-playbook", "--inventory", "localhost,", "--connection", "local", playbook
  )
  abort "managed npm install task failed under Ansible:\n#{stdout}\n#{stderr}" unless status.success?

  expected_args = [
    "install",
    "--yes",
    "npm:@openai/codex@latest",
    "npm:@earendil-works/pi-coding-agent@9.8.7"
  ]
  actual_args = File.readlines(args_file, chomp: true)
  abort "managed npm install passed unexpected mise arguments: #{actual_args.inspect}" unless actual_args == expected_args

  paranoid, exclusions, package_manager = File.readlines(env_file, chomp: true)
  abort "managed npm install must preserve paranoid mode" unless paranoid == "true"
  abort "managed npm install must select aube" unless package_manager == "aube"
  abort "managed npm install must exempt Codex from the release-age gate" unless exclusions.split(",").include?("@openai/codex")
end

puts "PASS  managed mise npm install targets only declared tools"
