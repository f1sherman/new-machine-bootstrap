#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

repo_root = File.expand_path("..", __dir__)
skills_root = File.join(repo_root, "roles/common/files/config/skills")
pi_root = File.join(skills_root, "pi")

source_skill_dirs = Dir.chdir(skills_root) do
  Dir.glob("{common,claude,codex}/*").select { |path| File.directory?(path) }
end
expected_pi_names = source_skill_dirs.map { |path| File.basename(path).sub(/^_/, "") }.uniq.sort
actual_pi_names = Dir.children(pi_root).select { |name| File.directory?(File.join(pi_root, name)) }.sort

abort "Pi shared skills do not match Claude/Codex/common counterparts\nExpected: #{expected_pi_names.inspect}\nActual:   #{actual_pi_names.inspect}" unless actual_pi_names == expected_pi_names

actual_pi_names.each do |name|
  abort "Pi skill name must not start with underscore: #{name}" if name.start_with?("_")

  skill_file = File.join(pi_root, name, "SKILL.md")
  abort "Missing SKILL.md for #{name}" unless File.file?(skill_file)

  contents = File.read(skill_file)
  frontmatter = contents[/\A---\n(.*?)\n---\n/m, 1]
  abort "Missing YAML frontmatter for #{name}" unless frontmatter

  metadata = YAML.safe_load(frontmatter)
  abort "Frontmatter name for #{name} must equal directory name, got #{metadata["name"].inspect}" unless metadata["name"] == name
  abort "Pi skill frontmatter name must not start with underscore: #{name}" if metadata["name"].start_with?("_")
end

commit_helper = File.join(pi_root, "commit", "commit.sh")
abort "Missing Pi commit helper" unless File.file?(commit_helper)
abort "Pi commit helper must be executable" unless File.executable?(commit_helper)

puts "PASS  Pi shared skills mirror NMB Claude/Codex/common skill counterparts"
