# frozen_string_literal: true

repo_root = File.expand_path("..", __dir__)
tasks = File.read(File.join(repo_root, "roles/common/tasks/main.yml"))
package_task = tasks[/^- name: Link pi-coding-agent.*?(?=^- name: Create ~\/\.local\/bin symlinks)/m]
bin_task = tasks[/^- name: Create ~\/\.local\/bin symlinks.*?(?=^- name: Set Codex CLI)/m]
abort "missing managed Pi package-link task" unless package_task
abort "missing managed Pi local-bin task" unless bin_task

platform_branch = %q{if [[ "{{ ansible_facts['os_family'] }}" == "Darwin" ]]; then}
darwin_bin = 'pi_bin="$pi_root/bin/pi"'
non_darwin_bin = 'pi_bin="$pi_root/node_modules/@earendil-works/pi-coding-agent/dist/cli.js"'
non_darwin_shim = 'pi_bin="$pi_root/node_modules/.bin/pi"'
non_darwin_package = 'PI_PACKAGE_ROOT="$pi_root/node_modules/@earendil-works/pi-coding-agent"'
executable_check = '[[ -x "$pi_bin" ]]'
package_check = 'abort "Managed Pi package root is missing or not a directory: #{package_root}" unless package_root.directory?'
pi_link = 'ln -sf "$pi_bin"'

[package_task, bin_task].each do |task|
  branch_index = task.index(platform_branch)
  darwin_index = task.index(darwin_bin, branch_index || 0)
  else_index = task.index("\n    else\n", darwin_index || 0)
  non_darwin_index = task.index(non_darwin_bin, else_index || 0)
  abort "managed Pi task must use explicit Darwin and non-Darwin branches" unless branch_index && darwin_index && else_index && non_darwin_index && branch_index < darwin_index && darwin_index < else_index && else_index < non_darwin_index
  abort "managed Pi task must not link the relocatable non-Darwin shell shim" if task.include?(non_darwin_shim)
end

abort "package-link task is missing the direct non-Darwin package layout" unless package_task.include?(non_darwin_package)
ruby_platform_index = package_task.index('if ENV.fetch("PI_OS_FAMILY") == "Darwin"')
ruby_darwin_index = package_task.index('pi_bin = Pathname.new(ENV.fetch("PI_BIN")).realpath', ruby_platform_index || 0)
ruby_else_index = package_task.index("\n    else\n", ruby_darwin_index || 0)
ruby_non_darwin_index = package_task.index('Pathname.new(ENV.fetch("PI_PACKAGE_ROOT")).realpath', ruby_else_index || 0)
abort "package-link task must select package resolution by explicit platform" unless ruby_platform_index && ruby_darwin_index && ruby_else_index && ruby_non_darwin_index && ruby_platform_index < ruby_darwin_index && ruby_darwin_index < ruby_else_index && ruby_else_index < ruby_non_darwin_index
abort "Darwin package root must be derived from the resolved executable" unless package_task.include?('pi_bin = Pathname.new(ENV.fetch("PI_BIN")).realpath') && package_task.include?('package_root = pi_bin.dirname.dirname')
abort "non-Darwin package root must resolve the direct package path" unless package_task.include?('Pathname.new(ENV.fetch("PI_PACKAGE_ROOT")).realpath')
abort "managed Pi package root must be validated" unless package_task.include?(package_check)

stale_link_replacement = ["if expected.symlink?", "current = expected.realpath.to_s rescue nil", "expected.delete"]
abort "stale managed package-link replacement must be preserved" unless stale_link_replacement.all? { |fragment| package_task.include?(fragment) }

package_bin_index = package_task.index('export PI_BIN="$pi_bin"')
package_check_index = package_task.index(executable_check, package_bin_index || 0)
ruby_index = package_task.index(%q{"${ruby_cmd[@]}" <<'RUBY'})
abort "package-link task must reject a missing executable before resolving the package" unless package_bin_index && package_check_index && ruby_index && package_check_index < ruby_index

bin_index = bin_task.index(non_darwin_bin)
check_index = bin_task.index(executable_check, bin_index || 0)
link_index = bin_task.index(pi_link, bin_index || 0)
abort "local-bin task must reject a missing executable before linking" unless bin_index && check_index && link_index && check_index < link_index

puts "Pi Aube install layout contract passed"
