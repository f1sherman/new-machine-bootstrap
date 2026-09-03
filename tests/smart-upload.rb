#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "tmpdir"

REPO_ROOT = File.expand_path("..", __dir__)
SCRIPT = File.join(REPO_ROOT, "roles/macos/files/bin/smart-upload")

class SmartUploadTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("smart-upload")
    @home = File.join(@tmpdir, "home")
    @bin = File.join(@tmpdir, "bin")
    @ssh_log = File.join(@tmpdir, "ssh.log")
    @scp_log = File.join(@tmpdir, "scp.log")
    @tmux_log = File.join(@tmpdir, "tmux.log")
    @clipboard_log = File.join(@tmpdir, "clipboard.log")
    FileUtils.mkdir_p([@home, @bin])
    write_fake("ssh", "FAKE_SSH_LOG")
    write_fake("scp", "FAKE_SCP_LOG")
    write_fake("tmux", "FAKE_TMUX_LOG")
    write_fake("osascript", "FAKE_CLIPBOARD_LOG")
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_uploads_to_explicit_target_without_tmux_status_or_clipboard_detection
    source_path = File.join(@tmpdir, "example.txt")
    File.write(source_path, "example")

    stdout, stderr, status = Open3.capture3(
      env,
      SCRIPT,
      source_path,
      "",
      "--ssh-target", "dev-alias",
      "--quiet-status"
    )

    assert status.success?, stderr
    assert_equal "/tmp/uploads/example.txt", stdout
    assert_equal ["dev-alias", "mkdir", "--parents", "/tmp/uploads"],
                 File.readlines(@ssh_log, chomp: true)
    assert_equal ["-q", source_path, "dev-alias:/tmp/uploads/example.txt"],
                 File.readlines(@scp_log, chomp: true)
    refute File.exist?(@tmux_log)
    refute File.exist?(@clipboard_log)
  end

  def test_rejects_empty_explicit_target_without_uploading
    source_path = File.join(@tmpdir, "example.txt")
    File.write(source_path, "example")

    _stdout, _stderr, status = Open3.capture3(
      env,
      SCRIPT,
      source_path,
      "",
      "--ssh-target", ""
    )

    refute status.success?
    refute File.exist?(@ssh_log)
    refute File.exist?(@scp_log)
  end

  def test_passes_through_legacy_clipboard_text_that_starts_with_a_dash
    stdout, stderr, status = Open3.capture3(env, SCRIPT, "--foo", "")

    assert status.success?, stderr
    assert_equal "--foo", stdout
    refute File.exist?(@ssh_log)
    refute File.exist?(@scp_log)
  end

  private

  def env
    {
      "HOME" => @home,
      "PATH" => "#{@bin}:#{ENV.fetch("PATH")}",
      "FAKE_SSH_LOG" => @ssh_log,
      "FAKE_SCP_LOG" => @scp_log,
      "FAKE_TMUX_LOG" => @tmux_log,
      "FAKE_CLIPBOARD_LOG" => @clipboard_log
    }
  end

  def write_fake(name, log_variable)
    path = File.join(@bin, name)
    File.write(path, <<~SH)
      #!/bin/sh
      printf '%s\\n' "$@" >>"$#{log_variable}"
    SH
    FileUtils.chmod(0o755, path)
  end
end
