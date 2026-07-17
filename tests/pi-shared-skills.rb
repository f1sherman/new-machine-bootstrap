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

legacy_pi_names = expected_pi_names.map { |name| name.delete_prefix("z-") }
tasks_file = File.read(File.join(repo_root, "roles/common/tasks/main.yml"))
cleanup_block = tasks_file[/^- name: Remove deleted managed Pi skills\n.*?(?=^- name:)/m]
abort "Missing managed Pi skill cleanup task" unless cleanup_block

missing_cleanup_names = legacy_pi_names.reject do |name|
  cleanup_block.match?(/^    - #{Regexp.escape(name)}$/)
end
abort "Managed Pi cleanup task is missing old names: #{missing_cleanup_names.inspect}" unless missing_cleanup_names.empty?

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

commit_helper = File.join(pi_root, "z-commit", "commit.sh")
abort "Missing Pi commit helper" unless File.file?(commit_helper)
abort "Pi commit helper must be executable" unless File.executable?(commit_helper)

puts "PASS  z-prefixed Pi skills mirror NMB Claude/Codex/common skill counterparts"
