#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

REPO_ROOT = File.expand_path("..", __dir__)
HELPER = File.join(REPO_ROOT, "roles/common/files/bin/tmux-attach-or-new")
DEV_HOST_TASKS = File.join(REPO_ROOT, "roles/dev_host/tasks/main.yml")

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
    @events_path = File.join(@tmpdir, "events.log")
    @lock_file = File.join(@tmpdir, "startup.lock")
    @manifest_path = File.join(@tmpdir, "ghostty-session-manifest.json")
    @queue_path = File.join(@tmpdir, "ghostty-restore-queue.json")
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

  def test_new_ghostty_process_claims_exact_manifest_set
    set_sessions(%w[17 19 journal hnp nmb command-proxy misc])
    write_manifest(pid: 100, sessions: %w[journal hnp nmb command-proxy misc])
    env = helper_env(
      "TMUX_GHOSTTY_APP_PID" => "200",
      "TMUX_ATTACH_LOCK_TIMEOUT" => "5",
      "FAKE_TMUX_ATTACH_DELAY" => "0.25"
    )

    results = 5.times.map do
      Thread.new { Open3.capture3(env, HELPER) }
    end.map(&:value)
    names = read_attachments.map { |entry| entry.fetch("session_name") }

    results.each do |out, err, status|
      assert status.success?, "helper failed:\n#{out}\n#{err}"
    end
    assert_equal [], fallback_invocations, File.read(@events_path)
    assert_equal %w[command-proxy hnp journal misc nmb], names.sort
    refute_includes names, "17"
    refute_includes names, "19"
    assert_event(/event=restore_queue_initialized\tghostty_pid=200\tsessions=5/)
  end

  def test_invalid_matching_restore_queue_is_rebuilt_from_manifest
    set_sessions(%w[17 journal])
    write_manifest(pid: 100, sessions: ["journal"])
    write_json(@queue_path, { "version" => 999, "ghostty_pid" => 200, "pending" => ["17"] })

    _out, _err, status = Open3.capture3(helper_env("TMUX_GHOSTTY_APP_PID" => "200"), HELPER)

    assert status.success?
    assert_equal ["journal"], read_attachments.map { |entry| entry.fetch("session_name") }
  end

  def test_non_ghostty_invocation_ignores_stale_manifest
    set_sessions(%w[17 journal])
    write_manifest(pid: 100, sessions: ["journal"])

    _out, _err, status = Open3.capture3(helper_env, HELPER)

    assert status.success?
    assert_equal ["17"], read_attachments.map { |entry| entry.fetch("session_name") }
  end

  def test_missing_diagnostics_library_does_not_abort_startup
    set_sessions(["17"])
    missing_log_library = File.join(@tmpdir, "missing-log-library")

    _out, _err, status = Open3.capture3(helper_env("TMUX_RESTORE_LOG_LIB" => missing_log_library), HELPER)

    assert status.success?
    assert_equal ["17"], read_attachments.map { |entry| entry.fetch("session_name") }
  end

  def test_queue_write_failure_uses_normal_selection_and_clear_diagnostic
    set_sessions(%w[17 journal])
    write_manifest(pid: 100, sessions: ["journal"])
    blocked_parent = File.join(@tmpdir, "blocked-parent")
    File.write(blocked_parent, "not a directory")
    env = helper_env(
      "TMUX_GHOSTTY_APP_PID" => "200",
      "TMUX_GHOSTTY_RESTORE_QUEUE" => File.join(blocked_parent, "queue.json")
    )

    _out, err, status = Open3.capture3(env, HELPER)

    assert status.success?
    assert_equal ["17"], read_attachments.map { |entry| entry.fetch("session_name") }
    assert_event(/event=restore_queue_skipped\tghostty_pid=200\treason=queue_write_failed/)
    refute_match(/Not a directory|Permission denied/, err)
  end

  def test_restore_queue_skips_missing_saved_session
    set_sessions(%w[17 journal])
    write_manifest(pid: 100, sessions: %w[missing journal])

    _out, _err, status = Open3.capture3(helper_env("TMUX_GHOSTTY_APP_PID" => "200"), HELPER)

    assert status.success?
    assert_equal ["journal"], read_attachments.map { |entry| entry.fetch("session_name") }
    assert_event(/event=restore_queue_candidate_skipped\tsession=missing\treason=missing/)
  end

  def test_helper_uses_normal_selection_after_restore_queue_is_exhausted
    set_sessions(%w[17 19 journal])
    write_manifest(pid: 100, sessions: ["journal"])
    env = helper_env("TMUX_GHOSTTY_APP_PID" => "200")

    first = Open3.capture3(env, HELPER)
    second = Open3.capture3(env, HELPER)

    assert first.last.success?
    assert second.last.success?
    assert_equal %w[journal 17], read_attachments.map { |entry| entry.fetch("session_name") }
  end

  def test_same_ghostty_process_as_manifest_uses_normal_selection
    set_sessions(%w[17 journal])
    write_manifest(pid: 200, sessions: ["journal"])

    _out, _err, status = Open3.capture3(helper_env("TMUX_GHOSTTY_APP_PID" => "200"), HELPER)

    assert status.success?
    assert_equal ["17"], read_attachments.map { |entry| entry.fetch("session_name") }
    assert_event(/event=restore_queue_skipped\tghostty_pid=200\treason=current_process_manifest/)
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
    attachments.each { |entry| assert_helper_owned_reservation(entry) }
    results.each { |_out, _err, status| assert status.success? }
  end

  def test_slow_restore_runs_once_and_waiter_never_uses_tmux_unlocked
    env = helper_env(
      "FAKE_RESTORE_DELAY" => "0.5",
      "FAKE_RESTORE_SESSIONS" => "restored-one,restored-two",
      "TMUX_ATTACH_LOCK_TIMEOUT" => "0.1"
    )

    first = Thread.new { Open3.capture3(env.merge("FAKE_HELPER_LABEL" => "restorer"), HELPER) }
    wait_until { File.exist?(@restore_marker) }
    second = Open3.capture3(env.merge("FAKE_HELPER_LABEL" => "timed-out-waiter"), HELPER)
    results = [first.value, second]
    state = read_state
    restore_invocations = state.fetch("restore_invocations")
    unlocked_bootstrap_attempts = state.fetch("unlocked_bootstrap_attempts")
    fallback_output = results.flat_map { |out, err, _status| [out, err] }.join

    assert_equal 1, restore_invocations
    assert_equal [], unlocked_bootstrap_attempts,
      "waiter ran tmux while restore held the startup lock: #{unlocked_bootstrap_attempts.inspect}"
    assert_includes fallback_output, "tmux-restore-debug-report"
    assert_equal ["timed-out-waiter"], fallback_invocations.map { |entry| entry.fetch("label") },
      "the timed-out waiter must be the helper that invokes the fallback shell"
    assert_event(/event=lock_failed\twait_seconds=\d+\treason=timeout/)
  end

  def test_dead_reservation_is_reclaimed_and_cleaned_up
    dead_pid = Process.spawn(RbConfig.ruby, "-e", "exit")
    Process.wait(dead_pid)
    set_sessions(["stale", "available"], owners: { "stale" => dead_pid.to_s })

    _out, _err, status = Open3.capture3(helper_env, HELPER)
    attachments = read_attachments
    session_options = session_named("stale").fetch("options")

    assert status.success?
    assert_equal "$1", attachments.first.fetch("session_id")
    assert_helper_owned_reservation(attachments.first)
    assert_nil session_options.fetch("@ghostty_attach_owner", nil)
  end

  def test_live_reservation_is_skipped
    set_sessions(["reserved", "available"], owners: { "reserved" => Process.pid.to_s })

    _out, _err, status = Open3.capture3(helper_env, HELPER)
    attachments = read_attachments

    assert status.success?
    assert_equal "$2", attachments.first.fetch("session_id")
    assert_helper_owned_reservation(attachments.first)
  end

  def test_tab_in_session_name_does_not_corrupt_selection_fields
    set_sessions(["tab\tname", "available"])

    _out, _err, status = Open3.capture3(helper_env, HELPER)
    attachment = read_attachments.first

    assert status.success?
    assert_equal "$1", attachment.fetch("session_id")
    assert_equal "tab\tname", attachment.fetch("session_name")
    assert_helper_owned_reservation(attachment)
  end

  def test_attach_failure_clears_reservation_and_opens_fallback_shell
    set_sessions(["broken"])
    env = helper_env(
      "FAKE_HELPER_LABEL" => "attach-failure",
      "FAKE_TMUX_ATTACH_FAILURE" => "$1"
    )

    stdin, stdout, stderr, wait_thread = Open3.popen3(env, HELPER)
    helper_pid = wait_thread.pid
    stdin.close
    out = stdout.read
    err = stderr.read
    status = wait_thread.value
    failed_session = session_named("broken")
    session_options = failed_session.fetch("options")
    fallback_output = out + err

    assert status.success?, "fallback shell should remain usable after attach failure"
    assert_equal 0, failed_session.fetch("attached"), "failed attach must not mark the session attached"
    assert_nil session_options.fetch("@ghostty_attach_owner", nil)
    assert_includes fallback_output, "tmux-restore-debug-report"
    assert_equal ["attach-failure"], fallback_invocations.map { |entry| entry.fetch("label") }
    assert_equal helper_pid, fallback_invocations.first.fetch("pid"),
      "fallback shell must replace the helper process rather than run as its child"
    assert_equal "1", fallback_invocations.first.fetch("fallback"),
      "fallback shell replacement must suppress managed login-shell handoffs"
    assert_event(/event=attach_start\ttarget=\$1/)
    assert_event(/event=attach_end\ttarget=\$1\telapsed_seconds=\d+\tstatus=42/)
  end

  def test_cleanup_lock_timeout_directly_clears_owned_reservation_before_fallback
    set_sessions(["broken"])
    env = helper_env(
      "FAKE_HELPER_LABEL" => "cleanup-timeout",
      "FAKE_TMUX_ATTACH_FAILURE" => "$1",
      "FAKE_TMUX_CLEANUP_LOCK_DELAY" => "0.25",
      "TMUX_ATTACH_LOCK_TIMEOUT" => "0.05"
    )

    _out, _err, status = Open3.capture3(env, HELPER)

    assert status.success?
    assert_nil session_named("broken").fetch("options").fetch("@ghostty_attach_owner", nil),
      "fallback exec must not retain a live PID reservation after cleanup lock timeout"
    assert_event(/event=reservation_cleanup_degraded\ttarget=\$1\treason=lock_timeout/)
    assert_equal ["cleanup-timeout"], fallback_invocations.map { |entry| entry.fetch("label") }
  end

  def test_missing_fallback_shell_keeps_visible_failure_diagnostics
    set_sessions(["broken"])
    missing_shell = File.join(@tmpdir, "missing-fallback-shell")
    env = helper_env(
      "FAKE_TMUX_ATTACH_FAILURE" => "$1",
      "TMUX_ATTACH_FALLBACK_SHELL" => missing_shell
    )

    out, err, status = Open3.capture3(env, HELPER)

    refute status.success?
    assert_includes out + err, "tmux-restore-debug-report"
    assert_includes out + err, "Unable to start fallback shell #{missing_shell}"
  end

  def test_existing_running_restore_state_is_treated_as_abandoned
    set_sessions(["available"])
    update_state { |state| state.fetch("global_options")["@ghostty_restore_state"] = "running" }

    out, err, status = Open3.capture3(helper_env("FAKE_HELPER_LABEL" => "abandoned-restore"), HELPER)
    state = read_state

    assert status.success?
    assert_equal [], read_attachments, "abandoned restore must not attach a normal session"
    assert_equal ["available"], state.fetch("sessions").map { |session| session.fetch("name") },
      "abandoned restore must not create a normal session"
    assert_equal ["abandoned-restore"], fallback_invocations.map { |entry| entry.fetch("label") }
    assert_includes out + err, "tmux-restore-debug-report"
    assert_event(/event=fallback_shell\treason=restore_abandoned/)
  end

  def test_restore_failure_is_shared_and_opens_fallback_shell
    env = helper_env(
      "FAKE_HELPER_LABEL" => "restore-failure",
      "FAKE_RESTORE_STATUS" => "23"
    )

    out, err, status = Open3.capture3(env, HELPER)
    state = read_state

    assert status.success?, "fallback shell should remain usable after restore failure"
    assert_equal 1, state.fetch("restore_invocations")
    assert_equal "failed", state.fetch("global_options").fetch("@ghostty_restore_state", nil)
    assert_includes out + err, "tmux-restore-debug-report"
    assert_equal ["restore-failure"], fallback_invocations.map { |entry| entry.fetch("label") }
  end

  def test_unreserved_restored_session_named_zero_is_selected
    env = helper_env("FAKE_RESTORE_SESSIONS" => "0")

    _out, _err, status = Open3.capture3(env, HELPER)
    attachment = read_attachments.first

    assert status.success?
    assert_equal "$2", attachment.fetch("session_id"),
      "numeric session name must not be parsed as a live reservation owner"
    assert_equal "0", attachment.fetch("session_name")
    assert_helper_owned_reservation(attachment)
    assert_equal ["0"], read_state.fetch("sessions").map { |session| session.fetch("name") },
      "helper must not create a new session when the restored session is available"
  end

  def test_managed_login_shell_handoffs_skip_tmux_fallbacks
    tasks = File.read(DEV_HOST_TASKS)
    fallback_guard = '[ -z "${TMUX_ATTACH_FALLBACK:-}" ]'

    assert_match(/Configure tmux auto-launch in \.zprofile.*?#{Regexp.escape(fallback_guard)}.*?tmux-attach-or-new/m, tasks)
    assert_match(/Configure zsh exec in \.bashrc.*?#{Regexp.escape(fallback_guard)}.*?exec \/usr\/bin\/zsh -l/m, tasks)
    assert_equal 2, tasks.scan(fallback_guard).length
  end

  def test_empty_restore_creates_and_attaches_normal_session
    env = helper_env("FAKE_RESTORE_SESSIONS" => "")

    _out, _err, status = Open3.capture3(env, HELPER)
    attachments = read_attachments

    assert status.success?
    assert_equal 1, attachments.length
    refute_equal "__bootstrap__", attachments.first.fetch("session_name")
    assert_event(/event=lock_attempt\ttimeout_seconds=1/)
    assert_event(/event=lock_acquired\twait_seconds=\d+/)
    assert_event(/event=server_snapshot\tphase=pre_decision\thas_server=0\trestore_state=unset\tsessions=none/)
    assert_event(/event=bootstrap_start\tsession=__bootstrap__/)
    assert_event(/event=bootstrap_end\tsession=__bootstrap__\telapsed_seconds=\d+\tstatus=0/)
    assert_event(/event=restore_start\tsnapshot=none\twrapper=/)
    assert_event(/event=restore_end\tsnapshot=none\telapsed_seconds=\d+\tstatus=0/)
    assert_event(/event=server_snapshot\tphase=post_restore\thas_server=1\trestore_state=ok\tsessions=/)
    assert_event(/event=attach_start\ttarget=\$\d+/)
    assert_event(/event=attach_end\ttarget=\$\d+\telapsed_seconds=\d+\tstatus=0/)
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
      "FAKE_TMUX_EVENTS" => @events_path,
      "TMUX_ATTACH_LOCK_FILE" => @lock_file,
      "TMUX_ATTACH_LOCK_TIMEOUT" => "1",
      "TMUX_RESTORE_LOG_LIB" => File.join(@tmpdir, "tmux-restore-log.sh"),
      "TMUX_RESURRECT_RESTORE_WRAPPER" => File.join(@tmpdir, "restore"),
      "TMUX_ATTACH_FALLBACK_SHELL" => File.join(@tmpdir, "fallback-shell"),
      "TMUX_GHOSTTY_MANIFEST" => @manifest_path,
      "TMUX_GHOSTTY_RESTORE_QUEUE" => @queue_path,
      "SHELL" => File.join(@tmpdir, "fallback-shell")
    }.merge(extra)
  end

  def write_manifest(pid:, sessions:)
    tabs = sessions.each_with_index.map do |name, index|
      { "tab_index" => index + 1, "session_name" => name }
    end
    write_json(@manifest_path, {
      "version" => 1,
      "ghostty_pid" => pid,
      "saved_at" => Time.now.to_i,
      "windows" => [{ "window_ordinal" => 1, "selected_tab_index" => 1, "tabs" => tabs }]
    })
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

  def assert_helper_owned_reservation(attachment)
    assert_equal attachment.fetch("tmux_parent_pid").to_s, attachment.fetch("reservation_owner"),
      "selected session reservation must contain the attaching helper PID"
  end

  def fallback_invocations
    return [] unless File.exist?(@fallback_log)

    File.readlines(@fallback_log, chomp: true).map do |line|
      pid, label, arguments, fallback = line.split("\t", 4)
      { "pid" => Integer(pid), "label" => label, "arguments" => arguments, "fallback" => fallback }
    end
  end

  def read_state
    JSON.parse(File.read(@state_path))
  end

  def read_attachments
    JSON.parse(File.read(@attachments_path))
  end

  def assert_event(pattern)
    events = File.exist?(@events_path) ? File.read(@events_path) : ""
    assert_match pattern, events, "expected recorded event matching #{pattern.inspect}; got:\n#{events}"
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
          .gsub('#{==:#{session_name},__bootstrap__}', (session.fetch("name") == "__bootstrap__" ? "1" : "0"))
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
        target = option_value(args, "-t")
        format = args.last
        if format == '#{session_id}'
          session = locked_json(state_path) { |state| find_session(state, target)&.dup }
          exit 1 unless session
          puts session.fetch("id")
        else
          puts File.join(ENV.fetch("HOME"), ".tmux", "fake-socket")
        end
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
        cleanup_lock_delay = ENV.fetch("FAKE_TMUX_CLEANUP_LOCK_DELAY", "0").to_f
        if cleanup_lock_delay.positive?
          ready_reader, ready_writer = IO.pipe
          fork do
            ready_reader.close
            File.open(ENV.fetch("TMUX_ATTACH_LOCK_FILE"), "w") do |lock|
              lock.flock(File::LOCK_EX)
              ready_writer.write("ready")
              ready_writer.close
              sleep cleanup_lock_delay
            end
            exit! 0
          end
          ready_writer.close
          ready_reader.read
          ready_reader.close
        end
        sleep ENV.fetch("FAKE_TMUX_ATTACH_DELAY", "0").to_f
        session = locked_json(state_path) do |state|
          selected = find_session(state, target)
          exit 1 unless selected
          selected.dup
        end
        exit 42 if [session.fetch("id"), session.fetch("name"), "all"].include?(ENV["FAKE_TMUX_ATTACH_FAILURE"])

        session = locked_json(state_path) do |state|
          selected = find_session(state, target)
          exit 1 unless selected
          selected["attached"] += 1
          selected.dup
        end
        locked_json(attachments_path) do |attachments|
          attachments << {
            "session_id" => session.fetch("id"),
            "session_name" => session.fetch("name"),
            "reservation_owner" => session.fetch("options").fetch("@ghostty_attach_owner", nil),
            "tmux_parent_pid" => Process.ppid
          }
        end
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
      printf '%s\t%s\t%s\t%s\n' \
        "$$" "${FAKE_HELPER_LABEL:-unlabeled}" "$*" "${TMUX_ATTACH_FALLBACK:-unset}" \
        >> "$FAKE_TMUX_FALLBACK_LOG"
    SH
  end

  def write_log_library
    File.write(File.join(@tmpdir, "tmux-restore-log.sh"), <<~'SH')
      tmux_restore_log_event() {
        local event field
        event="$1"
        shift
        {
          printf 'event=%s' "$event"
          for field in "$@"; do
            printf '\t%s' "$field"
          done
          printf '\n'
        } >> "$FAKE_TMUX_EVENTS"
      }
      tmux_restore_rotate_log() { :; }
    SH
  end
end
