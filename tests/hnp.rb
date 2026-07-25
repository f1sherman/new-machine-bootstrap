#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"

REPO_ROOT = File.expand_path("..", __dir__)
HNP = File.join(REPO_ROOT, "roles/common/files/bin/hnp")

class HnpTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("hnp-test")
    @home = File.join(@tmpdir, "home")
    @bin = File.join(@tmpdir, "bin")
    @state_path = File.join(@tmpdir, "tmux-state.json")
    @lock_path = File.join(@tmpdir, "hnp.lock")
    @pi_capture = File.join(@tmpdir, "pi.capture")
    @ssh_capture = File.join(@tmpdir, "ssh.capture")
    FileUtils.mkdir_p(repo_path)
    FileUtils.mkdir_p(@bin)
    write_state("sessions" => [], "attachments" => [], "created" => [], "client_pids" => [])
    write_fake_tmux
    write_fake_pi
    write_fake_ssh
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_missing_canonical_session_is_created_and_attached
    _out, err, status = run_hnp("two words")

    assert status.success?, err
    assert_equal ["hnp"], state.fetch("attachments")
    assert_equal 1, state.fetch("created").length
    created = state.fetch("created").fetch(0)
    assert_equal "hnp", created.fetch("name")
    assert_equal "env -u OPENAI_API_KEY pi two\\ words", created.fetch("command")
  end

  def test_detached_canonical_session_is_reconnected
    set_sessions([{ "name" => "hnp", "attached" => 0, "command" => "pi" }])

    _out, err, status = run_hnp

    assert status.success?, err
    assert_equal ["hnp"], state.fetch("attachments")
    assert_equal [], state.fetch("created")
  end

  def test_attached_canonical_session_creates_unique_session
    set_sessions([{ "name" => "hnp", "attached" => 1, "command" => "pi" }])

    _out, err, status = run_hnp

    assert status.success?, err
    assert_equal 1, state.fetch("created").length
    created_name = state.fetch("created").fetch(0).fetch("name")
    assert_match(/\Ahnp-\d+-\d+\z/, created_name)
    assert_equal [created_name], state.fetch("attachments")
    assert_equal 1, session("hnp").fetch("attached")
  end

  def test_concurrent_launchers_do_not_share_detached_canonical_session
    set_sessions([{ "name" => "hnp", "attached" => 0, "command" => "pi" }])
    env = launcher_env("FAKE_TMUX_ATTACH_DELAY" => "0.25")

    results = 2.times.map { Thread.new { Open3.capture3(env, HNP) } }.map(&:value)
    attachments = state.fetch("attachments")

    results.each { |_out, err, status| assert status.success?, err }
    assert_equal 2, attachments.length
    assert_equal 2, attachments.uniq.length,
      "concurrent launchers attached the same session: #{attachments.inspect}"
    assert_includes attachments, "hnp"
  end

  def test_attach_failure_reaps_client_and_allows_later_reconnect
    set_sessions([{ "name" => "hnp", "attached" => 0, "command" => "pi" }])

    _out, _err, status = run_hnp(env: { "FAKE_TMUX_ATTACH_FAILURE" => "1" })
    child_pid = state.fetch("client_pids").fetch(0)

    refute status.success?
    refute process_alive?(child_pid), "failed tmux client #{child_pid} leaked"

    _out, err, retry_status = run_hnp
    assert retry_status.success?, err
    assert_equal ["hnp"], state.fetch("attachments")
  end

  def test_timeout_kills_term_ignoring_client_and_allows_later_reconnect
    set_sessions([{ "name" => "hnp", "attached" => 0, "command" => "pi" }])
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = Thread.new do
      run_hnp(env: {
        "FAKE_TMUX_NEVER_CONFIRM" => "1",
        "FAKE_TMUX_IGNORE_TERM" => "1",
        "HNP_TMUX_ATTACH_TIMEOUT" => "0.2",
        "HNP_TMUX_TERM_GRACE" => "0.05"
      })
    end

    completed_promptly = result.join(1)
    unless completed_promptly
      state.fetch("client_pids").each { |pid| Process.kill("KILL", pid) if process_alive?(pid) }
      result.join(1)
    end
    _out, _err, status = result.value
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    child_pid = state.fetch("client_pids").fetch(0)

    assert completed_promptly, "timeout cleanup remained blocked after #{elapsed.round(2)}s"
    refute status.success?
    refute process_alive?(child_pid), "timed-out tmux client #{child_pid} leaked"

    _out, err, retry_status = run_hnp
    assert retry_status.success?, err
    assert_equal ["hnp"], state.fetch("attachments")
  end

  def test_interrupt_reaps_unconfirmed_client_and_releases_lock
    set_sessions([{ "name" => "hnp", "attached" => 0, "command" => "pi" }])
    error_path = File.join(@tmpdir, "interrupted.err")
    env = launcher_env(
      "FAKE_TMUX_NEVER_CONFIRM" => "1",
      "HNP_TMUX_ATTACH_TIMEOUT" => "10",
      "HNP_TMUX_TERM_GRACE" => "0.05"
    )
    launcher_pid = Process.spawn(env, HNP, out: File::NULL, err: error_path)
    wait_until { !state.fetch("client_pids").empty? }
    child_pid = state.fetch("client_pids").fetch(0)

    Process.kill("INT", launcher_pid)
    _, status = Process.wait2(launcher_pid)
    sleep 0.1

    refute status.success?
    refute process_alive?(child_pid), "interrupted tmux client #{child_pid} leaked"

    _out, err, retry_status = run_hnp
    assert retry_status.success?, "lock was not reusable: #{err}"
    assert_equal ["hnp"], state.fetch("attachments")
  ensure
    Process.kill("KILL", launcher_pid) if launcher_pid && process_alive?(launcher_pid)
    Process.kill("KILL", child_pid) if child_pid && process_alive?(child_pid)
  end

  def test_inside_tmux_runs_pi_directly_with_arguments
    _out, err, status = run_hnp("two words", "$(bad)", env: {
      "TMUX" => "/tmp/tmux",
      "PI_CAPTURE" => @pi_capture
    })

    assert status.success?, err
    assert_equal [repo_path, "two words", "$(bad)"], File.readlines(@pi_capture, chomp: true)
    assert_equal [], state.fetch("attachments")
  end

  def test_remote_host_routes_to_dev_with_shell_escaped_arguments
    _out, err, status = run_hnp("two words", "$(bad)", env: {
      "HNP_HOSTNAME" => "laptop",
      "FAKE_SSH_AVAILABLE" => "1",
      "SSH_CAPTURE" => @ssh_capture
    })

    assert status.success?, err
    args = File.readlines(@ssh_capture, chomp: true)
    assert_equal "-t", args.fetch(0)
    assert_equal "dev", args.fetch(1)
    assert_includes args.fetch(2), "HNP_REMOTE=1"
    assert_includes args.fetch(2), "two\\ words"
    assert_includes args.fetch(2), "\\\$\\\(bad\\\)"
  end

  private

  def repo_path
    File.join(@home, "projects", "home-network-provisioning")
  end

  def launcher_env(extra = {})
    {
      "HOME" => @home,
      "PATH" => "#{@bin}:#{ENV.fetch("PATH")}",
      "HNP_HOSTNAME" => "dev",
      "HNP_REMOTE" => nil,
      "SSH_CONNECTION" => nil,
      "TMUX" => nil,
      "FAKE_TMUX_STATE" => @state_path,
      "FAKE_TMUX_ATTACH_DELAY" => "0.2",
      "HNP_TMUX_LOCK_FILE" => @lock_path,
      "HNP_TMUX_ATTACH_TIMEOUT" => "1"
    }.merge(extra)
  end

  def run_hnp(*args, env: {})
    Open3.capture3(launcher_env(env), HNP, *args)
  end

  def set_sessions(sessions)
    write_state("sessions" => sessions, "attachments" => [], "created" => [], "client_pids" => [])
  end

  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def wait_until(timeout: 1)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      raise "timed out waiting for process state" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.01
    end
  end

  def state
    JSON.parse(File.read(@state_path))
  end

  def session(name)
    state.fetch("sessions").find { |candidate| candidate.fetch("name") == name }
  end

  def write_state(value)
    File.write(@state_path, JSON.generate(value))
  end

  def write_executable(path, contents)
    File.write(path, contents)
    FileUtils.chmod("+x", path)
  end

  def write_fake_pi
    write_executable(File.join(@bin, "pi"), <<~'SH')
      #!/usr/bin/env bash
      set -euo pipefail
      if [[ -n "${PI_CAPTURE:-}" ]]; then
        {
          pwd
          printf '%s\n' "$@"
        } >"$PI_CAPTURE"
      fi
    SH
  end

  def write_fake_ssh
    write_executable(File.join(@bin, "ssh"), <<~'SH')
      #!/usr/bin/env bash
      set -euo pipefail
      if [[ "${*: -1}" == "true" ]]; then
        [[ "${FAKE_SSH_AVAILABLE:-0}" == "1" ]]
        exit $?
      fi
      printf '%s\n' "$@" >"$SSH_CAPTURE"
    SH
  end

  def write_fake_tmux
    write_executable(File.join(@bin, "tmux"), <<~'RUBY')
      #!/usr/bin/env ruby
      require "json"

      state_path = ENV.fetch("FAKE_TMUX_STATE")

      def locked_state(path)
        File.open(path, File::RDWR) do |file|
          file.flock(File::LOCK_EX)
          value = JSON.parse(file.read)
          result = yield value
          file.rewind
          file.truncate(0)
          file.write(JSON.generate(value))
          file.flush
          result
        end
      end

      def option_value(args, option)
        index = args.index(option)
        index && args[index + 1]
      end

      def session_named(state, target)
        name = target.to_s.delete_prefix("=")
        state.fetch("sessions").find { |session| session.fetch("name") == name }
      end

      def display_session_named(state, target)
        match = target.to_s.match(/\A=(.+):\z/)
        return unless match

        session_named(state, match[1])
      end

      def attach(path, target)
        locked_state(path) { |state| state.fetch("client_pids") << Process.pid }
        exit 42 if ENV["FAKE_TMUX_ATTACH_FAILURE"] == "1"
        if ENV["FAKE_TMUX_NEVER_CONFIRM"] == "1"
          Signal.trap("TERM") {} if ENV["FAKE_TMUX_IGNORE_TERM"] == "1"
          sleep 30
          exit 0
        end

        session_name = locked_state(path) do |state|
          session = session_named(state, target)
          exit 1 unless session
          session["attached"] += 1
          state.fetch("attachments") << session.fetch("name")
          session.fetch("name")
        end
        sleep ENV.fetch("FAKE_TMUX_ATTACH_DELAY", "0.2").to_f
        locked_state(path) do |state|
          session_named(state, session_name)["attached"] -= 1
        end
      end

      args = ARGV.dup
      command = args.shift

      case command
      when "has-session"
        target = option_value(args, "-t")
        found = locked_state(state_path) { |state| !session_named(state, target).nil? }
        exit(found ? 0 : 1)
      when "display-message"
        target = option_value(args, "-t")
        session = locked_state(state_path) { |state| display_session_named(state, target)&.dup }
        exit 1 unless session
        puts session.fetch("attached")
      when "new-session"
        name = option_value(args, "-s")
        existing = locked_state(state_path) { |state| session_named(state, name)&.dup }
        if args.include?("-A") && existing
          attach(state_path, name)
          exit 0
        end

        command_index = args.index("-c")
        shell_command = command_index ? args[command_index + 2] : args.last
        locked_state(state_path) do |state|
          exit 1 if session_named(state, name)
          state.fetch("sessions") << { "name" => name, "attached" => 0, "command" => shell_command }
          state.fetch("created") << { "name" => name, "command" => shell_command }
        end
        attach(state_path, name) unless args.include?("-d")
      when "attach-session"
        attach(state_path, option_value(args, "-t"))
      else
        warn "unexpected fake tmux command: #{([command] + args).inspect}"
        exit 90
      end
    RUBY
  end
end
