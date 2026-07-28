# frozen_string_literal: true

require "fileutils"
require "open3"
require "shellwords"
require "tmpdir"

repo_root = File.expand_path("..", __dir__)
tasks = File.read(File.join(repo_root, "roles/common/tasks/main.yml"))
package_task = tasks[/^- name: Link pi-coding-agent.*?(?=^- name: Create ~\/\.local\/bin symlinks)/m]
bin_task = tasks[/^- name: Create ~\/\.local\/bin symlinks.*?(?=^- name: Set Codex CLI)/m]
abort "missing managed Pi package-link task" unless package_task
abort "missing managed Pi local-bin task" unless bin_task

platform_branch = %q{if [[ "{{ ansible_facts['os_family'] }}" == "Darwin" ]]; then}
darwin_bin = 'pi_bin="$pi_root/bin/pi"'
non_darwin_listing = 'list --global --parseable \'@earendil-works/pi-coding-agent\''
non_darwin_bin = 'pi_bin="$PI_PACKAGE_ROOT/dist/cli.js"'
non_darwin_local_bin = 'pi_bin="$pi_package_root/dist/cli.js"'
non_darwin_shim = 'pi_bin="$pi_root/bin/pi"'
invalid_non_darwin_bin = 'pi_bin="$pi_root/node_modules/@earendil-works/pi-coding-agent/dist/cli.js"'
non_darwin_package = 'PI_PACKAGE_ROOT="$pi_listing"'
aube_executable_check = '[[ -x "$aube_bin" ]]'
listing_cardinality_check = %q{[[ -n "$pi_listing" && "$pi_listing" != *$'\n'* ]]}
listing_identity_check = %q{[[ "$pi_name" == '@earendil-works/pi-coding-agent' && "$pi_version" == "{{ tool_versions.runtimes.pi_coding_agent }}" ]]}
executable_check = '[[ -x "$pi_bin" ]]'
package_check = 'abort "Managed Pi package root is missing or not a directory: #{package_root}" unless package_root.directory?'
pi_link = 'ln -sf "$pi_bin"'

[package_task, bin_task].each_with_index do |task, index|
  branch_index = task.index(platform_branch)
  darwin_index = task.index(darwin_bin, branch_index || 0)
  else_index = task.index("\n    else\n", darwin_index || 0)
  listing_index = task.index(non_darwin_listing, else_index || 0)
  expected_bin = index.zero? ? non_darwin_bin : non_darwin_local_bin
  non_darwin_index = task.index(expected_bin, listing_index || 0)
  abort "managed Pi task must use explicit Darwin and non-Darwin Aube layouts" unless branch_index && darwin_index && else_index && listing_index && non_darwin_index && branch_index < darwin_index && darwin_index < else_index && else_index < listing_index && listing_index < non_darwin_index
  abort "managed Pi task must not link the relocatable non-Darwin shell shim" if task.index(non_darwin_shim, else_index || 0)
  abort "managed Pi task must not assume packages live directly under the mise install root" if task.include?(invalid_non_darwin_bin)
  abort "managed Pi task must validate the Aube executable" unless task.include?(aube_executable_check)
  abort "managed Pi task must require exactly one Aube package listing" unless task.include?(listing_cardinality_check)
  abort "managed Pi task must validate the listed package identity and version" unless task.include?(listing_identity_check)
end

abort "package-link task is missing the Aube-listed non-Darwin package layout" unless package_task.include?(non_darwin_package)
abort "package-link task must export the Aube-listed package root" unless package_task.include?('export PI_PACKAGE_ROOT')
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

bin_index = bin_task.index(non_darwin_local_bin)
check_index = bin_task.index(executable_check, bin_index || 0)
link_index = bin_task.index(pi_link, bin_index || 0)
abort "local-bin task must reject a missing executable before linking" unless bin_index && check_index && link_index && check_index < link_index

non_darwin_parser = package_task[/^      pi_listing=.*?^      export PI_PACKAGE_ROOT$/m]
abort "missing non-Darwin Aube listing parser" unless non_darwin_parser
non_darwin_parser = non_darwin_parser.lines.map { |line| line.delete_prefix("      ") }.join

Dir.mktmpdir("pi-aube-layout") do |dir|
  version = "0.80.10"
  install_root = File.join(dir, "global-aube", "install")
  package_root = File.join(install_root, "node_modules/@earendil-works/pi-coding-agent")
  pi_bin = File.join(package_root, "dist/cli.js")
  aube_bin = File.join(dir, "aube")

  FileUtils.mkdir_p(File.dirname(pi_bin))
  File.write(pi_bin, "#!/bin/sh\n")
  FileUtils.chmod(0o755, pi_bin)
  File.write(File.join(package_root, "package.json"), %({"name":"@earendil-works/pi-coding-agent","version":"#{version}"}))
  File.write(aube_bin, "#!/bin/sh\nprintf '%s\\n' #{Shellwords.escape(package_root)}\n")
  FileUtils.chmod(0o755, aube_bin)

  parser = non_darwin_parser.gsub("{{ tool_versions.runtimes.pi_coding_agent }}", version)
  script = <<~BASH
    set -euo pipefail
    pi_root=#{Shellwords.escape(dir)}
    aube_bin=#{Shellwords.escape(aube_bin)}
    #{parser}
    printf '%s\\n%s\\n' "$pi_bin" "$PI_PACKAGE_ROOT"
  BASH
  stdout, stderr, status = Open3.capture3("bash", "-c", script)
  abort "non-Darwin parser rejected Aube global parseable output: #{stderr}" unless status.success?
  expected = "#{pi_bin}\n#{package_root}\n"
  abort "non-Darwin parser resolved the wrong Aube paths: #{stdout.inspect}" unless stdout == expected
end

puts "Pi Aube install layout contract passed"
