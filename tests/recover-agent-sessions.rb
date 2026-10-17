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

  private

  def write_executable(path, content)
    File.write(path, content)
    File.chmod(0o755, path)
  end
end
