#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"

REPO_ROOT = File.expand_path("..", __dir__)
HELPER = File.join(REPO_ROOT, "roles/common/files/bin/tmux-attach-or-new")

class TmuxRestoreStartupTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("tmux-restore-startup")
    @home = File.join(@tmpdir, "home")
    @bin = File.join(@home, ".local", "bin")
    FileUtils.mkdir_p(@bin)
    @state_path = File.join(@tmpdir, "tmux-state.json")
    @attachments_path = File.join(@tmpdir, "attachments.json")
    @restore_marker = File.join(@tmpdir, "restore-in-progress")
    @fallback_log = File.join(@tmpdir, "fallback.log")
    @lock_file = File.join(@tmpdir, "startup.lock")
    write_json(@state_path, base_state)
    write_json(@attachments_path, [])
    write_fake_tmux
    write_restore_script
    write_fallback_shell
    write_log_library
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_concurrent_helpers_select_distinct_restored_sessions
    set_sessions(%w[one two three four])
    env = helper_env("FAKE_TMUX_ATTACH_DELAY" => "0.25")

    results = 4.times.map do
      Thread.new { Open3.capture3(env, HELPER) }
    end.map(&:value)

    attachments = JSON.parse(File.read(@attachments_path))
    assert_equal 4, attachments.length
    assert_equal 4, attachments.map { |entry| entry.fetch("session_id") }.uniq.length,
      "concurrent helpers selected duplicate targets: #{attachments.inspect}"
    results.each { |_out, _err, status| assert status.success? }
  end

  def test_slow_restore_runs_once_and_waiter_never_uses_tmux_unlocked
    env = helper_env(
      "FAKE_RESTORE_DELAY" => "0.5",
      "FAKE_RESTORE_SESSIONS" => "restored-one,restored-two",
      "TMUX_ATTACH_LOCK_TIMEOUT" => "0.1"
    )

    first = Thread.new { Open3.capture3(env, HELPER) }
    wait_until { File.exist?(@restore_marker) }
    second = Open3.capture3(env, HELPER)
    results = [first.value, second]
    state = read_state
    restore_invocations = state.fetch("restore_invocations")
    unlocked_bootstrap_attempts = state.fetch("unlocked_bootstrap_attempts")
    fallback_output = results.flat_map { |out, err, _status| [out, err] }.join

    assert_equal 1, restore_invocations
    assert_equal [], unlocked_bootstrap_attempts,
      "waiter ran tmux while restore held the startup lock: #{unlocked_bootstrap_attempts.inspect}"
    assert_includes fallback_output, "tmux-restore-debug-report"
  end

  def test_dead_reservation_is_reclaimed_and_cleaned_up
    set_sessions(["stale", "available"], owners: { "stale" => "999999" })

    _out, _err, status = Open3.capture3(helper_env, HELPER)
    attachments = read_attachments
    session_options = session_named("stale").fetch("options")

    assert status.success?
    assert_equal "$1", attachments.first.fetch("session_id")
    assert_nil session_options.fetch("@ghostty_attach_owner", nil)
  end

  def test_live_reservation_is_skipped
    set_sessions(["reserved", "available"], owners: { "reserved" => Process.pid.to_s })

    _out, _err, status = Open3.capture3(helper_env, HELPER)
    attachments = read_attachments

    assert status.success?
    assert_equal "$2", attachments.first.fetch("session_id")
  end

  def test_attach_failure_clears_reservation_and_opens_fallback_shell
    set_sessions(["broken"])
    env = helper_env("FAKE_TMUX_ATTACH_FAILURE" => "$1")

    out, err, status = Open3.capture3(env, HELPER)
    session_options = session_named("broken").fetch("options")
    fallback_output = out + err

    assert status.success?, "fallback shell should remain usable after attach failure"
    assert_nil session_options.fetch("@ghostty_attach_owner", nil)
    assert_includes fallback_output, "tmux-restore-debug-report"
  end

  def test_restore_failure_is_shared_and_opens_fallback_shell
    env = helper_env("FAKE_RESTORE_STATUS" => "23")

    out, err, status = Open3.capture3(env, HELPER)
    state = read_state

    assert status.success?, "fallback shell should remain usable after restore failure"
    assert_equal 1, state.fetch("restore_invocations")
    assert_equal "failed", state.fetch("global_options").fetch("@ghostty_restore_state", nil)
    assert_includes out + err, "tmux-restore-debug-report"
  end

  def test_empty_restore_creates_and_attaches_normal_session
    env = helper_env("FAKE_RESTORE_SESSIONS" => "")

    _out, _err, status = Open3.capture3(env, HELPER)
    attachments = read_attachments

    assert status.success?
    assert_equal 1, attachments.length
    refute_equal "__bootstrap__", attachments.first.fetch("session_name")
  end

  private

  def base_state
    {
      "sessions" => [],
      "next_id" => 1,
      "global_options" => {},
      "restore_invocations" => 0,
      "unlocked_bootstrap_attempts" => []
    }
  end

  def helper_env(extra = {})
    {
      "HOME" => @home,
      "PATH" => "#{@bin}:#{ENV.fetch("PATH")}",
      "FAKE_TMUX_STATE" => @state_path,
      "FAKE_TMUX_ATTACHMENTS" => @attachments_path,
      "FAKE_TMUX_RESTORE_MARKER" => @restore_marker,
      "FAKE_TMUX_FALLBACK_LOG" => @fallback_log,
      "TMUX_ATTACH_LOCK_FILE" => @lock_file,
      "TMUX_ATTACH_LOCK_TIMEOUT" => "1",
      "TMUX_RESTORE_LOG_LIB" => File.join(@tmpdir, "tmux-restore-log.sh"),
      "TMUX_RESURRECT_RESTORE_WRAPPER" => File.join(@tmpdir, "restore"),
      "TMUX_ATTACH_FALLBACK_SHELL" => File.join(@tmpdir, "fallback-shell"),
      "SHELL" => File.join(@tmpdir, "fallback-shell")
    }.merge(extra)
  end

  def set_sessions(names, owners: {})
    update_state do |state|
      state["sessions"] = names.each_with_index.map do |name, index|
        options = {}
        options["@ghostty_attach_owner"] = owners.fetch(name) if owners.key?(name)
        { "id" => "$#{index + 1}", "name" => name, "attached" => 0, "options" => options }
      end
      state["next_id"] = names.length + 1
    end
  end

  def session_named(name)
    read_state.fetch("sessions").find { |session| session.fetch("name") == name }
  end

  def read_state
    JSON.parse(File.read(@state_path))
  end

  def read_attachments
    JSON.parse(File.read(@attachments_path))
  end

  def write_json(path, value)
    File.write(path, JSON.generate(value))
  end

  def update_state
    File.open(@state_path, File::RDWR) do |file|
      file.flock(File::LOCK_EX)
      state = JSON.parse(file.read)
      yield state
      file.rewind
      file.truncate(0)
      file.write(JSON.generate(state))
      file.flush
    end
  end

  def wait_until(timeout: 2)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      raise "timed out waiting for test state" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.01
    end
  end

  def write_executable(path, contents)
    File.write(path, contents)
    FileUtils.chmod("+x", path)
  end

  def write_fake_tmux
    write_executable(File.join(@bin, "tmux"), <<~'RUBY')
      #!/usr/bin/env ruby
      require "json"

      state_path = ENV.fetch("FAKE_TMUX_STATE")
      attachments_path = ENV.fetch("FAKE_TMUX_ATTACHMENTS")
      marker = ENV.fetch("FAKE_TMUX_RESTORE_MARKER")

      def locked_json(path)
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
        index ? args[index + 1] : nil
      end

      def find_session(state, target)
        normalized = target.to_s.delete_prefix("=")
        state.fetch("sessions").find do |session|
          session.fetch("id") == normalized || session.fetch("name") == normalized
        end
      end

      def render(format, session)
        format
          .gsub('#{session_id}', session.fetch("id"))
          .gsub('#{session_name}', session.fetch("name"))
          .gsub('#{session_attached}', session.fetch("attached").to_s)
          .gsub('#{@ghostty_attach_owner}', session.fetch("options").fetch("@ghostty_attach_owner", ""))
      end

      args = ARGV.dup
      command = args.shift

      if File.exist?(marker)
        locked_json(state_path) do |state|
          state["unlocked_bootstrap_attempts"] << ([command] + args).join(" ")
        end
      end

      case command
      when "list-sessions"
        format = option_value(args, "-F") || '#{session_name}'
        sessions = locked_json(state_path) { |state| state.fetch("sessions").map(&:dup) }
        exit 1 if sessions.empty?
        sessions.each { |session| puts render(format, session) }
      when "new-session"
        detached = args.include?("-d")
        requested_name = option_value(args, "-s")
        format = option_value(args, "-F")
        session = locked_json(state_path) do |state|
          id = "$#{state.fetch("next_id") }"
          state["next_id"] += 1
          created = {
            "id" => id,
            "name" => requested_name || id.delete_prefix("$"),
            "attached" => detached ? 0 : 1,
            "options" => {}
          }
          state["sessions"] << created
          created
        end
        puts render(format, session) if format
        unless detached
          locked_json(attachments_path) do |attachments|
            attachments << { "session_id" => session.fetch("id"), "session_name" => session.fetch("name") }
          end
        end
      when "display-message"
        puts File.join(ENV.fetch("HOME"), ".tmux", "fake-socket")
      when "kill-session"
        target = option_value(args, "-t")
        locked_json(state_path) do |state|
          state["sessions"].reject! { |session| find_session(state, target) == session }
        end
      when "set-option"
        flags = args.select { |arg| arg.start_with?("-") && arg != "-t" }
        unset = flags.any? { |flag| flag.include?("u") }
        global = flags.any? { |flag| flag.include?("g") }
        target = option_value(args, "-t")
        args.reject! { |arg| flags.include?(arg) }
        target_index = args.index("-t")
        args.slice!(target_index, 2) if target_index
        option = args.shift
        value = args.shift
        locked_json(state_path) do |state|
          options = global ? state.fetch("global_options") : find_session(state, target)&.fetch("options")
          exit 1 unless options
          unset ? options.delete(option) : options[option] = value
        end
      when "show-options"
        global = args.any? { |arg| arg.include?("g") && arg.start_with?("-") }
        target = option_value(args, "-t")
        option = args.last
        value = locked_json(state_path) do |state|
          options = global ? state.fetch("global_options") : find_session(state, target)&.fetch("options")
          options&.fetch(option, nil)
        end
        exit 1 if value.nil?
        puts value
      when "attach"
        target = option_value(args, "-t")
        sleep ENV.fetch("FAKE_TMUX_ATTACH_DELAY", "0").to_f
        session = locked_json(state_path) do |state|
          selected = find_session(state, target)
          exit 1 unless selected
          selected["attached"] += 1
          selected.dup
        end
        locked_json(attachments_path) do |attachments|
          attachments << { "session_id" => session.fetch("id"), "session_name" => session.fetch("name") }
        end
        exit 42 if [session.fetch("id"), session.fetch("name"), "all"].include?(ENV["FAKE_TMUX_ATTACH_FAILURE"])
      else
        warn "unexpected fake tmux command: #{([command] + args).inspect}"
        exit 90
      end
    RUBY
  end

  def write_restore_script
    restore = File.join(@tmpdir, "restore")
    write_executable(restore, <<~'RUBY')
      #!/usr/bin/env ruby
      require "json"

      state_path = ENV.fetch("FAKE_TMUX_STATE")
      marker = ENV.fetch("FAKE_TMUX_RESTORE_MARKER")
      File.write(marker, Process.pid.to_s)
      begin
        File.open(state_path, File::RDWR) do |file|
          file.flock(File::LOCK_EX)
          state = JSON.parse(file.read)
          state["restore_invocations"] += 1
          file.rewind
          file.truncate(0)
          file.write(JSON.generate(state))
        end
        sleep ENV.fetch("FAKE_RESTORE_DELAY", "0").to_f
        status = ENV.fetch("FAKE_RESTORE_STATUS", "0").to_i
        if status.zero?
          names = ENV.fetch("FAKE_RESTORE_SESSIONS", "").split(",").reject(&:empty?)
          File.open(state_path, File::RDWR) do |file|
            file.flock(File::LOCK_EX)
            state = JSON.parse(file.read)
            names.each do |name|
              state["sessions"] << {
                "id" => "$#{state.fetch("next_id")}", "name" => name,
                "attached" => 0, "options" => {}
              }
              state["next_id"] += 1
            end
            file.rewind
            file.truncate(0)
            file.write(JSON.generate(state))
          end
        end
        exit status
      ensure
        FileUtils.rm_f(marker) if defined?(FileUtils)
        File.delete(marker) if File.exist?(marker)
      end
    RUBY
    resurrect = File.join(@home, ".tmux", "plugins", "tmux-resurrect", "scripts", "restore.sh")
    FileUtils.mkdir_p(File.dirname(resurrect))
    FileUtils.cp(restore, resurrect)
    FileUtils.chmod("+x", resurrect)
  end

  def write_fallback_shell
    write_executable(File.join(@tmpdir, "fallback-shell"), <<~'SH')
      #!/bin/sh
      printf '%s\n' '[tmux] Startup failed; run tmux-restore-debug-report for details.'
      printf '%s\n' "$*" >> "$FAKE_TMUX_FALLBACK_LOG"
    SH
  end

  def write_log_library
    File.write(File.join(@tmpdir, "tmux-restore-log.sh"), <<~'SH')
      tmux_restore_log_event() { :; }
      tmux_restore_rotate_log() { :; }
    SH
  end
end
