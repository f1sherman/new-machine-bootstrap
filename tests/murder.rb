#!/usr/bin/env ruby

require "open3"
require "rbconfig"

repo_root = File.expand_path("..", __dir__)
murder_script = File.join(repo_root, "roles/macos/templates/murder")

pass = 0
fail = 0

pass_case = lambda do |name|
  pass += 1
  puts "PASS  #{name}"
end

fail_case = lambda do |name, detail|
  fail += 1
  puts "FAIL  #{name}"
  puts "      #{detail}"
end

assert = lambda do |condition, name, detail|
  if condition
    pass_case.call(name)
  else
    fail_case.call(name, detail)
  end
end

child_code = <<~RUBY
  trap("TERM") { exit 0 }
  puts "ready"
  STDOUT.flush
  sleep 60
RUBY

process_running = lambda do |pid|
  Process.kill(0, pid)
  true
rescue Errno::ESRCH
  false
end

wait_for_exit = lambda do |pid, timeout: 5|
  deadline = Time.now + timeout
  loop do
    reaped_pid, status = Process.waitpid2(pid, Process::WNOHANG)
    return status if reaped_pid
    return nil if Time.now >= deadline

    sleep 0.05
  end
rescue Errno::ECHILD
  true
end

cleanup_child = lambda do |pid|
  begin
    Process.kill("KILL", pid)
  rescue Errno::ESRCH
  end

  begin
    Process.wait(pid)
  rescue Errno::ECHILD
  end
end

with_child = lambda do |&block|
  reader, writer = IO.pipe
  pid = Process.spawn(RbConfig.ruby, "-e", child_code, out: writer, err: File::NULL)
  writer.close
  ready = reader.gets
  raise "child process did not become ready" unless ready == "ready\n"

  block.call(pid)
ensure
  cleanup_child.call(pid) if pid && process_running.call(pid)
  reader&.close
end

run_murder = lambda do |*args|
  stdout, stderr, status = Open3.capture3(RbConfig.ruby, murder_script, *args, stdin_data: "")
  [stdout, stderr, status]
end

with_child.call do |pid|
  stdout, stderr, status = run_murder.call("--yes", pid.to_s)
  assert.call(status.success?, "--yes exits successfully", "stdout:\n#{stdout}\nstderr:\n#{stderr}")
  assert.call(!stdout.include?("Do you really want to kill this process?"), "--yes skips prompt", stdout)
  assert.call(wait_for_exit.call(pid), "--yes terminates the process", "process #{pid} was still running")
end

with_child.call do |pid|
  stdout, stderr, status = run_murder.call("-y", pid.to_s)
  assert.call(status.success?, "-y exits successfully", "stdout:\n#{stdout}\nstderr:\n#{stderr}")
  assert.call(!stdout.include?("Do you really want to kill this process?"), "-y skips prompt", stdout)
  assert.call(wait_for_exit.call(pid), "-y terminates the process", "process #{pid} was still running")
end

with_child.call do |pid|
  stdout, stderr, status = run_murder.call("--force", pid.to_s)
  assert.call(status.success?, "--force exits successfully", "stdout:\n#{stdout}\nstderr:\n#{stderr}")
  assert.call(!stdout.include?("Do you really want to kill this process?"), "--force skips prompt", stdout)
  assert.call(wait_for_exit.call(pid), "--force terminates the process", "process #{pid} was still running")
end

with_child.call do |pid|
  stdout, stderr, status = run_murder.call(pid.to_s)
  assert.call(!status.success?, "closed stdin without --yes fails", "stdout:\n#{stdout}\nstderr:\n#{stderr}")
  assert.call(stderr.include?("Confirmation required but stdin is unavailable"), "closed stdin failure explains --yes", stderr)
  assert.call(process_running.call(pid), "closed stdin does not kill process", "process #{pid} was not running")
end

puts
puts "#{pass} passed, #{fail} failed"
exit(fail.zero?)
