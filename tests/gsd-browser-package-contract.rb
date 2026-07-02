#!/usr/bin/env ruby
# frozen_string_literal: true

repo_root = File.expand_path("..", __dir__)
install_task = File.read(File.join(repo_root, "roles/common/tasks/install_mise_node_global_tools.yml"))
default_packages = File.read(File.join(repo_root, "roles/macos/files/mise/default-npm-packages"))

unless install_task.include?("https://api.github.com/repos/open-gsd/gsd-browser/releases/latest")
  abort "FAIL  gsd-browser install must resolve the upstream GitHub release"
end

unless install_task.include?("https://github.com/open-gsd/gsd-browser/releases/download")
  abort "FAIL  gsd-browser install must download the upstream release binary"
end

if install_task.match?(/aube add .*gsd-browser/) || install_task.include?("@opengsd/gsd-browser@latest")
  abort "FAIL  gsd-browser install must not use npm packages for the native browser CLI"
end

unless install_task.include?("aube remove -g gsd-browser")
  abort "FAIL  gsd-browser install must remove legacy unscoped gsd-browser"
end

unless install_task.include?("mv -f \"$tmp\" \"$node_bin/gsd-browser\"")
  abort "FAIL  gsd-browser install must replace the managed gsd-browser binary"
end

if default_packages.lines.map(&:strip).any? { |line| line.include?("gsd-browser") }
  abort "FAIL  default npm packages must not install any gsd-browser npm package"
end

puts "PASS  gsd-browser package contract targets upstream release binary"
