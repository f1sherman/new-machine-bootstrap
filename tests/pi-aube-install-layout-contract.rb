# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "shellwords"
require "tmpdir"

repo_root = File.expand_path("..", __dir__)
tasks = File.read(File.join(repo_root, "roles/common/tasks/main.yml"))
package_task = tasks[/^- name: Link pi-coding-agent.*?(?=^- name: Create ~\/\.local\/bin symlinks)/m]
abort "missing managed Pi package-link task" unless package_task

resolver = package_task[/^    pi_package_root=.*?^    export PI_PACKAGE_ROOT$/m]
abort "missing managed Pi package resolver" unless resolver
resolver = resolver.lines.map { |line| line.delete_prefix("    ") }.join

def rendered_resolver(resolver, version, platform)
  resolver
    .gsub("{{ tool_versions.runtimes.pi_coding_agent }}", version)
    .gsub("{{ ansible_facts['os_family'] }}", platform)
end

def run_resolver(resolver, install_root)
  Open3.capture3("bash", "-c", <<~BASH)
    set -euo pipefail
    pi_root=#{Shellwords.escape(install_root)}
    #{resolver}
    printf '%s\n%s\n' "$pi_bin" "$PI_PACKAGE_ROOT"
  BASH
end

Dir.mktmpdir("pi-aube-layout") do |dir|
  version = "0.80.10"
  install_root = File.join(dir, "mise-install")
  package_root = File.join(install_root, "node_modules/@earendil-works/pi-coding-agent")
  pi_bin = File.join(package_root, "dist/cli.js")
  manifest = File.join(package_root, "package.json")
  FileUtils.mkdir_p(File.dirname(pi_bin))
  File.write(pi_bin, "#!/bin/sh\n")
  FileUtils.chmod(0o755, pi_bin)
  rendered = rendered_resolver(resolver, version, "Darwin")

  run_manifest = lambda do |contents|
    File.write(manifest, contents)
    run_resolver(rendered, install_root)
  end

  stdout, stderr, status = run_manifest.call(JSON.generate(
    "name" => "@earendil-works/pi-coding-agent", "version" => version
  ))
  abort "nested package layout failed: #{stderr}" unless status.success?
  abort "nested package layout resolved wrong paths: #{stdout.inspect}" unless stdout == "#{pi_bin}\n#{package_root}\n"

  invalid_manifests = {
    "malformed JSON" => "{not-json",
    "missing name" => JSON.generate("version" => version),
    "non-string name" => JSON.generate("name" => 1, "version" => version),
    "wrong name" => JSON.generate("name" => "other", "version" => version),
    "missing version" => JSON.generate("name" => "@earendil-works/pi-coding-agent"),
    "non-string version" => JSON.generate("name" => "@earendil-works/pi-coding-agent", "version" => 1),
    "wrong version" => JSON.generate("name" => "@earendil-works/pi-coding-agent", "version" => "old")
  }
  invalid_manifests.each do |description, contents|
    _stdout, invalid_stderr, invalid_status = run_manifest.call(contents)
    abort "resolver accepted #{description}" if invalid_status.success?
    abort "resolver omitted manifest path for #{description}" unless invalid_stderr.include?(manifest)
  end
end

Dir.mktmpdir("pi-aube-executable-layout") do |dir|
  version = "0.80.10"
  install_root = File.join(dir, "mise-install")
  package_root = File.join(dir, "aube-store/content/node_modules/@earendil-works/pi-coding-agent")
  pi_bin = File.join(package_root, "dist/cli.js")
  mise_bin = File.join(install_root, "bin/pi")
  FileUtils.mkdir_p(File.dirname(pi_bin))
  FileUtils.mkdir_p(File.dirname(mise_bin))
  File.write(File.join(package_root, "package.json"), JSON.generate(
    "name" => "@earendil-works/pi-coding-agent", "version" => version
  ))
  File.write(pi_bin, "#!/bin/sh\n")
  FileUtils.chmod(0o755, pi_bin)
  FileUtils.ln_s(pi_bin, mise_bin)

  stdout, stderr, status = run_resolver(
    rendered_resolver(resolver, version, "Debian"), install_root
  )
  abort "executable-link layout failed: #{stderr}" unless status.success?
  abort "executable-link layout resolved wrong paths: #{stdout.inspect}" unless stdout == "#{pi_bin}\n#{package_root}\n"
end

puts "Pi Aube install layout behavior passed"
