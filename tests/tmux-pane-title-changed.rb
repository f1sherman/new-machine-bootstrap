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
               task_state: "", task_source: "", task_label: "", agent_failure: false)
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
    "TMUX_TEST_TASK_LABEL" => task_label,
    "TMUX_TEST_AGENT_FAIL" => agent_failure ? "1" : "0"
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
    elsif args[0, 4] == ["show-options", "-qv", "-p", "-t"]
      case args[5]
      when "@pane-title-structured"
        exit 1 unless ENV.fetch("TMUX_TEST_STRUCTURED") == "1"
        puts "1"
      when "@task_state"
        puts ENV.fetch("TMUX_TEST_TASK_STATE")
      when "@task_source"
        puts ENV.fetch("TMUX_TEST_TASK_SOURCE")
      else
        exit 1
      end
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
    exit 1 if ENV.fetch("TMUX_TEST_AGENT_FAIL") == "1"
    if ARGV.first == "adopt-remote-provisional"
      system("tmux-window-label", ENV.fetch("TMUX_PANE")) or exit 1
    end
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
      structured: true,
      task_state: "provisional",
      task_source: "agent",
      task_label: "stale outer task"
    )
  end
  _out, err, status, log = provisional_results.last
  calls = log.lines.map(&:chomp)
  parser_call = calls.index { |call| call.start_with?("tmux-task-label\textract-remote-provisional") }
  state_call = calls.index("tmux-agent-state\tadopt-remote-provisional\trefined remote task")
  render_call = calls.index("tmux-window-label\t%95")
  border_call = calls.index("tmux-sync-pane-border-status\t%95")
  assert("eligible remote provisional title delegates canonical adoption before border sync", err) do
    provisional_results.all? { |result| result[2].success? } &&
      log.scan(/^tmux-task-label\textract-remote-provisional/).length == 2 &&
      log.scan(/^tmux-agent-state\tadopt-remote-provisional\trefined remote task$/).length == 2 &&
      !render_call.nil? && parser_call < state_call && state_call < render_call && render_call < border_call
  end
  assert("eligible remote provisional title avoids direct remote synchronization", log) do
    !log.include?("tmux-sync-remote-title\t%95") &&
      !log.include?("tmux-update-pane-label\t%95")
  end
  assert("state helper owns the only eligible window render", log) do
    log.scan(/^tmux-window-label\t%95$/).length == 2 &&
      log.scan(/^tmux-sync-pane-border-status\t%95$/).length == 2
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
  assert("active branch refreshes without remote canonical replacement", err) do
    status.success? &&
      !log.include?("tmux-agent-state\tadopt-remote-provisional") &&
      !log.include?("tmux-sync-remote-title\t%96") &&
      log.include?("tmux-update-pane-label\t%96")
  end

  File.write(File.join(tmpdir, "calls.log"), "")
  _out, err, status, log = run_helper(
    tmpdir,
    "%97",
    title: "~ valid but unavailable · project | remote-host",
    structured: true,
    task_state: "provisional",
    task_source: "agent",
    task_label: "last valid task",
    agent_failure: true
  )
  assert("state-helper failure preserves the last rendered task identity", err) do
    status.success? &&
      log.include?("tmux-agent-state\tadopt-remote-provisional\tvalid but unavailable") &&
      !log.include?("tmux-window-label\t%97") &&
      !log.include?("tmux-sync-remote-title\t%97") &&
      !log.include?("tmux-update-pane-label\t%97") &&
      log.include?("tmux-sync-pane-border-status\t%97")
  end

  [
    ["", "", "no prior task"],
    ["completed", "agent", "completed task"],
    ["provisional", "manual", "provisional non-agent task"],
    ["active", "goal", "active goal task"],
    ["active", "manual", "active manual task"]
  ].each_with_index do |(state, source, description), index|
    File.write(File.join(tmpdir, "calls.log"), "")
    _out, err, status, log = run_helper(
      tmpdir,
      "%#{100 + index}",
      title: "~ ignored remote task · project | remote-host",
      structured: true,
      task_state: state,
      task_source: source,
      task_label: description
    )
    assert("#{description} is not canonically adopted", err) do
      status.success? && !log.include?("tmux-agent-state\tadopt-remote-provisional")
    end
    if state.empty?
      assert("unmanaged structured title retains direct synchronization", log) do
        log.include?("tmux-sync-remote-title\t%#{100 + index}") &&
          log.include?("tmux-update-pane-label\t%#{100 + index}")
      end
    else
      assert("#{description} refreshes without direct remote rename", log) do
        !log.include?("tmux-sync-remote-title\t%#{100 + index}") &&
          log.include?("tmux-update-pane-label\t%#{100 + index}")
      end
    end
  end

  behavior_dir = File.join(tmpdir, "behavior")
  behavior_bin = File.join(behavior_dir, "bin")
  behavior_state = File.join(behavior_dir, "state")
  behavior_log = File.join(behavior_dir, "calls.log")
  FileUtils.mkdir_p([behavior_bin, behavior_state])
  File.write(behavior_log, "")
  pane = "%120"
  {
    "@task_label" => "stale outer task",
    "@task_source" => "agent",
    "@task_state" => "provisional",
    "@task_context" => "outer-project | outer-host",
    "@pane-label" => "~ stale outer task · outer-project | outer-host",
    "@window-label" => "~ stale outer task"
  }.each do |key, value|
    File.write(File.join(behavior_state, "#{pane}.#{key}"), value)
  end
  File.write(File.join(behavior_state, "window-name"), "~ stale outer task")

  write_executable(File.join(behavior_bin, "tmux"), <<~'RUBY')
    #!/usr/bin/env ruby
    require "fileutils"
    state = ENV.fetch("TMUX_BEHAVIOR_STATE")
    log = ENV.fetch("TMUX_BEHAVIOR_LOG")
    args = ARGV
    File.open(log, "a") { |file| file.puts((["tmux"] + args).join("\t")) }
    pane = "%120"

    case args.first
    when "display-message"
      format = args.last
      field_separator = "__NMB_TMUX_FIELD__"
      if format == "\#{pane_title}#{field_separator}\#{pane_current_command}"
        puts [ENV.fetch("TMUX_TEST_TITLE"), "ssh"].join(field_separator)
      elsif format.start_with?("\#{window_id}#{field_separator}")
        window_name = File.read(File.join(state, "window-name"))
        puts ["@120", "1", window_name, "/dev/null", "/tmp/outer-project", "ssh", ENV.fetch("TMUX_TEST_TITLE"), pane].join(field_separator)
      else
        exit 9
      end
    when "show-options"
      key = args.last
      path = File.join(state, "#{pane}.#{key}")
      exit 1 unless File.file?(path)
      print File.read(path)
    when "set-option"
      if args.include?("-u") || args.include?("-wqu")
        FileUtils.rm_f(File.join(state, "#{pane}.#{args.last}"))
      elsif (key_index = args.index { |arg| arg.start_with?("@") })
        File.write(File.join(state, "#{pane}.#{args[key_index]}"), args[key_index + 1].to_s)
      end
    when "rename-window"
      File.write(File.join(state, "window-name"), args.last)
      File.open(log, "a") { |file| file.puts("VISIBLE_RENAME\t#{args.last}") }
    else
      exit 9
    end
  RUBY
  write_executable(File.join(behavior_bin, "tmux-sync-pane-border-status"), <<~'RUBY')
    #!/usr/bin/env ruby
    File.open(ENV.fetch("TMUX_BEHAVIOR_LOG"), "a") { |file| file.puts((["tmux-sync-pane-border-status"] + ARGV).join("\t")) }
  RUBY
  write_executable(File.join(behavior_bin, "tmux-remote-title"), "#!/usr/bin/env bash\nexit 0\n")
  write_executable(File.join(behavior_bin, "failing-tmux-task-label"), <<~'BASH')
    #!/usr/bin/env bash
    if [[ "${1:-}" == "truncate" ]]; then
      exit 73
    fi
    exec "$TMUX_REAL_TASK_LABEL_BIN" "$@"
  BASH

  behavior_env = {
    "PATH" => "#{behavior_bin}:#{File.join(REPO_ROOT, "roles/common/files/bin")}:#{ENV.fetch("PATH")}",
    "TMUX" => "test",
    "TMUX_TASK_LABEL_BIN" => File.join(REPO_ROOT, "roles/common/files/bin/tmux-task-label"),
    "TMUX_AGENT_STATE_BIN" => File.join(REPO_ROOT, "roles/common/files/bin/tmux-agent-state"),
    "TMUX_AGENT_STATE_DIR" => behavior_state,
    "TMUX_AGENT_STATE_CURRENT_PATH" => "/tmp/outer-project",
    "TMUX_BEHAVIOR_STATE" => behavior_state,
    "TMUX_BEHAVIOR_LOG" => behavior_log,
    "TMUX_REAL_TASK_LABEL_BIN" => File.join(REPO_ROOT, "roles/common/files/bin/tmux-task-label"),
    "TMUX_TEST_TITLE" => "~ refined remote task · remote-project | remote-host [nmb-ind=waiting,]"
  }
  malformed_env = behavior_env.merge("TMUX_TEST_TITLE" => "~ rejected remote task ·    | remote-host")
  malformed_result = Open3.capture3(malformed_env, HELPER, pane)
  malformed_calls = File.read(behavior_log)
  assert("malformed structured title cannot mutate canonical state", malformed_result[1]) do
    malformed_result[2].success? &&
      File.read(File.join(behavior_state, "#{pane}.@task_label")) == "stale outer task" &&
      !malformed_calls.include?("VISIBLE_RENAME")
  end

  preserved_paths = %w[@task_label @task_source @task_state @task_context @pane-label @window-label].to_h do |key|
    [key, File.join(behavior_state, "#{pane}.#{key}")]
  end
  preserved_before = preserved_paths.transform_values { |path| File.read(path) }
  visible_before = File.read(File.join(behavior_state, "window-name"))
  File.write(behavior_log, "")
  failure_env = behavior_env.merge(
    "TMUX_TASK_LABEL_BIN" => File.join(behavior_bin, "failing-tmux-task-label")
  )
  failure_result = Open3.capture3(failure_env, HELPER, pane)
  failure_calls = File.read(behavior_log)
  assert("real state-helper render failure preserves every observable task option", failure_result[1]) do
    failure_result[2].success? &&
      preserved_paths.all? { |key, path| File.read(path) == preserved_before.fetch(key) }
  end
  assert("real state-helper render failure preserves the visible window name", failure_calls) do
    File.read(File.join(behavior_state, "window-name")) == visible_before &&
      !failure_calls.include?("VISIBLE_RENAME")
  end

  File.write(behavior_log, "")
  behavior_results = 2.times.map { Open3.capture3(behavior_env, HELPER, pane) }
  behavior_calls = File.read(behavior_log)
  assert("real parser and state helper adopt the full remote subject", behavior_results.map { |result| result[1] }.join) do
    behavior_results.all? { |result| result[2].success? } &&
      File.read(File.join(behavior_state, "#{pane}.@task_label")) == "refined remote task" &&
      File.read(File.join(behavior_state, "#{pane}.@task_source")) == "agent" &&
      File.read(File.join(behavior_state, "#{pane}.@task_state")) == "provisional"
  end
  assert("eligible adoption updates pane and window state before one visible rename", behavior_calls) do
    File.read(File.join(behavior_state, "#{pane}.@pane-label")) == "~ refined remote task · outer-project | outer-host" &&
      File.read(File.join(behavior_state, "#{pane}.@window-label")) == "~ refined remote task" &&
      File.read(File.join(behavior_state, "window-name")) == "~ refined remote task" &&
      behavior_calls.scan(/^VISIBLE_RENAME\t~ refined remote task$/).length == 1 &&
      !behavior_calls.include?("VISIBLE_RENAME\t~ stale outer task")
  end
  assert("repeated publication does not duplicate the visible rename", behavior_calls) do
    behavior_calls.scan(/^VISIBLE_RENAME/).length == 1 &&
      behavior_calls.scan(/^tmux-sync-pane-border-status\t%120$/).length == 2
  end
  end
end

puts
puts "#{@pass} passed, #{@fail} failed"
exit(@fail.zero? ? 0 : 1)
