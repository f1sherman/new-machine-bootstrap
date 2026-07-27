#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "timeout"
require "tmpdir"

REPO_ROOT = File.expand_path("..", __dir__)
RESTORE_EXTRA = File.join(REPO_ROOT, "roles/common/files/bin/tmux-resurrect-restore-extra")

class TmuxResurrectRestoreExtraTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("tmux-resurrect-restore-extra")
    @home = File.join(@tmpdir, "home")
    @bin = File.join(@tmpdir, "bin")
    @resurrect_dir = File.join(@home, ".tmux", "resurrect")
    @state_file = File.join(@resurrect_dir, "snapshot.txt")
    @sidecar = "#{@state_file}.meta.json"
    @log = File.join(@resurrect_dir, "restore-extra.log")
    @slow_started = File.join(@tmpdir, "slow-started")
    @slow_completed = File.join(@tmpdir, "slow-completed")
    @fast_started = File.join(@tmpdir, "fast-started")
    @failed_started = File.join(@tmpdir, "failed-started")
    FileUtils.mkdir_p([@bin, @resurrect_dir])
    File.write(@state_file, "snapshot\n")
    File.symlink(File.basename(@state_file), File.join(@resurrect_dir, "last"))
    write_fake_tmux
    @env = {
      "HOME" => @home,
      "PATH" => "#{@bin}:#{ENV.fetch("PATH")}",
      "SLOW_STARTED" => @slow_started,
      "SLOW_COMPLETED" => @slow_completed,
      "FAST_STARTED" => @fast_started,
      "FAILED_STARTED" => @failed_started
    }
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_handlers_start_independently_and_dispatcher_returns_promptly
    write_sidecar("slow" => "slow value", "fast" => "fast value")
    write_handler("slow", <<~'SH')
      printf '%s|%s\n' "$1" "$2" > "$SLOW_STARTED"
      sleep 2
      printf 'completed\n' > "$SLOW_COMPLETED"
    SH
    write_handler("fast", <<~'SH')
      printf '%s|%s\n' "$1" "$2" > "$FAST_STARTED"
    SH

    Timeout.timeout(1) { system(@env, RESTORE_EXTRA, exception: true) }

    wait_for(@slow_started)
    wait_for(@fast_started)
    assert_equal "%1|slow value\n", File.read(@slow_started)
    assert_equal "%1|fast value\n", File.read(@fast_started)
    wait_for(@slow_completed, timeout: 3)
    wait_for_log(/handler-complete: slow for work:1\.0/, timeout: 1)
    wait_for_log(/handler-complete: fast for work:1\.0/, timeout: 1)
  end

  def test_handler_failure_is_logged_without_failing_dispatcher
    write_sidecar("failed" => "failed value")
    write_handler("failed", <<~'SH')
      printf '%s|%s\n' "$1" "$2" > "$FAILED_STARTED"
      exit 17
    SH

    Timeout.timeout(1) { system(@env, RESTORE_EXTRA, exception: true) }

    wait_for(@failed_started)
    wait_for_log(/handler-failed: failed for work:1\.0/)
  end

  private

  def write_sidecar(values)
    File.write(@sidecar, JSON.generate("panes" => { "work:1.0" => values }))
  end

  def write_fake_tmux
    write_executable(File.join(@bin, "tmux"), <<~'SH')
      #!/bin/sh
      [ "$1" = "list-panes" ] || exit 90
      printf 'work\t1\t0\t%%1\n'
    SH
  end

  def write_handler(key, body)
    write_executable(File.join(@bin, "tmux-restore-handler-#{key}"), <<~SH)
      #!/bin/sh
      #{body}
    SH
  end

  def write_executable(path, contents)
    File.write(path, contents)
    FileUtils.chmod(0o755, path)
  end

  def wait_for(path, timeout: 1)
    wait_until(timeout:) { File.exist?(path) }
  end

  def wait_for_log(pattern, timeout: 1)
    wait_until(timeout:) { File.exist?(@log) && File.read(@log).match?(pattern) }
  end

  def wait_until(timeout:)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      raise "timed out waiting for test state" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.01
    end
  end
end
