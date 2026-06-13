#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require "open3"

SKIP_PATH_PATTERNS = [
  %r{\Adocs/},
  %r{\A\.coding-agent/},
  %r{\Atests/},
  %r{\Atests/paranoid-package-tools\.rb\z},
  %r{/(default-npm-packages|npmrc)\z}
].freeze

COMMENT_LINE = /\A\s*(#|\/\/)/
NPM_COMMAND = /(^|[;&|({\s"'])(npm|npx)(\s|$)/
AUBE_COMMAND = /(^|[;&|({\s"'])(aube|aubx)(\s|$)/
PARANOID_MODE = /\bAUBE_PARANOID\s*[:=]\s*"?true"?\b/

def command_like_string_literal?(line)
  line.match?(/\A\s*["'][^"']*(npm|npx|aube|aubx)[^"']*["'],?\s*\z/)
end

def metadata_line?(line)
  line.match?(/\A\s*-\s*name:/) ||
    line.match?(/\A\s*#/) ||
    line.include?(".npmrc") ||
    line.include?("default-npm-packages") ||
    line.include?("node_modules/npm") ||
    line.include?("bin/npm") ||
    line.include?("bin/npx") ||
    line.match?(/\baube@\{\{/) ||
    line.match?(/\baube@\d/)
end

def scanned_paths(root)
  if File.exist?(File.join(root, ".git"))
    output, status = Open3.capture2e("git", "-C", root, "ls-files")
    raise "git ls-files failed for #{root}: #{output.strip}" unless status.success?

    output.lines.map(&:chomp)
  else
    Dir.chdir(root) do
      Dir.glob("**/*", File::FNM_DOTMATCH).select { |path| File.file?(path) }
    end
  end
end

def skip_path?(path)
  SKIP_PATH_PATTERNS.any? { |pattern| path.match?(pattern) }
end

def text_file?(path)
  File.open(path, "rb") { |file| !file.read(4096).to_s.include?("\0") }
rescue Errno::ENOENT
  false
end

def paranoid_nearby?(lines, index)
  first = [index - 12, 0].max
  last = [index + 12, lines.length - 1].min

  lines[first..last].any? { |line| line.match?(PARANOID_MODE) }
end

def claude_permission_removal_line?(relative_path, lines, index)
  return false unless relative_path == "roles/common/vars/claude_permissions.yml"

  current_key = lines[0..index].reverse.find { |line| line.match?(/\A[a-zA-Z_]+:/) }
  current_key == "claude_permissions_allow_remove:"
end

def scan_violations(root)
  scanned_paths(root).flat_map do |relative_path|
    next [] if skip_path?(relative_path)

    path = File.join(root, relative_path)
    next [] unless text_file?(path)

    lines = File.readlines(path, chomp: true)

    lines.each_with_index.filter_map do |line, index|
      next if line.match?(COMMENT_LINE)
      next if claude_permission_removal_line?(relative_path, lines, index)
      next if metadata_line?(line)
      next if command_like_string_literal?(line)

      if line.match?(NPM_COMMAND)
        "#{relative_path}:#{index + 1}: npm/npx invocation is not allowed: #{line.strip}"
      elsif line.match?(AUBE_COMMAND) && !paranoid_nearby?(lines, index)
        "#{relative_path}:#{index + 1}: aube/aubx invocation lacks AUBE_PARANOID=true: #{line.strip}"
      end
    end
  end
end

def assert_violation(violations, expected)
  return if violations.any? { |violation| violation.include?(expected) }

  abort "expected violation containing #{expected.inspect}, got:\n#{violations.join("\n")}"
end

Dir.mktmpdir("paranoid-package-tools") do |dir|
  File.write(
    File.join(dir, "bad.sh"),
    "npm install left-pad\n" \
      "npm install npm:package-spec\n" \
      "aube add -g some-tool\n"
  )
  File.write(
    File.join(dir, "good.yml"),
    "- name: Install aube itself\n" \
      "  command: \"{{ mise_bin }} install aube@{{ tool_versions.runtimes.aube }}\"\n" \
      "- name: Install package via paranoid aube\n" \
      "  shell: |\n" \
      "    \"{{ mise_bin }}\" exec node@{{ tool_versions.runtimes.node }} aube -- \\\n" \
      "      aube add -g safe-tool\n" \
      "  environment:\n" \
      "    AUBE_PARANOID: \"true\"\n"
  )
  File.write(
    File.join(dir, "good.sh"),
    "AUBE_PARANOID=true aubx safe-tool@latest\n" \
      "pi install npm:pi-subdir-context\n"
  )

  violations = scan_violations(dir)
  assert_violation(violations, "npm install left-pad")
  assert_violation(violations, "npm install npm:package-spec")
  assert_violation(violations, "aube add -g some-tool")
end

Dir.mktmpdir("paranoid-package-tools-git-failure") do |dir|
  Dir.mkdir(File.join(dir, ".git"))

  begin
    scan_violations(dir)
  rescue RuntimeError => e
    abort "expected git ls-files failure, got #{e.message.inspect}" unless e.message.include?("git ls-files failed")
  else
    abort "expected git ls-files failure"
  end
end

repo_root = File.expand_path("..", __dir__)
violations = scan_violations(repo_root)

if violations.empty?
  puts "PASS  package tool invocations require paranoid mode"
else
  warn "FAIL  package tool invocations require paranoid mode"
  violations.each { |violation| warn "      #{violation}" }
  exit 1
end
