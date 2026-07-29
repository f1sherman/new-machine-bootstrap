#!/usr/bin/env ruby
# frozen_string_literal: true

repo_root = File.expand_path("..", __dir__)
tasks = File.read(File.join(repo_root, "roles/common/tasks/main.yml"))
task = tasks[/^- name: Install managed mise npm tools through aube\n.*?(?=^- name: |\z)/m]
abort "managed npm install task is missing" unless task

explicit_codex = "'npm:@openai/codex@latest'"
explicit_pi = %q{'npm:@earendil-works/pi-coding-agent@{{ tool_versions.runtimes.pi_coding_agent }}'}

abort "managed npm install must explicitly select Codex" unless task.include?(explicit_codex)
abort "managed npm install must explicitly select Pi" unless task.include?(explicit_pi)
abort "managed npm install must not install the entire home mise config" if task.include?("--cd {{ ansible_facts['user_dir'] }} install --yes")
abort "managed npm install must preserve paranoid mode" unless task.include?('AUBE_PARANOID: "true"')

puts "PASS  managed mise npm install targets only declared tools"
