#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"

REPO_ROOT = File.expand_path("..", __dir__)
SAVE_WRAPPER = File.join(REPO_ROOT, "roles/common/files/bin/tmux-resurrect-save-wrapper")

class TmuxResurrectSaveWrapperTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("tmux-resurrect-save-wrapper")
    @save_script = File.join(@tmpdir, "save")
    @lock = File.join(@tmpdir, "save.lock")
    @active = File.join(@tmpdir, "active")
    @entered = File.join(@tmpdir, "entered")
    @overlap = File.join(@tmpdir, "overlap")
    @arguments = File.join(@tmpdir, "arguments")
    write_blocking_save
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_complete_upstream_saves_are_serialized_with_arguments_and_status_preserved
    first_args = ["--first", "value with spaces"]
    second_args = ["--second", "semi;colon"]

    first = spawn_save(*first_args)
    wait_until { File.exist?(@entered) }
    second = spawn_save(*second_args)

    _, first_status = Process.wait2(first)
    _, second_status = Process.wait2(second)

    refute File.exist?(@overlap), "concurrent upstream save commands overlapped"
    assert_equal 23, first_status.exitstatus
    assert_equal 23, second_status.exitstatus
    assert_equal [first_args, second_args].sort, File.readlines(@arguments, chomp: true).map { |line| JSON.parse(line) }.sort
  end

  private

  def spawn_save(*args)
    env = {
      "TMUX_RESURRECT_SAVE_SCRIPT" => @save_script,
      "TMUX_RESURRECT_SAVE_LOCK" => @lock,
      "FAKE_SAVE_ACTIVE" => @active,
      "FAKE_SAVE_ENTERED" => @entered,
      "FAKE_SAVE_OVERLAP" => @overlap,
      "FAKE_SAVE_ARGUMENTS" => @arguments
    }
    command = File.exist?(SAVE_WRAPPER) ? SAVE_WRAPPER : @save_script
    Process.spawn(env, command, *args, out: File::NULL, err: File::NULL)
  end

  def wait_until(timeout: 3)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      raise "timed out waiting for fake save" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.01
    end
  end

  def write_blocking_save
    File.write(@save_script, <<~'RUBY')
      #!/usr/bin/env ruby
      require "json"

      owns_active = false
      begin
        Dir.mkdir(ENV.fetch("FAKE_SAVE_ACTIVE"))
        owns_active = true
      rescue Errno::EEXIST
        File.write(ENV.fetch("FAKE_SAVE_OVERLAP"), "overlap\n")
      end

      File.open(ENV.fetch("FAKE_SAVE_ARGUMENTS"), "a") { |file| file.puts(JSON.generate(ARGV)) }
      File.write(ENV.fetch("FAKE_SAVE_ENTERED"), "entered\n")
      sleep 0.3
      Dir.rmdir(ENV.fetch("FAKE_SAVE_ACTIVE")) if owns_active
      exit 23
    RUBY
    FileUtils.chmod(0o755, @save_script)
  end
end
