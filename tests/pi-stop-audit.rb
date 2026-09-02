#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "time"
require "tmpdir"

repo_root = File.expand_path("..", __dir__)
helper = File.join(repo_root, "roles/common/files/bin/pi-stop-audit")

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

message = lambda do |id:, parent:, timestamp:, role:, text:, stop: false|
  row = {
    "type" => "message",
    "id" => id,
    "parentId" => parent,
    "timestamp" => timestamp,
    "message" => {
      "role" => role,
      "content" => [{"type" => "text", "text" => text}]
    }
  }
  row["message"]["stopReason"] = "stop" if stop
  row
end

Dir.mktmpdir("pi-stop-audit") do |tmpdir|
  root = File.join(tmpdir, "sessions")
  first_dir = File.join(root, "repo-alpha", "session-one")
  second_dir = File.join(root, "repo-beta", "session-two")
  fake_bin = File.join(tmpdir, "bin")
  FileUtils.mkdir_p([first_dir, second_dir, fake_bin])

  network_marker = File.join(tmpdir, "network-called")
  %w[curl wget].each do |command|
    path = File.join(fake_bin, command)
    File.write(path, "#!/bin/sh\nprintf called >\"$NETWORK_MARKER\"\nexit 99\n")
    FileUtils.chmod(0o755, path)
  end

  recent_time = (Time.now.utc - 3600).iso8601(6)
  old_time = (Time.now.utc - (9 * 86_400)).iso8601(6)

  human = message.call(
    id: "u1", parent: nil, timestamp: recent_time, role: "user",
    text: "Deploy the selected fix."
  )
  stop = message.call(
    id: "a1", parent: "u1", timestamp: recent_time, role: "assistant",
    text: "Proceeding with deployment now. token: super-secret-value; " \
      "access_token=second-secret-value, " \
      "credential: correct horse battery staple, deployment queued",
    stop: true
  )
  continuation = message.call(
    id: "u2", parent: "a1", timestamp: recent_time, role: "user",
    text: "continue"
  )

  first_file = File.join(first_dir, "branch.jsonl")
  File.write(
    first_file,
    [human, stop, continuation].map { |row| JSON.generate(row) }.join("\n") + "\n"
  )

  approval_request = message.call(
    id: "a2", parent: "u3", timestamp: recent_time, role: "assistant",
    text: "The design is complete. Please approve it.", stop: true
  )
  compaction = message.call(
    id: "u5", parent: nil, timestamp: recent_time, role: "user",
    text: "Compaction completed. Continue from the summary."
  )
  monitor = message.call(
    id: "u7", parent: nil, timestamp: recent_time, role: "user",
    text: "Pi extension-generated PR monitor status event"
  )

  second_rows = [
    stop,
    message.call(
      id: "u3", parent: nil, timestamp: recent_time, role: "user",
      text: "Implement the known configuration change."
    ),
    approval_request,
    message.call(
      id: "u4", parent: "a2", timestamp: recent_time, role: "user",
      text: "approved"
    ),
    compaction,
    message.call(
      id: "a3", parent: "u5", timestamp: recent_time, role: "assistant",
      text: "The repository status is unchanged.", stop: true
    ),
    monitor,
    message.call(
      id: "a4", parent: "u7", timestamp: recent_time, role: "assistant",
      text: "Proceeding with routine PR work.", stop: true
    ),
    message.call(
      id: "u9", parent: nil, timestamp: old_time, role: "user",
      text: "Old request"
    ),
    message.call(
      id: "a5", parent: "u9", timestamp: old_time, role: "assistant",
      text: "Proceeding with old work.", stop: true
    )
  ]
  second_file = File.join(second_dir, "branch.jsonl")
  File.open(second_file, "w") do |file|
    second_rows.each { |row| file.puts(JSON.generate(row)) }
    file.puts(JSON.generate("type" => "message", "id" => "broken", "message" => "invalid"))
    file.puts("{malformed")
  end

  base_env = {
    "HOME" => tmpdir,
    "PATH" => "#{fake_bin}:/usr/bin:/bin",
    "NETWORK_MARKER" => network_marker
  }
  run_helper = lambda do |*arguments|
    Open3.capture3(base_env, helper, *arguments)
  end

  stdout, stderr, status = run_helper.call("7d", "--json", "--root", root)
  report = status.success? ? JSON.parse(stdout) : {}
  assert.call(status.success?, "audit succeeds", stderr)
  assert.call(
    report["unique_stops"] == 3,
    "deduplicates and excludes monitor and old stops",
    report.inspect
  )
  assert.call(
    report.dig("counts", "future_action") == 1,
    "finds future-action stop",
    report.inspect
  )
  assert.call(
    report.dig("counts", "short_continuation") == 1,
    "finds continue response",
    report.inspect
  )
  assert.call(
    report.dig("counts", "process_approval") == 1,
    "finds process approval",
    report.inspect
  )
  assert.call(
    report.dig("counts", "compaction_adjacent") == 1,
    "finds compaction-adjacent stop",
    report.inspect
  )
  assert.call(report["excluded_pr_monitor"] == 1, "counts monitor exclusion", report.inspect)
  assert.call(report["malformed_lines"] == 2, "counts malformed lines", report.inspect)
  assert.call(!stdout.include?("super-secret-value"), "redacts credential-like excerpts", stdout)
  assert.call(!stdout.include?("second-secret-value"), "redacts keys containing token", stdout)
  assert.call(
    !stdout.include?("correct horse battery staple"),
    "redacts unquoted multiword assigned secrets",
    stdout
  )
  assert.call(stdout.include?("[REDACTED]"), "shows redaction marker", stdout)
  assert.call(!File.exist?(network_marker), "does not invoke network commands")

  text, stderr, status = run_helper.call("7d", "--root", root)
  candidates_index = text.index("Candidates:")
  counts_index = text.index("Future action:")
  assert.call(status.success?, "text audit succeeds", stderr)
  assert.call(
    counts_index && candidates_index && counts_index < candidates_index,
    "text aggregates precede candidate details",
    text
  )
  assert.call(
    text.include?("Candidates require human review."),
    "text report states advisory status",
    text
  )

  limited_json, stderr, status = run_helper.call(
    "7d", "--json", "--root", root, "--limit", "1"
  )
  limited = status.success? ? JSON.parse(limited_json) : {}
  assert.call(status.success?, "limited audit succeeds", stderr)
  assert.call(limited["candidates"]&.length == 1, "limit bounds candidate records", limited.inspect)
  assert.call(limited["counts"] == report["counts"], "limit preserves aggregate counts", limited.inspect)

  session_json, stderr, status = run_helper.call(
    "7d", "--json", "--root", root, "--session", "session-one"
  )
  session_report = status.success? ? JSON.parse(session_json) : {}
  assert.call(status.success?, "session filter succeeds", stderr)
  assert.call(
    session_report["candidates"]&.map { |candidate| candidate["id"] } == ["a1"],
    "session filter selects one candidate",
    session_report.inspect
  )

  repository_json, stderr, status = run_helper.call(
    "7d", "--json", "--root", root, "--repository", "repo-alpha"
  )
  repository_report = status.success? ? JSON.parse(repository_json) : {}
  assert.call(status.success?, "repository filter succeeds", stderr)
  assert.call(
    repository_report["candidates"]&.map { |candidate| candidate["id"] } == ["a1"],
    "repository filter selects one candidate",
    repository_report.inspect
  )

  _stdout, stderr, status = run_helper.call("0d", "--root", root)
  assert.call(!status.success? && stderr.include?("Usage:"), "zero window fails with usage", stderr)

  _stdout, stderr, status = run_helper.call("seven-days", "--root", root)
  assert.call(!status.success? && stderr.include?("Usage:"), "invalid window fails with usage", stderr)

  missing_root = File.join(tmpdir, "missing")
  _stdout, stderr, status = run_helper.call("7d", "--root", missing_root)
  assert.call(
    !status.success? && stderr.include?("Session root is not a directory"),
    "missing root fails concisely",
    stderr
  )

  sort_root = File.join(tmpdir, "sort-sessions")
  FileUtils.mkdir_p(sort_root)
  base_time = Time.now.utc - 3600
  chronologically_early = base_time.getlocal("+02:00").iso8601
  chronologically_late = (base_time + 60).iso8601
  sort_rows = [
    message.call(
      id: "sort-u1", parent: nil, timestamp: chronologically_early,
      role: "user", text: "First request"
    ),
    message.call(
      id: "sort-a1", parent: "sort-u1", timestamp: chronologically_early,
      role: "assistant", text: "Proceeding with the first action.", stop: true
    ),
    message.call(
      id: "sort-u2", parent: nil, timestamp: chronologically_late,
      role: "user", text: "Second request"
    ),
    message.call(
      id: "sort-a2", parent: "sort-u2", timestamp: chronologically_late,
      role: "assistant", text: "Proceeding with the second action.", stop: true
    )
  ]
  File.write(
    File.join(sort_root, "offsets.jsonl"),
    sort_rows.map { |row| JSON.generate(row) }.join("\n") + "\n"
  )
  sorted_json, stderr, status = run_helper.call(
    "7d", "--json", "--root", sort_root
  )
  sorted_report = status.success? ? JSON.parse(sorted_json) : {}
  assert.call(status.success?, "offset timestamp audit succeeds", stderr)
  assert.call(
    sorted_report.fetch("candidates", []).map { |candidate| candidate["id"] } ==
      %w[sort-a1 sort-a2],
    "sorts candidates by chronological instant across offsets",
    sorted_report.inspect
  )
end

puts
puts "#{passed} passed, #{failed} failed"
exit(failed.zero? ? 0 : 1)
