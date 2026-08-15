#!/usr/bin/env ruby

require "fileutils"
require "json"
require "open3"
require "socket"
require "timeout"
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
  fake_bin = File.join(tmpdir, ".local", "bin")
  shadow_bin = File.join(tmpdir, "system-bin")
  FileUtils.mkdir_p(fake_bin)
  FileUtils.mkdir_p(shadow_bin)
  File.write(File.join(shadow_bin, "asr"), "#!/bin/sh\nexit 99\n")
  FileUtils.chmod(0o755, File.join(shadow_bin, "asr"))
  capture_path = File.join(tmpdir, "asr-calls.jsonl")
  fake_asr = File.join(fake_bin, "asr")
  File.write(fake_asr, <<~RUBY)
    #!/usr/bin/env ruby
    require "json"
    require "socket"
    File.open(ENV.fetch("ASR_CALL_CAPTURE"), "a") do |file|
      file.puts(JSON.generate({ "argv" => ARGV, "sync_socket" => ENV["ASR_SYNC_SOCKET"] }))
    end
    if ENV["FAKE_ASR_SYNC"] == "1"
      File.write(ENV.fetch("FAKE_SOURCE_DONE"), "done")
      socket = UNIXSocket.new(ENV.fetch("ASR_SYNC_SOCKET"))
      socket.puts(JSON.generate(
        "action" => "done",
        "source" => "pi",
        "hostname" => "dev",
        "session_id" => ENV.fetch("PI_SESSION_ID")
      ))
      response = JSON.parse(socket.gets)
      exit(response == { "ok" => true, "status" => "done" } ? 0 : 3)
    end
    exit Integer(ENV.fetch("FAKE_ASR_EXIT", "0"))
  RUBY
  FileUtils.chmod(0o755, fake_asr)

  base_env = {
    "HOME" => tmpdir,
    "PATH" => "#{shadow_bin}:#{ENV.fetch("PATH")}",
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
    "FAKE_ASR_EXIT" => "3"
  )
  captured = calls.call
  assert.call(status.exitstatus == 3, "synchronization failure exits with status 3", stdout)
  assert.call(
    stdout == "Source session session-1 is done, but laptop synchronization failed.\n",
    "synchronization failure reports the partial result",
    stdout.inspect
  )
  assert.call(captured.length == 1, "synchronization failure does not retry ASR", captured.inspect)

  [1, 2].each do |exit_status|
    stdout, stderr, status = run_helper.call(
      "ASR_SYNC_SOCKET" => "/tmp/asr-sync.sock",
      "FAKE_ASR_EXIT" => exit_status.to_s
    )
    captured = calls.call
    assert.call(
      status.exitstatus == exit_status,
      "ASR status #{exit_status} remains distinct",
      "status=#{status.exitstatus} stderr=#{stderr.inspect}"
    )
    assert.call(
      stdout.empty? && stderr.include?("Could not mark source session session-1 done."),
      "ASR status #{exit_status} does not claim source completion",
      "stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
    )
    assert.call(
      captured.length == 1,
      "ASR status #{exit_status} does not retry ASR",
      captured.inspect
    )
  end

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

  socket_path = File.join(tmpdir, "sync.sock")
  source_done_path = File.join(tmpdir, "source-done")
  server = UNIXServer.new(socket_path)
  request_queue = Queue.new
  release_reader, release_writer = IO.pipe
  server_thread = Thread.new do
    client = server.accept
    request_queue << client.gets
    release_reader.read(1)
    client.puts(JSON.generate("ok" => true, "status" => "done"))
    client.close
  end

  helper_env = {
    "ASR_SYNC_SOCKET" => socket_path,
    "FAKE_ASR_SYNC" => "1",
    "FAKE_SOURCE_DONE" => source_done_path
  }
  helper_stdin, helper_stdout, helper_stderr, helper_wait = Open3.popen3(
    base_env.merge(helper_env),
    helper
  )
  helper_stdin.close
  request = JSON.parse(Timeout.timeout(5) { request_queue.pop })
  assert.call(
    request == {
      "action" => "done",
      "source" => "pi",
      "hostname" => "dev",
      "session_id" => "session-1"
    },
    "ASR sends the exact completion request",
    request.inspect
  )
  assert.call(
    File.read(source_done_path) == "done",
    "source record is done before laptop acknowledgment"
  )
  assert.call(
    helper_wait.join(0.1).nil?,
    "helper waits for laptop acknowledgment"
  )
  pre_ack_output = if IO.select([helper_stdout], nil, nil, 0.2)
    helper_stdout.read_nonblock(4096, exception: false)
  else
    ""
  end
  pre_ack_output = "" if [:wait_readable, nil].include?(pre_ack_output)
  assert.call(
    !pre_ack_output.include?("Marked source and laptop session"),
    "helper does not claim both records before acknowledgment",
    pre_ack_output.inspect
  )

  release_writer.write("x")
  release_writer.close
  helper_status = helper_wait.value
  helper_output = helper_stdout.read
  helper_error = helper_stderr.read
  assert.call(helper_status.success?, "helper succeeds after acknowledgment", helper_error)
  assert.call(
    helper_output == "Marked source and laptop session session-1 done.\n",
    "helper claims both records only after acknowledgment",
    helper_output.inspect
  )
ensure
  release_reader&.close unless release_reader&.closed?
  release_writer&.close unless release_writer&.closed?
  server&.close
  server_thread&.join(1)
end

puts "\n#{passed} passed, #{failed} failed"
exit(failed.zero? ? 0 : 1)
