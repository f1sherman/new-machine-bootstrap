# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "shellwords"
require "tmpdir"
require "yaml"

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

parsed_tasks = YAML.safe_load(tasks, aliases: true)
owner_names = [
  "Check for external Pi runtime ownership",
  "Set Pi runtime ownership",
  "Remove per-Node Pi installs shadowing the managed mise npm tool",
  "Install managed mise npm tools through aube",
  "Repair broken managed Pi installation",
  "Install Pi async runtime dependencies",
  "Link pi-coding-agent into the active mise Node.js global package tree",
  "Create ~/.local/bin symlinks for managed npm tools"
]
selected = owner_names.map do |name|
  parsed_tasks.find { |task| task["name"] == name } || abort("missing runtime owner task: #{name}")
end

[false, true].product(%w[Darwin Debian]).each do |external, platform|
  Dir.mktmpdir("pi-runtime-owner") do |home|
    pi_root = File.join(home, "pi-install")
    package_root = File.join(pi_root, "node_modules/@earendil-works/pi-coding-agent")
    FileUtils.mkdir_p(File.join(package_root, "dist"))
    File.write(File.join(package_root, "package.json"), JSON.generate(
      "name" => "@earendil-works/pi-coding-agent", "version" => "1.0.2"
    ))
    File.write(File.join(package_root, "dist/cli.js"), "#!/bin/sh\nexit 0\n")
    FileUtils.chmod(0o755, File.join(package_root, "dist/cli.js"))
    FileUtils.mkdir_p(File.join(home, ".local/bin"))
    pi = File.join(home, ".local/bin/pi")
    original = "#!/bin/sh\necho external-runtime\n"
    File.write(pi, original)
    marker = File.join(home, ".config/new-machine-bootstrap/external-pi-runtime")
    FileUtils.mkdir_p(File.dirname(marker))
    File.write(marker, "#{package_root}\n") if external
    mise = File.join(home, "mise")
    File.write(mise, <<~SH)
      #!/bin/sh
      printf '%s\\n' "$*" >> "$HOME/invocations"
      case "$*" in
        'where npm:@earendil-works/pi-coding-agent') echo "$HOME/pi-install" ;;
        'where npm:@openai/codex') echo "$HOME/codex-install" ;;
        'exec ruby@3.4.0 -- ruby') exec ruby ;;
      esac
    SH
    FileUtils.chmod(0o755, mise)
    purge_dir = File.join(home, "roles/common/files/bin")
    FileUtils.mkdir_p(purge_dir)
    FileUtils.cp(File.join(repo_root, "roles/common/files/bin/purge-legacy-pi-coding-agent"), purge_dir)
    config = File.join(home, "mise.toml")
    playbook = File.join(home, "playbook.json")
    File.write(playbook, JSON.generate([{
      "hosts" => "localhost", "gather_facts" => false,
      "vars" => {
        "mise_bin" => mise,
        "ansible_facts" => {"user_dir" => home, "os_family" => platform, "env" => {"PATH" => ENV.fetch("PATH")}},
        "tool_versions" => {"runtimes" => {"pi_coding_agent" => "1.0.2", "node" => "22.19.0", "ruby" => "3.4.0", "aube" => "1.0.0"}},
        "common_aube_global_tools_node_path_macos" => {"stdout" => File.join(home, "node")},
        "common_aube_global_tools_node_path_linux" => {"stdout" => File.join(home, "node")}
      },
      "tasks" => selected + [{
        "name" => "Render runtime configuration",
        "ansible.builtin.template" => {"src" => File.join(repo_root, "roles/common/templates/dotfiles/mise/config.toml"), "dest" => config}
      }]
    }]))
    stdout, stderr, status = Open3.capture3(
      {"HOME" => home, "ANSIBLE_NOCOLOR" => "1"},
      "ansible-playbook", "-i", "localhost,", "-c", "local", playbook
    )
    abort "runtime ownership provision failed: #{stdout}\n#{stderr}" unless status.success?
    calls = File.read(File.join(home, "invocations"))
    abort "Codex setup was skipped" unless calls.include?("npm:@openai/codex")
    includes_pi = File.read(config).include?('"npm:@earendil-works/pi-coding-agent"')
    if external
      abort "external Pi launcher was replaced" unless File.read(pi) == original && !File.symlink?(pi)
      abort "external runtime triggered Pi ownership actions" if calls.include?("pi-coding-agent") || calls.include?("pi-server")
      abort "external runtime remained in mise config" if includes_pi
      abort "external runtime was linked into Node" if File.exist?(File.join(home, "node/lib/node_modules/@earendil-works/pi-coding-agent"))
    else
      abort "managed runtime disappeared from mise config" unless includes_pi
      abort "managed launcher was not installed" unless File.realpath(pi) == File.join(package_root, "dist/cli.js")
    end
  end
end

puts "Pi Aube install layout and external runtime ownership behavior passed"
