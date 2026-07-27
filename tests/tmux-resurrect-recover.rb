#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "rbconfig"
require "tmpdir"

REPO_ROOT = File.expand_path("..", __dir__)
RECOVER = File.join(REPO_ROOT, "roles/common/files/bin/tmux-resurrect-recover")

class TmuxResurrectRecoverTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("tmux-resurrect-recover")
    @bin = File.join(@tmpdir, "bin")
    @resurrect_dir = File.join(@tmpdir, "resurrect")
    @snapshot = File.join(@resurrect_dir, "tmux_resurrect_20260727T120000.txt")
    @restore_script = File.join(@tmpdir, "restore")
    @restore_marker = File.join(@tmpdir, "restore-started")
    @interval_state = File.join(@tmpdir, "continuum-interval")
    @set_log = File.join(@tmpdir, "continuum-set.log")
    @output = File.join(@tmpdir, "recover.log")
    FileUtils.mkdir_p([@bin, @resurrect_dir])
    File.write(@snapshot, "pane\tone\npane\ttwo\npane\tthree\n#{"state\n" * 200}")
    File.write(@interval_state, "5\n")
    write_fake_tmux
    write_blocking_restore
  end

  def teardown
    terminate_recovery
    FileUtils.remove_entry(@tmpdir)
  end

  def test_term_restores_continuum_interval_before_recovery_exits
    env = {
      "PATH" => "#{@bin}:#{ENV.fetch("PATH")}",
      "TMUX" => "/tmp/fake-tmux-socket,123,0",
      "FAKE_TMUX_INTERVAL_STATE" => @interval_state,
      "FAKE_TMUX_SET_LOG" => @set_log,
      "FAKE_RESTORE_MARKER" => @restore_marker
    }
    output = File.open(@output, "w")
    @pid = Process.spawn(
      env,
      RbConfig.ruby,
      RECOVER,
      "--source", @snapshot,
      "--resurrect-dir", @resurrect_dir,
      "--restore-script", @restore_script,
      pgroup: true,
      out: output,
      err: output
    )
    output.close

    wait_until { File.exist?(@restore_marker) }
    assert_equal "0", current_interval, "manual recovery did not pause continuum"

    Process.kill("TERM", -@pid)
    wait_until { current_interval == "5" || recovery_exited? }

    assert_equal "5", current_interval, "TERM left continuum autosaving paused"
    unless @status
      _waited_pid, @status = Process.wait2(@pid)
      @pid = nil
    end
    assert_equal 143, @status.exitstatus
    assert_equal %w[0 5], File.readlines(@set_log, chomp: true),
      "continuum interval should be paused and restored exactly once"
  end

  private

  def current_interval
    File.read(@interval_state).strip
  end

  def wait_until(timeout: 3)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        details = File.exist?(@output) ? File.read(@output) : ""
        raise "timed out waiting for recovery state:\n#{details}"
      end

      sleep 0.01
    end
  end

  def recovery_exited?
    waited_pid, status = Process.wait2(@pid, Process::WNOHANG)
    return false unless waited_pid

    @status = status
    @pid = nil
    true
  end

  def terminate_recovery
    return unless @pid

    Process.kill("KILL", -@pid)
  rescue Errno::ESRCH, Errno::EPERM
    nil
  ensure
    begin
      Process.wait(@pid) if @pid
    rescue Errno::ECHILD
      nil
    end
    @pid = nil
  end

  def write_executable(path, contents)
    File.write(path, contents)
    FileUtils.chmod(0o755, path)
  end

  def write_fake_tmux
    write_executable(File.join(@bin, "tmux"), <<~'RUBY')
      #!/usr/bin/env ruby
      state_path = ENV.fetch("FAKE_TMUX_INTERVAL_STATE")
      set_log = ENV.fetch("FAKE_TMUX_SET_LOG")
      command, *args = ARGV

      case command
      when "show"
        print File.read(state_path)
      when "set"
        value = args.last
        File.write(state_path, "#{value}\n")
        File.open(set_log, "a") { |file| file.puts(value) }
      when "list-sessions"
        puts "recovered\twindows=1\tattached=0"
      else
        warn "unexpected fake tmux command: #{ARGV.inspect}"
        exit 90
      end
    RUBY
  end

  def write_blocking_restore
    write_executable(@restore_script, <<~'RUBY')
      #!/usr/bin/env ruby
      File.write(ENV.fetch("FAKE_RESTORE_MARKER"), Process.pid.to_s)
      sleep
    RUBY
  end
end
