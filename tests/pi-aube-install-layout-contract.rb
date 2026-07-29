# frozen_string_literal: true

require "fileutils"
require "json"
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
non_darwin_bin = 'pi_bin="$(realpath "$pi_root/bin/pi")"'
non_darwin_package = 'pi_package_root="$(dirname "$(dirname "$pi_bin")")"'
non_darwin_manifest = 'pi_manifest="$pi_package_root/package.json"'
non_darwin_name = %q{pi_name="$(jq -er '.name | select(type == "string")' "$pi_manifest")" || { echo "Managed Pi package manifest is missing a string name: $pi_manifest" >&2; exit 1; }}
non_darwin_version = %q{pi_version="$(jq -er '.version | select(type == "string")' "$pi_manifest")" || { echo "Managed Pi package manifest is missing a string version: $pi_manifest" >&2; exit 1; }}
non_darwin_identity = %q{[[ "$pi_name" == '@earendil-works/pi-coding-agent' && "$pi_version" == "{{ tool_versions.runtimes.pi_coding_agent }}" ]]}
non_darwin_shim = 'pi_bin="$pi_root/bin/pi"'
executable_check = '[[ -x "$pi_bin" ]]'
package_check = 'abort "Managed Pi package root is missing or not a directory: #{package_root}" unless package_root.directory?'
pi_link = 'ln -sf "$pi_bin"'

[package_task, bin_task].each do |task|
  branch_index = task.index(platform_branch)
  darwin_index = task.index(darwin_bin, branch_index || 0)
  else_index = task.index("\n    else\n", darwin_index || 0)
  bin_index = task.index(non_darwin_bin, else_index || 0)
  package_index = task.index(non_darwin_package, bin_index || 0)
  manifest_index = task.index(non_darwin_manifest, package_index || 0)
  name_index = task.index(non_darwin_name, manifest_index || 0)
  version_index = task.index(non_darwin_version, name_index || 0)
  identity_index = task.index(non_darwin_identity, version_index || 0)
  unless branch_index && darwin_index && else_index && bin_index && package_index && manifest_index && name_index && version_index && identity_index &&
         branch_index < darwin_index && darwin_index < else_index && else_index < bin_index && bin_index < package_index &&
         package_index < manifest_index && manifest_index < name_index && name_index < version_index && version_index < identity_index
    abort "managed Pi task must resolve and validate the non-Darwin package through mise's executable link"
  end
  abort "managed Pi task must not query Aube global package state" if task.include?("list --global")
  abort "managed Pi task must not derive the package from an Aube listing" if task.include?("pi_install")
  abort "managed Pi task must not link the relocatable non-Darwin shell shim" if task.index(non_darwin_shim, else_index || 0)
end

abort "package-link task must export the resolved package root" unless package_task.include?('PI_PACKAGE_ROOT="$pi_package_root"') && package_task.include?('export PI_PACKAGE_ROOT')
ruby_platform_index = package_task.index('if ENV.fetch("PI_OS_FAMILY") == "Darwin"')
ruby_darwin_index = package_task.index('pi_bin = Pathname.new(ENV.fetch("PI_BIN")).realpath', ruby_platform_index || 0)
ruby_else_index = package_task.index("\n    else\n", ruby_darwin_index || 0)
ruby_non_darwin_index = package_task.index('Pathname.new(ENV.fetch("PI_PACKAGE_ROOT")).realpath', ruby_else_index || 0)
abort "package-link task must select package resolution by explicit platform" unless ruby_platform_index && ruby_darwin_index && ruby_else_index && ruby_non_darwin_index && ruby_platform_index < ruby_darwin_index && ruby_darwin_index < ruby_else_index && ruby_else_index < ruby_non_darwin_index
abort "Darwin package root must be derived from the resolved executable" unless package_task.include?('pi_bin = Pathname.new(ENV.fetch("PI_BIN")).realpath') && package_task.include?('package_root = pi_bin.dirname.dirname')
abort "non-Darwin package root must resolve the executable's package path" unless package_task.include?('Pathname.new(ENV.fetch("PI_PACKAGE_ROOT")).realpath')
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

resolver_start = package_task.index("      #{non_darwin_bin}")
resolver_end = package_task.index("      export PI_PACKAGE_ROOT", resolver_start || 0)
abort "missing non-Darwin executable resolver" unless resolver_start && resolver_end
resolver_end += "      export PI_PACKAGE_ROOT".length
non_darwin_resolver = package_task[resolver_start...resolver_end]
non_darwin_resolver = non_darwin_resolver.lines.map { |line| line.delete_prefix("      ") }.join
abort "non-Darwin resolver must not query Aube global package state" if non_darwin_resolver.include?("list --global")

Dir.mktmpdir("pi-aube-layout") do |dir|
  version = "0.80.10"
  install_root = File.join(dir, "mise-install")
  package_root = File.join(dir, "aube-store/content/node_modules/@earendil-works/pi-coding-agent")
  pi_bin = File.join(package_root, "dist/cli.js")
  manifest = File.join(package_root, "package.json")
  mise_bin = File.join(install_root, "bin/pi")

  FileUtils.mkdir_p(File.dirname(pi_bin))
  FileUtils.mkdir_p(File.dirname(mise_bin))
  File.write(pi_bin, "#!/bin/sh\n")
  FileUtils.chmod(0o755, pi_bin)
  FileUtils.ln_s(pi_bin, mise_bin)

  resolver = non_darwin_resolver.gsub("{{ tool_versions.runtimes.pi_coding_agent }}", version)
  run_resolver = lambda do |metadata|
    File.write(manifest, JSON.generate(metadata))
    script = <<~BASH
      set -euo pipefail
      pi_root=#{Shellwords.escape(install_root)}
      #{resolver}
      printf '%s\n%s\n' "$pi_bin" "$PI_PACKAGE_ROOT"
    BASH
    Open3.capture3("bash", "-c", script)
  end

  stdout, stderr, status = run_resolver.call("name" => "@earendil-works/pi-coding-agent", "version" => version)
  abort "non-Darwin resolver rejected the mise executable link: #{stderr}" unless status.success?
  expected = "#{pi_bin}\n#{package_root}\n"
  abort "non-Darwin resolver returned the wrong resolved paths: #{stdout.inspect}" unless stdout == expected

  invalid_metadata = [
    ["missing name", {"version" => version}],
    ["non-string name", {"name" => 1, "version" => version}],
    ["missing version", {"name" => "@earendil-works/pi-coding-agent"}],
    ["non-string version", {"name" => "@earendil-works/pi-coding-agent", "version" => 1}]
  ]
  invalid_metadata.each do |description, metadata|
    _stdout, invalid_stderr, invalid_status = run_resolver.call(metadata)
    abort "non-Darwin resolver accepted #{description} metadata" if invalid_status.success?
    abort "non-Darwin resolver did not report manifest path for #{description}: #{invalid_stderr.inspect}" unless invalid_stderr.include?(manifest)
  end
end

puts "Pi Aube install layout contract passed"
