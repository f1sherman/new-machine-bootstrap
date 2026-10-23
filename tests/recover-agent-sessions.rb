#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

class RecoverAgentSessionsTest < Minitest::Test
  SCRIPT = File.expand_path("../roles/common/files/bin/_recover-agent-sessions", __dir__)

  def test_stalled_summary_returns_session_with_fallback
    Dir.mktmpdir("recover-agent-sessions-test") do |root|
      bin = File.join(root, "bin")
      sessions = File.join(root, "sessions")
      FileUtils.mkdir_p([bin, sessions])

      %w[list-codex-sessions list-claude-sessions].each do |name|
        write_executable(File.join(bin, name), "#!/bin/sh\nprintf '[]\\n'\n")
      end
      codex = File.join(bin, "codex")
      write_executable(codex, "#!/bin/sh\nsleep 4\n")

      session = File.join(sessions, "sample.jsonl")
      File.write(session, [
        { type: "session", id: "sample-session", cwd: root },
        { type: "message", message: { role: "user", content: "Check the result" } }
      ].map { |row| JSON.generate(row) }.join("\n") + "\n")

      env = {
        "PATH" => "#{bin}:#{ENV.fetch('PATH')}",
        "HOME" => root,
        "XDG_CACHE_HOME" => File.join(root, "cache"),
        "RECOVER_AGENT_SESSIONS_PI_SESSION_DIR" => sessions,
        "RECOVER_AGENT_SESSIONS_CODEX_BIN" => codex,
        "RECOVER_AGENT_SESSIONS_SUMMARY_TIMEOUT_SECONDS" => "1"
      }
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, SCRIPT, "2d", "--json")
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      assert status.success?, stderr
      assert_operator elapsed, :<, 3
      entries = JSON.parse(stdout)
      assert_equal 1, entries.length
      assert_equal "sample-session", entries.first.fetch("session_id")
      refute_empty entries.first.fetch("summary")

      managed_bin = File.join(root, ".local", "bin")
      FileUtils.mkdir_p(managed_bin)
      write_executable(File.join(managed_bin, "codex"), <<~SH)
        #!/bin/sh
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "-o" ]; then
            shift
            output="$1"
          fi
          shift
        done
        printf '%s' '{"summary":"Verified result","status":"done","last_completed":"Finished","next_step":"None"}' > "$output"
      SH
      env.delete("RECOVER_AGENT_SESSIONS_CODEX_BIN")
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, SCRIPT, "2d", "--json")
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      assert status.success?, stderr
      assert_operator elapsed, :<, 3
      assert_equal "Verified result", JSON.parse(stdout).first.fetch("summary")
    end
  end

  def test_timeout_kills_descendant_when_launcher_exits_on_term
    Dir.mktmpdir("recover-descendant-test") do |root|
      bin = File.join(root, "bin")
      sessions = File.join(root, "sessions")
      FileUtils.mkdir_p([bin, sessions])
      %w[list-codex-sessions list-claude-sessions].each do |name|
        write_executable(File.join(bin, name), "#!/bin/sh\nprintf '[]\\n'\n")
      end
      pid_file = File.join(root, "child.pid")
      term_file = File.join(root, "launcher-terminated")
      codex = File.join(bin, "codex")
      write_executable(codex, <<~RUBY)
        #!#{RbConfig.ruby}
        Signal.trap("TERM") do
          File.write(#{term_file.inspect}, "terminated")
          exit! 0
        end
        child = fork do
          Signal.trap("TERM", "IGNORE")
          File.write(#{pid_file.inspect}, Process.pid)
          loop { sleep 0.1 }
        end
        Process.wait(child)
      RUBY
      File.write(File.join(sessions, "sample.jsonl"), [
        { type: "session", id: "descendant-session", cwd: root },
        { type: "message", message: { role: "user", content: "Check cleanup" } }
      ].map { |row| JSON.generate(row) }.join("\n") + "\n")
      env = {
        "PATH" => "#{bin}:#{ENV.fetch('PATH')}", "HOME" => root,
        "XDG_CACHE_HOME" => File.join(root, "cache"),
        "RECOVER_AGENT_SESSIONS_PI_SESSION_DIR" => sessions,
        "RECOVER_AGENT_SESSIONS_CODEX_BIN" => codex,
        "RECOVER_AGENT_SESSIONS_SUMMARY_TIMEOUT_SECONDS" => "1"
      }
      child_pid = nil
      begin
        stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, SCRIPT, "2d", "--json")
        assert status.success?, stderr
        assert File.exist?(pid_file), "descendant did not become ready"
        child_pid = Integer(File.read(pid_file))
        assert File.exist?(term_file), "launcher did not exit on TERM"
        assert_equal "descendant-session", JSON.parse(stdout).first.fetch("session_id")
        refute_empty JSON.parse(stdout).first.fetch("summary")
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
        while process_alive?(child_pid) && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
          sleep 0.02
        end
        refute process_alive?(child_pid), "TERM-resistant descendant survived its launcher"
      ensure
        child_pid ||= Integer(File.read(pid_file)) if File.exist?(pid_file)
        begin
          Process.kill("KILL", child_pid) if child_pid
        rescue Errno::ESRCH
          nil
        end
      end
    end
  end

  private

  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def write_executable(path, content)
    File.write(path, content)
    File.chmod(0o755, path)
  end
end
