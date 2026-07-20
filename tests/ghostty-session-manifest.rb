#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"

REPO_ROOT = File.expand_path("..", __dir__)
SAVER = File.join(REPO_ROOT, "roles/macos/files/bin/ghostty-session-manifest-save")
MACOS_TASKS = File.join(REPO_ROOT, "roles/macos/tasks/main.yml")
MACOS_TMUX_CONFIG = File.join(REPO_ROOT, "roles/macos/templates/dotfiles/tmux.conf")
LINUX_TMUX_CONFIG = File.join(REPO_ROOT, "roles/linux/files/dotfiles/tmux.conf")
MANIFEST_PLIST = File.join(REPO_ROOT,
  "roles/macos/templates/launchd/com.user.ghostty-session-manifest-save.plist")

class GhosttySessionManifestTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("ghostty-session-manifest")
    @home = File.join(@tmpdir, "home")
    @bin = File.join(@tmpdir, "bin")
    @manifest = File.join(@home, ".local", "state", "tmux", "ghostty-session-manifest.json")
    @manifest_lock = File.join(@tmpdir, "ghostty-session-manifest.lock")
    @sessions = File.join(@tmpdir, "sessions")
    FileUtils.mkdir_p(@bin)
    write_fake_osascript
    write_fake_pgrep
    write_fake_tmux
    write_fake_restore_logger
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_saves_regular_tabs_in_window_and_tab_order
    require_saver
    rows = [
      [1, 2, 2, "hnp"],
      [1, 2, 1, "journal"],
      [2, 1, 1, "nmb"]
    ]

    _out, err, status = run_saver(rows:, sessions: %w[journal hnp nmb 17], ghostty_pid: 4321)
    manifest = JSON.parse(File.read(@manifest))
    names = manifest.fetch("windows").flat_map do |window|
      window.fetch("tabs").map { |tab| tab.fetch("session_name") }
    end

    assert status.success?, err
    assert_equal 1, manifest.fetch("version")
    assert_equal 4321, manifest.fetch("ghostty_pid")
    assert_kind_of Integer, manifest.fetch("saved_at")
    assert_equal %w[journal hnp nmb], names
    refute_includes names, "17", "quick-terminal sessions absent from regular Ghostty tab rows must stay absent"
    assert_equal 2, manifest.fetch("windows").first.fetch("selected_tab_index")
    assert_equal "100600", format("%o", File.stat(@manifest).mode)
  end

  def test_new_ghostty_process_cannot_replace_last_good_with_different_session_set
    require_saver
    FileUtils.mkdir_p(File.dirname(@manifest))
    previous = {
      "version" => 1,
      "ghostty_pid" => 100,
      "saved_at" => 1,
      "windows" => [{
        "window_ordinal" => 1,
        "selected_tab_index" => 1,
        "tabs" => %w[journal hnp nmb command-proxy misc].each_with_index.map do |name, index|
          { "tab_index" => index + 1, "session_name" => name }
        end
      }]
    }
    File.write(@manifest, JSON.generate(previous))
    original = File.read(@manifest)

    _out, _err, status = run_saver(rows: [[1, 1, 1, "17"]], sessions: %w[17 journal hnp nmb command-proxy misc], ghostty_pid: 200)

    refute status.success?
    assert_equal original, File.read(@manifest)
  end

  def test_rejects_unknown_session_without_replacing_last_good
    require_saver
    FileUtils.mkdir_p(File.dirname(@manifest))
    File.write(@manifest, JSON.generate("version" => 1, "ghostty_pid" => 1, "windows" => []))
    original = File.read(@manifest)

    _out, _err, status = run_saver(rows: [[1, 1, 1, "missing"]], sessions: ["journal"], ghostty_pid: 4321)

    refute status.success?
    assert_equal original, File.read(@manifest)
  end

  def test_rejects_duplicate_session_without_replacing_last_good
    require_saver
    FileUtils.mkdir_p(File.dirname(@manifest))
    File.write(@manifest, JSON.generate("version" => 1, "ghostty_pid" => 1, "windows" => []))
    original = File.read(@manifest)

    _out, _err, status = run_saver(
      rows: [[1, 1, 1, "journal"], [1, 1, 2, "journal"]],
      sessions: ["journal"],
      ghostty_pid: 4321
    )

    refute status.success?
    assert_equal original, File.read(@manifest)
  end

  def test_no_ghostty_process_or_windows_is_a_noop
    require_saver

    _out, err, status = run_saver(rows: [], sessions: ["journal"], ghostty_pid: "")

    assert status.success?, err
    refute File.exist?(@manifest)
  end

  def test_concurrent_saves_are_serialized
    require_saver
    File.write(@sessions, "journal\nhnp\n")
    marker = File.join(@tmpdir, "first-osascript-started")
    first_env = saver_env(rows: [[1, 1, 1, "journal"]], ghostty_pid: 4321).merge(
      "FAKE_OSASCRIPT_MARKER" => marker,
      "FAKE_OSASCRIPT_SLEEP" => "0.4"
    )
    second_env = saver_env(rows: [[1, 1, 1, "hnp"]], ghostty_pid: 4321)

    first = Open3.popen3(first_env, SAVER)
    first[0].close
    100.times do
      break if File.exist?(marker)

      sleep 0.01
    end
    assert File.exist?(marker), "first saver did not reach AppleScript"

    second = Open3.popen3(second_env, SAVER)
    second[0].close
    first_err = first[2].read
    second_err = second[2].read
    first_status = first[3].value
    second_status = second[3].value

    assert first_status.success?, first_err
    assert second_status.success?, second_err
    assert_equal "hnp", JSON.parse(File.read(@manifest)).dig("windows", 0, "tabs", 0, "session_name")
  end

  def test_lock_timeout_preserves_last_good_manifest
    require_saver
    FileUtils.mkdir_p(File.dirname(@manifest))
    previous = {
      "version" => 1,
      "ghostty_pid" => 4321,
      "saved_at" => 1,
      "windows" => [{
        "window_ordinal" => 1,
        "selected_tab_index" => 1,
        "tabs" => [{ "tab_index" => 1, "session_name" => "journal" }]
      }]
    }
    File.write(@manifest, JSON.generate(previous))
    original = File.read(@manifest)
    marker = File.join(@tmpdir, "osascript-started")
    restore_log = File.join(@tmpdir, "restore.log")

    File.open(@manifest_lock, File::RDWR | File::CREAT, 0o600) do |lock|
      assert lock.flock(File::LOCK_EX | File::LOCK_NB)
      _out, err, status = run_saver(
        rows: [[1, 1, 1, "hnp"]],
        sessions: %w[journal hnp],
        ghostty_pid: 4321,
        extra_env: {
          "FAKE_OSASCRIPT_MARKER" => marker,
          "FAKE_RESTORE_LOG" => restore_log,
          "TMUX_GHOSTTY_MANIFEST_LOCK_TIMEOUT" => "0"
        }
      )

      assert status.success?, err
    end

    assert_equal original, File.read(@manifest)
    refute File.exist?(marker), "lock timeout must happen before AppleScript"
    assert_includes File.read(restore_log), "manifest_rejected reason=lock_timeout"
  end

  def test_macos_provisions_native_save_state_without_manifest_launch_agent
    tasks = File.read(MACOS_TASKS)

    assert_match(/line: 'window-save-state = never'/, tasks)
    refute_match(/line: 'window-save-state = always'/, tasks)
    refute_match(/Remove ghostty window-save-state setting/, tasks)
    assert_match(/Stat obsolete Ghostty session manifest LaunchAgent plist/, tasks)
    loaded_task = task_body(tasks, "Check whether Ghostty session manifest launchd job is loaded")
    assert_includes loaded_task, "launchctl print gui/"
    assert_includes loaded_task, "failed_when: false"
    unload_task = task_body(tasks, "Unload obsolete Ghostty session manifest launchd job")
    assert_includes unload_task, "when: ghostty_session_manifest_job.rc == 0"
    refute_includes unload_task, "failed_when: false"
    verify_task = task_body(tasks, "Verify Ghostty session manifest launchd job is unloaded")
    assert_includes verify_task, "launchctl print gui/"
    assert_includes verify_task, "failed_when: ghostty_session_manifest_job_after.rc == 0"
    remove_task = task_body(tasks, "Remove obsolete Ghostty session manifest LaunchAgent plist")
    assert_includes remove_task, "state: absent"
    refute_match(/Install Ghostty session manifest LaunchAgent plist/, tasks)
    refute_match(/Load Ghostty session manifest launchd job/, tasks)
    refute File.exist?(MANIFEST_PLIST)
    assert File.executable?(File.join(REPO_ROOT,
      "roles/macos/files/bin/ghostty-session-tabs-restore"))
  end

  def test_macos_tmux_hooks_save_manifest_after_client_events
    macos_config = File.read(MACOS_TMUX_CONFIG)
    linux_config = File.read(LINUX_TMUX_CONFIG)
    command = 'run-shell -b "sleep 0.2; $HOME/.local/bin/ghostty-session-manifest-save || :"'

    %w[client-attached client-detached client-session-changed client-focus-in].each do |event|
      pattern = /^set-hook -g #{Regexp.escape(event)}\[95\] '#{Regexp.escape(command)}'$/
      assert_equal 1, macos_config.scan(pattern).length, "missing unique #{event}[95] manifest hook"
    end
    refute_includes linux_config, "ghostty-session-manifest-save"
  end

  def test_applescript_uses_supported_tab_index_and_terminal_name
    require_saver
    script = File.read(SAVER)

    assert_includes script, "name of focused terminal of t"
    assert_includes script, "index of t"
    refute_includes script, "index of w"
  end

  private

  def require_saver
    assert File.executable?(SAVER), "missing executable #{SAVER}"
  end

  def run_saver(rows:, sessions:, ghostty_pid:, extra_env: {})
    File.write(@sessions, sessions.join("\n") + "\n")
    Open3.capture3(saver_env(rows:, ghostty_pid:).merge(extra_env), SAVER)
  end

  def saver_env(rows:, ghostty_pid:)
    {
      "HOME" => @home,
      "PATH" => "#{@bin}:#{ENV.fetch("PATH")}",
      "FAKE_GHOSTTY_ROWS" => rows.map { |row| row.join("\t") }.join("\n"),
      "FAKE_GHOSTTY_PID" => ghostty_pid.to_s,
      "FAKE_TMUX_SESSIONS" => @sessions,
      "TMUX_GHOSTTY_MANIFEST" => @manifest,
      "TMUX_GHOSTTY_MANIFEST_LOCK" => @manifest_lock
    }
  end

  def task_body(tasks, name)
    match = tasks.match(/^- name: #{Regexp.escape(name)}\n(?<body>(?:^(?!- name: ).*\n?)*)/)
    refute_nil match, "missing Ansible task: #{name}"
    match[:body]
  end

  def write_executable(name, content)
    path = File.join(@bin, name)
    File.write(path, content)
    FileUtils.chmod(0o755, path)
  end

  def write_fake_osascript
    write_executable("osascript", <<~'BASH')
      #!/usr/bin/env bash
      [ -z "${FAKE_OSASCRIPT_MARKER:-}" ] || : >"$FAKE_OSASCRIPT_MARKER"
      [ -z "${FAKE_OSASCRIPT_SLEEP:-}" ] || sleep "$FAKE_OSASCRIPT_SLEEP"
      printf '%s\n' "${FAKE_GHOSTTY_ROWS:-}"
    BASH
  end

  def write_fake_pgrep
    write_executable("pgrep", <<~'BASH')
      #!/usr/bin/env bash
      [ -n "${FAKE_GHOSTTY_PID:-}" ] || exit 1
      printf '%s\n' "$FAKE_GHOSTTY_PID"
    BASH
  end

  def write_fake_tmux
    write_executable("tmux", <<~'BASH')
      #!/usr/bin/env bash
      if [ "${1:-}" = "has-session" ] && [ "${2:-}" = "-t" ]; then
        target="${3#=}"
        grep -Fxq -- "$target" "$FAKE_TMUX_SESSIONS"
        exit
      fi
      exit 64
    BASH
  end

  def write_fake_restore_logger
    logger = File.join(@home, ".local", "bin", "tmux-restore-log.sh")
    FileUtils.mkdir_p(File.dirname(logger))
    File.write(logger, <<~'BASH')
      tmux_restore_log_event() {
        [ -z "${FAKE_RESTORE_LOG:-}" ] || printf '%s\n' "$*" >>"$FAKE_RESTORE_LOG"
      }
    BASH
  end
end
