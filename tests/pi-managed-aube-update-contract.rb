#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"
require "yaml"

def resolve_mise_bin
  candidates = [
    ENV["MISE_BIN"],
    File.join(Dir.home, ".local/bin/mise"),
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, "mise") }
  ].flatten.compact

  candidates.find { |candidate| File.executable?(candidate) } || abort("FAIL  could not resolve provisioned mise binary")
end

repo_root = File.expand_path("..", __dir__)
tool_versions_path = File.join(repo_root, "vars/tool_versions.yml")
mise_template_path = File.join(repo_root, "roles/common/templates/dotfiles/mise/config.toml")
zshenv_template_path = File.join(repo_root, "roles/common/templates/dotfiles/zshenv.d/10-common-env.zsh")

tool_versions_text = File.read(tool_versions_path)
tool_versions = YAML.safe_load(tool_versions_text).fetch("tool_versions")
pi_version = tool_versions.fetch("runtimes").fetch("pi_coding_agent")
mise_bin = resolve_mise_bin

unless tool_versions_text.match?(%r{# renovate: datasource=npm depName=@earendil-works/pi-coding-agent\s+pi_coding_agent:})
  abort "FAIL  Renovate must keep managing the pinned Pi npm version"
end

mise_template = File.read(mise_template_path)
rendered_mise = mise_template
  .gsub("{{ tool_versions.runtimes.node }}", tool_versions.fetch("runtimes").fetch("node"))
  .gsub("{{ tool_versions.runtimes.ruby }}", tool_versions.fetch("runtimes").fetch("ruby"))
  .gsub("{{ tool_versions.runtimes.aube }}", tool_versions.fetch("runtimes").fetch("aube"))
  .gsub("{{ tool_versions.runtimes.pi_coding_agent }}", pi_version)
  .gsub("{{ ansible_facts['user_dir'] }}", Dir.home)

Dir.mktmpdir("pi-managed-aube-contract") do |dir|
  File.write(File.join(dir, "mise.toml"), rendered_mise)

  env = { "MISE_TRUSTED_CONFIG_PATHS" => dir }
  pi_config_output, pi_status = Open3.capture2e(env, mise_bin, "-C", dir, "config", "get", "tools.npm:@earendil-works/pi-coding-agent")
  abort "FAIL  mise could not parse rendered Pi config:\n#{pi_config_output}" unless pi_status.success?

  parsed_pi_config = pi_config_output.lines.each_with_object({}) do |line, config|
    case line
    when /\Aversion\s*=\s*"([^"]+)"/
      config[:version] = Regexp.last_match(1)
    when /\Adepends\s*=\s*\[(.*)\]/
      config[:depends] = Regexp.last_match(1).scan(/"([^"]+)"/).flatten
    end
  end

  unless parsed_pi_config[:version] == pi_version && parsed_pi_config[:depends]&.include?("aube")
    abort "FAIL  rendered mise config must pin Pi #{pi_version.inspect} with an aube dependency, got #{parsed_pi_config.inspect}"
  end

  package_manager_output, package_manager_status = Open3.capture2e(env, mise_bin, "-C", dir, "config", "get", "settings.npm.package_manager")
  abort "FAIL  mise could not parse npm package manager setting:\n#{package_manager_output}" unless package_manager_status.success?
  abort "FAIL  mise npm package manager must be aube" unless package_manager_output.strip == "aube"

  zdotdir = File.join(dir, "zdotdir")
  Dir.mkdir(zdotdir)
  File.write(File.join(zdotdir, ".zshenv"), File.read(zshenv_template_path))
  zsh_output, zsh_status = Open3.capture2e({ "ZDOTDIR" => zdotdir, "ZSH_ENV_LOADED" => "1" }, "zsh", "-lc", "print -r -- ${PI_SKIP_VERSION_CHECK:-}")
  abort "FAIL  zshenv fragment did not execute cleanly:\n#{zsh_output}" unless zsh_status.success?
  abort "FAIL  zshenv must set PI_SKIP_VERSION_CHECK before the loaded guard" unless zsh_output.strip == "1"
end

puts "PASS  Pi remains mise/aube-managed while suppressing update nags"
