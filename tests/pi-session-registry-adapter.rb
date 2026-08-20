#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"

repo_root = File.expand_path("..", __dir__)
adapter = File.join(
  repo_root,
  "roles/common/files/agent-session-registry/adapters/pi-local"
)

passed = 0
failed = 0

assert = lambda do |condition, name, detail = nil|
  if condition
    passed += 1
    puts "PASS  #{name}"
  else
    failed += 1
    puts "FAIL  #{name}"
    puts "      #{detail}" if detail
  end
end

Dir.mktmpdir("pi-session-registry-adapter") do |tmpdir|
  fake_bin = File.join(tmpdir, "bin")
  FileUtils.mkdir_p(fake_bin)
  capture_path = File.join(tmpdir, "pi-argv.json")
  herdr_log = File.join(tmpdir, "herdr-log.jsonl")
  herdr_state = File.join(tmpdir, "herdr-state.json")

  File.write(File.join(fake_bin, "pi"), <<~RUBY)
    #!/usr/bin/env ruby
    require "json"
    File.write(ENV.fetch("PI_ARGV_CAPTURE"), JSON.generate(ARGV))
  RUBY

  File.write(File.join(fake_bin, "herdr"), <<~'RUBY')
    #!/usr/bin/env ruby
    require "json"

    state_path = ENV.fetch("HERDR_TEST_STATE")
    log_path = ENV.fetch("HERDR_TEST_LOG")
    state = JSON.parse(File.read(state_path))
    File.open(log_path, "a") { |file| file.puts(JSON.generate(ARGV)) }
    command = ARGV.take(2)

    if command == ["agent", "list"]
      abort "list failed" if state["fail_list"]
      puts JSON.generate("id" => "test:list", "result" => {
        "type" => "agent_list", "agents" => state.fetch("agents", [])
      })
    elsif command == ["workspace", "create"]
      abort "create failed" if state["fail_create"]
      response = state.fetch("create_response", {
        "id" => "test:create",
        "result" => {
          "type" => "workspace_created",
          "workspace" => {"workspace_id" => "w2"},
          "tab" => {"tab_id" => "w2:t1"},
          "root_pane" => {"pane_id" => "w2:p1"}
        }
      })
      puts JSON.generate(response)
    elsif command == ["agent", "start"]
      abort "start failed" if state["fail_start"]
      state["agents"] = [state.fetch("publish_agent")] if state["publish_agent"]
      File.write(state_path, JSON.generate(state))
      started_agent = state["publish_agent"] || {
        "workspace_id" => "w2", "pane_id" => "w2:p1"
      }
      puts JSON.generate("id" => "test:start", "result" => {
        "type" => "agent_started", "agent" => started_agent
      })
    elsif command == ["workspace", "focus"]
      abort "focus failed" if state["fail_focus"]
      puts JSON.generate("id" => "test:focus", "result" => {
        "type" => "workspace_focused", "workspace_id" => ARGV.fetch(2)
      })
    elsif command == ["workspace", "close"]
      puts JSON.generate("id" => "test:close", "result" => {
        "type" => "workspace_closed", "workspace_id" => ARGV.fetch(2)
      })
    else
      abort "unexpected herdr command: #{ARGV.inspect}"
    end
  RUBY
  FileUtils.chmod(0o755, Dir[File.join(fake_bin, "*")])

  run_adapter = lambda do |action, raw_config, herdr_env: nil, state: {}|
    FileUtils.rm_f(capture_path)
    FileUtils.rm_f(herdr_log)
    File.write(herdr_state, JSON.generate(state))
    env = {
      "PATH" => "#{fake_bin}:#{ENV.fetch("PATH")}",
      "PI_ARGV_CAPTURE" => capture_path,
      "HERDR_TEST_LOG" => herdr_log,
      "HERDR_TEST_STATE" => herdr_state,
      "HERDR_ENV" => nil,
      "ASR_ADAPTER_TIMEOUT" => "0.3",
      "ASR_ADAPTER_POLL_INTERVAL" => "0.01"
    }
    env["HERDR_ENV"] = herdr_env unless herdr_env.nil?
    result = Open3.capture3(
      env,
      adapter,
      action,
      "pi:host:session-1",
      raw_config,
      chdir: tmpdir
    )
    commands = if File.exist?(herdr_log)
      File.readlines(herdr_log, chomp: true).map { |line| JSON.parse(line) }
    else
      []
    end
    [*result, commands]
  end

  session_id = "019ff8e1-b7d4-7cc6-901f-b9b7bc3e7fd9"
  session_file = File.join(tmpdir, "2026-08-15_#{session_id}.jsonl")
  File.write(session_file, JSON.generate("type" => "session", "id" => session_id) + "\n")
  config = JSON.generate("session_file" => session_file)

  official_agent = lambda do |workspace: "w1", pane: "w1:p1", path: session_file|
    {
      "agent" => "pi",
      "workspace_id" => workspace,
      "pane_id" => pane,
      "agent_session" => {
        "source" => "integration:pi", "agent" => "pi",
        "kind" => "path", "value" => path
      }
    }
  end

  stdout, stderr, status, commands = run_adapter.call("resume", config)
  assert.call(status.success?, "direct resume exits successfully", "stdout:\n#{stdout}\nstderr:\n#{stderr}")
  args = JSON.parse(File.read(capture_path))
  assert.call(args == ["--session", session_file], "direct resume executes pi with session file", args.inspect)
  assert.call(commands.empty?, "direct resume does not call Herdr", commands.inspect)

  %w[true 01 1x].each do |marker|
    _stdout, stderr, status, commands = run_adapter.call(
      "resume", config, herdr_env: marker
    )
    assert.call(status.success?, "non-exact HERDR_ENV=#{marker} uses direct path", stderr)
    assert.call(commands.empty?, "non-exact HERDR_ENV=#{marker} does not call Herdr", commands.inspect)
  end

  stdout, stderr, status, commands = run_adapter.call(
    "resume", config, herdr_env: "1", state: {"agents" => [official_agent.call]}
  )
  assert.call(status.success?, "one official match focuses successfully", "stdout:\n#{stdout}\nstderr:\n#{stderr}")
  assert.call(commands == [["agent", "list"], ["workspace", "focus", "w1"]],
    "one official match focuses exact workspace without starting Pi", commands.inspect)
  assert.call(!File.exist?(capture_path), "one official match does not exec Pi in current terminal")

  expected_name = "asr-local-#{Digest::SHA256.hexdigest(session_file)[0, 20]}"
  published = official_agent.call(workspace: "w2", pane: "w2:p1")
  stdout, stderr, status, commands = run_adapter.call(
    "resume", config, herdr_env: "1",
    state: {"agents" => [], "publish_agent" => published}
  )
  assert.call(status.success?, "zero matches creates and focuses recovery", "stdout:\n#{stdout}\nstderr:\n#{stderr}")
  create = commands.find { |argv| argv.take(2) == ["workspace", "create"] }
  assert.call(create == ["workspace", "create", "--cwd", tmpdir, "--label", expected_name, "--no-focus"],
    "recovery creates deterministic unfocused workspace in current directory", create.inspect)
  start = commands.find { |argv| argv.take(2) == ["agent", "start"] }
  assert.call(start == ["agent", "start", expected_name, "--kind", "pi", "--pane", "w2:p1", "--", "pi", "--session", session_file],
    "recovery starts exact Pi session in exact pane", start.inspect)
  assert.call(commands.last == ["workspace", "focus", "w2"], "recovery focuses validated workspace", commands.last.inspect)

  _stdout, stderr, status, commands = run_adapter.call(
    "resume", config, herdr_env: "1",
    state: {"agents" => [official_agent.call, official_agent.call(workspace: "w2", pane: "w2:p1")]}
  )
  assert.call(!status.success? && stderr.include?("Multiple Herdr panes"), "duplicate official matches fail closed", stderr)
  assert.call(commands == [["agent", "list"]], "duplicate match creates and focuses nothing", commands.inspect)

  unofficial = official_agent.call
  unofficial["agent_session"]["source"] = "test:forged"
  _stdout, stderr, status, commands = run_adapter.call(
    "resume", config, herdr_env: "1",
    state: {"agents" => [unofficial], "publish_agent" => published}
  )
  assert.call(status.success?, "unofficial same-path report is not reused", stderr)
  assert.call(commands.any? { |argv| argv.take(2) == ["agent", "start"] },
    "unofficial same-path report causes owned recovery", commands.inspect)

  invalid_id = official_agent.call(workspace: "bad", pane: "bad:p1")
  _stdout, stderr, status, commands = run_adapter.call(
    "resume", config, herdr_env: "1", state: {"agents" => [invalid_id]}
  )
  assert.call(!status.success? && stderr.include?("Invalid Herdr pane identity"), "invalid matching IDs fail closed", stderr)
  assert.call(commands == [["agent", "list"]], "invalid matching IDs create nothing", commands.inspect)

  invalid_path = official_agent.call
  invalid_path["agent_session"]["value"] = 4
  _stdout, stderr, status, commands = run_adapter.call(
    "resume", config, herdr_env: "1", state: {"agents" => [invalid_path]}
  )
  assert.call(!status.success? && stderr.include?("Invalid Herdr Pi session report"), "invalid official path type fails closed", stderr)
  assert.call(commands == [["agent", "list"]], "invalid official path creates nothing", commands.inspect)

  _stdout, stderr, status, commands = run_adapter.call(
    "resume", config, herdr_env: "1", state: {"agents" => [], "fail_start" => true}
  )
  assert.call(!status.success? && stderr.include?("Herdr agent start failed"), "pre-validation start failure is reported", stderr)
  assert.call(commands.last == ["workspace", "close", "w2"], "pre-validation failure closes only owned workspace", commands.inspect)

  _stdout, stderr, status, commands = run_adapter.call(
    "resume", config, herdr_env: "1",
    state: {"agents" => [], "publish_agent" => published, "fail_focus" => true}
  )
  assert.call(!status.success? && stderr.include?("Herdr workspace focus failed"), "post-validation focus failure is reported", stderr)
  assert.call(!commands.any? { |argv| argv.take(2) == ["workspace", "close"] },
    "post-validation focus failure preserves recovered workspace", commands.inspect)

  _stdout, stderr, status, commands = run_adapter.call(
    "resume", config, herdr_env: "1", state: {"agents" => []}
  )
  assert.call(!status.success? && stderr.include?("Herdr Pi session registration timed out"), "registration timeout fails boundedly", stderr)
  assert.call(commands.last == ["workspace", "close", "w2"], "registration timeout closes owned workspace", commands.inspect)

  _stdout, stderr, status, _commands = run_adapter.call(
    "delete", config
  )
  assert.call(!status.success? && stderr.include?("Unsupported adapter action"), "unsupported action fails concisely", stderr)

  _stdout, stderr, status, _commands = run_adapter.call("resume", "{")
  assert.call(!status.success? && stderr.include?("Invalid adapter config JSON"), "malformed JSON fails concisely", stderr)

  _stdout, stderr, status, _commands = run_adapter.call("resume", "[]")
  assert.call(!status.success? && stderr.include?("Adapter config must be a JSON object"), "non-object JSON fails", stderr)

  _stdout, stderr, status, _commands = run_adapter.call("resume", "{}")
  assert.call(!status.success? && stderr.include?("Adapter config must include session_file"), "missing session_file fails", stderr)

  _stdout, stderr, status, _commands = run_adapter.call(
    "resume", JSON.generate("session_file" => "relative.jsonl")
  )
  assert.call(!status.success? && stderr.include?("Session file must be absolute and readable"), "relative session file fails", stderr)

  missing_file = File.join(tmpdir, "missing.jsonl")
  _stdout, stderr, status, _commands = run_adapter.call(
    "resume", JSON.generate("session_file" => missing_file)
  )
  assert.call(!status.success? && stderr.include?("Session file must be absolute and readable"), "missing session file fails", stderr)

  metachar_file = File.join(tmpdir, "session; touch owned; #.jsonl")
  marker = File.join(tmpdir, "owned")
  File.write(metachar_file, "{}\n")
  stdout, stderr, status, _commands = run_adapter.call(
    "resume", JSON.generate("session_file" => metachar_file)
  )
  assert.call(status.success?, "metacharacter path resumes directly", "stdout:\n#{stdout}\nstderr:\n#{stderr}")
  args = JSON.parse(File.read(capture_path))
  assert.call(args == ["--session", metachar_file], "metacharacter path remains one literal argument", args.inspect)
  assert.call(!File.exist?(marker), "metacharacter path does not execute shell content")
end

puts
puts "#{passed} passed, #{failed} failed"
exit(failed.zero?)
