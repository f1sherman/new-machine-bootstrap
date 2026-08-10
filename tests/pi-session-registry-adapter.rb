#!/usr/bin/env ruby

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
  fake_pi = File.join(fake_bin, "pi")
  capture_path = File.join(tmpdir, "pi-argv.json")

  File.write(fake_pi, <<~RUBY)
    #!/usr/bin/env ruby
    require "json"
    File.write(ENV.fetch("PI_ARGV_CAPTURE"), JSON.generate(ARGV))
  RUBY
  FileUtils.chmod(0o755, fake_pi)

  run_adapter = lambda do |action, raw_config|
    FileUtils.rm_f(capture_path)
    env = {
      "PATH" => "#{fake_bin}:#{ENV.fetch("PATH")}",
      "PI_ARGV_CAPTURE" => capture_path
    }
    Open3.capture3(
      env,
      adapter,
      action,
      "pi:host:session-1",
      raw_config,
      chdir: tmpdir
    )
  end

  session_file = File.join(tmpdir, "session.jsonl")
  File.write(session_file, "{}\n")
  stdout, stderr, status = run_adapter.call(
    "resume",
    JSON.generate("session_file" => session_file)
  )
  assert.call(status.success?, "resume exits successfully", "stdout:\n#{stdout}\nstderr:\n#{stderr}")
  args = JSON.parse(File.read(capture_path))
  assert.call(args == ["--session", session_file], "resume executes pi with the session file", args.inspect)

  _stdout, stderr, status = run_adapter.call(
    "delete",
    JSON.generate("session_file" => session_file)
  )
  assert.call(!status.success? && stderr.include?("Unsupported adapter action"), "unsupported action fails concisely", stderr)

  _stdout, stderr, status = run_adapter.call("resume", "{")
  assert.call(!status.success? && stderr.include?("Invalid adapter config JSON"), "malformed JSON fails concisely", stderr)

  _stdout, stderr, status = run_adapter.call("resume", "[]")
  assert.call(!status.success? && stderr.include?("Adapter config must be a JSON object"), "non-object JSON fails", stderr)

  _stdout, stderr, status = run_adapter.call("resume", "{}")
  assert.call(!status.success? && stderr.include?("Adapter config must include session_file"), "missing session_file fails", stderr)

  _stdout, stderr, status = run_adapter.call(
    "resume",
    JSON.generate("session_file" => "relative.jsonl")
  )
  assert.call(!status.success? && stderr.include?("Session file must be absolute and readable"), "relative session file fails", stderr)

  missing_file = File.join(tmpdir, "missing.jsonl")
  _stdout, stderr, status = run_adapter.call(
    "resume",
    JSON.generate("session_file" => missing_file)
  )
  assert.call(!status.success? && stderr.include?("Session file must be absolute and readable"), "missing session file fails", stderr)

  unreadable_file = File.join(tmpdir, "unreadable.jsonl")
  File.write(unreadable_file, "{}\n")
  begin
    FileUtils.chmod(0o000, unreadable_file)
    _stdout, stderr, status = run_adapter.call(
      "resume",
      JSON.generate("session_file" => unreadable_file)
    )
    assert.call(!status.success? && stderr.include?("Session file must be absolute and readable"), "unreadable session file fails", stderr)
  ensure
    FileUtils.chmod(0o600, unreadable_file)
  end

  metachar_file = File.join(tmpdir, "session; touch owned; #.jsonl")
  marker = File.join(tmpdir, "owned")
  File.write(metachar_file, "{}\n")
  stdout, stderr, status = run_adapter.call(
    "resume",
    JSON.generate("session_file" => metachar_file)
  )
  assert.call(status.success?, "metacharacter path resumes successfully", "stdout:\n#{stdout}\nstderr:\n#{stderr}")
  args = JSON.parse(File.read(capture_path))
  assert.call(args == ["--session", metachar_file], "metacharacter path remains one literal argument", args.inspect)
  assert.call(!File.exist?(marker), "metacharacter path does not execute shell content")
end

puts
puts "#{passed} passed, #{failed} failed"
exit(failed.zero?)
