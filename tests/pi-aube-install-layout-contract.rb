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

primary_package = 'pi_package_root="$pi_root/node_modules/@earendil-works/pi-coding-agent"'
primary_manifest = 'pi_manifest="$pi_package_root/package.json"'
fallback_condition = %q{if [[ ! -f "$pi_manifest" && "{{ ansible_facts['os_family'] }}" != "Darwin" ]]; then}
fallback_launcher = 'pi_launcher="$pi_root/bin/pi"'
manifest_name = %q{pi_name="$(jq -er '.name | select(type == "string")' "$pi_manifest")" || { echo "Managed Pi package manifest is missing a string name: $pi_manifest" >&2; exit 1; }}
manifest_version = %q{pi_version="$(jq -er '.version | select(type == "string")' "$pi_manifest")" || { echo "Managed Pi package manifest is missing a string version: $pi_manifest" >&2; exit 1; }}
manifest_identity = %q{[[ "$pi_name" == '@earendil-works/pi-coding-agent' && "$pi_version" == "{{ tool_versions.runtimes.pi_coding_agent }}" ]]}
direct_bin = 'pi_bin="$pi_package_root/dist/cli.js"'
executable_check = '[[ -x "$pi_bin" ]]'
package_check = 'abort "Managed Pi package root is missing or not a directory: #{package_root}" unless package_root.directory?'
pi_link = 'ln -sf "$pi_bin"'

[package_task, bin_task].each do |task|
  package_index = task.index(primary_package)
  manifest_index = task.index(primary_manifest, package_index || 0)
  fallback_index = task.index(fallback_condition, manifest_index || 0)
  launcher_index = task.index(fallback_launcher, fallback_index || 0)
  name_index = task.index(manifest_name, launcher_index || 0)
  version_index = task.index(manifest_version, name_index || 0)
  identity_index = task.index(manifest_identity, version_index || 0)
  bin_index = task.index(direct_bin, identity_index || 0)
  unless package_index && manifest_index && fallback_index && launcher_index && name_index && version_index && identity_index && bin_index &&
         package_index < manifest_index && manifest_index < fallback_index && fallback_index < launcher_index &&
         launcher_index < name_index && name_index < version_index && version_index < identity_index && identity_index < bin_index
    abort "managed Pi task must validate the shared nested package layout before the Linux-only executable fallback"
  end
  abort "managed Pi task must not query Aube global package state" if task.include?("list --global")
  abort "managed Pi task must not derive the package from an Aube listing" if task.include?("pi_install")
  abort "managed Pi task must not use the Aube node_modules/.bin/pi shim" if task.include?("node_modules/.bin/pi")
end

abort "package-link task must always export the validated package root" unless package_task.include?('PI_PACKAGE_ROOT="$pi_package_root"') && package_task.include?('export PI_PACKAGE_ROOT')
abort "package-link task must resolve the validated package root directly" unless package_task.include?('package_root = Pathname.new(ENV.fetch("PI_PACKAGE_ROOT")).realpath')
abort "package-link task must not derive the package root from the executable" if package_task.include?('package_root = pi_bin.dirname.dirname')
abort "managed Pi package root must be validated" unless package_task.include?(package_check)

stale_link_replacement = ["if expected.symlink?", "current = expected.realpath.to_s rescue nil", "expected.delete"]
abort "stale managed package-link replacement must be preserved" unless stale_link_replacement.all? { |fragment| package_task.include?(fragment) }

package_bin_index = package_task.index('export PI_BIN="$pi_bin"')
package_check_index = package_task.index(executable_check, package_bin_index || 0)
ruby_index = package_task.index(%q{"${ruby_cmd[@]}" <<'RUBY'})
abort "package-link task must reject a missing executable before resolving the package" unless package_bin_index && package_check_index && ruby_index && package_check_index < ruby_index

bin_index = bin_task.index(direct_bin)
check_index = bin_task.index(executable_check, bin_index || 0)
link_index = bin_task.index(pi_link, bin_index || 0)
abort "local-bin task must reject a missing executable before linking" unless bin_index && check_index && link_index && check_index < link_index

