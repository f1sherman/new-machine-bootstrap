#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

REPO_ROOT = File.expand_path("..", __dir__)
SAVE_EXTRA = File.join(REPO_ROOT, "roles/common/files/bin/tmux-resurrect-save-extra")

class TmuxResurrectSaveExtraTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("tmux-resurrect-save-extra")
    @home = File.join(@tmpdir, "home")
    @bin = File.join(@tmpdir, "bin")
    @resurrect_dir = File.join(@home, ".tmux", "resurrect")
    @state_file = File.join(@resurrect_dir, "tmux_resurrect_20260727T120000.txt")
    @last = File.join(@resurrect_dir, "last")
    FileUtils.mkdir_p([@bin, @resurrect_dir])
    File.write(@state_file, "pane\tone\npane\ttwo\npane\tthree\n#{"state\n" * 200}")
    write_fake_tmux
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_same_target_last_is_removed_after_safe_rotation
    File.symlink(File.basename(@state_file), @last)

    run_save_extra

    assert File.file?(File.join(@resurrect_dir, "last.safe"))
    refute File.exist?(@last)
    refute File.symlink?(@last)
  end

  def test_different_target_last_remains_unchanged
    different_state = File.join(@resurrect_dir, "tmux_resurrect_20260727T110000.txt")
    File.write(different_state, "previous state\n")
    File.symlink(File.basename(different_state), @last)

    run_save_extra

    assert File.symlink?(@last)
    assert_equal File.basename(different_state), File.readlink(@last)
  end

  private

  def run_save_extra
    env = {
      "HOME" => @home,
      "PATH" => "#{@bin}:#{ENV.fetch("PATH")}"
    }
    stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, SAVE_EXTRA, @state_file)
    assert status.success?, "save hook failed:\n#{stdout}\n#{stderr}"
  end

  def write_fake_tmux
    tmux = File.join(@bin, "tmux")
    File.write(tmux, "#!/bin/sh\nexit 0\n")
    FileUtils.chmod(0o755, tmux)
  end
end
