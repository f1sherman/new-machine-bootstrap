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

class GhosttySessionManifestTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("ghostty-session-manifest")
    @home = File.join(@tmpdir, "home")
    @bin = File.join(@tmpdir, "bin")
    @manifest = File.join(@home, ".local", "state", "tmux", "ghostty-session-manifest.json")
    @sessions = File.join(@tmpdir, "sessions")
    FileUtils.mkdir_p(@bin)
    write_fake_osascript
    write_fake_pgrep
    write_fake_tmux
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

  def run_saver(rows:, sessions:, ghostty_pid:)
    File.write(@sessions, sessions.join("\n") + "\n")
    env = {
      "HOME" => @home,
      "PATH" => "#{@bin}:#{ENV.fetch("PATH")}",
      "FAKE_GHOSTTY_ROWS" => rows.map { |row| row.join("\t") }.join("\n"),
      "FAKE_GHOSTTY_PID" => ghostty_pid.to_s,
      "FAKE_TMUX_SESSIONS" => @sessions,
      "TMUX_GHOSTTY_MANIFEST" => @manifest
    }
    Open3.capture3(env, SAVER)
  end

  def write_executable(name, content)
    path = File.join(@bin, name)
    File.write(path, content)
    FileUtils.chmod(0o755, path)
  end

  def write_fake_osascript
    write_executable("osascript", <<~'BASH')
      #!/usr/bin/env bash
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
end
