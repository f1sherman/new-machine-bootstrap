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

def run_helper(tmpdir, *args, title:, command: "ssh", structured: false,
               task_state: "", task_source: "", task_label: "")
  bin = File.join(tmpdir, "bin")
  env = {
    "PATH" => "#{bin}:#{ENV.fetch("PATH")}",
    "TMUX_TASK_LABEL_BIN" => File.join(bin, "tmux-task-label"),
    "TMUX_AGENT_STATE_BIN" => File.join(bin, "tmux-agent-state"),
    "TMUX_TEST_LOG" => File.join(tmpdir, "calls.log"),
    "TMUX_TEST_TITLE" => title,
    "TMUX_TEST_COMMAND" => command,
    "TMUX_TEST_STRUCTURED" => structured ? "1" : "0",
    "TMUX_TEST_TASK_STATE" => task_state,
    "TMUX_TEST_TASK_SOURCE" => task_source,
    "TMUX_TEST_TASK_LABEL" => task_label
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

    field_separator = "__NMB_TMUX_FIELD__"
    if args[0, 3] == ["display-message", "-p", "-t"] && args[4] == "\#{pane_title}#{field_separator}\#{pane_current_command}"
      puts [ENV.fetch("TMUX_TEST_TITLE"), ENV.fetch("TMUX_TEST_COMMAND")].join(field_separator)
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

  %w[tmux-sync-remote-title tmux-sync-pane-border-status tmux-update-pane-label tmux-window-label].each do |name|
    write_executable(File.join(bin, name), <<~RUBY)
      #!/usr/bin/env ruby
      File.open(ENV.fetch("TMUX_TEST_LOG"), "a") { |f| f.puts(([#{name.inspect}] + ARGV).join("\\t")) }
    RUBY
  end

  write_executable(File.join(bin, "tmux-task-label"), <<~'RUBY')
    #!/usr/bin/env ruby
    File.open(ENV.fetch("TMUX_TEST_LOG"), "a") { |f| f.puts((["tmux-task-label"] + ARGV).join("\t")) }
    exit 1 unless ARGV.first == "extract-remote-provisional"
    title = ARGV.drop(1).join(" ")
    match = title.match(/^~ (.*) · .* \| /)
    exit 1 unless match
    puts match[1]
  RUBY

  write_executable(File.join(bin, "tmux-agent-state"), <<~'RUBY')
    #!/usr/bin/env ruby
    File.open(ENV.fetch("TMUX_TEST_LOG"), "a") { |f| f.puts((["tmux-agent-state"] + ARGV).join("\t")) }
  RUBY

  _out, err, status, log = run_helper(tmpdir, "", "", title: "ignored", structured: false)
  assert("empty pane targets are a quiet no-op", err) { status.success? && log.empty? }

  File.write(File.join(tmpdir, "calls.log"), "")
  _out, err, status, log = run_helper(tmpdir, "%91", title: "repo | remote-host", structured: false)
  assert("structured title marks pane structured", err) do
    status.success? && log.include?("tmux\tset-option\t-p\t-q\t-t\t%91\t@pane-title-structured\t1")
  end
  assert("structured non-provisional title refreshes remote title and labels", log) do
    log.include?("tmux-task-label\textract-remote-provisional\trepo | remote-host") &&
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
  _out, err, status, log = run_helper(tmpdir, "%93", title: "dev-host", structured: true)
  assert("degraded title preserves previous structured marker", err) do
    status.success? &&
      !log.include?("tmux\tset-option\t-p\t-q\t-u\t-t\t%93\t@pane-title-structured")
  end
  assert("degraded title cannot overwrite structured task labels", log) do
    !log.include?("tmux-sync-remote-title\t%93") &&
      !log.include?("tmux-sync-pane-border-status\t%93") &&
      !log.include?("tmux-update-pane-label\t%93") &&
      !log.include?("tmux-window-label\t%93")
  end

  File.write(File.join(tmpdir, "calls.log"), "")
  _out, err, status, log = run_helper(tmpdir, "%94", title: "dev-host", command: "zsh", structured: true)
  assert("same-pane remote exit clears structured marker immediately", err) do
    status.success? &&
      log.include?("tmux\tset-option\t-p\t-q\t-u\t-t\t%94\t@pane-title-structured")
  end
  assert("same-pane remote exit refreshes pane and window labels immediately", log) do
    log.include?("tmux-sync-pane-border-status\t%94") &&
      log.include?("tmux-update-pane-label\t%94") &&
      log.include?("tmux-window-label\t%94") &&
      !log.include?("tmux-sync-remote-title\t%94")
  end

  File.write(File.join(tmpdir, "calls.log"), "")
  provisional_results = 2.times.map do
    run_helper(
      tmpdir,
      "%95",
      title: "~ refined remote task · project | remote-host [nmb-ind=waiting,]",
      structured: true
    )
  end
  _out, err, status, log = provisional_results.last
  calls = log.lines.map(&:chomp)
  parser_call = calls.index { |call| call.start_with?("tmux-task-label\textract-remote-provisional") }
  state_call = calls.index("tmux-agent-state\tset-provisional\trefined remote task")
  render_call = calls.index("tmux-sync-pane-border-status\t%95")
  assert("remote provisional title updates canonical state before rendering", err) do
    provisional_results.all? { |result| result[2].success? } &&
      log.scan(/^tmux-task-label\textract-remote-provisional/).length == 2 &&
      log.scan(/^tmux-agent-state\tset-provisional\trefined remote task$/).length == 2 &&
      !render_call.nil? && parser_call < state_call && state_call < render_call
  end
  assert("remote provisional title avoids intermediate direct rename", log) do
    !log.include?("tmux-sync-remote-title\t%95")
  end
  assert("remote provisional title renders canonical pane and window labels", log) do
    log.scan(/^tmux-sync-pane-border-status\t%95$/).length == 2 &&
      log.scan(/^tmux-window-label\t%95$/).length == 2 &&
      !log.include?("tmux-update-pane-label\t%95")
  end

  File.write(File.join(tmpdir, "calls.log"), "")
  _out, err, status, log = run_helper(
    tmpdir,
    "%96",
    title: "~ ignored remote task · project | remote-host [nmb-ind=waiting,]",
    structured: true,
    task_state: "active",
    task_source: "branch",
    task_label: "local-feature"
  )
  assert("active branch retains canonical state authority", err) do
    status.success? &&
      log.include?("tmux-agent-state\tset-provisional\tignored remote task") &&
      !log.include?("tmux-sync-remote-title\t%96") &&
      !log.include?("tmux-update-pane-label\t%96")
  end
  end
end

puts
puts "#{@pass} passed, #{@fail} failed"
exit(@fail.zero? ? 0 : 1)
