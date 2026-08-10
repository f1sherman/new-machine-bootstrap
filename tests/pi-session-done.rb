#!/usr/bin/env ruby

require "fileutils"
require "json"
require "open3"
require "tmpdir"

repo_root = File.expand_path("..", __dir__)
helper = File.join(repo_root, "roles/common/files/bin/pi-session-done")

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

Dir.mktmpdir("pi-session-done") do |tmpdir|
  fake_bin = File.join(tmpdir, "bin")
  FileUtils.mkdir_p(fake_bin)
  capture_path = File.join(tmpdir, "asr-calls.jsonl")
  fake_asr = File.join(fake_bin, "asr")
  File.write(fake_asr, <<~RUBY)
    #!/usr/bin/env ruby
    require "json"
    File.open(ENV.fetch("ASR_CALL_CAPTURE"), "a") do |file|
      file.puts(JSON.generate({ "argv" => ARGV, "sync_socket" => ENV["ASR_SYNC_SOCKET"] }))
    end
    exit Integer(ENV.fetch("FAKE_ASR_EXIT", "0"))
  RUBY
  FileUtils.chmod(0o755, fake_asr)

  base_env = {
    "PATH" => "#{fake_bin}:#{ENV.fetch("PATH")}",
    "ASR_CALL_CAPTURE" => capture_path,
    "PI_SESSION_FILE" => "/home/brian/.pi/agent/sessions/project/session.jsonl",
    "PI_SESSION_ID" => "session-1",
    "FAKE_ASR_EXIT" => "0",
    "ASR_SYNC_SOCKET" => nil
  }

  run_helper = lambda do |env = {}, *arguments|
    FileUtils.rm_f(capture_path)
    Open3.capture3(base_env.merge(env), helper, *arguments)
  end

  calls = lambda do
    next [] unless File.exist?(capture_path)

    File.readlines(capture_path, chomp: true).map { |line| JSON.parse(line) }
  end

  _stdout, stderr, status = run_helper.call({ "PI_SESSION_FILE" => "" })
  assert.call(!status.success?, "missing session file fails", stderr)
  assert.call(calls.call.empty?, "missing session file does not call ASR", calls.call.inspect)

  _stdout, stderr, status = run_helper.call({ "PI_SESSION_ID" => "" })
  assert.call(!status.success?, "missing session ID fails", stderr)
  assert.call(calls.call.empty?, "missing session ID does not call ASR", calls.call.inspect)

  _stdout, stderr, status = run_helper.call({}, "another-session")
  assert.call(!status.success?, "positional identity is rejected", stderr)
  assert.call(calls.call.empty?, "rejected identity does not call ASR", calls.call.inspect)

  stdout, stderr, status = run_helper.call
  captured = calls.call
  assert.call(status.success?, "source-only completion succeeds", stderr)
  assert.call(
    stdout == "Marked source session session-1 done.\n",
    "source-only completion reports its scope",
    stdout.inspect
  )
  assert.call(captured.length == 1, "source completion calls ASR exactly once", captured.inspect)
  assert.call(
    captured.dig(0, "argv") == ["done", "--source", "pi", "--session-id", "session-1"],
    "source completion uses the exact current session identity",
    captured.inspect
  )

  stdout, stderr, status = run_helper.call("ASR_SYNC_SOCKET" => "/tmp/asr-sync.sock")
  captured = calls.call
  assert.call(status.success?, "synchronized completion succeeds", stderr)
  assert.call(
    stdout == "Marked source and laptop session session-1 done.\n",
    "synchronized completion reports both records",
    stdout.inspect
  )
  assert.call(captured.length == 1, "synchronized completion calls ASR exactly once", captured.inspect)
  assert.call(
    captured.dig(0, "sync_socket") == "/tmp/asr-sync.sock",
    "synchronized completion preserves the ASR socket",
    captured.inspect
  )

  stdout, _stderr, status = run_helper.call(
    "ASR_SYNC_SOCKET" => "/tmp/asr-sync.sock",
    "FAKE_ASR_EXIT" => "1"
  )
  captured = calls.call
  assert.call(!status.success?, "synchronization failure exits nonzero", stdout)
  assert.call(
    stdout == "Source session session-1 is done, but laptop synchronization failed.\n",
    "synchronization failure reports the partial result",
    stdout.inspect
  )
  assert.call(captured.length == 1, "synchronization failure does not retry ASR", captured.inspect)

  stdout, stderr, status = run_helper.call(
    "TASK_STATUS" => "complete",
    "PR_STATUS" => "merged",
    "USER_TEXT" => "goodbye"
  )
  assert.call(status.success?, "unrelated completion-like environment does not change behavior", stderr)
  assert.call(
    stdout == "Marked source session session-1 done.\n" && calls.call.length == 1,
    "helper does not infer completion from unrelated state",
    "stdout=#{stdout.inspect} calls=#{calls.call.inspect}"
  )
end

puts "\n#{passed} passed, #{failed} failed"
exit(failed.zero? ? 0 : 1)
