#!/usr/bin/env ruby

require "fileutils"
require "json"
require "open3"
require "tmpdir"

repo_root = File.expand_path("..", __dir__)
helper = File.join(repo_root, "roles/common/files/bin/pi-friction")

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

mode = ->(path) { File.stat(path).mode & 0o777 }

Dir.mktmpdir("pi-friction") do |tmpdir|
  state_dir = File.join(tmpdir, "state")
  base_env = {"PI_FRICTION_STATE_DIR" => state_dir}
  run_helper = lambda do |*arguments, env: {}|
    Open3.capture3(base_env.merge(env), helper, *arguments)
  end

  log_arguments = [
    "log", "--category", "correction",
    "--summary", "Agent changed the wrong file",
    "--repository", "/tmp/repo", "--session-id", "session-1"
  ]
  stdout, stderr, status = run_helper.call(*log_arguments)
  event = JSON.parse(stdout) if status.success?
  assert.call(status.success?, "valid event is logged", stderr)
  assert.call(
    event&.slice("version", "category", "summary", "repository", "session_id") == {
      "version" => 1,
      "category" => "correction",
      "summary" => "Agent changed the wrong file",
      "repository" => "/tmp/repo",
      "session_id" => "session-1"
    },
    "logged event has the expected fields",
    event.inspect
  )
  assert.call(
    event&.fetch("id", "")&.include?(event&.fetch("host", "")) &&
      event&.fetch("timestamp", "")&.end_with?("Z"),
    "logged event has host-based ID and UTC timestamp",
    event.inspect
  )

  events_path = File.join(state_dir, "events.jsonl")
  assert.call(mode.call(state_dir) == 0o700, "state directory is private", mode.call(state_dir).to_s(8))
  assert.call(mode.call(events_path) == 0o600, "event log is private", mode.call(events_path).to_s(8))

  child_outputs = 8.times.map do |index|
    stdout_path = File.join(tmpdir, "concurrent-#{index}.out")
    stderr_path = File.join(tmpdir, "concurrent-#{index}.err")
    pid = Process.spawn(
      base_env,
      helper,
      "log", "--category", "other", "--summary", "Concurrent event #{index}",
      out: stdout_path,
      err: stderr_path
    )
    [pid, stdout_path, stderr_path]
  end
  child_statuses = child_outputs.map do |pid, stdout_path, stderr_path|
    _finished_pid, child_status = Process.wait2(pid)
    [child_status, stdout_path, stderr_path]
  end
  assert.call(
    child_statuses.all? { |child_status, _stdout_path, _stderr_path| child_status.success? },
    "concurrent log processes succeed",
    child_statuses.map { |child_status, _stdout_path, stderr_path| [child_status.exitstatus, File.read(stderr_path)] }.inspect
  )

  events = File.readlines(events_path, chomp: true).map { |line| JSON.parse(line) }
  assert.call(events.length == 9, "concurrent appends preserve every event", events.length.inspect)
  assert.call(events.map { |item| item.fetch("id") }.uniq.length == 9, "concurrent event IDs are unique")

  stdout, stderr, status = run_helper.call("pending")
  first_snapshot = JSON.parse(stdout) if status.success?
  assert.call(status.success?, "pending exports valid events", stderr)
  assert.call(
    first_snapshot&.fetch("events", [])&.map { |item| item.fetch("id") } == events.map { |item| item.fetch("id") },
    "pending preserves event order",
    first_snapshot.inspect
  )
  assert.call(
    first_snapshot&.fetch("token", nil) == events.last.fetch("id"),
    "pending token identifies the final snapshot event",
    first_snapshot.inspect
  )

  later_stdout, later_stderr, later_status = run_helper.call(
    "log", "--category", "stopped-early", "--summary", "Agent stopped before verification"
  )
  later_event = JSON.parse(later_stdout) if later_status.success?
  assert.call(later_status.success?, "event can arrive during review", later_stderr)

  stdout, stderr, status = run_helper.call(
    "mark-reviewed", "--token", first_snapshot.fetch("token")
  )
  mark_result = JSON.parse(stdout) if status.success?
  assert.call(status.success?, "snapshot token advances the cursor", stderr)
  assert.call(
    mark_result&.fetch("reviewed_through", nil) == first_snapshot.fetch("token"),
    "cursor update reports the reviewed event",
    mark_result.inspect
  )

  cursor_path = File.join(state_dir, "reviewed-through")
  assert.call(mode.call(cursor_path) == 0o600, "review cursor is private", mode.call(cursor_path).to_s(8))

  stdout, stderr, status = run_helper.call("pending")
  remaining = JSON.parse(stdout) if status.success?
  assert.call(status.success?, "pending succeeds after cursor update", stderr)
  assert.call(
    remaining&.fetch("events", [])&.map { |item| item.fetch("id") } == [later_event.fetch("id")],
    "event appended during review remains pending",
    remaining.inspect
  )

  validation_cases = {
    "invalid category" => ["log", "--category", "mistake", "--summary", "Summary"],
    "blank summary" => ["log", "--category", "other", "--summary", "   "],
    "multiline summary" => ["log", "--category", "other", "--summary", "line one\nline two"]
  }
  cursor_before_validation = File.read(cursor_path)
  validation_cases.each do |name, arguments|
    _stdout, stderr, status = run_helper.call(*arguments)
    assert.call(!status.success?, "#{name} is rejected", stderr)
    assert.call(!stderr.empty?, "#{name} reports an error")
  end
  assert.call(
    File.read(cursor_path) == cursor_before_validation,
    "invalid log requests do not move the cursor"
  )

  _stdout, stderr, status = run_helper.call("mark-reviewed", "--token", "unknown-event")
  assert.call(!status.success?, "unknown review token is rejected", stderr)
  assert.call(
    File.read(cursor_path) == cursor_before_validation,
    "unknown review token does not move the cursor"
  )

  stale_token = events.first.fetch("id")
  _stdout, stderr, status = run_helper.call("mark-reviewed", "--token", stale_token)
  assert.call(!status.success?, "stale review token cannot move the cursor backward", stderr)
  assert.call(
    File.read(cursor_path) == cursor_before_validation,
    "stale review token leaves the cursor unchanged"
  )

  invalid_cursor_dir = File.join(tmpdir, "invalid-cursor")
  FileUtils.mkdir_p(invalid_cursor_dir)
  FileUtils.cp(events_path, File.join(invalid_cursor_dir, "events.jsonl"))
  invalid_cursor_path = File.join(invalid_cursor_dir, "reviewed-through")
  File.write(invalid_cursor_path, "missing-id\n")
  invalid_cursor_before = File.read(invalid_cursor_path)
  _stdout, stderr, status = run_helper.call("pending", env: {"PI_FRICTION_STATE_DIR" => invalid_cursor_dir})
  assert.call(!status.success?, "unknown stored cursor is rejected", stderr)
  assert.call(
    File.read(invalid_cursor_path) == invalid_cursor_before,
    "unknown stored cursor failure preserves the cursor"
  )

  malformed_dir = File.join(tmpdir, "malformed")
  FileUtils.mkdir_p(malformed_dir)
  malformed_cursor = events.first.fetch("id")
  File.write(
    File.join(malformed_dir, "events.jsonl"),
    "#{JSON.generate(events.first)}\n{not-json}\n"
  )
  malformed_cursor_path = File.join(malformed_dir, "reviewed-through")
  File.write(malformed_cursor_path, "#{malformed_cursor}\n")
  malformed_cursor_before = File.read(malformed_cursor_path)
  _stdout, stderr, status = run_helper.call("pending", env: {"PI_FRICTION_STATE_DIR" => malformed_dir})
  assert.call(!status.success?, "malformed event data is rejected", stderr)
  assert.call(
    File.read(malformed_cursor_path) == malformed_cursor_before,
    "malformed event failure preserves the cursor"
  )

  [
    "not-an-iso8601-timestamp",
    "2026-09-07T18:00:00+01:00",
    "2026-09-07T18:00:00-00:00"
  ].each do |timestamp|
    invalid_timestamp_dir = File.join(tmpdir, "invalid-timestamp-#{timestamp.hash}")
    FileUtils.mkdir_p(invalid_timestamp_dir)
    invalid_timestamp_event = events.first.merge("timestamp" => timestamp)
    File.write(
      File.join(invalid_timestamp_dir, "events.jsonl"),
      "#{JSON.generate(invalid_timestamp_event)}\n"
    )
    _stdout, stderr, status = run_helper.call(
      "pending",
      env: {"PI_FRICTION_STATE_DIR" => invalid_timestamp_dir}
    )
    assert.call(!status.success?, "non-UTC ISO-8601 timestamp #{timestamp.inspect} is rejected", stderr)
  end

  empty_dir = File.join(tmpdir, "empty")
  stdout, stderr, status = run_helper.call("pending", env: {"PI_FRICTION_STATE_DIR" => empty_dir})
  empty_snapshot = JSON.parse(stdout) if status.success?
  assert.call(status.success?, "empty state has a valid pending snapshot", stderr)
  assert.call(
    empty_snapshot&.fetch("events", nil) == [] && empty_snapshot&.fetch("token", "missing").nil?,
    "empty pending snapshot has no token",
    empty_snapshot.inspect
  )
end

puts "\n#{passed} passed, #{failed} failed"
exit(failed.zero? ? 0 : 1)
