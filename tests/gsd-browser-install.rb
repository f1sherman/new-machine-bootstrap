#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"
require "yaml"

repo_root = File.expand_path("..", __dir__)
tasks = YAML.safe_load_file(
  File.join(repo_root, "roles/common/tasks/install_mise_node_global_tools.yml")
)
install_task = tasks.find do |task|
  task["name"] == "Install or update gsd-browser release binary"
end
abort "missing gsd-browser install task" unless install_task

run_install = lambda do |installed_version:, curl_allowed:|
  Dir.mktmpdir("gsd-browser-install") do |dir|
    node_root = File.join(dir, "node")
    node_bin = File.join(node_root, "bin")
    fake_bin = File.join(dir, "fake-bin")
    FileUtils.mkdir_p([node_bin, fake_bin])

    mise = File.join(fake_bin, "mise")
    File.write(mise, <<~SH)
      #!/bin/sh
      if [ "$5" = "aube" ] && [ "$6" = "list" ]; then
        printf '[]\\n'
        exit 0
      fi
      exit 1
    SH
    FileUtils.chmod(0o755, mise)

    browser = File.join(node_bin, "gsd-browser")
    File.write(browser, <<~SH)
      #!/bin/sh
      printf 'gsd-browser #{installed_version}\\n'
    SH
    FileUtils.chmod(0o755, browser)

    curl = File.join(fake_bin, "curl")
    File.write(curl, <<~SH)
      #!/bin/bash
      set -euo pipefail
      #{curl_allowed ? "" : "echo 'curl must not run' >&2; exit 90"}
      args=" $* "
      [[ "$args" == *" --retry 5 "* ]] || exit 91
      [[ "$args" == *" --retry-all-errors "* ]] || exit 92
      [[ "$args" == *" --retry-max-time 120 "* ]] || exit 93
      output=""
      url=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          -o) output="$2"; shift 2 ;;
          -*) shift ;;
          *) url="$1"; shift ;;
        esac
      done
      expected="https://github.com/open-gsd/gsd-browser/releases/download/v0.2.1/gsd-browser-linux-x64"
      [ "$url" = "$expected" ] || exit 94
      cat > "$output" <<'BINARY'
      #!/bin/sh
      printf 'gsd-browser 0.2.1\\n'
      BINARY
    SH
    FileUtils.chmod(0o755, curl)

    uname = File.join(fake_bin, "uname")
    File.write(uname, <<~SH)
      #!/bin/sh
      case "$1" in
        -s) printf 'Linux\\n' ;;
        -m) printf 'x86_64\\n' ;;
        *) exit 1 ;;
      esac
    SH
    FileUtils.chmod(0o755, uname)

    shell = install_task.fetch("shell")
      .gsub("{{ mise_node_global_tools_node_path.stdout }}", node_root)
      .gsub("{{ mise_bin }}", mise)
      .gsub("{{ tool_versions.runtimes.node }}", "24.19.0")
      .gsub("{{ tool_versions.runtimes.gsd_browser }}", "0.2.1")

    stdout, stderr, status = Open3.capture3(
      {"PATH" => "#{fake_bin}:/usr/bin:/bin"},
      "/bin/bash", "-c", shell
    )
    unless status.success?
      abort "gsd-browser install failed (#{status.exitstatus}): #{stdout}#{stderr}"
    end

    [browser, File.read(browser)]
  end
end

_matching_path, matching_contents = run_install.call(
  installed_version: "0.2.1", curl_allowed: false
)
unless matching_contents.include?("gsd-browser 0.2.1")
  abort "matching gsd-browser was replaced"
end

_outdated_path, outdated_contents = run_install.call(
  installed_version: "0.1.0", curl_allowed: true
)
unless outdated_contents.include?("gsd-browser 0.2.1")
  abort "outdated gsd-browser was not replaced"
end

puts "gsd-browser install behavior passed"
