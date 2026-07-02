#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"
require "yaml"

repo_root = File.expand_path("..", __dir__)
task_path = File.join(repo_root, "roles/common/tasks/install_mise_node_global_tools.yml")
default_packages_path = File.join(repo_root, "roles/macos/files/mise/default-npm-packages")

tasks = YAML.safe_load_file(task_path)
install_task = tasks.find { |task| task["name"] == "Install or update gsd-browser release binary" }
abort "FAIL  missing gsd-browser release install task" unless install_task

shell = install_task.fetch("shell")

Dir.mktmpdir("gsd-browser-contract") do |dir|
  node_root = File.join(dir, "node")
  node_bin = File.join(node_root, "bin")
  fake_bin = File.join(dir, "bin")
  state_dir = File.join(dir, "state")
  FileUtils.mkdir_p([node_bin, fake_bin, state_dir])

  mise_path = File.join(fake_bin, "mise")
  File.write(mise_path, <<~BASH)
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "${1:-}" = "exec" ] && [ "${3:-}" = "aube" ] && [ "${4:-}" = "--" ] && [ "${5:-}" = "aube" ]; then
      shift 5
      case "${1:-}" in
        list)
          printf '[{"name":"gsd-browser","version":"0.9.1"}]\\n'
          ;;
        remove)
          [ "${2:-}" = "-g" ] && [ "${3:-}" = "gsd-browser" ] || exit 9
          touch "#{state_dir}/removed-legacy"
          ;;
        *)
          exit 10
          ;;
      esac
    else
      exit 11
    fi
  BASH
  File.chmod(0o755, mise_path)

  File.write(File.join(fake_bin, "curl"), <<~BASH)
    #!/usr/bin/env bash
    set -euo pipefail
    output=""
    url=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -o) output="$2"; shift 2 ;;
        -*) shift ;;
        *) url="$1"; shift ;;
      esac
    done
    case "$url" in
      https://api.github.com/repos/open-gsd/gsd-browser/releases/latest)
        printf '{"tag_name":"v9.8.7"}\\n'
        ;;
      https://github.com/open-gsd/gsd-browser/releases/download/v9.8.7/gsd-browser-linux-x64)
        printf 'release-binary\\n' > "$output"
        ;;
      *)
        echo "unexpected curl URL: $url" >&2
        exit 12
        ;;
    esac
  BASH
  File.chmod(0o755, File.join(fake_bin, "curl"))

  File.write(File.join(fake_bin, "uname"), <<~BASH)
    #!/usr/bin/env bash
    case "${1:-}" in
      -s) printf 'Linux\\n' ;;
      -m) printf 'x86_64\\n' ;;
      *) /usr/bin/uname "$@" ;;
    esac
  BASH
  File.chmod(0o755, File.join(fake_bin, "uname"))

  rendered_shell = shell
    .gsub("{{ mise_node_global_tools_node_path.stdout }}", node_root)
    .gsub("{{ mise_bin }}", mise_path)
    .gsub("{{ tool_versions.runtimes.node }}", "24.18.0")

  env = { "PATH" => "#{fake_bin}:#{ENV.fetch("PATH")}" }
  output, status = Open3.capture2e(env, "bash", "-c", rendered_shell)
  abort "FAIL  release install shell failed:\n#{output}" unless status.success?

  installed_binary = File.join(node_bin, "gsd-browser")
  unless File.executable?(installed_binary) && File.read(installed_binary) == "release-binary\n"
    abort "FAIL  release install shell did not install the downloaded gsd-browser binary"
  end

  unless File.exist?(File.join(state_dir, "removed-legacy"))
    abort "FAIL  release install shell did not remove the legacy unscoped gsd-browser package"
  end
end

default_packages = File.read(default_packages_path)
if default_packages.lines.map(&:strip).any? { |line| line.include?("gsd-browser") }
  abort "FAIL  default npm packages must not install any gsd-browser npm package"
end

puts "PASS  gsd-browser package contract executes release-binary install path"
