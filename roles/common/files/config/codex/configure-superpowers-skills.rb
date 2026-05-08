#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "set"

config_file = ENV.fetch("CONFIG_FILE")
superpowers_root = ENV.fetch("SUPERPOWERS_SKILLS_ROOT")

keep_names = ENV.fetch("KEEP_SUPERPOWERS_SKILLS", "")
  .split(",")
  .map(&:strip)
  .reject(&:empty?)
  .map { |name| name.include?(":") ? name : "superpowers:" + name }
  .to_set
keep_names = Set.new(["superpowers:systematic-debugging", "superpowers:using-git-worktrees"]) if keep_names.empty?

skill_names = Dir.glob(File.join(superpowers_root, "*", "SKILL.md"))
  .select { |path| File.file?(path) }
  .map { |path| "superpowers:" + File.basename(File.dirname(path)) }
  .sort

if skill_names.empty?
  puts "unchanged"
  exit 0
end

managed_names = skill_names.to_set
existing_lines = File.exist?(config_file) ? File.read(config_file).lines : []
filtered_lines = []
index = 0

while index < existing_lines.length
  line = existing_lines[index]
  if line.strip == "[[skills.config]]"
    section = [line]
    index += 1
    while index < existing_lines.length && !existing_lines[index].strip.start_with?("[")
      section << existing_lines[index]
      index += 1
    end

    name = section.filter_map do |section_line|
      match = section_line.strip.match(/^name\s*=\s*"([^"]+)"/)
      match && match[1]
    end.first

    filtered_lines.concat(section) unless name && managed_names.include?(name)
    next
  end

  filtered_lines << line
  index += 1
end

managed_block = []
skill_names.each do |name|
  enabled = keep_names.include?(name) ? "true" : "false"
  managed_block << "[[skills.config]]\n"
  managed_block << "name = " + name.dump + "\n"
  managed_block << "enabled = " + enabled + "\n"
  managed_block << "\n"
end

filtered_lines << "\n" if !filtered_lines.empty? && filtered_lines.last.strip != ""
new_text = (filtered_lines + managed_block).join.sub(/\n+\z/, "\n")
original_text = existing_lines.join

if new_text != original_text
  FileUtils.mkdir_p(File.dirname(config_file))
  File.write(config_file, new_text)
  File.chmod(0o600, config_file)
  puts "changed"
else
  puts "unchanged"
end
