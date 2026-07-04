#!/usr/bin/env ruby
# frozen_string_literal: true

repo_root = File.expand_path("..", __dir__)
tasks = File.read(File.join(repo_root, "roles/common/tasks/main.yml"))

required_cleanup_paths = [
  ".agents/skills/committing-changes",
  ".agents/skills/review"
]

missing = required_cleanup_paths.reject { |path| tasks.include?(path) }

abort "Missing cleanup for legacy Pi-conflicting skill paths: #{missing.join(', ')}" unless missing.empty?

puts "PASS  Legacy Pi-conflicting skill paths are removed by provisioning"
