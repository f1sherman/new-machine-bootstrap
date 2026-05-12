#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

REPO_ROOT = File.expand_path("..", __dir__)
HELPER = File.join(REPO_ROOT, "roles/common/files/bin/tmux-pane-title-changed")
CONFIGS = [
  File.join(REPO_ROOT, "roles/macos/templates/dotfiles/tmux.conf"),
  File.join(REPO_ROOT, "roles/linux/files/dotfiles/tmux.conf")
].freeze

@pass = 0
@fail = 0

def pass(label)
  @pass += 1
  puts "PASS  #{label}"
end

def fail(label, detail)
  @fail += 1
  warn "FAIL  #{label}"
  warn "      #{detail}"
end

def assert(label, detail = nil)
  if yield
    pass(label)
  else
    fail(label, detail || "assertion failed")
  end
end

def write_executable(path, body)
  File.write(path, body)
  FileUtils.chmod("+x", path)
end

def run_helper(tmpdir, *args, title:, structured: false)
  env = {
    "PATH" => "#{File.join(tmpdir, "bin")}:#{ENV.fetch("PATH")}",
    "TMUX_TEST_LOG" => File.join(tmpdir, "calls.log"),
    "TMUX_TEST_TITLE" => title,
    "TMUX_TEST_STRUCTURED" => structured ? "1" : "0"
  }
  out, err, status = Open3.capture3(env, HELPER, *args)
  [out, err, status, File.read(env["TMUX_TEST_LOG"])]
end

assert("pane title helper exists", HELPER) { File.exist?(HELPER) }
assert("pane title helper is executable", HELPER) { File.executable?(HELPER) }

CONFIGS.each do |config|
  line = File.readlines(config).find { |candidate| candidate.include?("set-hook -g pane-title-changed") }
  assert("#{config} defines pane-title-changed hook") { line }
  next unless line

  assert("#{config} routes pane-title-changed through helper") do
    line.include?("tmux-pane-title-changed")
  end
  assert("#{config} passes hook pane target first") do
    line.include?('tmux-pane-title-changed #{hook_pane} #{pane_id}')
  end
  assert("#{config} gates pane-title-changed before spawning a shell") do
    line.include?("if-shell -F") &&
      line.include?('#{m:* | *,#{pane_title}}') &&
      line.include?('#{@pane-title-structured}')
  end
  assert("#{config} avoids inline set-option in pane-title-changed") do
    !line.include?("set-option")
  end
end

if File.exist?(HELPER) && File.executable?(HELPER)
  Dir.mktmpdir("tmux-pane-title-test") do |tmpdir|
  bin = File.join(tmpdir, "bin")
  FileUtils.mkdir_p(bin)
  File.write(File.join(tmpdir, "calls.log"), "")

  write_executable(File.join(bin, "tmux"), <<~'RUBY')
    #!/usr/bin/env ruby
    args = ARGV
    File.open(ENV.fetch("TMUX_TEST_LOG"), "a") { |f| f.puts((["tmux"] + args).join("\t")) }

    if args[0, 3] == ["display-message", "-p", "-t"] && args[4] == '#{pane_title}'
      puts ENV.fetch("TMUX_TEST_TITLE")
    elsif args[0, 4] == ["show-options", "-qv", "-p", "-t"] && args[5] == "@pane-title-structured"
      exit 1 unless ENV.fetch("TMUX_TEST_STRUCTURED") == "1"
      puts "1"
    elsif args[0] == "set-option"
      exit 0
    else
      warn "unexpected tmux args: #{args.inspect}"
      exit 9
    end
  RUBY

  %w[tmux-sync-remote-title tmux-sync-pane-border-status tmux-update-pane-label].each do |name|
    write_executable(File.join(bin, name), <<~RUBY)
      #!/usr/bin/env ruby
      File.open(ENV.fetch("TMUX_TEST_LOG"), "a") { |f| f.puts(([#{name.inspect}] + ARGV).join("\\t")) }
    RUBY
  end

  _out, err, status, log = run_helper(tmpdir, "", "", title: "ignored", structured: false)
  assert("empty pane targets are a quiet no-op", err) { status.success? && log.empty? }

  File.write(File.join(tmpdir, "calls.log"), "")
  _out, err, status, log = run_helper(tmpdir, "%91", title: "repo | dev", structured: false)
  assert("structured title marks pane structured", err) do
    status.success? && log.include?("tmux\tset-option\t-p\t-q\t-t\t%91\t@pane-title-structured\t1")
  end
  assert("structured title refreshes remote title and labels", log) do
    log.include?("tmux-sync-remote-title\t%91") &&
      log.include?("tmux-sync-pane-border-status\t%91") &&
      log.include?("tmux-update-pane-label\t%91")
  end

  File.write(File.join(tmpdir, "calls.log"), "")
  _out, err, status, log = run_helper(tmpdir, "", "%92", title: "repo | dev", structured: false)
  assert("fallback pane target is used when hook pane is empty", err) do
    status.success? && log.include?("tmux\tset-option\t-p\t-q\t-t\t%92\t@pane-title-structured\t1")
  end

  File.write(File.join(tmpdir, "calls.log"), "")
  _out, err, status, log = run_helper(tmpdir, "%93", title: "repo", structured: true)
  assert("unstructured title clears previous structured marker", err) do
    status.success? && log.include?("tmux\tset-option\t-p\t-q\t-u\t-t\t%93\t@pane-title-structured")
  end
    assert("unstructured title refreshes labels without remote title sync", log) do
      log.include?("tmux-sync-pane-border-status\t%93") &&
        log.include?("tmux-update-pane-label\t%93") &&
        !log.include?("tmux-sync-remote-title\t%93")
    end
  end
end

puts
puts "#{@pass} passed, #{@fail} failed"
exit(@fail.zero? ? 0 : 1)
