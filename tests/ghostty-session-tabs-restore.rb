#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"

REPO_ROOT = File.expand_path("..", __dir__)
BUILDER = File.join(REPO_ROOT, "roles/macos/files/bin/ghostty-session-tabs-restore")

class GhosttySessionTabsRestoreTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("ghostty-session-tabs-restore")
    @home = File.join(@tmpdir, "home")
    @bin = File.join(@tmpdir, "bin")
    @manifest = File.join(@tmpdir, "manifest.json")
    @queue = File.join(@tmpdir, "queue.json")
    @actions = File.join(@tmpdir, "actions.log")
    @events = File.join(@tmpdir, "events.log")
    @log_lib = File.join(@tmpdir, "tmux-restore-log.sh")
    FileUtils.mkdir_p(@bin)
    write_fake_osascript
    write_fake_ps
    write_log_library
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_creates_one_tab_per_pending_claim_and_restores_selection
    require_builder
    write_manifest(selected: 3, sessions: %w[journal hnp nmb command-proxy misc])
    write_queue(pid: Process.pid, pending: %w[hnp nmb command-proxy misc])

    _out, err, status = run_builder

    assert status.success?, err
    actions = File.readlines(@actions, chomp: true)
    assert_equal ["create", "create", "create", "create", "select:3"], actions
    assert_equal [], JSON.parse(File.read(@queue)).fetch("pending")
    assert_event(/event=tab_builder_complete\tghostty_pid=#{Process.pid}\tcreated=4/)
  end

  def test_non_ghostty_pid_creates_no_tabs
    require_builder
    write_manifest(selected: 1, sessions: %w[journal hnp])
    write_queue(pid: Process.pid, pending: ["hnp"])

    _out, _err, status = run_builder("FAKE_PID_COMMAND" => "/usr/bin/ruby tests")

    assert status.success?
    refute File.exist?(@actions)
    assert_event(/event=tab_builder_skipped\treason=invalid_process/)
  end

  def test_stale_queue_pid_creates_no_tabs
    require_builder
    write_manifest(selected: 1, sessions: %w[journal hnp])
    write_queue(pid: Process.pid + 1, pending: ["hnp"])

    _out, _err, status = run_builder

    assert status.success?
    refute File.exist?(@actions)
    assert_event(/event=tab_builder_skipped\treason=stale_queue/)
  end

  def test_queue_pid_change_stops_before_second_tab
    require_builder
    write_manifest(selected: 1, sessions: %w[journal hnp nmb])
    write_queue(pid: Process.pid, pending: %w[hnp nmb])

    _out, _err, status = run_builder("FAKE_QUEUE_PID_CHANGE" => "1")

    refute status.success?
    assert_equal ["create"], File.readlines(@actions, chomp: true)
    assert_event(/event=tab_builder_failed\treason=stale_queue/)
  end

  def test_selection_uses_original_manifest_when_saver_replaces_it
    require_builder
    write_manifest(selected: 2, sessions: %w[journal hnp])
    write_queue(pid: Process.pid, pending: ["hnp"])

    _out, err, status = run_builder("FAKE_MANIFEST_REPLACEMENT" => "1")

    assert status.success?, err
    assert_equal ["create", "select:2"], File.readlines(@actions, chomp: true)
  end

  def test_empty_queue_creates_no_tabs
    require_builder
    write_manifest(selected: 1, sessions: ["journal"])
    write_queue(pid: Process.pid, pending: [])

    _out, _err, status = run_builder

    assert status.success?
    refute File.exist?(@actions)
  end

  def test_applescript_failure_stops_without_creating_more_tabs
    require_builder
    write_manifest(selected: 1, sessions: %w[journal hnp nmb])
    write_queue(pid: Process.pid, pending: %w[hnp nmb])

    _out, _err, status = run_builder("FAKE_OSASCRIPT_CREATE_FAILURE" => "1")

    refute status.success?
    assert_equal ["create-failed"], File.readlines(@actions, chomp: true)
    assert_equal %w[hnp nmb], JSON.parse(File.read(@queue)).fetch("pending")
  end

  def test_claim_timeout_stops_after_one_created_tab
    require_builder
    write_manifest(selected: 1, sessions: %w[journal hnp nmb])
    write_queue(pid: Process.pid, pending: %w[hnp nmb])

    _out, _err, status = run_builder("FAKE_QUEUE_STUCK" => "1")

    refute status.success?
    assert_equal ["create"], File.readlines(@actions, chomp: true)
    assert_equal %w[hnp nmb], JSON.parse(File.read(@queue)).fetch("pending")
    assert_event(/event=tab_builder_failed\treason=claim_timeout\tsession=hnp/)
  end

  private

  def require_builder
    assert File.executable?(BUILDER), "missing executable #{BUILDER}"
  end

  def write_manifest(selected:, sessions:)
    tabs = sessions.each_with_index.map do |name, index|
      { "tab_index" => index + 1, "session_name" => name }
    end
    File.write(@manifest, JSON.generate(
      "version" => 1,
      "ghostty_pid" => 100,
      "windows" => [{ "window_ordinal" => 1, "selected_tab_index" => selected, "tabs" => tabs }]
    ))
  end

  def write_queue(pid:, pending:)
    File.write(@queue, JSON.generate("version" => 1, "ghostty_pid" => pid, "pending" => pending))
  end

  def run_builder(extra = {})
    env = {
      "HOME" => @home,
      "PATH" => "#{@bin}:#{ENV.fetch("PATH")}",
      "TMUX_GHOSTTY_APP_PID" => Process.pid.to_s,
      "TMUX_GHOSTTY_MANIFEST" => @manifest,
      "TMUX_GHOSTTY_RESTORE_QUEUE" => @queue,
      "TMUX_GHOSTTY_TABS_RESTORE_LOCK" => File.join(@tmpdir, "builder.lock"),
      "TMUX_GHOSTTY_TABS_RESTORE_MAX_POLLS" => "3",
      "TMUX_GHOSTTY_TABS_RESTORE_POLL_INTERVAL" => "0.01",
      "TMUX_RESTORE_LOG_LIB" => @log_lib,
      "FAKE_GHOSTTY_ACTIONS" => @actions,
      "FAKE_GHOSTTY_QUEUE" => @queue,
      "FAKE_GHOSTTY_MANIFEST" => @manifest,
      "FAKE_PID_COMMAND" => "/Applications/Ghostty.app/Contents/MacOS/ghostty"
    }.merge(extra)
    Open3.capture3(env, BUILDER)
  end

  def assert_event(pattern)
    contents = File.exist?(@events) ? File.read(@events) : ""
    assert_match pattern, contents
  end

  def write_executable(name, content)
    path = File.join(@bin, name)
    File.write(path, content)
    FileUtils.chmod(0o755, path)
  end

  def write_fake_osascript
    write_executable("osascript", <<~'BASH')
      #!/usr/bin/env bash
      script="$(cat)"
      case "$script" in
        *"return id of front window"*)
          printf '%s\n' 'window-1'
          ;;
        *"new tab in targetWindow"*)
          if [ "${FAKE_OSASCRIPT_CREATE_FAILURE:-0}" = "1" ]; then
            printf '%s\n' 'create-failed' >> "$FAKE_GHOSTTY_ACTIONS"
            exit 1
          fi
          printf '%s\n' 'create' >> "$FAKE_GHOSTTY_ACTIONS"
          if [ "${FAKE_QUEUE_STUCK:-0}" != "1" ]; then
            tmp="$(mktemp "$(dirname "$FAKE_GHOSTTY_QUEUE")/queue.XXXXXX")"
            if [ "${FAKE_QUEUE_PID_CHANGE:-0}" = "1" ]; then
              jq '.pending |= .[1:] | .ghostty_pid += 1' "$FAKE_GHOSTTY_QUEUE" > "$tmp"
            else
              jq '.pending |= .[1:]' "$FAKE_GHOSTTY_QUEUE" > "$tmp"
            fi
            mv "$tmp" "$FAKE_GHOSTTY_QUEUE"
          fi
          if [ "${FAKE_MANIFEST_REPLACEMENT:-0}" = "1" ]; then
            tmp="$(mktemp "$(dirname "$FAKE_GHOSTTY_MANIFEST")/manifest.XXXXXX")"
            jq '.windows[0].selected_tab_index = 1' "$FAKE_GHOSTTY_MANIFEST" > "$tmp"
            mv "$tmp" "$FAKE_GHOSTTY_MANIFEST"
          fi
          ;;
        *"select tab"*)
          selected="$(printf '%s\n' "$script" | sed -n 's/.*tab \([0-9][0-9]*\) of targetWindow.*/\1/p' | head -n 1)"
          printf 'select:%s\n' "$selected" >> "$FAKE_GHOSTTY_ACTIONS"
          ;;
        *)
          exit 64
          ;;
      esac
    BASH
  end

  def write_fake_ps
    write_executable("ps", <<~'BASH')
      #!/usr/bin/env bash
      printf '%s\n' "$FAKE_PID_COMMAND"
    BASH
  end

  def write_log_library
    File.write(@log_lib, <<~SH)
      tmux_restore_log_event() {
        event="$1"
        shift
        {
          printf 'event=%s' "$event"
          for field in "$@"; do printf '\\t%s' "$field"; done
          printf '\\n'
        } >> "#{@events}"
      }
    SH
  end
end
