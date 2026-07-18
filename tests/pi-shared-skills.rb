#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

repo_root = File.expand_path("..", __dir__)
skills_root = File.join(repo_root, "roles/common/files/config/skills")
pi_root = File.join(skills_root, "pi")

source_skill_dirs = Dir.chdir(skills_root) do
  Dir.glob("{common,claude,codex}/*").select { |path| File.directory?(path) }
end
expected_pi_names = source_skill_dirs.map do |path|
  "z-#{File.basename(path).sub(/^_/, "")}"
end.uniq.sort
actual_pi_names = Dir.children(pi_root).select { |name| File.directory?(File.join(pi_root, name)) }.sort

legacy_pi_names = expected_pi_names.map { |name| name.delete_prefix("z-") }.reject { |name| name == "quick-pr" }
tasks_file = File.read(File.join(repo_root, "roles/common/tasks/main.yml"))
claude_cleanup_block = tasks_file[/^- name: Remove deleted managed Claude skills\n.*?(?=^- name:)/m]
codex_cleanup_block = tasks_file[/^- name: Remove deleted managed Codex skills\n.*?(?=^- name:)/m]
pi_cleanup_block = tasks_file[/^- name: Remove deleted managed Pi skills\n.*?(?=^- name:)/m]
abort "Missing managed Claude skill cleanup task" unless claude_cleanup_block
abort "Missing managed Codex skill cleanup task" unless codex_cleanup_block
abort "Missing managed Pi skill cleanup task" unless pi_cleanup_block

missing_cleanup_names = legacy_pi_names.reject do |name|
  pi_cleanup_block.match?(/^    - #{Regexp.escape(name)}$/)
end
abort "Managed Pi cleanup task is missing old names: #{missing_cleanup_names.inspect}" unless missing_cleanup_names.empty?
abort "Pi cleanup must not remove unmanaged quick-pr" if pi_cleanup_block.match?(/^    - quick-pr$/)

abort "Pi shared skills do not match z-prefixed Claude/Codex/common counterparts\nExpected: #{expected_pi_names.inspect}\nActual:   #{actual_pi_names.inspect}" unless actual_pi_names == expected_pi_names

actual_pi_names.each do |name|
  abort "Pi skill name must start with z-: #{name}" unless name.start_with?("z-")

  skill_file = File.join(pi_root, name, "SKILL.md")
  abort "Missing SKILL.md for #{name}" unless File.file?(skill_file)

  contents = File.read(skill_file)
  frontmatter = contents[/\A---\n(.*?)\n---\n/m, 1]
  abort "Missing YAML frontmatter for #{name}" unless frontmatter

  metadata = YAML.safe_load(frontmatter)
  abort "Frontmatter name for #{name} must equal directory name, got #{metadata["name"].inspect}" unless metadata["name"] == name
  abort "Pi skill frontmatter name must start with z-: #{name}" unless metadata["name"].start_with?("z-")
end

quick_pr_file = File.join(pi_root, "z-quick-pr", "SKILL.md")
quick_pr_contents = File.read(quick_pr_file)
abort "Pi z-quick-pr must return from writing-plans to z-quick-pr" unless quick_pr_contents.include?("return directly to `z-quick-pr`")
abort "Pi z-quick-pr must not return from writing-plans to old spec-to-pr names" if quick_pr_contents.match?(/return directly to `(?:z-)?spec-to-pr`/)

abort "Old common _spec-to-pr skill directory still exists" if Dir.exist?(File.join(skills_root, "common", "_spec-to-pr"))
abort "Old Pi z-spec-to-pr skill directory still exists" if Dir.exist?(File.join(pi_root, "z-spec-to-pr"))

%w[_spec-to-pr].each do |name|
  abort "Claude cleanup is missing #{name}" unless claude_cleanup_block.match?(/^    - #{Regexp.escape(name)}$/)
  abort "Codex cleanup is missing #{name}" unless codex_cleanup_block.match?(/^    - #{Regexp.escape(name)}$/)
end

%w[spec-to-pr z-spec-to-pr].each do |name|
  abort "Pi cleanup is missing #{name}" unless pi_cleanup_block.match?(/^    - #{Regexp.escape(name)}$/)
end

commit_helper = File.join(pi_root, "z-commit", "commit.sh")
abort "Missing Pi commit helper" unless File.file?(commit_helper)
abort "Pi commit helper must be executable" unless File.executable?(commit_helper)

puts "PASS  z-prefixed Pi skills mirror NMB Claude/Codex/common skill counterparts"