primary_resolver = package_task[/^    pi_package_root=.*?^    export PI_PACKAGE_ROOT$/m]
abort "missing shared nested package resolver" unless primary_resolver
primary_resolver = primary_resolver.lines.map { |line| line.delete_prefix("    ") }.join
abort "shared resolver must not query Aube global package state" if primary_resolver.include?("list --global")

Dir.mktmpdir("pi-aube-layout") do |dir|
  version = "0.80.10"
  install_root = File.join(dir, "mise-install")
  package_root = File.join(install_root, "node_modules/@earendil-works/pi-coding-agent")
  pi_bin = File.join(package_root, "dist/cli.js")
  manifest = File.join(package_root, "package.json")
  aube_shim = File.join(install_root, "node_modules/.bin/pi")

  FileUtils.mkdir_p(File.dirname(pi_bin))
  FileUtils.mkdir_p(File.dirname(aube_shim))
  File.write(pi_bin, "#!/bin/sh\n")
  FileUtils.chmod(0o755, pi_bin)
  File.write(aube_shim, "#!/bin/sh\n")
  FileUtils.chmod(0o755, aube_shim)

  resolver = primary_resolver
    .gsub("{{ tool_versions.runtimes.pi_coding_agent }}", version)
    .gsub("{{ ansible_facts['os_family'] }}", "Darwin")
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
  abort "macOS resolver rejected the current Aube layout: #{stderr}" unless status.success?
  expected = "#{pi_bin}\n#{package_root}\n"
  abort "macOS resolver returned the wrong current Aube paths: #{stdout.inspect}" unless stdout == expected

  invalid_metadata = [
    ["missing name", {"version" => version}],
    ["non-string name", {"name" => 1, "version" => version}],
    ["missing version", {"name" => "@earendil-works/pi-coding-agent"}],
    ["non-string version", {"name" => "@earendil-works/pi-coding-agent", "version" => 1}]
  ]
  invalid_metadata.each do |description, metadata|
    _stdout, invalid_stderr, invalid_status = run_resolver.call(metadata)
    abort "macOS resolver accepted #{description} metadata" if invalid_status.success?
    abort "macOS resolver did not report manifest path for #{description}: #{invalid_stderr.inspect}" unless invalid_stderr.include?(manifest)
  end
end

Dir.mktmpdir("pi-aube-executable-layout") do |dir|
  version = "0.80.10"
  install_root = File.join(dir, "mise-install")
  package_root = File.join(dir, "aube-store/content/node_modules/@earendil-works/pi-coding-agent")
  pi_bin = File.join(package_root, "dist/cli.js")
  manifest = File.join(package_root, "package.json")
  mise_bin = File.join(install_root, "bin/pi")

  FileUtils.mkdir_p(File.dirname(pi_bin))
  FileUtils.mkdir_p(File.dirname(mise_bin))
  File.write(manifest, JSON.generate("name" => "@earendil-works/pi-coding-agent", "version" => version))
  File.write(pi_bin, "#!/bin/sh\n")
  FileUtils.chmod(0o755, pi_bin)
  FileUtils.ln_s(pi_bin, mise_bin)

  resolver = primary_resolver
    .gsub("{{ tool_versions.runtimes.pi_coding_agent }}", version)
    .gsub("{{ ansible_facts['os_family'] }}", "Debian")
  script = <<~BASH
    set -euo pipefail
    pi_root=#{Shellwords.escape(install_root)}
    #{resolver}
    printf '%s\n%s\n' "$pi_bin" "$PI_PACKAGE_ROOT"
  BASH
  stdout, stderr, status = Open3.capture3("bash", "-c", script)
  abort "Linux resolver rejected the executable-link layout: #{stderr}" unless status.success?
  expected = "#{pi_bin}\n#{package_root}\n"
  abort "Linux resolver returned the wrong executable-link paths: #{stdout.inspect}" unless stdout == expected
end

puts "Pi Aube install layout contract passed"
